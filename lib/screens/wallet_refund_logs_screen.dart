import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import 'diamond_store_screen.dart';

/// Screen 7/7 — a focused view over the existing GET /api/wallet data,
/// isolating auto-refund entries the way the spec describes (full
/// transaction history — purchases, spends, everything else — still lives
/// in wallet_screen.dart; this screen is the refund-focused counterpart).
class WalletRefundLogsScreen extends StatefulWidget {
  const WalletRefundLogsScreen({super.key});
  @override
  State<WalletRefundLogsScreen> createState() => _WalletRefundLogsScreenState();
}

class _WalletRefundLogsScreenState extends State<WalletRefundLogsScreen> {
  Map<String, dynamic>? _wallet;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.instance.getWallet();
      setState(() => _wallet = res['wallet']);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '');
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final all = (_wallet?['transactions'] as List?) ?? [];
    final refunds = all.where((t) => t['type'] == 'diamond_refund').toList();
    final balance = _wallet?['diamondBalance'] ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('wallet_refund_logs_title'))),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.purple,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(context.tr('diamond_balance_label'), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Row(children: [
                            const Text('💎', style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 8),
                            Text('$balance', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                          ]),
                        ]),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen())).then((_) => _load()),
                          child: Text(context.tr('upgrade_btn')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(context.tr('auto_refund_history'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (refunds.isEmpty)
                    EmptyView(message: context.tr('no_auto_refunds_yet'), icon: Icons.replay_rounded)
                  else
                    ...refunds.map((t) {
                      final amount = t['diamondsForSpend'] ?? t['diamondPackage'] ?? 0;
                      final note = (t['adminNote'] ?? '').toString();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(border: Border.all(color: AppColors.green.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Text('🟢', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 6),
                              Text(
                                context.tr('diamonds_auto_refunded').replaceAll('%d', '$amount'),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.green, fontSize: 13.5),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Text(_formatDate(t['createdAt']), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(note, style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
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