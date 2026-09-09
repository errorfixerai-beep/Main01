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

// ⚠️ FIX: previous version imported from `package:cashfree_pg/...` and
// declared `implements CFCallback` — neither is correct. The package that
// actually exposes CFPaymentGatewayService / CFSessionBuilder /
// CFDropCheckoutPaymentBuilder is `flutter_cashfree_pg_sdk` (see
// pubspec.yaml), and its own official examples never implement a
// CFCallback interface — setCallback() just takes two plain function
// references matching (String orderId) and (CFErrorResponse, String
// orderId). cfenums/cfexceptions also live under utils/, not api/.
class DiamondStoreScreen extends StatefulWidget {
  const DiamondStoreScreen({super.key});
  @override
  State<DiamondStoreScreen> createState() => _DiamondStoreScreenState();
}

class _DiamondStoreScreenState extends State<DiamondStoreScreen> {
  List<dynamic> packages = [];
  int balance = 0;
  bool loading = true;
  int? _payingDiamonds;
  // ⚠️ Read from the backend (GET /packages -> cashfreeEnvironment), NOT
  // hardcoded — this is what lets Play Store publishing be a pure backend
  // .env change (CASHFREE_ENV=PRODUCTION + live keys + restart) with zero
  // Flutter code changes or rebuilds required. Defaults to PRODUCTION as a
  // safe fallback if the field is ever missing from an older backend.
  CFEnvironment _cashfreeEnvironment = CFEnvironment.PRODUCTION;
  // ⚠️ FIX ("Buy fails to trigger payment screen"): doPayment() hands off
  // to the native Cashfree checkout Activity/ViewController and does NOT
  // await — control returns to _buy() immediately, and the actual result
  // only ever arrives via the _onVerify/_onError callbacks below. If the
  // native checkout UI fails to launch for any reason that doesn't throw
  // a catchable Dart exception (a real, observed class of native SDK
  // issues), NEITHER callback ever fires — and _payingDiamonds would stay
  // permanently non-null, which disables every "Buy" button on this
  // screen forever (exactly the "tapping Buy does nothing" symptom).
  // This timer is the safety net: if no callback has arrived within a
  // generous window, it force-resets the paying state and shows a
  // retryable error instead of leaving the screen silently stuck.
  Timer? _paymentTimeoutTimer;
  static const _paymentCallbackTimeout = Duration(seconds: 90);

  final CFPaymentGatewayService _cfPaymentGatewayService = CFPaymentGatewayService();

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
        // Backend reports 'SANDBOX' or 'PRODUCTION' — anything else/missing
        // safely falls back to PRODUCTION.
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

      // Session/payment object construction can throw CFException if a
      // required field is missing/invalid — caught here so a malformed
      // order response shows a normal error toast instead of crashing.
      try {
        final session = CFSessionBuilder()
            // Read from the backend (see _load() above) — never hardcoded,
            // so this always matches whichever keys the backend .env is
            // currently configured with.
            .setEnvironment(_cashfreeEnvironment)
            .setOrderId(orderId)
            .setPaymentSessionId(paymentSessionId)
            .build();

        final cfDropCheckoutPayment = CFDropCheckoutPaymentBuilder()
            .setSession(session)
            .build();

        _cfPaymentGatewayService.doPayment(cfDropCheckoutPayment);
        // Execution continues in _onVerify()/_onError() below once the
        // checkout screen closes — NOT here, doPayment() doesn't await.
        // Arm the timeout safety net (see field doc above).
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

  // Fired by the Cashfree SDK once checkout closes with what looks like a
  // successful payment. This is still just a client-side signal — the
  // actual credit only happens after our backend re-confirms directly with
  // Cashfree's server (see verify-payment route notes).
  void _onVerify(String orderId) {
    _paymentTimeoutTimer?.cancel();
    _confirmWithBackend(orderId);
  }

  // Fired on failure/cancel. Still asks the backend to check — a failure
  // callback can occasionally fire even when the payment actually
  // succeeded on Cashfree's side (e.g. the user backgrounded the app right
  // at the end of checkout), so this is not treated as automatic proof of
  // failure either.
  void _onError(CFErrorResponse errorResponse, String orderId) {
    _paymentTimeoutTimer?.cancel();
    _confirmWithBackend(orderId, sdkReportedError: errorResponse.getMessage());
  }

  // ⚠️ FIX: previously called verify-payment ONCE, right when checkout
  // closes — but Cashfree's own server can take a few seconds to mark the
  // order PAID even though the checkout sheet already closed successfully
  // on the phone. That race is exactly why "Payment is still processing"
  // was showing up on payments that had actually gone through fine — the
  // very first check just landed a moment too early.
  //
  // Fix: retry the same verify-payment call a few times with a short delay
  // between attempts (up to ~18s total) while status stays 'pending'. This
  // is safe to loop — verify-payment is idempotent on the backend. Only
  // shows the "still processing" message if it's STILL not resolved after
  // every retry.
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

        // status == 'pending' — wait and try again, unless this was the
        // last attempt.
        if (attempt < maxAttempts) {
          await Future.delayed(delayBetweenAttempts);
        }
      }

