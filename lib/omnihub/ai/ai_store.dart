/// OmniHub AI 本地存储
///
/// Key、选中模型、对话记录全部存本地 JSON 文件（文档目录 omnihub_ai.json）。
/// Key 只存本地，不上云（网页端为 AES 加密存 Supabase，方案不互通，
/// 云端同步仅同步非敏感的选中项配置）。
library ai_store;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_api.dart';
import 'ai_providers.dart';

class AiConversation {
  String id;
  String title;
  String providerSlug;
  String model;
  List<AiMessage> messages;

  /// 书籍上下文（来自漫画详情页「问 AI」）：书名/简介/标签等
  String? bookContext;

  /// 关联书籍标识（comicId@sourceKey），用于注释归属
  String? bookRef;
  int updatedAt;

  /// 置顶（最多 3 个，按 pinAt 排序）
  bool pinned;
  int pinAt;

  /// 是否已由 AI 自动命名过
  bool autoTitled;

  AiConversation({
    required this.id,
    required this.title,
    required this.providerSlug,
    required this.model,
    required this.messages,
    this.bookContext,
    this.bookRef,
    required this.updatedAt,
    this.pinned = false,
    this.pinAt = 0,
    this.autoTitled = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'provider': providerSlug,
        'model': model,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (bookContext != null) 'bookContext': bookContext,
        if (bookRef != null) 'bookRef': bookRef,
        'updatedAt': updatedAt,
        if (pinned) 'pinned': true,
        if (pinAt > 0) 'pinAt': pinAt,
        if (autoTitled) 'autoTitled': true,
      };

  factory AiConversation.fromJson(Map<String, dynamic> j) => AiConversation(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '新对话',
        providerSlug: j['provider'] as String? ?? 'openai',
        model: j['model'] as String? ?? '',
        messages: ((j['messages'] as List?) ?? [])
            .map((e) => AiMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        bookContext: j['bookContext'] as String?,
        bookRef: j['bookRef'] as String?,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        pinned: j['pinned'] == true,
        pinAt: (j['pinAt'] as num?)?.toInt() ?? 0,
        autoTitled: j['autoTitled'] == true,
      );
}

/// 常用语（提示词库）
class AiPrompt {
  String id;
  String title;
  String content;
  int updatedAt;
  bool fromCloud;

  AiPrompt({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.fromCloud = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'updatedAt': updatedAt,
        if (fromCloud) 'fromCloud': true,
      };

  factory AiPrompt.fromJson(Map<String, dynamic> j) => AiPrompt(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        content: j['content'] as String? ?? '',
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        fromCloud: j['fromCloud'] == true,
      );
}

class AiStore extends ChangeNotifier {
  AiStore._();
  static final AiStore instance = AiStore._();

  /// keySlug → API Key（仅本地）
  final Map<String, String> keys = {};

  /// 自定义厂商 Base URL
  String customBase = '';

  String selectedProvider = 'deepseek';
  String selectedModel = '';

  final List<AiConversation> conversations = [];

  /// 常用语（本地）
  final List<AiPrompt> prompts = [];

  File? _file;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/omnihub_ai.json');
      if (!_file!.existsSync()) return;
      final j = jsonDecode(await _file!.readAsString());
      if (j['keys'] is Map) {
        (j['keys'] as Map).forEach((k, v) {
          if (v is String && v.isNotEmpty) keys[k.toString()] = v;
        });
      }
      customBase = j['customBase'] as String? ?? '';
      selectedProvider = j['selectedProvider'] as String? ?? 'deepseek';
      selectedModel = j['selectedModel'] as String? ?? '';
      for (final c in (j['conversations'] as List? ?? [])) {
        conversations
            .add(AiConversation.fromJson(Map<String, dynamic>.from(c)));
      }
      for (final p in (j['prompts'] as List? ?? [])) {
        prompts.add(AiPrompt.fromJson(Map<String, dynamic>.from(p)));
      }
      _sortConversations();
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file ??= File('${dir.path}/omnihub_ai.json');
      await _file!.writeAsString(jsonEncode({
        'keys': keys,
        'customBase': customBase,
        'selectedProvider': selectedProvider,
        'selectedModel': selectedModel,
        'conversations': conversations.map((c) => c.toJson()).toList(),
        'prompts': prompts.map((p) => p.toJson()).toList(),
      }));
    } catch (_) {}
  }

  String getKey(String slug) => keys[slug] ?? '';

  void setKey(String slug, String value) {
    final v = value.trim();
    if (v.isEmpty) {
      keys.remove(slug);
    } else {
      keys[slug] = v;
    }
    notifyListeners();
    save();
  }

  bool hasAnyKey() => keys.values.any((k) => k.isNotEmpty);

  AiProvider? get currentProvider => AiProviders.get(selectedProvider);

  String get effectiveModel {
    if (selectedModel.isNotEmpty) return selectedModel;
    final p = currentProvider;
    if (p != null && p.models.isNotEmpty) return p.models.first;
    return '';
  }

  void select(String slug, String model) {
    selectedProvider = slug;
    selectedModel = model;
    notifyListeners();
    save();
  }

  /// 排序：置顶在前（pinAt 新→旧），其余按 updatedAt 新→旧
  void _sortConversations() {
    conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.pinned && b.pinned) return b.pinAt.compareTo(a.pinAt);
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  AiConversation newConversation({String? bookContext, String? bookRef}) {
    final c = AiConversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: bookRef != null ? '书籍问答' : '新对话',
      providerSlug: selectedProvider,
      model: effectiveModel,
      messages: [],
      bookContext: bookContext,
      bookRef: bookRef,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    conversations.insert(0, c);
    notifyListeners();
    // 空对话先不落盘，有消息后才 save（updateConversation 里会存）
    return c;
  }

  void updateConversation(AiConversation c) {
    c.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _sortConversations();
    notifyListeners();
    save();
  }

  void deleteConversation(String id) {
    conversations.removeWhere((c) => c.id == id);
    notifyListeners();
    save();
  }

  /// 清除没有任何消息的空对话（页面销毁/返回时调用）
  void pruneEmpty() {
    final before = conversations.length;
    conversations.removeWhere((c) => c.messages.isEmpty);
    if (conversations.length != before) {
      notifyListeners();
      save();
    }
  }

  int get pinnedCount => conversations.where((c) => c.pinned).length;

  /// 置顶/取消置顶，最多 3 个；返回 false 表示超出上限未操作
  bool togglePin(String id) {
    final c = conversations.firstWhere((e) => e.id == id);
    if (!c.pinned && pinnedCount >= 3) return false;
    c.pinned = !c.pinned;
    c.pinAt = c.pinned ? DateTime.now().millisecondsSinceEpoch : 0;
    _sortConversations();
    notifyListeners();
    save();
    return true;
  }

  void renameConversation(String id, String title) {
    final c = conversations.firstWhere((e) => e.id == id);
    c.title = title;
    c.autoTitled = true; // 手动命名后不再自动改名
    notifyListeners();
    save();
  }

  // ---------------- 常用语 ----------------

  void addPrompt(String title, String content) {
    prompts.insert(
        0,
        AiPrompt(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          content: content,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
    notifyListeners();
    save();
  }

  void updatePrompt(AiPrompt p, String title, String content) {
    p.title = title;
    p.content = content;
    p.updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    save();
  }

  void deletePrompt(String id) {
    prompts.removeWhere((p) => p.id == id);
    notifyListeners();
    save();
  }

  /// 导入常用语（JSON 数组 [{title, content}]），返回新增条数（按标题去重）
  int importPrompts(List<Map<String, dynamic>> list) {
    var added = 0;
    for (final j in list) {
      final title = (j['title'] ?? '').toString().trim();
      final content = (j['content'] ?? '').toString().trim();
      if (content.isEmpty) continue;
      if (prompts.any((p) => p.title == title && p.content == content)) {
        continue;
      }
      prompts.add(AiPrompt(
        id: '${DateTime.now().millisecondsSinceEpoch}-$added',
        title: title.isEmpty ? '未命名' : title,
        content: content,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      added++;
    }
    if (added > 0) {
      notifyListeners();
      save();
    }
    return added;
  }

  List<Map<String, dynamic>> exportPrompts() =>
      prompts.map((p) => {'title': p.title, 'content': p.content}).toList();
}
