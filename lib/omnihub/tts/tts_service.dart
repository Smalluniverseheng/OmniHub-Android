/// OmniHub 听书服务
///
/// 两种引擎：
/// - system：flutter_tts，调用手机自带语音模块（离线）
/// - edge：Edge TTS 在线语音（音质更好，需联网），对应 Legado
///   社区的「在线朗读引擎」用法
///
/// 使用方式：OmniTts.instance.start(paragraphs) 后按段落顺序朗读，
/// 支持 播放/暂停/上一段/下一段/停止，章节播完回调 onChapterEnd。
library omni_tts;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../foundation/appdata.dart';
import 'edge_tts.dart';

enum OmniTtsState { idle, loading, playing, paused }

class OmniTts extends ChangeNotifier {
  OmniTts._();
  static final OmniTts instance = OmniTts._();

  // 设置键（appdata.settings）
  static const String kEngine = 'ttsEngine'; // 'system' | 'edge'
  static const String kVoice = 'ttsVoice'; // edge voice id
  static const String kRate = 'ttsRate'; // double 0.5 ~ 2.0

  OmniTtsState state = OmniTtsState.idle;
  List<String> paragraphs = [];
  int index = 0;
  String? error;

  /// 一章朗读完毕回调（阅读器用来自动翻下一章）
  VoidCallback? onChapterEnd;

  FlutterTts? _system;
  AudioPlayer? _player;
  bool _stopRequested = false;

  String get engine => appdata.settings[kEngine]?.toString() ?? 'system';
  double get rate =>
      (appdata.settings[kRate] as num?)?.toDouble() ?? 1.0;
  String get voice =>
      appdata.settings[kVoice]?.toString() ?? 'zh-CN-XiaoxiaoNeural';

  bool get isActive => state != OmniTtsState.idle;

  void _setState(OmniTtsState s) {
    state = s;
    notifyListeners();
  }

  Future<void> _ensureSystem() async {
    if (_system != null) return;
    _system = FlutterTts();
    try {
      await _system!.setLanguage('zh-CN');
      await _system!.setSpeechRate(rate * 0.5); // flutter_tts 0.5≈正常
      await _system!.setVolume(1.0);
      _system!.setCompletionHandler(() {
        if (_stopRequested) return;
        _speakNext();
      });
      _system!.setErrorHandler((msg) {
        error = '$msg';
        _setState(OmniTtsState.idle);
      });
    } catch (_) {
      // 部分平台（桌面）不支持系统 TTS
    }
  }

  Future<void> _ensurePlayer() async {
    _player ??= AudioPlayer();
  }

  /// 开始朗读一章：[text] 按换行拆段
  Future<void> start(String text, {int fromIndex = 0}) async {
    await stop(notify: false);
    paragraphs = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return;
    index = fromIndex.clamp(0, paragraphs.length - 1);
    error = null;
    _stopRequested = false;
    _setState(OmniTtsState.loading);
    _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    if (_stopRequested || index < 0 || index >= paragraphs.length) return;
    notifyListeners();
    if (engine == 'edge') {
      await _speakEdge(paragraphs[index]);
    } else {
      await _speakSystem(paragraphs[index]);
    }
  }

  Future<void> _speakSystem(String text) async {
    try {
      await _ensureSystem();
      _setState(OmniTtsState.playing);
      await _system!.speak(text);
    } catch (e) {
      error = '系统语音不可用：$e';
      _setState(OmniTtsState.idle);
    }
  }

  int _edgeJob = 0;

  Future<void> _speakEdge(String text) async {
    final job = ++_edgeJob;
    try {
      _setState(OmniTtsState.loading);
      final bytes = await EdgeTts.synthesize(text, voice: voice, rate: rate);
      if (_stopRequested || job != _edgeJob) return;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/omni_tts_$job.mp3');
      await f.writeAsBytes(bytes, flush: true);
      await _ensurePlayer();
      await _player!.setFilePath(f.path);
      if (_stopRequested || job != _edgeJob) return;
      _setState(OmniTtsState.playing);
      // 播完 → 下一段
      _player!.playerStateStream.listen((s) async {
        if (job != _edgeJob || _stopRequested) return;
        if (s.processingState == ProcessingState.completed) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (!_stopRequested && job == _edgeJob) _speakNext();
        }
      });
      await _player!.play();
    } catch (e) {
      if (_stopRequested || job != _edgeJob) return;
      error = '在线语音失败：$e（可切换系统语音）';
      _setState(OmniTtsState.idle);
    }
  }

  void _speakNext() {
    if (index < paragraphs.length - 1) {
      index++;
      _speakCurrent();
    } else {
      // 本章播完
      _setState(OmniTtsState.idle);
      onChapterEnd?.call();
    }
  }

  Future<void> next() async {
    if (paragraphs.isEmpty) return;
    await _interrupt();
    if (index < paragraphs.length - 1) {
      index++;
      _speakCurrent();
    } else {
      _setState(OmniTtsState.idle);
      onChapterEnd?.call();
    }
  }

  Future<void> prev() async {
    if (paragraphs.isEmpty) return;
    await _interrupt();
    if (index > 0) {
      index--;
      _speakCurrent();
    }
  }

  Future<void> toggle() async {
    if (state == OmniTtsState.playing) {
      await pause();
    } else if (state == OmniTtsState.paused) {
      await resume();
    } else if (paragraphs.isNotEmpty) {
      _speakCurrent();
    }
  }

  Future<void> pause() async {
    if (engine == 'edge') {
      await _player?.pause();
    } else {
      try {
        await _system?.pause();
      } catch (_) {
        await _system?.stop();
      }
    }
    _setState(OmniTtsState.paused);
  }

  Future<void> resume() async {
    if (engine == 'edge') {
      _setState(OmniTtsState.playing);
      await _player?.play();
    } else {
      // flutter_tts 多数平台不支持从中间恢复 → 重读本段
      _speakCurrent();
    }
  }

  Future<void> _interrupt() async {
    _edgeJob++;
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _system?.stop();
    } catch (_) {}
  }

  Future<void> stop({bool notify = true}) async {
    _stopRequested = true;
    await _interrupt();
    paragraphs = [];
    index = 0;
    _stopRequested = false;
    if (notify) _setState(OmniTtsState.idle);
  }

  Future<void> applySettings() async {
    if (_system != null) {
      try {
        await _system!.setSpeechRate(rate * 0.5);
      } catch (_) {}
    }
  }
}
