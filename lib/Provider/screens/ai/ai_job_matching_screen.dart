import 'dart:convert';
import 'package:fyp2/shared/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/profile_service.dart';
import 'package:fyp2/Provider/screens/home/provider_floating_nav_bar.dart';

class AiJobMatchingScreen extends StatefulWidget {
  const AiJobMatchingScreen({super.key});

  @override
  State<AiJobMatchingScreen> createState() => _AiJobMatchingScreenState();
}

class _AiJobMatchingScreenState extends State<AiJobMatchingScreen> {
  final _service = ProfileService();
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _matches = [];
  bool _loading = true;
  String? _error;
  bool _isProcessing = false;

  static const _primaryColor = Color(0xFFFF6B00);
  static const _accentColor = Color(0xFFFFF7ED);

  String _localText(String key, bool isZh, bool isMs) {
    if (key == 'ai_intro') {
      return isZh
          ? '根据您的技能和证书，我们的AI为您推荐这些服务类别。'
          : (isMs
          ? 'Berdasarkan kemahiran dan sijil anda, AI kami mengesyorkan kategori perkhidmatan ini untuk anda.'
          : 'Based on your skills and certifications, our AI recommends these service categories for you.');
    }
    if (key == 'ai_analyzing') {
      return isZh
          ? 'AI 正在分析您的个人资料...'
          : (isMs
          ? 'AI sedang menganalisis profil anda...'
          : 'AI is analyzing your profile...');
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await _service.getMyProfile();
      final certs = await _service.getCertifications();

      final response = await _client.functions.invoke(
        'provider-ai-job-match',
        body: {
          'profile': profile,
          'certs': certs,
        },
      );

      if (!mounted) return;

      var aiData = response.data;
      List<dynamic> parsedList = [];

      if (aiData is List) {
        parsedList = aiData;
      } else if (aiData is Map && aiData['matches'] != null) {
        parsedList = aiData['matches'];
      } else if (aiData is String) {
        final match = RegExp(r'\[.*\]', dotAll: true).firstMatch(aiData);
        if (match != null) {
          parsedList = jsonDecode(match.group(0)!);
        }
      }

      if (parsedList.isNotEmpty) {
        setState(() {
          _matches = List<Map<String, dynamic>>.from(parsedList);
          _loading = false;
        });
      } else {
        _fallbackCompute(profile, certs);
      }

    } catch (e) {
      if (!mounted) return;
      debugPrint("AI error: $e");
      _fallbackCompute(await _service.getMyProfile(), await _service.getCertifications());
    }
  }

