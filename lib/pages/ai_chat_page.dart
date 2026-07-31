/// OmniHub AI 对话页
///
/// 会话列表 + 聊天界面（流式输出）。支持从漫画详情页带书籍上下文
/// 打开（「问 AI」），AI 回答可一键存为阅读注释。
library ai_chat_page;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/omnihub/ai/ai_api.dart';
import 'package:venera/omnihub/ai/ai_providers.dart';
import 'package:venera/omnihub/ai/ai_store.dart';
import 'package:venera/omnihub/ai/annotations.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/utils/translations.dart';

/// 会话列表页
class AiChatListPage extends StatefulWidget {
  const AiChatListPage({super.key});

  @override
  State<AiChatListPage> createState() => _AiChatListPageState();
}

class _AiChatListPageState extends State<AiChatListPage> {
  @override
  void initState() {
    super.initState();
    AiStore.instance.addListener(_onChange);
    AiStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AiStore.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AiStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text("AI Chat".tl),
        actions: [
          IconButton(
            tooltip: "AI Settings".tl,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.to(() => const SettingsPage(initialPage: 6)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (!store.hasAnyKey()) {
            context.showMessage(message: "请先在 AI 设置中配置 API Key");
            context.to(() => const SettingsPage(initialPage: 6));
            return;
          }
          final c = store.newConversation();
          context.to(() => AiChatPage(conversationId: c.id));
        },
        child: const Icon(Icons.add),
      ),
      body: store.conversations.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_outlined,
                      size: 64, color: context.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text("还没有对话，点右下角开始".tl,
                      style: TextStyle(color: context.colorScheme.outline)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: store.conversations.length,
              itemBuilder: (context, i) {
                final c = store.conversations[i];
                final last = c.messages.isEmpty
                    ? ''
                    : c.messages.last.content.replaceAll('\n', ' ');
                return ListTile(
                  leading: Icon(c.bookRef != null
                      ? Icons.menu_book_outlined
                      : Icons.chat_bubble_outline),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    last.isEmpty ? '（空）' : last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.deleteConversation(c.id),
                  ),
                  onTap: () =>
                      context.to(() => AiChatPage(conversationId: c.id)),
                );
              },
            ),
    );
  }
}

/// 聊天页
class AiChatPage extends StatefulWidget {
  final String? conversationId;

  /// 新建对话时可带书籍上下文（漫画详情页「问 AI」入口）
  final String? bookContext;
  final String? bookRef;

