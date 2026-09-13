import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfdropcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../providers/language_provider.dart';

// ⚠️ FIX: previous version imported from `package:cashfree_pg/...` and
// declared `implements CFCallback` — neither is correct. The package that
// actually exposes CFPaymentGatewayService / CFSessionBuilder /
// CFDropCheckoutPaymentBuilder is `flutter_cashfree_pg_sdk` (see
// pubspec.yaml), and its own official examples never implement a
// CFCallback interface — setCallback() just takes two plain function
// references matching (String orderId) and (CFErrorResponse, String
// orderId). cfenums/cfexceptions also live under utils/, not api/.
//
// ⚠️ BOSS UPDATE:
// 1. Removed the "TEST MODE — Sandbox" banner entirely. Backend already
//    switches live/sandbox purely via its own .env (CASHFREE_ENV) — no
//    frontend rebuild needed either way.
// 2. Package cards upgraded: badges (Popular / Best Value), a feature
//    checklist line, and a "diamonds per ₹1" value line.
// 3. Pricing lives entirely on the backend (this screen only renders
//    whatever GET /diamonds/packages returns).
// 4. Enterprise card upgraded with a feature list + support email.
// 5. FIX ("BOTTOM OVERFLOWED BY 30/31 PIXELS"): switched from a 2-column
//    GridView with a fixed childAspectRatio to a single-column list of
//    full-width cards with no fixed height.
// 6. Every package card lists the app-wide AI/creator tools included.
//
// ⚠️ FIX (this revision — Boss request: "niche button Android OS ke
// bujjton ke peeche dab raha hai, scrollable banao"): wrapped the body in
// SafeArea(bottom: true) AND added the device's actual system
// navigation-bar height (MediaQuery.of(context).padding.bottom) as extra
// bottom padding on top of the usual 20px — so the last card (Enterprise)
// always scrolls fully clear of a gesture bar or 3-button nav on every
// device, not just ones with a small nav bar.
class DiamondStoreScreen extends StatefulWidget {
  const DiamondStoreScreen({super.key});
  @override
  State<DiamondStoreScreen> createState() => _DiamondStoreScreenState();
}

class _DiamondStoreScreenState extends State<DiamondStoreScreen> {
  static const String supportEmail = 'support@tubepilot.com';

  List<dynamic> packages = [];
  int balance = 0;
  bool loading = true;
  int? _payingDiamonds;
  CFEnvironment _cashfreeEnvironment = CFEnvironment.PRODUCTION;
  Timer? _paymentTimeoutTimer;
  static const _paymentCallbackTimeout = Duration(seconds: 90);

  final CFPaymentGatewayService _cfPaymentGatewayService = CFPaymentGatewayService();

