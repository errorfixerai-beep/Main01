import 'dart:async';
import 'package:flutter/material.dart';
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

/// Day Pass aur Month Pass dono ek hi screen mein, tab switcher ke saath.
/// Diamond Store screen (diamond_store_screen.dart) jaisa hi structure aur
/// design pattern follow karta hai — same Cashfree checkout flow, same
/// card style, taaki poori app mein UI consistent lage.
class LivePlansScreen extends StatefulWidget {
  const LivePlansScreen({super.key});
  @override
  State<LivePlansScreen> createState() => _LivePlansScreenState();
}

class _LivePlansScreenState extends State<LivePlansScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<dynamic> dayPasses = [];
  List<dynamic> monthPasses = [];
  bool loading = true;
  bool freeTrialUsed = false;
  Map<String, dynamic>? currentPlan;
  String? _payingPlanName;
  CFEnvironment _cashfreeEnvironment = CFEnvironment.PRODUCTION;
  Timer? _paymentTimeoutTimer;
  static const _paymentCallbackTimeout = Duration(seconds: 90);

  final CFPaymentGatewayService _cfPaymentGatewayService = CFPaymentGatewayService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cfPaymentGatewayService.setCallback(_onVerify, _onError);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _paymentTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await ApiService.instance.getLivePlans();
      setState(() {
        dayPasses = res['dayPasses'] ?? [];
        monthPasses = res['monthPasses'] ?? [];
        freeTrialUsed = res['freeTrialUsed'] ?? false;
        currentPlan = res['currentPlan'];
        _cashfreeEnvironment =
            (res['cashfreeEnvironment'] == 'SANDBOX') ? CFEnvironment.SANDBOX : CFEnvironment.PRODUCTION;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _buy(String category, String planName) async {
    if (_payingPlanName != null) return;
    setState(() => _payingPlanName = planName);
    try {
      final res = await ApiService.instance.createLivePlanOrder(category: category, planName: planName);
      final orderId = res['orderId'] as String;
      final paymentSessionId = res['paymentSessionId'] as String;

      try {
        final session = CFSessionBuilder()
            .setEnvironment(_cashfreeEnvironment)
            .setOrderId(orderId)
            .setPaymentSessionId(paymentSessionId)
            .build();

        final cfDropCheckoutPayment = CFDropCheckoutPaymentBuilder().setSession(session).build();

        _cfPaymentGatewayService.doPayment(cfDropCheckoutPayment);
        _paymentTimeoutTimer?.cancel();
        _paymentTimeoutTimer = Timer(_paymentCallbackTimeout, () {
          if (!mounted || _payingPlanName == null) return;
          setState(() => _payingPlanName = null);
          showToast(context, 'Checkout didn\'t open — please check your connection and try again.', isError: true);
        });
      } on CFException catch (e) {
        if (mounted) {
          setState(() => _payingPlanName = null);
          showToast(context, e.message ?? 'Could not open checkout.', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _payingPlanName = null);
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
        final res = await ApiService.instance.verifyLivePlanPayment(orderId);
        final status = res['status'];

        if (status == 'approved') {
          if (mounted) {
            showToast(context, 'Live plan activated! 🎉', isSuccess: true);
            _load();
          }
          return;
        }
        if (status == 'rejected') {
          if (mounted) showToast(context, sdkReportedError ?? 'Payment was not completed.', isError: true);
          return;
        }
        if (attempt < maxAttempts) await Future.delayed(delayBetweenAttempts);
      }
      if (mounted) {
        showToast(context, 'Payment is taking longer than usual — it will activate automatically once confirmed.', isError: false);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      _paymentTimeoutTimer?.cancel();
      if (mounted) setState(() => _payingPlanName = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _payingPlanName == null,
      onPopInvoked: (didPop) {
        if (!didPop && _payingPlanName != null) {
          showToast(context, 'Please wait — confirming your payment...', isError: false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live Streaming Plans'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Day Pass'), Tab(text: 'Monthly Pass')],
          ),
        ),
        body: loading
            ? const LoadingView()
            : SafeArea(
                bottom: true,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPlanList('day', dayPasses),
                    _buildPlanList('month', monthPasses),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPlanList(String category, List<dynamic> plans) {
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 24),
      children: [
        if (!freeTrialUsed) _freeTrialBanner(),
        if (currentPlan != null && currentPlan!['planCategory'] != 'none') _currentPlanBanner(),
        const SizedBox(height: 10),
        ...List.generate(
          plans.length,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _planCard(category, plans[index], isPopular: index == (plans.length / 2).floor()),
          ),
        ),
      ],
    );
  }

  Widget _freeTrialBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard_rounded, color: AppColors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Aapka 5-minute FREE trial abhi tak use nahi hua — koi bhi video select karke try karein!',
              style: TextStyle(fontSize: 12.5, color: context.surfaces.textDim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentPlanBanner() {
    final planName = currentPlan!['planName'] ?? '';
    final allottedSec = (currentPlan!['hoursAllottedSeconds'] ?? 0) as int;
    final usedSec = (currentPlan!['hoursUsedSeconds'] ?? 0) as int;
    final remainingHours = ((allottedSec - usedSec) / 3600).clamp(0, double.infinity);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.podcasts_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active Plan: $planName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 2),
                Text('${remainingHours.toStringAsFixed(1)} hours remaining', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(String category, dynamic plan, {required bool isPopular}) {
    final name = plan['name'] as String;
    final price = plan['priceINR'] as int;
    final hours = plan['hours'] as int;
    final isPaying = _payingPlanName == name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: isPopular ? AppColors.purple : context.surfaces.border,
          width: isPopular ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isPopular)
            Positioned(
              top: -22,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(999)),
                  child: const Text('POPULAR', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // ⚠️ CHANGED: pehle yahan 📡 emoji tha (dish antenna jaisa). Ab Live Stream ka asli icon —
                  // wahi icon jo Dashboard ke Quick Actions mein "Live Stream" button par hai.
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.podcasts_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                        const SizedBox(height: 2),
                        Text('₹$price', style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: context.surfaces.border),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 15, color: AppColors.green),
                  const SizedBox(width: 8),
                  Text(
                    category == 'day' ? '$hours hours (usi din tak)' : '$hours hours / month',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.video_settings_rounded, size: 15, color: AppColors.green),
                  const SizedBox(width: 8),
                  const Text('Max 2GB video size', style: TextStyle(fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _payingPlanName != null ? null : () => _buy(category, name),
                  child: isPaying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Buy Now'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}