  const AiChatPage({super.key, this.conversationId, this.bookContext, this.bookRef});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  AiConversation? _conv;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    AiStore.instance.load().then((_) {
      final store = AiStore.instance;
      if (widget.conversationId != null) {
        try {
          _conv = store.conversations.firstWhere((c) => c.id == widget.conversationId);
        } catch (_) {}
      }
      _conv ??= store.newConversation(
          bookContext: widget.bookContext, bookRef: widget.bookRef);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _cancel?.cancel();
    super.dispose();
  }

  List<AiMessage> _buildRequestMessages() {
    final msgs = <AiMessage>[];
    if (_conv?.bookContext != null && _conv!.bookContext!.isNotEmpty) {
      msgs.add(AiMessage('system',
          '你是用户的阅读伴侣（参考 ReadAware 的理念：AI 陪伴阅读而不是取代阅读）。'
          '用户正在阅读以下作品，回答时请结合作品上下文，简洁准确，必要时引用原文：\n\n'
          '${_conv!.bookContext}'));
    } else {
      msgs.add(AiMessage('system', '你是 OmniHub 内置的 AI 助手，回答简洁准确。'));
    }
    msgs.addAll(_conv!.messages);
    return msgs;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _conv == null) return;
    final store = AiStore.instance;
    final provider = AiProviders.get(_conv!.providerSlug) ?? store.currentProvider;
    if (provider == null) return;
    final key = store.getKey(provider.keySlug);
    if (key.isEmpty) {
      context.showMessage(message: "请先配置 ${provider.name} 的 API Key");
      return;
    }
    final model = _conv!.model.isNotEmpty ? _conv!.model : store.effectiveModel;
    if (model.isEmpty) {
      context.showMessage(message: "请先在 AI 设置中选择模型");
      return;
    }

    _input.clear();
    setState(() {
      _conv!.messages.add(AiMessage('user', text));
      _conv!.messages.add(const AiMessage('assistant', ''));
      _sending = true;
    });
    _scrollToBottom();

    _cancel = CancelToken();
    try {
      await AiApi.chatStream(
        provider: provider,
        apiKey: key,
        model: model,
        messages: _buildRequestMessages(),
        cancelToken: _cancel,
        onToken: (token) {
          if (!mounted) return;
          setState(() {
            final last = _conv!.messages.last;
            _conv!.messages[_conv!.messages.length - 1] =
                AiMessage('assistant', last.content + token);
          });
          _scrollToBottom();
        },
      );
      if (_conv!.title == '新对话' || _conv!.title == '书籍问答') {
        _conv!.title =
            text.length > 20 ? '${text.substring(0, 20)}…' : text;
      }
      store.updateConversation(_conv!);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        // 用户主动停止，保留已输出内容
        store.updateConversation(_conv!);
      } else {
        _markError(e.toString());
      }
    } catch (e) {
      _markError(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _markError(String err) {
    if (!mounted) return;
    setState(() {
      _conv!.messages[_conv!.messages.length - 1] =
          AiMessage('assistant', '⚠ 请求失败：$err');
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final conv = _conv;
    return Scaffold(
      appBar: AppBar(
        title: Text(conv?.title ?? "AI Chat".tl,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (conv?.bookRef != null)
            IconButton(
              tooltip: "保存最后一条回答为注释",
              icon: const Icon(Icons.note_add_outlined),
              onPressed: _saveLastAsAnnotation,
            ),
          if (_sending)
            IconButton(
              tooltip: "停止".tl,
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () => _cancel?.cancel(),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: conv == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: conv.messages.length,
                    itemBuilder: (context, i) =>
                        _buildBubble(conv.messages[i], i),
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBubble(AiMessage m, int index) {
    final isUser = m.role == 'user';
    final isLast = index == (_conv?.messages.length ?? 0) - 1;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: m.content));
          context.showMessage(message: "Copied".tl);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: isUser
                ? context.colorScheme.primaryContainer
                : context.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m.content.isEmpty && !isUser && _sending && isLast)
                const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                SelectableText(m.content),
              if (!isUser &&
                  _conv?.bookRef != null &&
                  m.content.isNotEmpty &&
                  !(_sending && isLast))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.note_add_outlined, size: 16),
                    label: Text("存为注释".tl, style: const TextStyle(fontSize: 12)),
                    onPressed: () => _saveAnnotation(m),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: "输入问题…".tl,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  void _saveLastAsAnnotation() {
    if (_conv == null) return;
    for (var i = _conv!.messages.length - 1; i >= 0; i--) {
      final m = _conv!.messages[i];
      if (m.role == 'assistant' && m.content.isNotEmpty) {
        _saveAnnotation(m);
        return;
      }
    }
    context.showMessage(message: "还没有可保存的回答");
  }

  void _saveAnnotation(AiMessage m) {
    final conv = _conv;
    if (conv == null || conv.bookRef == null) return;
    final idx = conv.messages.indexOf(m);
    final question =
        (idx > 0 && conv.messages[idx - 1].role == 'user')
            ? conv.messages[idx - 1].content
            : '';
    AnnotationStore.instance.add(AiAnnotation(
      id: 'ask-${DateTime.now().millisecondsSinceEpoch}',
      bookRef: conv.bookRef!,
      bookTitle: conv.bookContext?.split('\n').first
              .replaceFirst('书名：', '') ??
          conv.title,
      type: 'ask',
      question: question,
      content: m.content,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    context.showMessage(message: "已保存为注释".tl);
  }
}