      // Exhausted every retry and it's still pending — genuinely slow on
      // Cashfree's side (or a webhook will catch it shortly). The backend
      // keeps checking too, so diamonds will still be credited
      // automatically once it resolves; this just stops polling here.
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
    // ⚠️ FIX (Payment Sheet Auto-Close Bug): the native Cashfree checkout
    // is launched via doPayment() as its own top-level UI, not a Flutter
    // showModalBottomSheet — so there's no in-tree modal a stray
    // Navigator.pop() could close. The equivalent risk on THIS screen is
    // the user's Android back gesture/button popping the whole
    // DiamondStoreScreen route while a payment is in flight (_payingDiamonds
    // != null), which would abandon the verify-payment polling loop before
    // it confirms. PopScope blocks that until payment finishes or fails —
    // matches the spec's "stays open until Close/Cancel or payment
    // completes" requirement for this screen's actual architecture.
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
        // Visible only when the backend is running in Sandbox — a plain,
        // hard-to-miss signal that no real money is involved right now.
        bottom: _cashfreeEnvironment == CFEnvironment.SANDBOX
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  width: double.infinity,
                  color: AppColors.red,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: const Text(
                    '⚠️ TEST MODE — Sandbox, no real payment',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              )
            : null,
      ),
      body: loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(20),
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
                const SizedBox(height: 14),
                // ⚠️ UPDATE (Boss request): changed from a single-row
                // horizontal scroll (which only showed 2 cards on screen at
                // once, e.g. 10 & 50, with 100 & 200 hidden off to the
                // side needing a swipe) to a 2-COLUMN GRID. Same card
                // template, same _buy()/_payingDiamonds logic per card —
                // only the layout changed, so ALL packages the backend
                // sends (10, 50, 100, 200, or any future ones) are visible
                // at once without scrolling sideways: 10 & 50 in the first
                // row, 100 & 200 in the second row, etc.
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: packages.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.79,
                  ),
                  itemBuilder: (context, index) {
                    final p = packages[index];
                    final diamonds = p['diamonds'] as int;
                    final isPaying = _payingDiamonds == diamonds;
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('💎', style: TextStyle(fontSize: 28)),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('diamonds_suffix').replaceAll('%d', '$diamonds'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text('₹${p['priceINR']}', style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                          const SizedBox(height: 10),
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
                    );
                  },
                ),
                const SizedBox(height: 24),
                // ⚠️ REMOVED (Boss request): "Have a Gift Code? Redeem it
                // here" used to link out to GiftCodeScreen from this
                // screen. Gift code redemption now lives on its own entry
                // point in Profile & Settings, so this card was removed
                // entirely to avoid a duplicate path into the same screen.
                _enterpriseCard(),
              ],
            ),
      ),
    );
  }

  // ⚠️ NEW (Boss request — "enterprises rakho"): static bulk/custom
  // diamonds card. The numbered packages above (₹10 / ₹50 / ₹100 / ₹200
  // etc.) come entirely from GET /diamonds/packages on the backend — this
  // card is intentionally NOT one of those, since a large custom/bulk
  // order isn't a fixed SKU. It just opens a contact channel instead of a
  // purchase flow.
  Widget _enterpriseCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
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
          TextButton(
            onPressed: () => showToast(context, context.tr('diamond_enterprise_toast')),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: Text(context.tr('diamond_enterprise_cta'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}