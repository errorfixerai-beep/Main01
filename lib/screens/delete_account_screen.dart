import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../providers/language_provider.dart';
import 'login_screen.dart';

/// Self-service account deletion — required by Google Play's Account
/// Deletion policy (any app that lets users create an account must offer an
/// in-app way to delete it, not just a "contact support" email link).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmCtrl = TextEditingController();
  bool _deleting = false;
  bool _understood = false;

  // Translation keys for each consequence line — resolved via context.tr()
  // in build() so this list follows the selected language.
  static const _consequenceKeys = [
    'delete_consequence_profile',
    'delete_consequence_videos',
    'delete_consequence_payment',
    'delete_consequence_connections',
    'delete_consequence_referral',
  ];

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _expectedConfirmText(Map<String, dynamic> user) {
    return (user['username'] ?? user['email'] ?? user['userId'] ?? 'DELETE').toString();
  }

  Future<void> _submitDelete(Map<String, dynamic> user) async {
    final expected = _expectedConfirmText(user);
    if (_confirmCtrl.text.trim() != expected) {
      showToast(context, context.tr('text_doesnt_match'), isError: true);
      return;
    }

    setState(() => _deleting = true);
    try {
      await ApiService.instance.deleteMyAccount();
      if (!mounted) return;
      await context.read<AuthProvider>().logout();
      if (!mounted) return;
      showToast(context, context.tr('account_permanently_deleted'), isSuccess: true);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? {};
    final expected = _expectedConfirmText(user);
    final canDelete = _understood && _confirmCtrl.text.trim() == expected && !_deleting;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('delete_account_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_rounded, color: AppColors.red, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('delete_permanent_warning'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.red),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text(context.tr('what_gets_deleted'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: context.surfaces.card2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.surfaces.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: _consequenceKeys.map((k) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.close_rounded, size: 16, color: AppColors.red),
                        const SizedBox(width: 10),
                        Expanded(child: Text(context.tr(k), style: const TextStyle(fontSize: 13.5))),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('delete_no_refund_note'),
              style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
            ),
            const SizedBox(height: 24),

            CheckboxListTile(
              value: _understood,
              onChanged: (v) => setState(() => _understood = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.red,
              title: Text(
                context.tr('delete_understand_checkbox'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),

            Text(context.tr('delete_type_to_confirm').replaceAll('%s', expected), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: context.surfaces.card2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.surfaces.border),
              ),
              child: TextField(
                controller: _confirmCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: expected,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canDelete ? () => _submitDelete(user) : null,
                icon: _deleting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.delete_forever, size: 18),
                label: Text(_deleting ? context.tr('deleting_ellipsis') : context.tr('delete_my_account_permanently')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _deleting ? null : () => Navigator.of(context).pop(),
                child: Text(context.tr('cancel_keep_account')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}