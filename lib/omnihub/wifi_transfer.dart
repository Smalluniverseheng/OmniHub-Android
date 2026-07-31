/// WiFi 传书（局域网传输）
///
/// 手机启动局域网 HTTP 服务并生成网址（如 http://192.168.1.5:1967），
/// 电脑/另一台设备在同一网络下用浏览器打开，即可把文件上传到手机。
/// 上传的小说文件（txt/epub）自动导入书架，漫画压缩包等保存在收件箱。
library wifi_transfer;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WifiReceivedFile {
  final String name;
  final int size;
  final String path;
  final String note; // 导入结果说明

  const WifiReceivedFile(this.name, this.size, this.path, this.note);
}

class WifiTransferServer {
  WifiTransferServer._();
  static final WifiTransferServer instance = WifiTransferServer._();

  HttpServer? _server;
  int port = 1967;

  final StreamController<WifiReceivedFile> _onFile =
      StreamController.broadcast();
  Stream<WifiReceivedFile> get onFile => _onFile.stream;

  bool get isRunning => _server != null;

  /// 收到文件后的处理回调（由页面注入：txt/epub → 导入小说）
  Future<String> Function(String savedPath, String fileName)? fileHandler;

  Future<String> start() async {
    if (_server != null) return address;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (_) {
      // 端口被占用时换随机端口
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      port = _server!.port;
    }
    _server!.listen(_handle);
    return address;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  String get address {
    final ip = _firstIPv4() ?? '0.0.0.0';
    return 'http://$ip:$port';
  }

  static String? _firstIPv4Cache;

  static String? _firstIPv4() {
    return _firstIPv4Cache;
  }

  static Future<String?> resolveIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            _firstIPv4Cache = addr.address;
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method == 'GET' && req.uri.path == '/') {
        await _servePage(req);
      } else if (req.method == 'POST' && req.uri.path == '/upload') {
        await _receive(req);
      } else if (req.method == 'OPTIONS') {
        req.response
          ..headers.add('Access-Control-Allow-Origin', '*')
          ..headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
          ..headers.add('Access-Control-Allow-Headers', '*');
        await req.response.close();
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _servePage(HttpRequest req) async {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_kUploadPage);
    await req.response.close();
  }

  Future<void> _receive(HttpRequest req) async {
    final name = req.uri.queryParameters['name'] ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
    final safeName = name.replaceAll(RegExp(r'[/\\]'), '_');
    final dir = Directory(
        '${Directory.systemTemp.path}/omnihub_wifi_inbox');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/$safeName');
    final sink = file.openWrite();
    await for (final chunk in req) {
      sink.add(chunk);
    }
    await sink.close();
    final size = await file.length();

    var note = '已保存到收件箱';
    if (fileHandler != null) {
      try {
        note = await fileHandler!(file.path, safeName);
      } catch (e) {
        note = '保存成功，导入失败：$e';
      }
    }
    _onFile.add(WifiReceivedFile(safeName, size, file.path, note));

    req.response
      ..statusCode = HttpStatus.ok
      ..headers.add('Access-Control-Allow-Origin', '*')
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'ok': true, 'name': safeName, 'note': note}));
    await req.response.close();
  }
}

/// 电脑端上传页（深色，拖拽 + 进度条）
const String _kUploadPage = r'''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OmniHub WiFi 传书</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;
    background:#0D0E13;color:#E4E7EF;min-height:100vh;display:flex;flex-direction:column;align-items:center;padding:40px 16px}
  .logo{width:72px;height:72px;border-radius:18px;background:linear-gradient(135deg,#6366F1,#8B5CF6);
    display:flex;align-items:center;justify-content:center;font-size:34px;box-shadow:0 8px 32px rgba(99,102,241,.35)}
  h1{font-size:20px;margin:18px 0 4px}
  .sub{color:#8B93A7;font-size:13px;margin-bottom:28px}
  .drop{width:100%;max-width:520px;border:2px dashed #3A4055;border-radius:16px;padding:48px 20px;
    text-align:center;color:#8B93A7;transition:.2s;cursor:pointer}
  .drop.over{border-color:#6366F1;background:rgba(99,102,241,.08);color:#C7CBE0}
  .drop b{color:#6366F1}
  .list{width:100%;max-width:520px;margin-top:24px}
  .item{background:#171923;border-radius:12px;padding:12px 16px;margin-bottom:10px;font-size:14px}
  .item .bar{height:6px;background:#262A3A;border-radius:3px;margin-top:8px;overflow:hidden}
  .item .bar i{display:block;height:100%;width:0;background:linear-gradient(90deg,#6366F1,#8B5CF6);border-radius:3px;transition:width .15s}
  .item .note{color:#7BE0A3;font-size:12px;margin-top:6px}
  .item .err{color:#F47067;font-size:12px;margin-top:6px}
  input[type=file]{display:none}
</style>
</head>
<body>
<div class="logo">📚</div>
<h1>OmniHub WiFi 传书</h1>
<div class="sub">选择或拖入文件，即刻传到手机 · 支持 txt / epub / 漫画压缩包</div>
<div class="drop" id="drop">点击选择文件，或把文件拖到这里<br><b>支持多选</b></div>
<input type="file" id="file" multiple>
<div class="list" id="list"></div>
<script>
var drop=document.getElementById('drop'),input=document.getElementById('file'),list=document.getElementById('list');
drop.onclick=function(){input.click()};
drop.ondragover=function(e){e.preventDefault();drop.classList.add('over')};
drop.ondragleave=function(){drop.classList.remove('over')};
drop.ondrop=function(e){e.preventDefault();drop.classList.remove('over');uploadAll(e.dataTransfer.files)};
input.onchange=function(){uploadAll(input.files)};
function uploadAll(files){for(var i=0;i<files.length;i++)upload(files[i])}
function upload(f){
  var el=document.createElement('div');el.className='item';
  el.innerHTML='<div>'+f.name+' <span style="color:#8B93A7">('+(f.size/1048576).toFixed(1)+' MB)</span></div>'
    +'<div class="bar"><i></i></div>';
  list.prepend(el);
  var bar=el.querySelector('i');
  var xhr=new XMLHttpRequest();
  xhr.open('POST','/upload?name='+encodeURIComponent(f.name));
  xhr.upload.onprogress=function(e){if(e.lengthComputable)bar.style.width=(e.loaded/e.total*100)+'%'};
  xhr.onload=function(){
    try{var r=JSON.parse(xhr.responseText);
      if(r.ok){bar.style.width='100%';
        var n=document.createElement('div');n.className='note';n.textContent='✓ '+r.note;el.appendChild(n);}
      else throw 0;
    }catch(_){var n2=document.createElement('div');n2.className='err';n2.textContent='✗ 上传失败';el.appendChild(n2);}
  };
  xhr.onerror=function(){var n=document.createElement('div');n.className='err';n.textContent='✗ 网络错误';el.appendChild(n)};
  xhr.send(f);
}
</script>
</body>
</html>
''';
