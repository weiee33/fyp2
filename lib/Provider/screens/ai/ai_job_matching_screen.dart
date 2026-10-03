import 'package:flutter/material.dart';
import '../../services/profile_service.dart';

class AiJobMatchingScreen extends StatefulWidget {
  const AiJobMatchingScreen({super.key});

  @override
  State<AiJobMatchingScreen> createState() => _AiJobMatchingScreenState();
}

class _AiJobMatchingScreenState extends State<AiJobMatchingScreen> {
  final _service = ProfileService();

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _certifications = [];
  List<Map<String, dynamic>> _matches = [];
  bool _loading = true;

  static const _primaryColor = Color(0xFF1E3A8A);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profile = await _service.getMyProfile();
      final certs = await _service.getCertifications();
      if (!mounted) return;

      final matches = _computeMatches(profile, certs);

      setState(() {
        _profile = profile;
        _certifications = certs;
        _matches = matches;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to compute matches: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Simple weighted scoring algorithm (Module 10)
  List<Map<String, dynamic>> _computeMatches(
      Map<String, dynamic>? profile,
      List<Map<String, dynamic>> certs,
      ) {
    final rating = (profile?['overall_rating'] as num?)?.toDouble() ?? 0;
    final years = (profile?['years_experience'] as num?)?.toInt() ?? 0;
    final certCount = certs.length;

    // Candidate categories with their required skills
    final candidates = [
      {
        'category': 'Electrical Wiring Repair',
        'requiredSkill': 'Electrical',
        'avgEarning': 250,
        'jobsAvailable': 45,
      },
      {
        'category': 'AC Servicing',
        'requiredSkill': 'Air-Conditioning',
        'avgEarning': 180,
        'jobsAvailable': 30,
      },
      {
        'category': 'Pipe Repair',
        'requiredSkill': 'Plumbing',
        'avgEarning': 120,
        'jobsAvailable': 60,
      },
      {
        'category': 'Deep Cleaning',
        'requiredSkill': 'Cleaning',
        'avgEarning': 220,
        'jobsAvailable': 25,
      },
      {
        'category': 'Faucet Installation',
        'requiredSkill': 'Plumbing',
        'avgEarning': 90,
        'jobsAvailable': 50,
      },
    ];

    final results = <Map<String, dynamic>>[];

    for (final c in candidates) {
      // 1. Skill match (40%): does provider have the required certification?
      final hasSkill = certs.any((cert) {
        final name =
            cert['certification_name']?.toString().toLowerCase() ?? '';
        final issuer = cert['issuer']?.toString().toLowerCase() ?? '';
        final skill = c['requiredSkill']!.toString().toLowerCase();
        return name.contains(skill) || issuer.contains(skill);
      });
      final skillScore = hasSkill ? 40.0 : 15.0;

      // 2. Rating score (25%): overall rating / 5 * 25
      final ratingScore = (rating / 5.0) * 25;

      // 3. Experience score (15%): capped at 10 years
      final expScore = (years.clamp(0, 10) / 10.0) * 15;

      // 4. Certification count score (20%): more certs = higher
      final certScore = (certCount.clamp(0, 5) / 5.0) * 20;

      final total = skillScore + ratingScore + expScore + certScore;
      final matchPercent = total.round().clamp(0, 100);

      results.add({
        ...c,
        'hasSkill': hasSkill,
        'matchPercent': matchPercent,
      });
    }

    // Sort by match percentage, descending
    results.sort((a, b) =>
        (b['matchPercent'] as int).compareTo(a['matchPercent'] as int));

    return results;
  }

  void _onAccept(Map<String, dynamic> m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Accepted: ${m['category']}'),
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
        content: Text('Removed: ${m['category']}'),
        backgroundColor: Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('AI Job Matching'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: _primaryColor,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
                        child: const Icon(
                          Icons.auto_awesome,
                          color: _primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Based on your skills and certifications, we recommend these service categories for you.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (_matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'No recommendations available',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ..._matches.map((m) => _matchCard(m)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _matchCard(Map<String, dynamic> m) {
    final matchPercent = m['matchPercent'] as int;
    final hasSkill = m['hasSkill'] as bool;
    final matchColor = matchPercent >= 80
        ? const Color(0xFF10B981)
        : (matchPercent >= 60
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444));

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + match badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    m['category'].toString(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: matchColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$matchPercent% match',
                    style: TextStyle(
                      color: matchColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Meta
            Text(
              'Jobs available: ${m['jobsAvailable']} · Avg. earnings: RM${m['avgEarning']}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),

            // Skill status
            Row(
              children: [
                Icon(
                  hasSkill ? Icons.check_circle : Icons.info_outline,
                  size: 14,
                  color: hasSkill
                      ? Colors.green.shade600
                      : Colors.orange.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasSkill
                        ? 'You have: ${m['requiredSkill']} certificate'
                        : 'Missing: ${m['requiredSkill']} certification',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasSkill
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _onAccept(m),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _onNotInterested(m),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Not Interested'),
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