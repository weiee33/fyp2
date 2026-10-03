class ApiConfig {
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  // AI is deferred. No private AI credential belongs in the app bundle.
  static const String geminiApiKey = '';
  static const String geminiModel = 'gemini-1.5-flash';
}
