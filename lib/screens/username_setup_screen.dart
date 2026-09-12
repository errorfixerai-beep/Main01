import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart' as custom_tabs;
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/language_provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/custom_dropdown.dart';
import '../widgets/app_brand_background.dart';
import 'dashboard_screen.dart';

class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});
  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  final _usernameCtrl = TextEditingController();
  String _language = 'English';
  bool _loading = false;

  // NOTE: kept as language NAMES (not translated) since this list is sent
  // to the backend as-is and also drives ApiService.setupUsername(language: ...).
  final _languages = const ['English', 'Hindi', 'Hinglish', 'Tamil', 'Bengali', 'Marathi', 'Urdu'];

  @override
  void initState() {
    super.initState();
    _prefillSuggestedUsername();
  }

  void _prefillSuggestedUsername() {
    final user = context.read<AuthProvider>().user ?? {};
    String base = (user['name'] ?? '').toString().trim();
    if (base.isEmpty) {
      final email = (user['email'] ?? '').toString();
      base = email.contains('@') ? email.split('@').first : 'creator';
    }
    base = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (base.length < 3) base = 'creator';
    if (base.length > 15) base = base.substring(0, 15);
    final suffix = (DateTime.now().millisecondsSinceEpoch % 900 + 100).toString();
    _usernameCtrl.text = '${base}_$suffix';
  }

  // ⚠️ FIX (Boss request): language picker now opens as a bottom sheet
  // (drag handle + title + tick on selected item) instead of the old
  // top-overlay DropdownButtonFormField menu — same visual pattern as the
  // "Select Platform" sheet already used elsewhere in the app.
  Future<void> _openLanguageSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(context.tr('select_language_label'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 8),
                ..._languages.map((lang) => ListTile(
                      title: Text(lang, style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: lang == _language ? const Icon(Icons.check_rounded, color: AppColors.purple) : null,
                      onTap: () => Navigator.pop(sheetContext, lang),
                    )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _language = selected);
    }
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim().replaceFirst('@', '');
    if (username.length < 3) {
      showToast(context, context.tr('username_min_length_error'), isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AuthProvider>().setupUsername(username: username, language: _language);
      if (!mounted) return;
      await _showWelcomeFlow();
    } catch (e) {
      showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showReferralDialog() async {
    final referralCtrl = TextEditingController();
    bool submitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(context.tr('referral_dialog_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('referral_dialog_body')),
              const SizedBox(height: 14),
              TextField(
                controller: referralCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'e.g. 102458XK9F2'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: Text(context.tr('skip')),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final code = referralCtrl.text.trim();
                      if (code.isEmpty) {
                        Navigator.pop(dialogContext);
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        final res = await ApiService.instance.applyReferralCode(code);
                        if (mounted) showToast(context, res['message'] ?? context.tr('referral_applied'), isSuccess: true);
                      } catch (e) {
                        if (mounted) showApiError(context, e);
                      } finally {
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      }
                    },
              child: submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('apply')),
            ),
          ],
        ),
      ),
    );
  }

  // Same Custom Tabs launcher profile_screen.dart's _launchOAuth() uses —
  // kept consistent so every OAuth entry point in the app (Settings/Profile
  // connect AND this first-run popup) opens the same in-app browser sheet
  // instead of switching to an external browser app.
  Future<void> _launchOAuth(String url) async {
    await custom_tabs.launchUrl(
      Uri.parse(url),
      customTabsOptions: custom_tabs.CustomTabsOptions(
        shareState: custom_tabs.CustomTabsShareState.off,
        urlBarHidingEnabled: true,
        showTitle: true,
      ),
      safariVCOptions: const custom_tabs.SafariViewControllerOptions(
        barCollapsingEnabled: true,
        dismissButtonStyle: custom_tabs.SafariViewControllerDismissButtonStyle.close,
      ),
    );
  }

  // ⚠️ NEW (Boss request — "welcome pop ke baad channel connect ka pop
  // aaye aur bagal me skip ka option"): shown right after the welcome
  // dialog. "Connect" kicks off the same YouTube OAuth flow used
  // elsewhere in the app (GET /youtube/oauth/url -> Custom Tabs, same as
  // profile_screen.dart's _connectYoutube); "Skip" just closes it — either
  // way the flow continues to the idea popup next.
  Future<void> _showChannelConnectDialog() async {
    bool connecting = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            const Icon(Icons.link_rounded, color: AppColors.purple, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr('channel_connect_dialog_title'))),
          ]),
          content: Text(context.tr('channel_connect_dialog_body')),
          actions: [
            TextButton(
              onPressed: connecting ? null : () => Navigator.pop(dialogContext),
              child: Text(context.tr('skip')),
            ),
            ElevatedButton(
              onPressed: connecting
                  ? null
                  : () async {
                      setDialogState(() => connecting = true);
                      try {
                        final res = await ApiService.instance.getYoutubeOAuthUrl();
                        final url = res['url'] as String?;
                        if (url != null) {
                          await _launchOAuth(url);
                        }
                      } catch (e) {
                        if (mounted) showApiError(context, e);
                      } finally {
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      }
                    },
              child: connecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('connect_channel_btn')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWelcomeFlow() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Icon(Icons.celebration_rounded, color: AppColors.purple, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(context.tr('welcome_title'))),
        ]),
        content: Text(context.tr('welcome_body')),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('lets_go'))),
        ],
      ),
    );
    if (!mounted) return;

    await _showReferralDialog();
    if (!mounted) return;

    // ⚠️ NEW — Channel Connect step, added between Referral and the Idea
    // popup per Boss's flow: Referral -> Welcome -> Channel Connect (+Skip)
    // -> Idea popup -> Dashboard.
    await _showChannelConnectDialog();
    if (!mounted) return;

    // Channel category isn't known synchronously here (connecting happens
    // in an external browser tab, so there's no channel data back yet) —
    // the popup falls back to a generic niche this one time. The
    // dashboard's 24-hour recheck (see dashboard_screen.dart) will use the
    // real connected channel's category for every subsequent refresh.
    await showIdeaPopup(context);
    if (!mounted) return;

    // Stamp "now" as the last-shown time so the dashboard doesn't
    // immediately show a second idea popup right after this one.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kIdeasPopupLastShownKey, DateTime.now().millisecondsSinceEpoch);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final avatar = auth.user?['avatar'];

    return Scaffold(
      // ⚠️ FIX (Boss request): same off-white base + watermark as Splash,
      // for a modern/consistent look on the profile setup step.
      backgroundColor: const Color(0xFFFAF7FC),
      body: AppBrandBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),
                Text(context.tr('setup_profile_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 82, height: 82,
                    decoration: BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
                    child: avatar != null && avatar.toString().isNotEmpty
                        ? ClipOval(child: Image.network(avatar, fit: BoxFit.cover))
                        : const Center(child: Icon(Icons.person_rounded, color: Colors.white, size: 36)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(context.tr('username_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                const SizedBox(height: 4),
                Text(context.tr('username_suggested_hint'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
                const SizedBox(height: 6),
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(hintText: '@tech_creator', prefixIcon: Icon(Icons.alternate_email_rounded, size: 18)),
                ),
                const SizedBox(height: 16),
                Text(context.tr('select_language_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                const SizedBox(height: 6),
                // ⚠️ FIX: bottom-sheet PickerField instead of CustomDropdown.
                PickerField(
                  value: _language,
                  onTap: _openLanguageSheet,
                  prefixIcon: const Icon(Icons.language_rounded, size: 18, color: AppColors.purple),
                ),
                const SizedBox(height: 30),
                GradientButton(label: context.tr('continue_btn'), loading: _loading, onPressed: _save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
