import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/matrix.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/apple_subscription_service.dart';

class SubscriptionScreen extends StatefulWidget {
  @override
  _SubscriptionScreenState createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _subscriptionData;
  String? _error;
  final AppleSubscriptionService _appleService = AppleSubscriptionService();
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
    if (Platform.isIOS) {
      _appleService.initialize();
    }
  }
  
  @override
  void dispose() {
    if (Platform.isIOS) {
      _appleService.dispose();
    }
    super.dispose();
  }

  Future<void> _checkSubscriptionStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final jwt = prefs.getString('loginToken');
      
      if (jwt == null) {
        setState(() {
          _error = 'Not authenticated';
          _isLoading = false;
        });
        return;
      }

      final authUrl = dotenv.env['GAUTH_URL'];
      final response = await http.get(
        Uri.parse('$authUrl/api/subscription/status'),
        headers: {
          'Authorization': 'Bearer $jwt',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _subscriptionData = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load subscription status';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openCheckout() async {
    if (Platform.isIOS) {
      setState(() {
        _isPurchasing = true;
      });
      
      // Clear any previous purchase state
      _appleService.clearPurchaseState();
      
      // Use Apple In-App Purchase
      await _appleService.purchaseSubscription(context);
      
      // Wait a moment for purchase to process
      await Future.delayed(Duration(milliseconds: 500));
      
      setState(() {
        _isPurchasing = false;
      });
      
      // Check result and show appropriate feedback
      if (_appleService.lastSuccessfulPurchase != null) {
        _showSuccessModal();
      } else if (_appleService.lastError != null) {
        // Check if user canceled (error code 2 is user canceled)
        if (_appleService.lastError!.code == 'storekit_cancelled_payment') {
          _showFloatingSnackBar('Purchase canceled', isError: false);
        } else {
          _showFloatingSnackBar('Unable to complete purchase', isError: true);
        }
      }
    } else {
      // Use Stripe for Android/Web
      final client = Provider.of<Client>(context, listen: false);
      final userId = client.userID?.split(':')[0].replaceAll('@', '') ?? '';
      
      final subscribeUrl = dotenv.env['SUBSCRIBE_URL'] ?? '';
      final checkoutUrl = '$subscribeUrl/checkout?userId=${Uri.encodeComponent(userId)}';
      
      if (await canLaunch(checkoutUrl)) {
        await launch(checkoutUrl);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open checkout')),
        );
      }
    }
  }

  Future<void> _openManageSubscription() async {
    if (Platform.isIOS) {
      // Open Apple's subscription management
      await _appleService.openManageSubscriptions();
    } else {
      // Use Stripe management for Android/Web
      final client = Provider.of<Client>(context, listen: false);
      final userId = client.userID?.split(':')[0].replaceAll('@', '') ?? '';
      
      // Get subscription data
      final stripeCustomerId = _subscriptionData?['stripe_customer_id'] ?? '';
      final subscriptionExpires = _subscriptionData?['subscription_expires'] ?? '';
      final subscriptionType = _subscriptionData?['subscription_type'] ?? '';
      final autoRenew = _subscriptionData?['auto_renew'] ?? false;
      
      // Build URL with all necessary parameters
      final subscribeUrl = dotenv.env['SUBSCRIBE_URL'] ?? '';
      final manageUrl = '$subscribeUrl/manage'
          '?userId=${Uri.encodeComponent(userId)}'
          '&customerId=${Uri.encodeComponent(stripeCustomerId)}'
          '&expires=${Uri.encodeComponent(subscriptionExpires)}'
          '&type=${Uri.encodeComponent(subscriptionType)}'
          '&autoRenew=${Uri.encodeComponent(autoRenew.toString())}';
      
      if (await canLaunch(manageUrl)) {
        await launch(manageUrl);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open subscription management')),
        );
      }
    }
  }

  void _showFloatingSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        backgroundColor: isError 
            ? Colors.red.shade400 
            : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: 20,
          left: 20,
          right: 20,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: Duration(seconds: 3),
        elevation: 6,
      ),
    );
  }
  
  void _showSuccessModal() {
    bool isLoading = false;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final colorScheme = Theme.of(context).colorScheme;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: colorScheme.surface,
              child: Container(
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: colorScheme.surface,
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.2),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle_outline,
                        color: colorScheme.primary,
                        size: 48,
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Thank You!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Your subscription greatly helps keep Grid running and independent.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface.withOpacity(0.8),
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Satellite maps are privately routed through Cloudflare for enhanced privacy.',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface.withOpacity(0.7),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : () async {
                          setState(() {
                            isLoading = true;
                          });
                          
                          // Poll for subscription to be active
                          bool subscriptionActive = false;
                          for (int i = 0; i < 20; i++) { // Try for up to 10 seconds
                            await _checkSubscriptionStatus();
                            if (_subscriptionData?['is_active'] == true) {
                              subscriptionActive = true;
                              break;
                            }
                            await Future.delayed(Duration(milliseconds: 500));
                          }
                          
                          if (mounted) {
                            Navigator.of(context).pop();
                            if (!subscriptionActive) {
                              _showFloatingSnackBar('Subscription is being processed...', isError: false);
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: colorScheme.primary.withOpacity(0.6),
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Continue',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: Text(
          'Subscriptions',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onBackground,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.1),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(colorScheme)
              : _buildSubscriptionContent(colorScheme),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 64,
            ),
            SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _checkSubscriptionStatus,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Retry',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionContent(ColorScheme colorScheme) {
    final hasSubscription = _subscriptionData?['has_subscription'] ?? false;
    final isActive = _subscriptionData?['is_active'] ?? false;
    final subscriptionType = _subscriptionData?['subscription_type'] ?? '';
    final expiresAt = _subscriptionData?['subscription_expires'] ?? '';
    final autoRenew = _subscriptionData?['auto_renew'] ?? false;

    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy and Mission Statement
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 20,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Grid will never paywall core features. We believe privacy is a fundamental right. Optional subscriptions for cosmetic features like satellite maps help sustain development.',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withOpacity(0.8),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          
          // Current Subscriptions Section
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Subscriptions',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(0.6),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  hasSubscription && isActive ? 'Satellite Maps' : 'None',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: hasSubscription && isActive 
                        ? colorScheme.primary 
                        : colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          
          // Available Subscriptions Label
          Text(
            'Available Subscriptions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 16),
          
          // Satellite Maps Subscription Card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: hasSubscription && isActive
                  ? LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: hasSubscription && isActive ? null : colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: hasSubscription && isActive
                  ? null
                  : Border.all(
                      color: colorScheme.outline.withOpacity(0.15),
                      width: 1,
                    ),
              boxShadow: [
                BoxShadow(
                  color: hasSubscription && isActive
                      ? colorScheme.primary.withOpacity(0.3)
                      : colorScheme.shadow.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Satellite Preview Image
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasSubscription && isActive
                              ? Colors.white.withOpacity(0.3)
                              : colorScheme.outline.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.asset(
                          'assets/extras/satellite.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Satellite Maps',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: hasSubscription && isActive ? Colors.white : colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'High-resolution satellite imagery',
                            style: TextStyle(
                              fontSize: 14,
                              color: hasSubscription && isActive
                                  ? Colors.white.withOpacity(0.9)
                                  : colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasSubscription && isActive)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'ACTIVE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                
                if (!hasSubscription || !isActive) ...[
                  SizedBox(height: 16),
                  // Subscription Details
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Monthly Subscription',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            Text(
                              '\$4.99/month',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Auto-renews monthly. Cancel anytime.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withOpacity(0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isPurchasing ? null : _openCheckout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isPurchasing
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Subscribe',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: 12),
                  // Terms and Privacy Links
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: _openTermsOfUse,
                        child: Text(
                          'Terms of Use',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      Text(
                        ' • ',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                      GestureDetector(
                        onTap: _openPrivacyPolicy,
                        child: Text(
                          'Privacy Policy',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                
                if (hasSubscription && isActive) ...[
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: Colors.white.withOpacity(0.8),
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  autoRenew 
                                      ? 'Auto-renews: ${_formatDate(expiresAt)}'
                                      : 'Expires: ${_formatDate(expiresAt)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Container(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _openManageSubscription,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.2),
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Text(
                            'Manage',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required ColorScheme colorScheme,
    required bool isActive,
  }) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary.withOpacity(0.1)
                : colorScheme.outline.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isActive ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.4),
            size: 20,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? colorScheme.onSurface
                      : colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: isActive
                      ? colorScheme.onSurface.withOpacity(0.7)
                      : colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ),
        if (isActive)
          Icon(
            Icons.check_circle,
            color: colorScheme.primary,
            size: 20,
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: colorScheme.onSurface.withOpacity(0.4),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _openTermsOfUse() async {
    const url = 'https://mygrid.app/terms';
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    const url = 'https://mygrid.app/privacy';
    if (await canLaunch(url)) {
      await launch(url);
    }
  }
}