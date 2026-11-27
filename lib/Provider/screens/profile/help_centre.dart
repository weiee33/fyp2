import 'package:flutter/material.dart';

import '../../../shared/localization/app_language.dart';
import '../../services/support_service.dart';
import '../../widgets/support_card.dart';
import '../support/support_screen.dart';

class HelpCentreScreen extends StatefulWidget {
  final ProviderSupportService? service;
  const HelpCentreScreen({super.key, this.service});
  @override
  State<HelpCentreScreen> createState() => _HelpCentreScreenState();
}

class _HelpCentreScreenState extends State<HelpCentreScreen> {
  late final _service = widget.service ?? ProviderSupportService();
  final _requests = <Map<String, dynamic>>[];
  bool _loading = false, _more = false;
  String? _error;

  static const _primaryOrange = Color(0xFFFF6B00);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.requests(offset: more ? _requests.length : 0);
      if (mounted) {
        setState(() {
          if (!more) _requests.clear();
          _requests.addAll(rows);
          _more = rows.length == 30;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
        final lang = Localizations.localeOf(context).languageCode;
        _showAppDialog(
          title: lang == 'zh' ? '错误' : (lang == 'ms' ? 'Ralat' : 'Error'),
          message: lang == 'zh'
              ? '加载支持请求失败：$e'
              : (lang == 'ms' ? 'Gagal memuatkan permintaan sokongan: $e' : 'Failed to load support requests: $e'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _compose() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderSupportComposeScreen(service: _service),
      ),
    );
    if (!mounted || id == null) return;
    await _load();
    if (mounted) await _open(id);
  }

  Future<void> _open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderSupportDetailScreen(id: id, service: _service),
      ),
    );
    if (mounted) await _load();
  }

  // ============= Pop-up Box 弹窗 =============
  void _showAppDialog({required String title, required String message, required bool isError}) {
    showDialog(
      context: context,
      builder: (ctx) {
        final lang = Localizations.localeOf(context).languageCode;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isError ? Colors.red.shade50 : Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: isError ? Colors.red.shade600 : Colors.green.shade600,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      lang == 'zh' ? '知道了' : (lang == 'ms' ? 'OK' : 'OK'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 翻译辅助方法
  String _tr(BuildContext context, String en, String zh, String ms) {
    final lang = Localizations.localeOf(context).languageCode;
    if (lang == 'zh') return zh;
    if (lang == 'ms') return ms;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        // 👇 背景改为橙色，和你的主色调搭配
        backgroundColor: _primaryOrange,
        // 👇 强制标题为白色
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _tr(context, 'Help Centre', '帮助中心', 'Pusat Bantuan'),
          // 👇 最关键的：在这里也显式设置白色
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white, // 强制白色
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _primaryOrange,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(20),
          children: [
            ProviderSupportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.support_agent_rounded, color: _primaryOrange, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    _tr(context, 'How can we help?', '我们能帮您什么？', 'Bagaimana kami boleh membantu?'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(context, 'Ask a question, share feedback or make a complaint.', '提出问题、分享反馈或提出投诉。', 'Tanya soalan, kongsi maklum balas atau buat aduan.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _primaryOrange, foregroundColor: Colors.white),
                    onPressed: _compose,
                    // 👇 改成了 Contact Support
                    child: Text(_tr(context, 'Contact Support', '联系客服', 'Hubungi Sokongan')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(_tr(context, 'Before you send', '发送前', 'Sebelum anda hantar'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ProviderSupportCard(
              child: Column(
                children: [
                  _HelpTopic(
                    title: _tr(context, 'Booking and payout help', '预约与付款帮助', 'Bantuan tempahan dan pembayaran'),
                    body: _tr(context, 'Open Booking Details to contact your customer or request support linked to that booking.', '打开预约详情联系您的客户或请求与该预约相关的支持。', 'Buka Butiran Tempahan untuk menghubungi pelanggan anda atau meminta sokongan berkaitan tempahan tersebut.'),
                  ),
                  const Divider(),
                  _HelpTopic(
                    title: _tr(context, 'Account and privacy help', '账户与隐私帮助', 'Bantuan akaun dan privasi'),
                    body: _tr(context, 'Use Profile to update your business details, services, service areas and working hours.', '使用“我的”来更新您的业务详情、服务、服务区域和工作时间。', 'Gunakan Profil untuk mengemas kini butiran perniagaan, perkhidmatan, kawasan perkhidmatan dan waktu bekerja anda.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(_tr(context, 'Your support requests', '您的支持请求', 'Permintaan sokongan anda'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_error != null)
              ProviderSupportCard(
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: Text(_tr(context, 'Retry', '重试', 'Cuba lagi'))),
                  ],
                ),
              ),
            if (_requests.isEmpty && !_loading && _error == null)
              ProviderSupportCard(
                child: Text(_tr(context, 'No support requests yet. Your messages and support responses will appear here.', '暂无支持请求。您的消息和支持回复将在此显示。', 'Tiada permintaan sokongan lagi. Mesej dan respons sokongan anda akan dipaparkan di sini.')),
              ),
            for (final row in _requests)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ProviderSupportCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['subject'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${_tr(context, row['booking_id'] == null ? 'General enquiry' : 'Booking support', row['booking_id'] == null ? '一般咨询' : '预约支持', row['booking_id'] == null ? 'Pertanyaan umum' : 'Sokongan tempahan')}\n${row['status'] as String} · ${formatSupportDate(row['created_at'])}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(row['id'] as String),
                  ),
                ),
              ),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: _primaryOrange))),
            if (_more && !_loading)
              TextButton(onPressed: () => _load(more: true), child: Text(_tr(context, 'Load more', '加载更多', 'Muat lagi'))),
            const SizedBox(height: 16),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}

class _HelpTopic extends StatelessWidget {
  final String title, body;
  const _HelpTopic({required this.title, required this.body});
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    shape: const Border(),
    collapsedShape: const Border(),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    children: [Text(body)],
  );
}