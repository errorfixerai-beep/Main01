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
// ⚠️ BOSS UPDATE (this revision):
// 1. Removed the "TEST MODE — Sandbox" banner entirely. Backend already
//    switches live/sandbox purely via its own .env (CASHFREE_ENV) — no
//    frontend rebuild needed either way — so a permanent on-screen banner
//    isn't required any more; the app just quietly uses whatever
//    environment the backend reports.
// 2. Package cards upgraded: badges (Popular / Best Value), a feature
//    checklist line, and a "diamonds per ₹1" value line so the user can
//    actually see what they're getting, not just a bare price.
// 3. Pricing (₹10→99, ₹50→299, ₹100→599, ₹200→799) lives on the BACKEND
//    (this screen only renders whatever GET /diamonds/packages returns) —
//    see the note at the bottom of this file for what needs to change
//    server-side.
// 4. Enterprise card upgraded with a feature list + support email.
//
// ⚠️ BOSS UPDATE (THIS revision — bottom-overflow fix + facility list):
// 5. FIX: the 2-column GridView with a fixed childAspectRatio was the
//    root cause of "BOTTOM OVERFLOWED BY 30/31 PIXELS" — a fixed aspect
//    ratio gives every card the same locked height regardless of how much
//    text is inside it, so adding more lines (the new facility checklist
//    below) would only have made the overflow worse, not better. Switched
//    from a 2-column GridView to a single-column list of FULL-WIDTH cards
//    with no fixed height — each card is free to grow as tall as its
//    content needs (Column with mainAxisSize.min), and the screen's outer
//    ListView already scrolls, so a taller card just means more scrolling,
//    never an overflow.
// 6. Every package card now lists the app-wide AI/creator tools included
//    with ANY diamond purchase — AI Title Generation, AI Description
//    Generation, Thumbnail Prompt Copy, SEO/Score Analysis, Competitor
//    Analysis — not just the generic "Instant credit" line from before.
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
  // ⚠️ Read from the backend (GET /packages -> cashfreeEnvironment), NOT
  // hardcoded — this is what lets Play Store publishing be a pure backend
  // .env change (CASHFREE_ENV=PRODUCTION + live keys + restart) with zero
  // Flutter code changes or rebuilds required. Defaults to PRODUCTION as a
  // safe fallback if the field is ever missing from an older backend.
  // (Kept — still needed to build the correct CFSessionBuilder environment
  // — only the on-screen "TEST MODE" banner that used to read this was
  // removed per boss's request.)
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

  // ⚠️ BOSS UPDATE: tapping the enterprise card now opens the device's
  // email app directly (via mailto:) addressed to support@tubepilot.com —
  // the address itself is never shown as visible text anywhere on this
  // screen, only used inside this link.
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
        // Backend reports 'SANDBOX' or 'PRODUCTION' — anything else/missing
        // safely falls back to PRODUCTION. Still used for CFSessionBuilder
        // below even though we no longer show a banner for it.
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
        // ⚠️ BOSS UPDATE: removed the SANDBOX "TEST MODE" bottom banner
        // that used to live here. Backend controls live vs sandbox purely
        // via its own .env — no frontend indicator needed, and no
        // frontend change needed when boss flips the backend to live keys.
        appBar: AppBar(
          title: Text(context.tr('diamond_store_title')),
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
                  const SizedBox(height: 16),
                  // ⚠️ FIX: was a 2-column GridView with a fixed
                  // childAspectRatio (the actual cause of the pixel
                  // overflow — a locked-height cell can't grow to fit more
                  // text). Now a single-column list of full-width cards
                  // with no fixed height, each wrapped in its own
                  // SizedBox+margin instead of a grid cell — every card is
                  // free to be as tall as its content (including the new
                  // facility checklist) needs, and the screen already
                  // scrolls (outer ListView), so a taller card just scrolls
                  // further instead of overflowing.
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
    );
  }

  // ⚠️ UPGRADED CARD — now full-width (no more grid aspect-ratio
  // constraint) and lists every AI/creator tool included with any diamond
  // purchase, not just a generic "instant credit" line. Same
  // border/color/radius language as before — only the layout (full width,
  // free height) and the content (facility list) changed.
  Widget _packageCard(BuildContext context, int index) {
    final p = packages[index];
    final diamonds = p['diamonds'] as int;
    final price = (p['priceINR'] as num).toDouble();
    final isPaying = _payingDiamonds == diamonds;
    final perRupee = price > 0 ? (diamonds / price) : 0;

    // Simple, robust badge logic: with 3+ packages, tag the second-cheapest
    // as "Popular" and the most expensive as "Best Value". Doesn't break
    // if the backend ever ships fewer/more packages — badges just don't
    // show.
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

    // ⚠️ NEW — the "what every purchase unlocks" checklist Boss asked for,
    // shown on every single package card (not gated per-tier). Uses new
    // translation keys (diamond_feature_ai_title /
    // diamond_feature_ai_description / diamond_feature_thumbnail_prompt /
    // diamond_feature_score_analysis / diamond_feature_competitor_analysis)
    // — these need to be added to the app's language/translation files,
    // which weren't part of what was shared with me. Send those over and
    // I'll add the actual translated strings for every supported language;
    // for now context.tr() will just fall back to showing the raw key if
    // it's missing.
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
              // ---- Top row: diamonds + price side by side (full-width
              // layout gives room for this instead of a stacked/centered
              // block) ----
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

              // ---- Facility checklist — same tools on every card ----
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

  // ⚠️ UPGRADED (Boss request — "enterprise wale card ko bhi upgrade karo,
  // gmail lagao"): same gradient/color as before (AppColors.gradient) —
  // just more information: a short feature list plus a tappable support
  // email row. No new package for it — this stays a "contact us" card,
  // not a purchase flow, same as before.
  Widget _enterpriseCard() {
    // ⚠️ BOSS UPDATE: the whole card is now one tap target that opens the
    // device's email app (mailto:) straight to support@tubepilot.com. The
    // CTA button no longer just shows a toast — it (and tapping anywhere
    // else on the card) opens Gmail/Mail app directly. The email address
    // itself is never printed as visible text anywhere on this card, or
    // anywhere else on this screen.
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

// ─────────────────────────────────────────────────────────────────────────
// ⚠️ BOSS — BACKEND UPDATE STILL NEEDED (I don't have that file yet):
//
// This screen never hardcodes prices — it just renders whatever
// GET /diamonds/packages sends back (see `packages = pkgRes['packages']`
// in _load() above). So to make the new pricing live:
//   ₹10  → 99 diamonds
//   ₹50  → 299 diamonds
//   ₹100 → 599 diamonds
//   ₹200 → 799 diamonds
// you only need to edit the backend route/config that defines that
// packages array (likely something like routes/diamonds.js or a
// config/packages file) — zero Flutter changes needed for that part.
//
// Please send me that backend file/path and I'll update the numbers
// there too.
//
// ⚠️ ALSO NEEDED — translation keys for the new facility checklist lines
// used above (diamond_feature_ai_title, diamond_feature_ai_description,
// diamond_feature_thumbnail_prompt, diamond_feature_score_analysis,
// diamond_feature_competitor_analysis, diamond_whats_included). Send me
// wherever your other `diamond_*` keys are defined (LanguageProvider /
// your translations json/arb files) and I'll add these alongside them for
// every language the app supports.
// ─────────────────────────────────────────────────────────────────────────