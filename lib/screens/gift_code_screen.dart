import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../providers/language_provider.dart';

// Extracted out of diamond_store_screen.dart into its own screen so gift
// code redemption isn't tied to the diamond purchase flow anymore — same
// logic, same API call (ApiService.redeemGiftCode), just living on its own
// route now (see profile_screen.dart, added right below "Buy Diamonds").
class GiftCodeScreen extends StatefulWidget {
  const GiftCodeScreen({super.key});
  @override
  State<GiftCodeScreen> createState() => _GiftCodeScreenState();
}

class _GiftCodeScreenState extends State<GiftCodeScreen> {
  final _giftCodeCtrl = TextEditingController();
  bool _redeemingGiftCode = false;

  @override
  void dispose() {
    _giftCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _redeemGiftCode() async {
    final code = _giftCodeCtrl.text.trim();
    if (code.isEmpty) {
      showToast(context, context.tr('gift_code_empty_error'), isError: true);
      return;
    }
    setState(() => _redeemingGiftCode = true);
    try {
      final res = await ApiService.instance.redeemGiftCode(code);
      _giftCodeCtrl.clear();
      if (mounted) showToast(context, res['message'] ?? context.tr('gift_code_success_default'), isSuccess: true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _redeemingGiftCode = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('gift_code_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ⚠️ FIX (Boss request — "bada sa plum background hata do, isko
          // transparent karo"): was a solid AppColors.gradient header
          // band with white text. Swapped to the app's neutral
          // bordered-card style (card2 + border), icon in a soft
          // purple-tinted rounded square, heading/body in normal text
          // colors. Same _redeemGiftCode() logic, same "How it works"
          // steps and footer note below — untouched.
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.surfaces.card2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.surfaces.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.card_giftcard_rounded, color: AppColors.purple, size: 26),
                ),
                const SizedBox(height: 14),
                Text(context.tr('gift_code_header'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  context.tr('gift_code_description'),
                  style: TextStyle(color: context.surfaces.textDim, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: context.surfaces.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _giftCodeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(hintText: context.tr('gift_code_hint')),
                  onSubmitted: (_) => _redeemGiftCode(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _redeemingGiftCode ? null : _redeemGiftCode,
                  child: _redeemingGiftCode
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(context.tr('gift_code_redeem_btn')),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text(context.tr('gift_code_how_it_works'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                _stepRow(context, 1, context.tr('gift_code_step1')),
                Divider(height: 1, color: context.surfaces.border),
                _stepRow(context, 2, context.tr('gift_code_step2')),
                Divider(height: 1, color: context.surfaces.border),
                _stepRow(context, 3, context.tr('gift_code_step3')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: context.surfaces.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(context.tr('gift_code_note'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepRow(BuildContext context, int step, String text) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
            child: Text('$step', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}