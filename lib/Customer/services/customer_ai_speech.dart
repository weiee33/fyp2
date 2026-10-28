import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import '../../shared/localization/app_language.dart';

/// Speech remains a draft until the customer presses Send.
class CustomerAiSpeech {
  CustomerAiSpeech({SpeechToText? speech}) : _speech = speech ?? SpeechToText();
  final SpeechToText _speech;

  String? errorMessage;
  int _generation = 0;
  void Function()? _done, _error;

  static String recognitionLocale(String language, Iterable<String> locales) {
    final preferred = switch (language) {
      'zh' => ['zh-CN', 'zh-Hans-CN', 'cmn-Hans-CN', 'cmn-CN', 'zh-SG'],
      'ms' => ['ms-MY', 'msa-MY', 'ms'],
      _ => ['en-MY', 'en-SG', 'en-US', 'en-GB'],
    };
    String normalize(String value) => value.replaceAll('_', '-').toLowerCase();
    final available = locales.toList();
    for (final candidate in preferred) {
      for (final locale in available) {
        if (normalize(locale) == normalize(candidate)) return locale;
      }
    }
    for (final locale in available) {
      final parts = normalize(locale).split('-');
      final matches = switch (language) {
        'zh' =>
          (parts.first == 'zh' && !parts.contains('yue')) ||
              parts.first == 'cmn',
        'ms' => parts.first == 'ms' || parts.first == 'msa',
        _ => parts.first == 'en',
      };
      if (matches) return locale;
    }
    // Some engines return only the device language (or no inventory). Request
    // the chosen language explicitly and let the recognizer report support.
    // Never fall back to English for a Chinese or Malay request.
    return preferred.first;
  }

  Future<bool> start(
    void Function(String) text,
    void Function() done,
    void Function() error,
  ) async {
    final generation = ++_generation;
    // Read the current app language for every recording, including after
    // changing Settings without recreating the AI screen.
    final language = AppLanguage.instance.code;
    errorMessage = null;
    _done = done;
    _error = error;
    void status(String s) {
      if (s == 'done' || s == 'notListening') {
        _done?.call();
      }
    }

    void failure(SpeechRecognitionError error) {
      if (_error == null) return;
      errorMessage = switch (error.errorMsg) {
        'error_language_not_supported' || 'error_language_unavailable' =>
          'Speech recognition for the app language is unavailable on your device. Enable or download that language in your speech recognition settings, then try again.',
        'error_network' || 'error_network_timeout' =>
          'Voice input needs a connection. Check your internet and try again.',
        'error_permission' || 'error_audio_error' =>
          'Microphone unavailable. Check microphone permissions and try again.',
        _ => 'Voice input stopped. You can edit the text or type instead.',
      };
      _error?.call();
    }

    // initialize is cached by the plugin. Rebind callbacks when a new AI screen
    // uses the shared recognizer so errors cannot target a disposed screen.
    _speech.statusListener = status;
    _speech.errorListener = failure;
    final available = await _speech.initialize(
      onStatus: status,
      onError: failure,
    );
    if (!available || generation != _generation) return false;
    List<LocaleName> locales;
    try {
      locales = await _speech.locales();
    } catch (_) {
      locales = [];
    }
    if (generation != _generation) return false;
    await _speech.listen(
      localeId: recognitionLocale(language, locales.map((l) => l.localeId)),
      onResult: (r) {
        if (generation == _generation) text(r.recognizedWords);
      },
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
        listenMode: ListenMode.dictation,
      ),
    );
    return generation == _generation && errorMessage == null;
  }

  Future<void> stop() => _speech.stop();
  Future<void> cancel() async {
    _generation++;
    _done = null;
    _error = null;
    await _speech.cancel();
  }
}
