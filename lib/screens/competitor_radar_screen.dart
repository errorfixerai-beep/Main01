import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';

class CompetitorRadarScreen extends StatefulWidget {
  const CompetitorRadarScreen({super.key});
  @override
  State<CompetitorRadarScreen> createState() => _CompetitorRadarScreenState();
}

class _CompetitorRadarScreenState extends State<CompetitorRadarScreen> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = true;
  bool _adding = false;
  List<Map<String, dynamic>> _competitors = [];
  String? _apiKeyError;

  // ---------------- Typeahead state ----------------
  Timer? _debounce;
  bool _searching = false;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _load();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        // small delay so a tap on a suggestion registers before we hide the list
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showSuggestions = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.instance.listCompetitors();
      final list = (res['competitors'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _competitors = list;
        _apiKeyError = list.isNotEmpty && list.every((c) => (c['lastStats']?['error'] ?? '').toString().contains('YOUTUBE_DATA_API_KEY'))
            ? list.first['lastStats']['error']
            : null;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------- Typeahead search (debounced) ----------------
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);
    try {
      final res = await ApiService.instance.searchCompetitors(query);
      final results = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _showSuggestions = true;
      });
    } catch (e) {
      if (mounted) setState(() => _showSuggestions = false);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addFromSuggestion(Map<String, dynamic> suggestion) async {
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
      _inputCtrl.clear();
    });
    _focusNode.unfocus();
    await _addCompetitor(
      channelId: suggestion['channelId'] as String?,
      label: suggestion['title'] as String?,
    );
  }

  Future<void> _addCompetitor({String? channelId, String? handle, String? label}) async {
    final input = _inputCtrl.text.trim();
    if (channelId == null && handle == null && input.isEmpty) return;
    setState(() => _adding = true);
    try {
      final isHandle = handle != null || input.startsWith('@');
      await ApiService.instance.addCompetitor(
        channelId: channelId ?? (isHandle ? null : (input.isNotEmpty ? input : null)),
        handle: handle ?? (isHandle ? (input.isNotEmpty ? input : null) : null),
        label: label,
      );
      _inputCtrl.clear();
      await _load();
      if (mounted) showToast(context, context.tr('radar_competitor_added_toast'), isSuccess: true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(String id) async {
    try {
      await ApiService.instance.deleteCompetitor(id);
      setState(() => _competitors.removeWhere((c) => c['_id'] == id));
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  String _fmt(num? n) {
    if (n == null) return '—';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final vphValues = _competitors
        .map((c) => (c['lastStats']?['vph'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final avgVph = vphValues.isEmpty ? 0.0 : vphValues.reduce((a, b) => a + b) / vphValues.length;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('radar_title'))),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.purple,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ---------------- Search + Add (with typeahead suggestions) ----------------
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _inputCtrl,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: context.tr('radar_search_hint'),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                  ),
                  onChanged: _onSearchChanged,
                  onFieldSubmitted: (_) => _addCompetitor(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _adding ? null : () => _addCompetitor(),
                  child: _adding
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_rounded),
                ),
              ),
            ]),

            // ---------------- Suggestions dropdown ----------------
            if (_showSuggestions && _suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: context.surfaces.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: context.surfaces.border),
                  itemBuilder: (_, i) {
                    final s = _suggestions[i];
                    final thumb = (s['thumbnail'] ?? '').toString();
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.purple.withValues(alpha: 0.14),
                        backgroundImage: thumb.isNotEmpty ? NetworkImage(thumb) : null,
                        child: thumb.isEmpty ? const Icon(Icons.person_rounded, color: AppColors.purple, size: 18) : null,
                      ),
                      title: Text(s['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      subtitle: Text(s['description'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
                      onTap: () => _addFromSuggestion(s),
                    );
                  },
                ),
              )
            else if (_showSuggestions && !_searching && _suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(context.tr('radar_no_channels_found'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
              ),

            const SizedBox(height: 20),
            if (_apiKeyError != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.08), border: Border.all(color: AppColors.red.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.tr('radar_api_key_error'), style: TextStyle(color: AppColors.red, fontSize: 12.5))),
                ]),
              ),
            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: LoadingView())
            else if (_competitors.isEmpty)
              EmptyView(message: context.tr('radar_empty_state'), icon: Icons.radar_rounded)
            else
              ..._competitors.map((c) {
                final stats = c['lastStats'] as Map<String, dynamic>? ?? {};
                final vph = (stats['vph'] as num?)?.toDouble();
                final isTrending = vph != null && avgVph > 0 && vph > avgVph * 2;
                final thumbnail = (stats['thumbnail'] ?? '').toString();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: isTrending ? AppColors.green.withValues(alpha: 0.5) : context.surfaces.border),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.purple.withValues(alpha: 0.14),
                          backgroundImage: thumbnail.isNotEmpty ? NetworkImage(thumbnail) : null,
                          child: thumbnail.isEmpty ? const Icon(Icons.person_rounded, color: AppColors.purple) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c['label'] ?? c['handle'] ?? c['channelId'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Text('${_fmt(stats['subscriberCount'] as num?)} ${context.tr('radar_subscribers_suffix')}', style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => _remove(c['_id']), icon: const Icon(Icons.close_rounded, size: 18)),
                      ]),
                      if (stats['error'] != null && !stats['error'].toString().contains('YOUTUBE_DATA_API_KEY')) ...[
                        const SizedBox(height: 8),
                        Text(stats['error'], style: const TextStyle(color: AppColors.red, fontSize: 11.5)),
                      ] else if (vph != null) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Icon(Icons.speed_rounded, size: 15, color: isTrending ? AppColors.green : context.surfaces.textDim),
                          const SizedBox(width: 5),
                          Text('${vph.toStringAsFixed(1)} VPH', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: isTrending ? AppColors.green : null)),
                          if (isTrending) ...[
                            const SizedBox(width: 8),
                            AppBadge(label: context.tr('radar_trending_badge'), color: AppColors.green),
                          ],
                        ]),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}