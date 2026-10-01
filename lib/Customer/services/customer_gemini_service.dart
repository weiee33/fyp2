import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api_config.dart';

class CustomerGeminiService {
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  /// Sends the customer's problem description to Gemini and extracts structured triage data
  Future<Map<String, dynamic>> triageCustomerIssue(String userQuery) async {
    final url = Uri.parse(
      '$_baseUrl/${ApiConfig.geminiModel}:generateContent?key=${ApiConfig.geminiApiKey}',
    );

    final systemInstruction = '''
You are the AI triage assistant for the Malaysian home services app "Local Life Service Assistant".
Analyze the user's issue and return ONLY a valid JSON object matching this schema:
{
  "category": "Plumbing" | "Electrical" | "Cleaning" | "Aircon" | "Other",
  "urgency": "Low" | "Medium" | "High" | "Emergency",
  "explanation": "Short 1-2 sentence assessment explaining the immediate danger or recommended action in friendly tone.",
  "recommended_action": "Specific repair recommendation (e.g. Chemical Wash, Stopcock Valve Replacement)"
}
Do not include markdown fences (```json) or extra text. Output raw JSON only.
''';

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': '$systemInstruction\n\nUser Issue: "$userQuery"'}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawText = data['candidates']?[0]?['content']?[0]?['text'] ??
            data['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
            '';

        // Clean out any accidental markdown code fences
        final cleanedJson = rawText.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(cleanedJson) as Map<String, dynamic>;
      } else {
        return {
          'category': 'Other',
          'urgency': 'Medium',
          'explanation': 'Service request received. Route to general maintenance technician.',
          'recommended_action': 'General On-site Inspection',
        };
      }
    } catch (e) {
      return {
        'category': 'Other',
        'urgency': 'Medium',
        'explanation': 'Local diagnosis fallback: please choose your technician from the service catalog.',
        'recommended_action': 'General Service',
      };
    }
  }
}