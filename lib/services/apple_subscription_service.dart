import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppleSubscriptionService {
  static const String satelliteMonthlyId = 'app.mygrid.grid_satellite_monthly';
  
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  List<PurchaseDetails> _purchases = [];
  bool _isActivePurchaseAttempt = false;
  
  bool get isAvailable => _isAvailable;
  List<ProductDetails> get products => _products;
  
  Future<void> initialize() async {
    if (!Platform.isIOS) return;
    
    final bool available = await _inAppPurchase.isAvailable();
    _isAvailable = available;
    
    if (!available) {
      print('In-app purchases not available');
      return;
    }
    
    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await iosPlatformAddition.setDelegate(_ApplePaymentQueueDelegate());
    }
    
    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription.cancel(),
      onError: (error) => {},
    );
    
    await loadProducts();
    
    await restorePurchases();
  }
  
  Future<void> loadProducts() async {
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(
      {satelliteMonthlyId},
    );
    
    if (response.error != null) {
      print('Error loading products: ${response.error!.message}');
      return;
    }
    
    if (response.notFoundIDs.isNotEmpty) {
      print('Products not found: ${response.notFoundIDs}');
    }
    
    _products = response.productDetails;
    print('Loaded ${_products.length} products');
  }
  
  Future<void> purchaseSubscription(BuildContext context) async {
    print('[IAP] Starting purchase flow...');
    _isActivePurchaseAttempt = true;
    
    if (_products.isEmpty) {
      print('[IAP] No products loaded, attempting to load...');
      await loadProducts();
      if (_products.isEmpty) {
        print('[IAP] Still no products after loading attempt');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscription not available'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }
    
    final ProductDetails productDetails = _products.first;
    print('[IAP] Purchasing product: ${productDetails.id}');
    
    final client = Provider.of<Client>(context, listen: false);
    final userId = client.userID?.split(':')[0].replaceAll('@', '') ?? '';
    print('[IAP] User ID for purchase: $userId');
    
    // Get UUID from backend
    String? userUuid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jwt = prefs.getString('loginToken');
      
      if (jwt == null) {
        throw Exception('Not authenticated');
      }
      
      final response = await http.get(
        Uri.parse('${dotenv.env['GAUTH_URL']}/api/user/uuid'),
        headers: {'Authorization': 'Bearer $jwt'},
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        userUuid = data['uuid'];
        print('[IAP] Got UUID from backend: $userUuid');
      } else {
        throw Exception('Failed to get UUID');
      }
    } catch (e) {
      print('[IAP] Error getting UUID: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to initialize purchase'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
      );
      return;
    }
    
    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
        applicationUserName: userUuid,  // Pass UUID instead of username
      );
      
      print('[IAP] Calling buyNonConsumable...');
      bool result = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      print('[IAP] buyNonConsumable returned: $result');
    } catch (e) {
      print('[IAP] Purchase error: $e');
      _showErrorSnackBar(context, 'Unable to complete purchase');
    }
  }
  
  Future<void> restorePurchases() async {
    try {
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      print('Restore purchases error: $e');
    }
  }
  
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    print('[IAP] Purchase update received: ${purchaseDetailsList.length} items');
    for (PurchaseDetails purchaseDetails in purchaseDetailsList) {
      print('[IAP] Purchase status: ${purchaseDetails.status}, productID: ${purchaseDetails.productID}');
      print('[IAP] Purchase ID: ${purchaseDetails.purchaseID}');
      print('[IAP] Transaction date: ${purchaseDetails.transactionDate}');
      print('[IAP] Is active purchase attempt: $_isActivePurchaseAttempt');
      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        print('[IAP] Purchase pending...');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        print('[IAP] Purchase error: ${purchaseDetails.error?.code} - ${purchaseDetails.error?.message}');
        if (_isActivePurchaseAttempt) {
          _handleError(purchaseDetails.error!);
        }
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                 purchaseDetails.status == PurchaseStatus.restored) {
        print('[IAP] Purchase successful/restored: ${purchaseDetails.productID}');
        // Only set lastSuccessfulPurchase if user actively initiated purchase
        if (_isActivePurchaseAttempt && purchaseDetails.status == PurchaseStatus.purchased) {
          _verifyAndDeliverProduct(purchaseDetails);
        }
      }
      
      if (purchaseDetails.pendingCompletePurchase) {
        print('[IAP] Completing purchase...');
        _inAppPurchase.completePurchase(purchaseDetails);
      }
      
      // Reset flag after processing a user-initiated purchase
      if (_isActivePurchaseAttempt && 
          (purchaseDetails.status == PurchaseStatus.purchased || 
           purchaseDetails.status == PurchaseStatus.error ||
           purchaseDetails.status == PurchaseStatus.canceled)) {
        _isActivePurchaseAttempt = false;
      }
    }
    
    _purchases = purchaseDetailsList;
  }
  
  void _verifyAndDeliverProduct(PurchaseDetails purchaseDetails) {
    // Store the successful purchase for the UI to handle
    _lastSuccessfulPurchase = purchaseDetails;
  }
  
  PurchaseDetails? _lastSuccessfulPurchase;
  PurchaseDetails? get lastSuccessfulPurchase => _lastSuccessfulPurchase;
  
  void _handleError(IAPError error) {
    _lastError = error;
  }
  
  IAPError? _lastError;
  IAPError? get lastError => _lastError;
  
  bool _wasCanceled = false;
  bool get wasCanceled => _wasCanceled;
  
  void clearPurchaseState() {
    _lastSuccessfulPurchase = null;
    _lastError = null;
    _wasCanceled = false;
    _isActivePurchaseAttempt = false;
  }
  
  Future<bool> hasActiveSubscription() async {
    return false;
  }
  
  Future<void> openManageSubscriptions() async {
    if (Platform.isIOS) {
      const url = 'https://apps.apple.com/account/subscriptions';
      if (await canLaunch(url)) {
        await launch(url);
      }
    }
  }
  
  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void dispose() {
    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      iosPlatformAddition.setDelegate(null);
    }
    _subscription.cancel();
  }
}

class _ApplePaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
      SKPaymentTransactionWrapper transaction, SKStorefrontWrapper storefront) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return false;
  }
}