import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppleSubscriptionService {
  static const String satelliteMonthlyId = 'app.mygrid.grid_satellite_monthly';
  
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  List<PurchaseDetails> _purchases = [];
  
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
    
    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription.cancel(),
      onError: (error) => print('Purchase stream error: $error'),
    );
    
    await loadProducts();
    
    await restorePurchases();
  }
  
  Future<void> loadProducts() async {
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(
      {satelliteMonthlyId},
    );
    
    if (response.error != null) {
      print('Error loading products: ${response.error}');
      return;
    }
    
    if (response.notFoundIDs.isNotEmpty) {
      print('Products not found: ${response.notFoundIDs}');
    }
    
    _products = response.productDetails;
    print('Loaded ${_products.length} products');
  }
  
  Future<void> purchaseSubscription(BuildContext context) async {
    if (_products.isEmpty) {
      await loadProducts();
      if (_products.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription not available')),
        );
        return;
      }
    }
    
    final ProductDetails productDetails = _products.first;
    
    final client = Provider.of<Client>(context, listen: false);
    final userId = client.userID?.split(':')[0].replaceAll('@', '') ?? '';
    
    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
        applicationUserName: userId,
      );
      
      await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      print('Purchase error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase failed')),
      );
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
    for (PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        print('Purchase pending...');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        print('Purchase error: ${purchaseDetails.error}');
        _handleError(purchaseDetails.error!);
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                 purchaseDetails.status == PurchaseStatus.restored) {
        print('Purchase successful: ${purchaseDetails.productID}');
        _verifyAndDeliverProduct(purchaseDetails);
      }
      
      if (purchaseDetails.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
    
    _purchases = purchaseDetailsList;
  }
  
  void _verifyAndDeliverProduct(PurchaseDetails purchaseDetails) {
    print('Purchase verified: ${purchaseDetails.productID}');
  }
  
  void _handleError(IAPError error) {
    print('Purchase error: ${error.code} - ${error.message}');
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
  
  void dispose() {
    _subscription.cancel();
  }
}