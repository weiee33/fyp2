import 'package:speech_to_text/speech_to_text.dart';

/// Speech remains a draft until the customer presses Send.
class CustomerAiSpeech {
  final SpeechToText _speech = SpeechToText();
  int _generation = 0;
  void Function()? _done, _error;
  Future<bool> start(
    void Function(String) text,
    void Function() done,
    void Function() error,
  ) async {
    final generation = ++_generation;
    _done = done;
    _error = error;
    final available = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          _done?.call();
        }
      },
      onError: (_) {
        _error?.call();
      },
    );
    if (!available || generation != _generation) return false;
    await _speech.listen(
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
    return true;
  }

  Future<void> stop() => _speech.stop();
  Future<void> cancel() async {
    _generation++;
    _done = null;
    _error = null;
    await _speech.cancel();
  }
}
