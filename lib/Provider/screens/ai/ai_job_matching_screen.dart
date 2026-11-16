import 'dart:convert'; // Required for parsing JSON
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

  // 🎨 Unified Orange theme
  static const _primaryColor = Color(0xFFFF6B00);
  static const _accentColor = Color(0xFFFFF7ED);

  // 👇 新增：本地硬编码翻译函数，避免修改 JSON 文件
  String _localText(String key) {
    final langCode = Localizations.localeOf(context).languageCode;
    if (langCode == 'zh') {
      if (key == 'ai_intro') return '根据您的技能和证书，我们的AI为您推荐这些服务类别。';
      if (key == 'ai_analyzing') return 'AI 正在分析您的个人资料...';
    } else if (langCode == 'ms') {
      if (key == 'ai_intro') return 'Berdasarkan kemahiran dan sijil anda, AI kami mengesyorkan kategori perkhidmatan ini untuk anda.';
      if (key == 'ai_analyzing') return 'AI sedang menganalisis profil anda...';
    }
    // 默认英文
    if (key == 'ai_intro') return 'Based on your skills and certifications, our AI recommends these service categories for you.';
    if (key == 'ai_analyzing') return 'AI is analyzing your profile...';

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

      // Call the Supabase Edge Function (Gemini API).
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

  void _onAccept(Map<String, dynamic> m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr("Accepted: {0}", [m['category']])),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onNotInterested(Map<String, dynamic> m) {
    setState(() {
      _matches.removeWhere((x) => x['category'] == m['category']);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr("Removed: {0}", [m['category']])),
        backgroundColor: Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      appBar: AppBar(
        title: Text(tr('AI Job Matching')),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading
                ? _buildAiLoading()
                : SafeArea(
              child: RefreshIndicator(
                onRefresh: _load,
                color: _primaryColor,
                child: ListView(
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
                              ElevatedButton(onPressed: _load, child: Text(tr('Retry'))),
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
                                  // 👇 修改：移除原来的 tr()，使用本地硬编码函数
                                  _localText('ai_intro'),
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
                            child: Text(tr('No recommendations available'), style: const TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        ..._matches.map((m) => _matchCard(m)),
                    ],
                  ],
                ),
              ),
            ),
          ),

          ProviderFloatingNavBar(
            currentIndex: 0,
            onTabChanged: (index) => Navigator.pop(context),
            onOpenAi: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildAiLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _primaryColor),
          const SizedBox(height: 24),
          Text(
            // 👇 修改：移除原来的 tr()，使用本地硬编码函数
            _localText('ai_analyzing'),
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _matchCard(Map<String, dynamic> m) {
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
                    tr(m['category'].toString()),
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
                    tr("{0}% match", [matchPercent]),
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
                        ? tr("You have: {0} certificate", [m['requiredSkill'] ?? ''])
                        : tr("Missing: {0} certification", [m['requiredSkill'] ?? '']),
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
                    onPressed: () => _onAccept(m),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(tr('Accept')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _onNotInterested(m),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      side: const BorderSide(color: _primaryColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(tr('Not Interested')),
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