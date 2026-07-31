/// OmniHub 阅读注释（AI 注释 + 手写笔记）
///
/// 参考 read-aware 的 ask-note 思路：每次「问 AI」或手写批注都留下
/// 锚定到书籍的笔记。本地 JSON 持久化，登录后经 Supabase
/// user_data 表（module = annotations）与网页端互通。
library annotations;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../sync/omni_sync.dart';

class AiAnnotation {
  String id;

  /// 书籍标识：comicId@sourceKey
  String bookRef;
  String bookTitle;

  /// 类型：note（手写笔记）/ ask（AI 问答留痕）
  String type;

  /// 引用的原文/选中文本（可为空）
  String quote;

  /// 笔记内容 / AI 回答
  String content;

  /// 提问（ask 类型时为用户的原始问题）
  String question;
  int updatedAt;

  AiAnnotation({
    required this.id,
    required this.bookRef,
    required this.bookTitle,
    required this.type,
    this.quote = '',
    this.content = '',
    this.question = '',
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookRef': bookRef,
        'bookTitle': bookTitle,
        'type': type,
        'quote': quote,
        'content': content,
        'question': question,
        'updatedAt': updatedAt,
      };

  factory AiAnnotation.fromJson(Map<String, dynamic> j) => AiAnnotation(
        id: j['id'] as String? ?? '',
        bookRef: j['bookRef'] as String? ?? '',
        bookTitle: j['bookTitle'] as String? ?? '',
        type: j['type'] as String? ?? 'note',
        quote: j['quote'] as String? ?? '',
        content: j['content'] as String? ?? '',
        question: j['question'] as String? ?? '',
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class AnnotationSyncResult {
  final bool ok;
  final int pushed;
  final int pulled;
  final String error;

  AnnotationSyncResult(
      {required this.ok, this.pushed = 0, this.pulled = 0, this.error = ''});
}

class AnnotationStore extends ChangeNotifier {
  AnnotationStore._();
  static final AnnotationStore instance = AnnotationStore._();

  static const String syncModule = 'annotations';

  final List<AiAnnotation> items = [];

  /// 本地已删除但云端可能还存在的墓碑 id（上行时传 _deleted）
  final Set<String> _tombstones = {};

  File? _file;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/omnihub_annotations.json');
      if (!_file!.existsSync()) return;
      final j = jsonDecode(await _file!.readAsString());
      for (final a in (j['items'] as List? ?? [])) {
        items.add(AiAnnotation.fromJson(Map<String, dynamic>.from(a)));
      }
      for (final t in (j['tombstones'] as List? ?? [])) {
        _tombstones.add(t.toString());
      }
      _sort();
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file ??= File('${dir.path}/omnihub_annotations.json');
      await _file!.writeAsString(jsonEncode({
        'items': items.map((a) => a.toJson()).toList(),
        'tombstones': _tombstones.toList(),
      }));
    } catch (_) {}
  }

  void _sort() => items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<AiAnnotation> forBook(String bookRef) =>
      items.where((a) => a.bookRef == bookRef).toList();

  void add(AiAnnotation a) {
    items.insert(0, a);
    _tombstones.remove(a.id);
    _sort();
    notifyListeners();
    save();
  }

  void remove(String id) {
    items.removeWhere((a) => a.id == id);
    _tombstones.add(id);
    notifyListeners();
    save();
  }

  /// 与云端双向同步（last-write-wins，按 updatedAt 合并）
  Future<AnnotationSyncResult> sync() async {
    if (!OmniSync.instance.isLoggedIn) {
      return AnnotationSyncResult(ok: false, error: '未登录');
    }
    try {
      // 上行：本地全量 + 墓碑
      final records = <String, Map<String, dynamic>>{
        for (final a in items) a.id: a.toJson(),
        for (final t in _tombstones) t: {'_deleted': true},
      };
      await OmniSync.instance.pushRecords(syncModule, records);
      final pushed = records.length;

      // 下行：云端全量合并
      final remote = await OmniSync.instance.pullModule(syncModule);
      var pulled = 0;
      final localById = {for (final a in items) a.id: a};
      for (final row in remote) {
        final id = row['key'] as String? ?? '';
        final value = row['value'];
        if (id.isEmpty || value is! Map) continue;
        if (value['_deleted'] == true) {
          if (localById.remove(id) != null) pulled++;
          continue;
        }
        final ra = AiAnnotation.fromJson(Map<String, dynamic>.from(value));
        final la = localById[id];
        if (la == null || ra.updatedAt > la.updatedAt) {
          localById[id] = ra;
          _tombstones.remove(id);
          pulled++;
        }
      }
      items
        ..clear()
        ..addAll(localById.values);
      _sort();
      _tombstones.clear(); // 已上行成功，墓碑清空
      notifyListeners();
      save();
      return AnnotationSyncResult(ok: true, pushed: pushed, pulled: pulled);
    } catch (e) {
      return AnnotationSyncResult(ok: false, error: e.toString());
    }
  }
}
