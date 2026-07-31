/// Edge TTS（微软大声朗读接口）在线语音合成
///
/// 免费、无需 API Key，中文语音质量高，是 Legado 社区
/// 「在线朗读引擎」的主流方案之一；系统 TTS 走 flutter_tts。
///
/// 协议：wss://speech.platform.bing.com + Sec-MS-GEC 签名
library edge_tts;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class EdgeTtsVoice {
  final String id;
  final String name;
  final String gender;

  const EdgeTtsVoice(this.id, this.name, this.gender);
}

/// 常用中文语音
const List<EdgeTtsVoice> kEdgeTtsVoices = [
  EdgeTtsVoice('zh-CN-XiaoxiaoNeural', '晓晓（女声·温暖）', 'female'),
  EdgeTtsVoice('zh-CN-XiaoyiNeural', '晓伊（女声·甜美）', 'female'),
  EdgeTtsVoice('zh-CN-YunxiNeural', '云希（男声·清朗）', 'male'),
  EdgeTtsVoice('zh-CN-YunjianNeural', '云健（男声·浑厚）', 'male'),
  EdgeTtsVoice('zh-CN-YunxiaNeural', '云夏（男声·少年）', 'male'),
  EdgeTtsVoice('zh-CN-YunyangNeural', '云扬（男声·专业播报）', 'male'),
  EdgeTtsVoice('zh-CN-liaoning-XiaobeiNeural', '晓北（东北女声）', 'female'),
  EdgeTtsVoice('zh-CN-shaanxi-XiaoniNeural', '晓妮（陕西女声）', 'female'),
];

class EdgeTts {
  static const String _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String _wss =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';

  /// Sec-MS-GEC: 以 5 分钟为窗口的时间戳 + TrustedClientToken 的 SHA-256
  static String _secMsGec() {
    var ticks =
        (DateTime.now().millisecondsSinceEpoch / 1000 + 11644473600) *
            10000000;
    ticks -= ticks % 3000000000;
    final str = '${ticks.toInt()}$_token';
    return sha256.convert(utf8.encode(str)).toString().toUpperCase();
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _timestamp() {
    final now = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}T'
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.'
        '${(now.millisecond * 1000 + now.microsecond).toString().padLeft(6, '0')}Z';
  }

  /// 合成一段文本为 mp3 字节
  /// [rate] 1.0 为原速，范围 0.5 ~ 2.0
  static Future<Uint8List> synthesize(
    String text, {
    String voice = 'zh-CN-XiaoxiaoNeural',
    double rate = 1.0,
  }) async {
    if (text.trim().isEmpty) return Uint8List(0);
    // 单段过长时服务端会截断，调用方应分段；此处兜底截 2500 字
    if (text.length > 2500) text = text.substring(0, 2500);

    final connId = const Uuid().v4().replaceAll('-', '');
    final url = '$_wss'
        '?TrustedClientToken=$_token'
        '&Sec-MS-GEC=${_secMsGec()}'
        '&Sec-MS-GEC-Version=1-131.0.2903.99'
        '&ConnectionId=$connId';

    final channel = WebSocketChannel.connect(Uri.parse(url));

    final config = 'X-Timestamp:${_timestamp()}\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":'
        '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
        '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
    channel.sink.add(config);

    final pct = ((rate - 1.0) * 100).round();
    final rateStr = '${pct >= 0 ? '+' : ''}$pct%';
    final ssml = "<speak version='1.0' "
        "xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>"
        "<voice name='$voice'>"
        "<prosody pitch='+0Hz' rate='$rateStr' volume='+0%'>"
        "${_escapeXml(text)}"
        '</prosody></voice></speak>';
    final req = 'X-RequestId:$connId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:${_timestamp()}\r\n'
        'Path:ssml\r\n\r\n'
        '$ssml';
    channel.sink.add(req);

    final audio = BytesBuilder();
    var ok = false;
    try {
      await for (final data in channel.stream.timeout(
        const Duration(seconds: 20),
        onTimeout: (sink) => sink.close(),
      )) {
        if (data is String) {
          if (data.contains('Path:turn.end')) {
            ok = true;
            break;
          }
        } else if (data is List<int>) {
          final b = data is Uint8List ? data : Uint8List.fromList(data);
          if (b.length < 2) continue;
          final headerLen = (b[0] << 8) | b[1];
          if (b.length < 2 + headerLen) continue;
          final header = utf8.decode(b.sublist(2, 2 + headerLen));
          if (header.contains('Path:audio')) {
            audio.add(b.sublist(2 + headerLen));
          }
        }
      }
    } finally {
      try {
        await channel.sink.close();
      } catch (_) {}
    }
    final result = audio.toBytes();
    if (!ok || result.isEmpty) {
      throw 'Edge TTS 合成失败';
    }
    return result;
  }
}