  void _fallbackCompute(Map<String, dynamic>? profile, List<Map<String, dynamic>> certs) {
    final matches = _computeMatches(profile, certs);
    if (!mounted) return;
    setState(() {
      _matches = matches;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _computeMatches(
      Map<String, dynamic>? profile,
      List<Map<String, dynamic>> certs,
      ) {
    final rating = (profile?['overall_rating'] as num?)?.toDouble() ?? 0;
    final years = (profile?['years_experience'] as num?)?.toInt() ?? 0;
    final certCount = certs.length;

    final candidates = [
      {'category': 'Electrical Wiring Repair', 'requiredSkill': 'Electrical', 'avgEarning': 250, 'jobsAvailable': 45},
      {'category': 'AC Servicing', 'requiredSkill': 'Air-Conditioning', 'avgEarning': 180, 'jobsAvailable': 30},
      {'category': 'Pipe Repair', 'requiredSkill': 'Plumbing', 'avgEarning': 120, 'jobsAvailable': 60},
      {'category': 'Deep Cleaning', 'requiredSkill': 'Cleaning', 'avgEarning': 220, 'jobsAvailable': 25},
      {'category': 'Faucet Installation', 'requiredSkill': 'Plumbing', 'avgEarning': 90, 'jobsAvailable': 50},
    ];

    final results = <Map<String, dynamic>>[];

    for (final c in candidates) {
      final hasSkill = certs.any((cert) {
        final name = cert['certification_name']?.toString().toLowerCase() ?? '';
        final issuer = cert['issuer']?.toString().toLowerCase() ?? '';
        final skill = c['requiredSkill']!.toString().toLowerCase();
        return name.contains(skill) || issuer.contains(skill);
      });
      final skillScore = hasSkill ? 40.0 : 15.0;
      final ratingScore = (rating / 5.0) * 25;
      final expScore = (years.clamp(0, 10) / 10.0) * 15;
      final certScore = (certCount.clamp(0, 5) / 5.0) * 20;

      final total = skillScore + ratingScore + expScore + certScore;
      final matchPercent = total.round().clamp(0, 100);

      results.add({...c, 'hasSkill': hasSkill, 'matchPercent': matchPercent, 'reason': ''});
    }

    results.sort((a, b) => (b['matchPercent'] as int).compareTo(a['matchPercent'] as int));
    return results;
  }

  Future<void> _onAccept(Map<String, dynamic> m) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    final categoryName = m['category'].toString();
    final requiredSkill = m['requiredSkill']?.toString() ?? categoryName;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          elevation: 8,
          shape: CircleBorder(),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(color: _primaryColor),
          ),
        ),
      ),
    );

    try {
      String? catId;
      String? providerId;

      try {
        final pRes = await _client
            .from('provider_profiles')
            .select('provider_id')
            .eq('user_id', _client.auth.currentUser!.id)
            .maybeSingle();
        if (pRes != null) {
          providerId = pRes['provider_id']?.toString();
        }
      } catch (_) {}

      try {
        final catRes = await _client
            .from('service_categories')
            .select('category_id')
            .ilike('category_name', '%$requiredSkill%')
            .limit(1)
            .maybeSingle();
        if (catRes != null) {
          catId = catRes['category_id']?.toString();
        }
      } catch (e) {
        debugPrint("Find category error: $e");
      }

      if (providerId != null) {
        final existingService = await _client
            .from('services')
            .select('service_id')
            .eq('provider_id', providerId)
            .eq('service_name', categoryName)
            .eq('is_active', true)
            .maybeSingle();

        if (existingService != null) {
          if (!mounted) return;
          Navigator.pop(context);
          _showAppDialog(
            title: isZh ? '服务已存在' : (isMs ? 'Perkhidmatan Sudah Ada' : 'Service Exists'),
            message: isZh
                ? '您的“我的服务”中已有此服务。'
                : (isMs
                ? 'Anda sudah mempunyai perkhidmatan ini dalam "Perkhidmatan Saya".'
                : 'You already have this service active in "My Services".'),
            isError: true,
          );
          setState(() {
            _matches.removeWhere((x) => x['category'] == m['category']);
            _isProcessing = false;
          });
          return;
        }
      }

      final Map<String, dynamic> insertData = {
        'service_name': categoryName,
        'description': 'Professional $categoryName provided by certified experts.',
        'pricing_type': 'Fixed',
        'base_price': 50.00,
        'estimated_duration': 60,
        'is_active': true,
      };

      if (catId != null) insertData['category_id'] = catId;
      if (providerId != null) insertData['provider_id'] = providerId;

      await _client.from('services').insert(insertData);

      if (!mounted) return;

      Navigator.pop(context);

      setState(() {
        _matches.removeWhere((x) => x['category'] == m['category']);
        _isProcessing = false;
      });

      _showAppDialog(
        title: isZh ? '成功' : (isMs ? 'Berjaya' : 'Success'),
        message: isZh
            ? '成功添加到我的服务！'
            : (isMs
            ? 'Berjaya ditambah ke Perkhidmatan Saya!'
            : 'Successfully added to My Services!'),
        isError: false,
      );

    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      setState(() => _isProcessing = false);

      _showAppDialog(
        title: isZh ? '添加失败' : (isMs ? 'Gagal Menambah' : 'Add Failed'),
        message: isZh
            ? '添加服务失败：$e'
            : (isMs
            ? 'Gagal menambah perkhidmatan: $e'
            : 'Failed to add service: $e'),
        isError: true,
      );
    }
  }

  void _onNotInterested(Map<String, dynamic> m) {
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    setState(() {
      _matches.removeWhere((x) => x['category'] == m['category']);
    });

    _showAppDialog(
      title: isZh ? '已移除' : (isMs ? 'Dibuang' : 'Removed'),
      message: isZh
          ? '已移除推荐：${m['category']}'
          : (isMs
          ? 'Dibuang: ${m['category']}'
          : 'Removed: ${m['category']}'),
      isError: false,
    );
  }

  void _showAppDialog({required String title, required String message, required bool isError}) {
    showDialog(
      context: context,
      builder: (ctx) {
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
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'zh'
                          ? '知道了'
                          : (Localizations.localeOf(context).languageCode == 'ms' ? 'OK' : 'OK'),
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

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      appBar: AppBar(
        title: Text(
          isZh ? 'AI 职位匹配' : (isMs ? 'Padanan Pekerjaan AI' : 'AI Job Matching'),
          // 👇 强制指定白色
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading
                ? _buildAiLoading(isZh, isMs)
                : SafeArea(
              child: RefreshIndicator(
                onRefresh: _load,
                color: _primaryColor,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    if (_error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _load,
                                child: Text(isZh ? '重试' : (isMs ? 'Cuba lagi' : 'Retry')),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      Card(
                        elevation: 2,
                        color: _accentColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _primaryColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.auto_awesome, color: _primaryColor, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _localText('ai_intro', isZh, isMs),
                                  style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_matches.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              isZh
                                  ? '暂无推荐'
                                  : (isMs
                                  ? 'Tiada cadangan tersedia'
                                  : 'No recommendations available'),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ..._matches.map((m) => _matchCard(m, isZh, isMs)),
                    ],
                  ],
                ),
              ),
            ),
          ),

          ProviderFloatingNavBar(
            currentIndex: 2,
            onTabChanged: (index) => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAiLoading(bool isZh, bool isMs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _primaryColor),
          const SizedBox(height: 24),
          Text(
            _localText('ai_analyzing', isZh, isMs),
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _matchCard(Map<String, dynamic> m, bool isZh, bool isMs) {
    final matchPercent = m['matchPercent'] as int;
    final hasSkill = m['hasSkill'] as bool;
    final reason = m['reason']?.toString() ?? '';

    final matchColor = matchPercent >= 80
        ? const Color(0xFF10B981)
        : (matchPercent >= 60
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444));

    return Card(
      elevation: 2,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m['category'].toString(),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: matchColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isZh
                        ? '$matchPercent% 匹配'
                        : (isMs
                        ? '$matchPercent% padanan'
                        : '$matchPercent% match'),
                    style: TextStyle(color: matchColor, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),

            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                reason,
                style: const TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
              ),
            ],

            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  hasSkill ? Icons.check_circle : Icons.info_outline,
                  size: 14,
                  color: hasSkill ? Colors.green.shade600 : Colors.orange.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasSkill
                        ? (isZh
                        ? '您有：${m['requiredSkill'] ?? ''} 证书'
                        : (isMs
                        ? 'Anda mempunyai: sijil ${m['requiredSkill'] ?? ''}'
                        : 'You have: ${m['requiredSkill'] ?? ''} certificate'))
                        : (isZh
                        ? '缺少：${m['requiredSkill'] ?? ''} 认证'
                        : (isMs
                        ? 'Tiada: pensijilan ${m['requiredSkill'] ?? ''}'
                        : 'Missing: ${m['requiredSkill'] ?? ''} certification')),
                    style: TextStyle(
                      fontSize: 12,
                      color: hasSkill ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : () => _onAccept(m),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isZh ? '接受' : (isMs ? 'Terima' : 'Accept')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : () => _onNotInterested(m),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: const BorderSide(color: _primaryColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isZh ? '不感兴趣' : (isMs ? 'Tidak Berminat' : 'Not Interested')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}