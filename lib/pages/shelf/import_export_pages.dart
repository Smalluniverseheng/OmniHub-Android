/// 导入图书（本机文件管理器）与 WiFi 传书页面
library import_export_pages;

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/omnihub/novel/book_source.dart';
import 'package:venera/omnihub/novel/local_import.dart';
import 'package:venera/omnihub/wifi_transfer.dart';
import 'package:venera/utils/cbz.dart';
import 'package:venera/utils/import_comic.dart';
import 'package:venera/utils/translations.dart';

/// 从本机导入：打开文件管理器选择文件
/// 支持小说格式（txt/epub）与漫画格式（cbz/zip/7z/cb7）
Future<void> importBooksFromDevice(BuildContext context,
    {String? folder}) async {
  List<file_selector.XFile> files;
  try {
    files = await file_selector.openFiles(
      acceptedTypeGroups: [
        const file_selector.XTypeGroup(
          label: 'books',
          extensions: ['txt', 'epub', 'cbz', 'zip', '7z', 'cb7'],
        ),
      ],
    );
  } catch (_) {
    return; // 用户取消
  }
  if (files.isEmpty) return;

  var novels = 0, comics = 0, failed = 0;
  final controller = showLoadingDialog(App.rootContext, allowCancel: false);
  for (final x in files) {
    final ext = x.path.split('.').last.toLowerCase();
    try {
      if (ext == 'txt' || ext == 'epub') {
        final book = await LocalNovelImporter.import(x.path);
        await NovelShelf.instance.add(book);
        novels++;
      } else if (const ['cbz', 'zip', '7z', 'cb7'].contains(ext)) {
        final comic = await CBZ.import(File(x.path));
        await ImportComic(selectedFolder: folder, copyToLocal: false)
            .registerComics({folder: [comic]}, false);
        comics++;
      } else {
        failed++;
      }
    } catch (e, s) {
      failed++;
      Log.error("Import from device", e.toString(), s);
    }
  }
  controller.close();

  if (context.mounted) {
    final parts = <String>[
      if (novels > 0) "@n 本小说".tlParams({'n': novels}),
      if (comics > 0) "@c 部漫画".tlParams({'c': comics}),
    ];
    context.showMessage(
      message: parts.isEmpty
          ? (failed > 0 ? "导入失败，请检查文件格式".tl : "未导入任何文件".tl)
          : "已导入 ${parts.join('、')}"
              "${failed > 0 ? '，$failed 个失败' : ''}",
    );
  }
}

/// WiFi 传书页：手机开局域网服务，电脑浏览器上传
class WifiTransferPage extends StatefulWidget {
  const WifiTransferPage({super.key});

  @override
  State<WifiTransferPage> createState() => _WifiTransferPageState();
}

class _WifiTransferPageState extends State<WifiTransferPage> {
  final _server = WifiTransferServer.instance;
  final List<WifiReceivedFile> _received = [];
  StreamSubscription<WifiReceivedFile>? _sub;
  bool _running = false;
  String _url = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _server.fileHandler = _handleFile;
    _sub = _server.onFile.listen((f) {
      if (mounted) setState(() => _received.insert(0, f));
    });
    _start();
  }

  Future<String> _handleFile(String savedPath, String fileName) async {
    final ext = fileName.split('.').last.toLowerCase();
    if (ext == 'txt' || ext == 'epub') {
      final book = await LocalNovelImporter.import(savedPath);
      await NovelShelf.instance.add(book);
      return '已导入小说《${book.name}》（${"小说书架".tl}）';
    }
    if (const ['cbz', 'zip', '7z', 'cb7'].contains(ext)) {
      final comic = await CBZ.import(File(savedPath));
      await ImportComic(copyToLocal: false)
          .registerComics({null: [comic]}, false);
      return '已导入漫画《${comic.title}》';
    }
    return '已接收 $fileName（暂不支持自动导入）';
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      await WifiTransferServer.resolveIPv4();
      final url = await _server.start();
      if (mounted) {
        setState(() {
          _running = true;
          _url = url;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _stop() async {
    await _server.stop();
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _server.fileHandler = null;
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("WiFi 传书".tl)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    _running ? Icons.wifi : Icons.wifi_off,
                    size: 40,
                    color: _running
                        ? context.colorScheme.primary
                        : context.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  if (_running) ...[
                    Text("在电脑浏览器打开以下网址".tl,
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _url));
                        context.showMessage(message: "已复制".tl);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _url,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.colorScheme.onPrimaryContainer,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "电脑需与手机连接同一 WiFi。\n在网页中选择或拖入文件即可传输到手机。"
                      .tl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: context.colorScheme.outline),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop, size: 18),
                      label: Text("停止服务".tl),
                    ),
                  ] else if (_error != null) ...[
                    Text(_error!,
                        style: TextStyle(color: context.colorScheme.error)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text("重试".tl),
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_received.isNotEmpty) ...[
            Text("已接收".tl,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            for (final f in _received)
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.file_present, size: 20),
                  title: Text(f.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${(f.size / 1048576).toStringAsFixed(1)} MB · ${f.note}',
                    maxLines: 2,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ] else ...[
            const SizedBox(height: 24),
            Center(
              child: Text(
                "还没有收到文件".tl,
                style: TextStyle(color: context.colorScheme.outline),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