  Future<void> _openSupportEmail() async {
    final uri = Uri(scheme: 'mailto', path: supportEmail);
    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      showToast(context, context.tr('diamond_support_error'), isError: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _cfPaymentGatewayService.setCallback(_onVerify, _onError);
    _load();
  }

  @override
  void dispose() {
    _paymentTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final pkgRes = await ApiService.instance.getDiamondPackages();
      setState(() {
        packages = pkgRes['packages'];
        balance = pkgRes['currentBalance'] ?? 0;
        _cashfreeEnvironment = (pkgRes['cashfreeEnvironment'] == 'SANDBOX')
            ? CFEnvironment.SANDBOX
            : CFEnvironment.PRODUCTION;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _buy(int diamonds) async {
    if (_payingDiamonds != null) return;
    setState(() => _payingDiamonds = diamonds);
    try {
      final res = await ApiService.instance.createCashfreeOrder(diamonds);
      final orderId = res['orderId'] as String;
      final paymentSessionId = res['paymentSessionId'] as String;

      try {
        final session = CFSessionBuilder()
            .setEnvironment(_cashfreeEnvironment)
            .setOrderId(orderId)
            .setPaymentSessionId(paymentSessionId)
            .build();

        final cfDropCheckoutPayment = CFDropCheckoutPaymentBuilder()
            .setSession(session)
            .build();

        _cfPaymentGatewayService.doPayment(cfDropCheckoutPayment);
        _paymentTimeoutTimer?.cancel();
        _paymentTimeoutTimer = Timer(_paymentCallbackTimeout, () {
          if (!mounted || _payingDiamonds == null) return;
          setState(() => _payingDiamonds = null);
          showToast(context, 'Checkout didn\'t open — please check your connection and try again.', isError: true);
        });
      } on CFException catch (e) {
        if (mounted) {
          setState(() => _payingDiamonds = null);
          showToast(context, e.message ?? 'Could not open checkout.', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _payingDiamonds = null);
        showApiError(context, e);
      }
    }
  }

  void _onVerify(String orderId) {
    _paymentTimeoutTimer?.cancel();
    _confirmWithBackend(orderId);
  }

  void _onError(CFErrorResponse errorResponse, String orderId) {
    _paymentTimeoutTimer?.cancel();
    _confirmWithBackend(orderId, sdkReportedError: errorResponse.getMessage());
  }

  Future<void> _confirmWithBackend(String orderId, {String? sdkReportedError}) async {
    const maxAttempts = 6;
    const delayBetweenAttempts = Duration(seconds: 3);

    try {
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        final res = await ApiService.instance.verifyCashfreePayment(orderId);
        final status = res['status'];

        if (status == 'approved') {
          if (mounted) {
            showToast(context, context.tr('payment_submitted_msg'), isSuccess: true);
            _load();
          }
          return;
        }

        if (status == 'rejected') {
          if (mounted) showToast(context, sdkReportedError ?? 'Payment was not completed.', isError: true);
          return;
        }

        if (attempt < maxAttempts) {
          await Future.delayed(delayBetweenAttempts);
        }
      }

      if (mounted) {
        showToast(context, 'Payment is taking a bit longer than usual — it will be credited automatically once confirmed.', isError: false);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      _paymentTimeoutTimer?.cancel();
      if (mounted) setState(() => _payingDiamonds = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _payingDiamonds == null,
      onPopInvoked: (didPop) {
        if (!didPop && _payingDiamonds != null) {
          showToast(context, 'Please wait — confirming your payment...', isError: false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('diamond_store_title')),
        ),
        body: loading
            ? const LoadingView()
            : SafeArea(
                bottom: true,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(context.tr('your_balance'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                        Text('💎 $balance', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text(context.tr('choose_package'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('diamond_store_description'),
                      style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(
                      packages.length,
                      (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _packageCard(context, index),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _enterpriseCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _packageCard(BuildContext context, int index) {
    final p = packages[index];
    final diamonds = p['diamonds'] as int;
    final price = (p['priceINR'] as num).toDouble();
    final isPaying = _payingDiamonds == diamonds;
    final perRupee = price > 0 ? (diamonds / price) : 0;

    String? badgeText;
    Color? badgeColor;
    if (packages.length >= 3) {
      if (index == packages.length - 1) {
        badgeText = context.tr('diamond_badge_best_value');
        badgeColor = AppColors.green;
      } else if (index == 1) {
        badgeText = context.tr('diamond_badge_popular');
        badgeColor = Theme.of(context).colorScheme.primary;
      }
    }

    final facilityKeys = [
      'diamond_feature_ai_title',
      'diamond_feature_ai_description',
      'diamond_feature_thumbnail_prompt',
      'diamond_feature_score_analysis',
      'diamond_feature_competitor_analysis',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
      decoration: BoxDecoration(
        border: Border.all(color: badgeText != null ? (badgeColor ?? context.surfaces.border) : context.surfaces.border, width: badgeText != null ? 1.4 : 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (badgeText != null)
            Positioned(
              top: -22,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    badgeText.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  ),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('💎', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('diamonds_suffix').replaceAll('%d', '$diamonds'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                        ),
                        const SizedBox(height: 2),
                        Text('₹${p['priceINR']}', style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (perRupee > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        context.tr('diamond_value_rate').replaceAll('%d', perRupee.toStringAsFixed(1)),
                        style: TextStyle(color: context.surfaces.textDim, fontSize: 10.5, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: context.surfaces.border),
              const SizedBox(height: 12),
              Text(
                context.tr('diamond_whats_included'),
                style: TextStyle(color: context.surfaces.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.2),
              ),
              const SizedBox(height: 8),
              ...facilityKeys.map((key) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr(key),
                            style: const TextStyle(fontSize: 12.5, height: 1.25),
                          ),
                        ),
                      ],
                    ),
                  )),
              Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: AppColors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('diamond_feature_instant'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _payingDiamonds != null ? null : () => _buy(diamonds),
                  child: isPaying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(context.tr('buy_btn')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _enterpriseCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _openSupportEmail,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.workspaces_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('diamond_enterprise_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(context.tr('diamond_enterprise_subtitle'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                      Text(context.tr('diamond_enterprise_cta'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _enterpriseFeatureRow(context.tr('diamond_enterprise_feature_1')),
                const SizedBox(height: 6),
                _enterpriseFeatureRow(context.tr('diamond_enterprise_feature_2')),
                const SizedBox(height: 6),
                _enterpriseFeatureRow(context.tr('diamond_enterprise_feature_3')),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app_rounded, color: Colors.white70, size: 13),
                const SizedBox(width: 6),
                Text(
                  context.tr('diamond_support_title'),
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _enterpriseFeatureRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
      ],
    );
  }
}