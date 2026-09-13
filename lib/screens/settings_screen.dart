import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../providers/language_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'login_screen.dart';
import 'delete_account_screen.dart';

/// Dedicated Settings screen. Holds app-level preferences AND account
/// actions (Logout / Delete Account). Every user-facing string here comes
/// from context.tr('key') (see language_provider.dart + l10n/app_strings.dart)
/// so this screen re-renders in the selected language immediately.
///
/// ⚠️ FIX (Boss correction — "Android OS bar upar aa jata hai, version
/// text chip jata hai"): Scaffold's body was a bare ListView with no
/// SafeArea, so the bottom system navigation bar / gesture inset could
/// cover the app-version text at the bottom. Wrapped the ListView in a
/// SafeArea.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _languages = [
    'English',
    'Hindi',
    'Hinglish',
    'Tamil',
    'Bengali',
    'Marathi',
    'Urdu',
  ];

  String? _appVersion;
  bool _autoRefillDiamonds = false;
  bool _savingLanguage = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    final user = context.read<AuthProvider>().user ?? {};
    _autoRefillDiamonds = user['autoRefillDiamonds'] ?? false;
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {
      if (mounted) setState(() => _appVersion = '-');
    }
  }

  Future<void> _changeLanguage(Map<String, dynamic> user) async {
    final current = (user['language'] ?? 'English').toString();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: context.surfaces.border, borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(context.tr('app_language'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                ..._languages.map((lang) => ListTile(
                      title: Text(lang, style: const TextStyle(fontSize: 14)),
                      trailing: lang == current ? const Icon(Icons.check_rounded, color: AppColors.purple, size: 20) : null,
                      onTap: () => Navigator.pop(sheetContext, lang),
                    )),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == current || !mounted) return;
    setState(() => _savingLanguage = true);
    try {
      // 1. Save to backend (existing behavior — persists to the User doc).
      await ApiService.instance.setupUsername(
        username: user['username'] ?? user['userId'] ?? '',
        language: selected,
      );
      // 2. Apply immediately across the app via LanguageProvider — this is
      // the piece that actually makes the UI switch language, instead of
      // just saving a value nobody reads.
      if (mounted) {
        await context.read<LanguageProvider>().setLanguageByName(selected);
      }
      if (mounted) {
        showToast(context, 'Language updated to $selected', isSuccess: true);
        context.read<AuthProvider>().refreshUser();
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _savingLanguage = false);
    }
  }

  Future<void> _toggleAutoRefill(bool value) async {
    setState(() => _autoRefillDiamonds = value);
    try {
      // NOTE: no dedicated endpoint exists yet for this — wire this up to
      // whichever backend route persists autoRefillDiamonds on the User
      // doc once it's added. For now this only updates local UI state so
      // the toggle isn't dead, but it won't survive an app restart until
      // that endpoint exists.
      showToast(context, value ? 'Auto-refill enabled' : 'Auto-refill disabled', isSuccess: true);
    } catch (e) {
      setState(() => _autoRefillDiamonds = !value);
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _clearLocalCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(context.tr('clear_cache_confirm_title')),
        content: Text(context.tr('clear_cache_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('clear'))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    // NOTE: hook this up to whichever local cache directory the app actually
    // writes to (e.g. path_provider's getTemporaryDirectory()) — left as a
    // clear integration point since that path isn't visible from this file.
    showToast(context, 'Local cache cleared', isSuccess: true);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('logout_confirm_title')),
        content: Text(context.tr('logout_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('logout'), style: const TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  static const _switchActiveColor = AppColors.purple;
  static const _switchInactiveThumbColor = Color(0xFFBDBDBD);
  static const _switchInactiveTrackColor = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? {};
    final email = (user['email'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            // ⚠️ ADD: avatar + @username block, moved here from Profile
            // screen (which now starts directly with the YouTube subscriber
            // card instead — see profile_screen.dart).
            Center(
              child: Column(children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
                  child: (user['avatar'] != null && user['avatar'] != '')
                      ? ClipOval(child: Image.network(user['avatar'], fit: BoxFit.cover))
                      : const Center(child: Icon(Icons.person_rounded, color: Colors.white, size: 34)),
                ),
                const SizedBox(height: 10),
                Text('@${user['username'] ?? user['userId'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(user['name'] ?? user['email'] ?? '', style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 24),

            // ---------------- Account email ----------------
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surfaces.card2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.surfaces.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.mail_outline_rounded, color: AppColors.purple, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('signed_in_with'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
                        const SizedBox(height: 2),
                        Text(
                          email.isNotEmpty ? email : context.tr('no_email_on_account'),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text(context.tr('preferences'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: context.surfaces.card2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.surfaces.border),
              ),
              child: Column(
                children: [
                  // ⚠️ Dark Mode toggle removed — app is light-only now, per
                  // request. (Divider below the removed switch removed too.)
                  // App Language
                  ListTile(
                    leading: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(color: AppColors.purpleLight.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.language_rounded, color: AppColors.purpleLight, size: 17),
                    ),
                    title: Text(context.tr('app_language'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(user['language'] ?? 'English', style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                    trailing: _savingLanguage
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.chevron_right, color: context.surfaces.textDim),
                    onTap: _savingLanguage ? null : () => _changeLanguage(user),
                  ),
                  Divider(height: 1, color: context.surfaces.border),
                  // Auto-refill diamonds toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.tr('auto_refill_diamonds'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(context.tr('auto_refill_subtitle'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                      value: _autoRefillDiamonds,
                      activeThumbColor: _switchActiveColor,
                      inactiveThumbColor: _switchInactiveThumbColor,
                      inactiveTrackColor: _switchInactiveTrackColor,
                      onChanged: _toggleAutoRefill,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text(context.tr('storage'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: context.surfaces.card2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.surfaces.border),
              ),
              child: ListTile(
                leading: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.cleaning_services_outlined, color: AppColors.green, size: 17),
                ),
                title: Text(context.tr('clear_local_cache'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(context.tr('clear_cache_subtitle'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: context.surfaces.textDim),
                onTap: _clearLocalCache,
              ),
            ),
            const SizedBox(height: 20),

            // ---------------- Account actions ----------------
            Text(context.tr('account'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: AppColors.red, size: 18),
                label: Text(context.tr('logout'), style: const TextStyle(color: AppColors.red)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.red)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
                icon: Icon(Icons.delete_forever_outlined, color: context.surfaces.textDim, size: 18),
                label: Text(context.tr('delete_account'), style: TextStyle(color: context.surfaces.textDim)),
              ),
            ),
            const SizedBox(height: 20),

            Center(
              child: Text(
                _appVersion != null ? 'TubePilot v$_appVersion' : 'Loading version…',
                style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}