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

  AiConversation({
    required this.id,
    required this.title,
    required this.providerSlug,
    required this.model,
    required this.messages,
    this.bookContext,
    this.bookRef,
    required this.updatedAt,
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
      conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
    save();
    return c;
  }

  void updateConversation(AiConversation c) {
    c.updatedAt = DateTime.now().millisecondsSinceEpoch;
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
    save();
  }

  void deleteConversation(String id) {
    conversations.removeWhere((c) => c.id == id);
    notifyListeners();
    save();
  }
}
