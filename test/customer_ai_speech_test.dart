import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:fyp2/Customer/services/customer_ai_speech.dart';
import 'package:fyp2/shared/localization/app_language.dart';

class Recognizer extends SpeechToText {
  Recognizer() : super.withMethodChannel();
  List<String> languages = ['en_US'];
  String? requestedLocale, failWith;
  bool permitted = true, inventoryFails = false;
  Completer<void>? inventoryWait;
  SpeechResultListener? result;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    debugLogging = false,
    Duration finalTimeout = SpeechToText.defaultFinalTimeout,
    List<SpeechConfigOption>? options,
  }) async => permitted;

  @override
  Future<List<LocaleName>> locales() async {
    await inventoryWait?.future;
    if (inventoryFails) throw StateError('No language inventory');
    return languages.map((l) => LocaleName(l, l)).toList();
  }

  @override
  Future<void> listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    cancelOnError = false,
    partialResults = true,
    onDevice = false,
    ListenMode listenMode = ListenMode.confirmation,
    sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {
    requestedLocale = localeId;
    result = onResult;
    expect(listenOptions?.onDevice, false);
    if (failWith != null) {
      errorListener?.call(SpeechRecognitionError(failWith!, true));
    }
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.select('en');
  });
  tearDown(() async => AppLanguage.instance.select('en'));

  test('Mandarin aliases, script tags, case and separators are recognized', () {
    for (final locale in [
      'cmn-Hans-CN',
      'zh_Hans_CN',
      'ZH_cn',
      'cmn-Hant-TW',
    ]) {
      expect(
        CustomerAiSpeech.recognitionLocale('zh', ['en-US', locale]),
        locale,
      );
    }
    expect(CustomerAiSpeech.recognitionLocale('zh', ['yue-Hant-HK']), 'zh-CN');
    expect(CustomerAiSpeech.recognitionLocale('zh', ['zh-yue-HK']), 'zh-CN');
  });

  test('Malay aliases and preferred English region are recognized', () {
    for (final locale in ['ms_MY', 'MS-my', 'msa-MY', 'ms-BN']) {
      expect(
        CustomerAiSpeech.recognitionLocale('ms', ['en-US', locale]),
        locale,
      );
    }
    expect(
      CustomerAiSpeech.recognitionLocale('en', ['en-US', 'en_MY']),
      'en_MY',
    );
    expect(CustomerAiSpeech.recognitionLocale('ms', ['id-ID']), 'ms-MY');
  });

  for (final language in ['en', 'zh', 'ms']) {
    test(
      '$language uses display language even with English-only inventory',
      () async {
        await AppLanguage.instance.select(language);
        final engine = Recognizer();
        final speech = CustomerAiSpeech(speech: engine);
        expect(await speech.start((_) {}, () {}, () {}), true);
        expect(
          engine.requestedLocale,
          {'en': 'en_US', 'zh': 'zh-CN', 'ms': 'ms-MY'}[language],
        );
      },
    );
  }

  test(
    'explicit voice choice overrides English UI and preserves Chinese text',
    () async {
      final engine = Recognizer()..languages = ['en_US', 'cmn-Hans-CN'];
      final speech = CustomerAiSpeech(speech: engine)..languageCode = 'zh';
      var draft = '';
      await speech.start((words) => draft = words, () {}, () {});
      expect(engine.requestedLocale, 'cmn-Hans-CN');
      engine.result!(
        SpeechRecognitionResult([
          SpeechRecognitionWords('我要找水管工', null, 1),
        ], true),
      );
      expect(draft, '我要找水管工');
      expect(AppLanguage.instance.code, 'en');
      await speech.cancel();
      engine.result!(
        SpeechRecognitionResult([
          SpeechRecognitionWords('late', null, 1),
        ], true),
      );
      expect(draft, '我要找水管工');
    },
  );

  test('Malay text is returned without translation', () async {
    final engine = Recognizer();
    final speech = CustomerAiSpeech(speech: engine)..languageCode = 'ms';
    var draft = '';
    await speech.start((words) => draft = words, () {}, () {});
    engine.result!(
      SpeechRecognitionResult([
        SpeechRecognitionWords('Saya perlukan tukang paip', null, 1),
      ], true),
    );
    expect(draft, 'Saya perlukan tukang paip');
  });

  test(
    'missing or failing inventory still requests selected language',
    () async {
      for (final fails in [false, true]) {
        final engine = Recognizer()
          ..languages = []
          ..inventoryFails = fails;
        final speech = CustomerAiSpeech(speech: engine)..languageCode = 'ms';
        expect(await speech.start((_) {}, () {}, () {}), true);
        expect(engine.requestedLocale, 'ms-MY');
      }
    },
  );

  test('language errors explain setup and permit a later retry', () async {
    for (final code in [
      'error_language_unavailable',
      'error_language_not_supported',
    ]) {
      final engine = Recognizer()..failWith = code;
      final speech = CustomerAiSpeech(speech: engine)..languageCode = 'ms';
      var errors = 0;
      expect(await speech.start((_) {}, () {}, () => errors++), false);
      expect(errors, 1);
      expect(speech.errorMessage, contains('speech recognition settings'));
      engine.failWith = null;
      expect(await speech.start((_) {}, () {}, () {}), true);
      expect(speech.errorMessage, isNull);
    }
  });

  test('permission denial never starts listening', () async {
    final engine = Recognizer()..permitted = false;
    expect(
      await CustomerAiSpeech(speech: engine).start((_) {}, () {}, () {}),
      false,
    );
    expect(engine.requestedLocale, isNull);
  });

  test('cancel during locale lookup cannot start microphone later', () async {
    final engine = Recognizer()..inventoryWait = Completer<void>();
    final speech = CustomerAiSpeech(speech: engine);
    final starting = speech.start((_) {}, () {}, () {});
    await Future<void>.delayed(Duration.zero);
    await speech.cancel();
    engine.inventoryWait!.complete();
    expect(await starting, false);
    expect(engine.requestedLocale, isNull);
  });

  test('reopened AI screen receives shared recognizer errors', () async {
    final engine = Recognizer();
    final first = CustomerAiSpeech(speech: engine);
    var firstErrors = 0, secondErrors = 0;
    await first.start((_) {}, () {}, () => firstErrors++);
    await first.cancel();
    final second = CustomerAiSpeech(speech: engine);
    await second.start((_) {}, () {}, () => secondErrors++);
    engine.errorListener!(SpeechRecognitionError('error_network', false));
    expect(firstErrors, 0);
    expect(secondErrors, 1);
    expect(second.errorMessage, contains('internet'));
  });
}
