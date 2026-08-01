/// OmniHub AI 对话主页（Kimi 风格）
///
/// - 左侧 4/5 宽历史抽屉：三杠按钮或整页右滑均可呼出，点右侧 1/5 区域返回
/// - 输入栏：+ 面板（拍照/照片/文件/常用语/联网搜索）、语音长按转文字、
///   有内容时才显示发送键
/// - 长文本粘贴自动转附件（可撤销）
/// - 模型选择：厂商树状折叠、聊天/图片/视频分类、过期模型隐藏
/// - 能力感知：非视觉模型隐藏图片/拍照入口
/// - 对话 5 轮后 AI 自动命名标题；置顶最多 3 个；空对话不保存
library ai_chat_page;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/omnihub/ai/ai_api.dart';
import 'package:venera/omnihub/ai/ai_media_api.dart';
import 'package:venera/omnihub/ai/ai_media_models.dart';
import 'package:venera/omnihub/ai/ai_models.dart';
import 'package:venera/omnihub/ai/ai_providers.dart';
import 'package:venera/omnihub/ai/ai_store.dart';
import 'package:venera/omnihub/ai/ai_websearch.dart';
import 'package:venera/omnihub/ai/annotations.dart';
import 'package:venera/omnihub/ai/brand_icon.dart';
import 'package:venera/omnihub/sync/omni_sync.dart';
import 'package:venera/pages/settings/settings_page.dart';
import 'package:venera/pages/video/video_pages.dart';
import 'package:venera/utils/translations.dart';

part 'ai_chat_parts.dart';

/// 剪贴板超过该长度自动转为附件
const int kPasteToAttachmentThreshold = 800;

/// AI 主页
class AiChatListPage extends StatefulWidget {
  /// 打开指定历史对话（可选）
  final String? conversationId;

  /// 书籍上下文（漫画详情页「问 AI」入口）
  final String? bookContext;
  final String? bookRef;

  const AiChatListPage(
      {super.key, this.conversationId, this.bookContext, this.bookRef});

  @override
  State<AiChatListPage> createState() => AiHomePageState();
}

/// 对外开放 State 类型名（drawer 手势需要）
class AiHomePageState extends State<AiChatListPage>
    with SingleTickerProviderStateMixin {
  AiConversation? _conv;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  bool _sending = false;
  CancelToken? _cancel;

  /// 待发送附件 [{type, name, path}]
  final List<Map<String, String>> _pendingAttachments = [];

  /// 抽屉开合动画（0=关闭 1=打开）
  late final AnimationController _drawerCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  bool _drawerDragging = false;
  double get _drawerT => _drawerCtrl.value;

  /// 语音
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;

  /// 联网搜索：auto / off
  String get _webSearch => appdata.settings['aiWebSearch']?.toString() ?? 'auto';

  /// 生图比例 / 生视频比例与时长
  String _mediaRatio = '1:1';
  String _videoRatio = '16:9';
  String _videoDuration = '5';

  bool get _hasText => _input.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    AiStore.instance.addListener(_onStore);
    AiStore.instance.load().then((_) {
      AiStore.instance.pruneEmpty();
      if (widget.conversationId != null) {
        try {
          _conv = AiStore.instance.conversations
              .firstWhere((c) => c.id == widget.conversationId);
        } catch (_) {}
      } else if (widget.bookContext != null) {
        _conv = AiStore.instance.newConversation(
            bookContext: widget.bookContext, bookRef: widget.bookRef);
      }
      if (mounted) setState(() {});
    });
    _input.addListener(() => setState(() {}));
    _drawerCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _initSpeech();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  /// 供 part 扩展方法安全触发重建（setState 为 protected）
  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _initSpeech() async {
    try {
      _speechReady = await _speech.initialize();
    } catch (_) {
      _speechReady = false;
    }
  }

  @override
  void dispose() {
    AiStore.instance.removeListener(_onStore);
    AiStore.instance.pruneEmpty();
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    _cancel?.cancel();
    _speech.stop();
    _drawerCtrl.dispose();
    super.dispose();
  }

  /// 当前会话使用的模型 id
  String get _currentModelId {
    if (_conv != null && _conv!.model.isNotEmpty) return _conv!.model;
    return AiStore.instance.effectiveModel;
  }

  /// 当前模型目录条目（可能为 null：聚合平台自定义模型）
  AiModel? get _currentCatalogModel => AiModels.get(_currentModelId);

  /// 当前模型能力：视觉（未收录的聚合模型默认允许，由用户自行判断）
  bool get _modelSupportsVision =>
      _currentCatalogModel == null || _currentCatalogModel!.vision;

  /// 当前选中的媒体模型（图像/视频），null 表示聊天模型
  AiMediaModel? get _currentMediaModel {
    final id = _currentModelId;
    for (final m in kAiMediaModels) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _newConversation() {
    setState(() {
      _conv = null;
      _pendingAttachments.clear();
      _input.clear();
    });
    _closeDrawer();
  }

  void _openConversation(String id) {
    final store = AiStore.instance;
    try {
      _conv = store.conversations.firstWhere((c) => c.id == id);
    } catch (_) {
      _conv = null;
    }
    setState(() {});
    _closeDrawer();
    _scrollToBottom();
  }

  void _closeDrawer() {
    _drawerCtrl.animateTo(0, curve: Curves.easeOutCubic);
  }

  void _openDrawer() {
    _drawerCtrl.animateTo(1, curve: Curves.easeOutCubic);
  }

  // ---------------- 发送 ----------------

  List<AiMessage> _buildRequestMessages() {
    final msgs = <AiMessage>[];
    if (_conv?.bookContext != null && _conv!.bookContext!.isNotEmpty) {
      msgs.add(AiMessage('system',
          '你是用户的阅读伴侣。用户正在阅读以下作品，回答时请结合作品上下文，简洁准确：\n\n'
          '${_conv!.bookContext}'));
    } else {
      msgs.add(AiMessage('system', '你是 OmniHub 内置的 AI 助手，回答简洁准确。'));
    }
    msgs.addAll(_conv!.messages);
    return msgs;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _pendingAttachments.isEmpty) || _sending) return;
    final store = AiStore.instance;
    final provider = AiProviders.get(
            _conv?.providerSlug ?? store.selectedProvider) ??
        store.currentProvider;
    if (provider == null) return;
    final key = store.getKey(provider.keySlug);
    if (key.isEmpty) {
      context.showMessage(message: "请先配置 ${provider.name} 的 API Key");
      context.to(() => const SettingsPage(initialPage: 6));
      return;
    }
    final model = _currentModelId;
    if (model.isEmpty) {
      context.showMessage(message: "请先选择模型");
      return;
    }

    _conv ??= store.newConversation();
    final attachments = List<Map<String, String>>.from(_pendingAttachments);
    _input.clear();
    setState(() {
      _pendingAttachments.clear();
      _conv!.messages
          .add(AiMessage('user', text, attachments: attachments));
      _sending = true;
    });
    _scrollToBottom();

    final media = _currentMediaModel;
    if (media != null) {
      await _sendMedia(media, provider, key, text);
      return;
    }
    await _sendChat(provider, key, model);
  }

  /// 若配置了独立联网搜索 API，先检索并注入上下文
  Future<List<AiMessage>> _messagesWithSearch() async {
    final base = _buildRequestMessages();
    if (_webSearch != 'auto' || !AiWebSearch.configured) return base;
    final lastUser = base.lastWhere((m) => m.role == 'user',
        orElse: () => const AiMessage('user', ''));
    if (lastUser.content.isEmpty) return base;
    final results = await AiWebSearch.search(lastUser.content);
    if (results.isEmpty) return base;
    return [
      ...base,
      AiMessage('system', AiWebSearch.digest(results)),
    ];
  }

  /// 文本对话流式发送
  Future<void> _sendChat(
      AiProvider provider, String key, String model) async {
    setState(() {
      _conv!.messages.add(const AiMessage('assistant', ''));
    });
    _scrollToBottom();
    _cancel = CancelToken();
    try {
      await AiApi.chatStream(
        provider: provider,
        apiKey: key,
        model: model,
        messages: await _messagesWithSearch(),
        cancelToken: _cancel,
        webSearch: _webSearch == 'auto',
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
      AiStore.instance.updateConversation(_conv!);
      _maybeAutoTitle(provider, key, model);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        AiStore.instance.updateConversation(_conv!);
      } else {
        _markError(e.toString());
      }
    } catch (e) {
      _markError(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 图像/视频生成
  Future<void> _sendMedia(
      AiMediaModel media, AiProvider provider, String key, String prompt) async {
    final store = AiStore.instance;
    try {
      if (media.type == 'image') {
        const sizeMap = {
          '1:1': '1024x1024',
          '16:9': '1280x720',
          '9:16': '720x1280',
          '4:3': '1152x864',
          '3:4': '864x1152',
        };
        final res = await AiMediaApi.generateImage(
          provider: provider,
          apiKey: key,
          model: media.id,
          prompt: prompt,
          customBase: store.customBase,
          size: sizeMap[_mediaRatio] ?? '1024x1024',
        );
        final saved = <Map<String, String>>[];
        var i = 0;
        for (final b64 in res.b64Images) {
          final p = await _saveBytes(
              base64Decode(b64), 'gen_${DateTime.now().millisecondsSinceEpoch}_$i.png');
          saved.add({'type': 'image', 'name': '生成图.png', 'path': p});
          i++;
        }
        for (final url in res.urls) {
          try {
            final bytes = await _download(url);
            final p = await _saveBytes(
                bytes, 'gen_${DateTime.now().millisecondsSinceEpoch}_$i.png');
            saved.add({'type': 'image', 'name': '生成图.png', 'path': p});
            i++;
          } catch (_) {
            // 下载失败时保留链接
            saved.add({'type': 'imageUrl', 'name': '生成图', 'path': url});
          }
        }
        setState(() {
          _conv!.messages.add(AiMessage('assistant', prompt,
              attachments: saved, kind: 'image'));
        });
      } else {
        // 视频：任务制轮询
        final taskId = await AiMediaApi.createVideoTask(
          provider: provider,
          apiKey: key,
          model: media.id,
          prompt: prompt,
          customBase: store.customBase,
          ratio: _videoRatio,
          duration: _videoDuration,
        );
        setState(() {
          _conv!.messages
              .add(const AiMessage('assistant', '⏳ 视频生成中，请稍候…', kind: 'video'));
        });
        String? url;
        for (var i = 0; i < 60; i++) {
          await Future.delayed(const Duration(seconds: 5));
          url = await AiMediaApi.pollVideoTask(
            provider: provider,
            apiKey: key,
            taskId: taskId,
            customBase: store.customBase,
          );
          if (url != null) break;
          if (!mounted) return;
        }
        if (!mounted) return;
        setState(() {
          _conv!.messages[_conv!.messages.length - 1] = AiMessage(
              'assistant',
              url != null ? url : '视频生成超时，请稍后在历史记录中查看任务状态',
              kind: 'video');
        });
      }
      store.updateConversation(_conv!);
    } catch (e) {
      setState(() {
        _conv!.messages
            .add(AiMessage('assistant', '⚠ 生成失败：$e', kind: 'text'));
      });
      store.updateConversation(_conv!);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom();
  }

  /// 对话满 5 轮后让 AI 生成标题（仅一次）
  void _maybeAutoTitle(AiProvider provider, String key, String model) {
    final conv = _conv!;
    if (conv.autoTitled) return;
    final userRounds = conv.messages.where((m) => m.role == 'user').length;
    if (userRounds < 5) return;
    conv.autoTitled = true;
    final history = conv.messages
        .take(12)
        .map((m) => '${m.role == 'user' ? '用户' : 'AI'}: ${m.content}')
        .join('\n');
    final buf = StringBuffer();
    AiApi.chatStream(
      provider: provider,
      apiKey: key,
      model: model,
      messages: [
        AiMessage('system',
            '根据以下对话内容，生成一个不超过 15 个字的简短标题。只输出标题本身，不要标点结尾，不要解释。'),
        AiMessage('user', history),
      ],
      onToken: (t) => buf.write(t),
    ).then((_) {
      final title = buf.toString().trim().replaceAll('\n', ' ');
      if (title.isNotEmpty && mounted) {
        conv.title = title.length > 20 ? title.substring(0, 20) : title;
        AiStore.instance.updateConversation(conv);
      }
    }).catchError((_) {});
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

  // ---------------- 附件 ----------------

  Future<String> _saveBytes(List<int> bytes, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/ai_attachments');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final file = File('${folder.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<List<int>> _download(String url) async {
    final res = await Dio().get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes));
    return res.data!;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: source, imageQuality: 85);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final path = await _saveBytes(
          bytes, 'img_${DateTime.now().millisecondsSinceEpoch}.${x.name.split('.').last}');
      setState(() {
        _pendingAttachments
            .add({'type': 'image', 'name': x.name, 'path': path});
      });
    } catch (e) {
      if (mounted) context.showMessage(message: '选择图片失败：$e');
    }
  }

  Future<void> _pickFile() async {
    try {
      const typeGroup = XTypeGroup(label: '文件');
      final x = await openFile(acceptedTypeGroups: [typeGroup]);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final path = await _saveBytes(
          bytes, 'file_${DateTime.now().millisecondsSinceEpoch}_${x.name}');
      setState(() {
        _pendingAttachments
            .add({'type': 'file', 'name': x.name, 'path': path});
      });
    } catch (e) {
      if (mounted) context.showMessage(message: '选择文件失败：$e');
    }
  }

  /// 长文本粘贴 → 附件
  Future<void> _checkPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.length < kPasteToAttachmentThreshold) {
      if (text.isNotEmpty) {
        _input.text = _input.text + text;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        setState(() {});
      }
      return;
    }
    // 判断类型：markdown / 代码 / 纯文本
    var ext = 'txt';
    if (RegExp(r'^#{1,6}\s|\*\*|- \[|\[.+\]\(.+\)|```', multiLine: true)
        .hasMatch(text)) {
      ext = 'md';
    } else if (RegExp(r'^\s*(import |package |void |class |function |def |#include)',
            multiLine: true)
        .hasMatch(text)) {
      ext = 'txt';
    }
    final path = await _saveBytes(utf8.encode(text),
        'paste_${DateTime.now().millisecondsSinceEpoch}.$ext');
    setState(() {
      _pendingAttachments
          .add({'type': 'file', 'name': '粘贴文本.$ext', 'path': path});
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已将长文本转为附件（${text.length} 字）'),
      action: SnackBarAction(
        label: '返回',
        onPressed: () {
          setState(() {
            _pendingAttachments
                .removeWhere((a) => a['path'] == path);
            _input.text = text;
            _input.selection =
                TextSelection.collapsed(offset: _input.text.length);
          });
          try {
            File(path).deleteSync();
          } catch (_) {}
        },
      ),
      duration: const Duration(seconds: 4),
    ));
  }

  // ---------------- 语音 ----------------

  Future<void> _startVoice() async {
    if (!_speechReady) {
      _speechReady = await _speech.initialize();
    }
    if (!_speechReady) {
      if (mounted) context.showMessage(message: '语音识别不可用，请检查麦克风权限');
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        _input.text = r.recognizedWords;
        _input.selection =
            TextSelection.collapsed(offset: _input.text.length);
        setState(() {});
      },
      localeId: 'zh_CN',
      listenOptions: SpeechListenOptions(partialResults: true),
    );
  }

  Future<void> _stopVoice() async {
    await _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final drawerWidth = size.width * 0.8;
    return GestureDetector(
      onHorizontalDragStart: (d) {
        _drawerDragging = true;
      },
      onHorizontalDragUpdate: (d) {
        if (!_drawerDragging) return;
        _drawerCtrl.stop();
        final delta = d.delta.dx / drawerWidth;
        _drawerCtrl.value = (_drawerCtrl.value + delta).clamp(0.0, 1.0);
      },
      onHorizontalDragEnd: (d) {
        _drawerDragging = false;
        final velocity = d.primaryVelocity ?? 0;
        final open = velocity > 300 ||
            (velocity > -300 && _drawerCtrl.value > 0.32);
        _drawerCtrl.animateTo(open ? 1 : 0, curve: Curves.easeOutCubic);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: ClipRect(
          child: Stack(
            children: [
              // 历史抽屉（底层，固定左 4/5）
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: drawerWidth,
                child: AiHistoryDrawer(
                  currentId: _conv?.id,
                  onOpen: _openConversation,
                  onNew: _newConversation,
                ),
              ),
              // 主对话区：整页左右平移
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(drawerWidth * _drawerT, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(26 * _drawerT),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.colorScheme.surface,
                        boxShadow: [
                          if (_drawerT > 0)
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: 0.18 * _drawerT),
                              blurRadius: 24,
                              offset: const Offset(-6, 0),
                            ),
                        ],
                      ),
                      child: _buildChatBody(context),
                    ),
                  ),
                ),
              ),
              // 遮罩：抽屉开着时点击对话区（右 1/5）返回
              if (_drawerT > 0)
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(drawerWidth * _drawerT, 0),
                    child: GestureDetector(
                      onTap: _closeDrawer,
                      child: Container(
                        color:
                            Colors.black.withValues(alpha: 0.10 * _drawerT),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatBody(BuildContext context) {
    final messages = _conv?.messages ?? const <AiMessage>[];
    return SafeArea(
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: messages.isEmpty
                ? _buildGreeting()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) =>
                        _buildBubble(messages[i], i),
                  ),
          ),
          if (_sending)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextButton.icon(
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: Text("停止".tl),
                onPressed: () => _cancel?.cancel(),
              ),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  /// 顶栏：三杠 + 模型选择 + 新对话
  Widget _buildTopBar() {
    final media = _currentMediaModel;
    final modelName = media?.name ??
        _currentCatalogModel?.name ??
        (_currentModelId.isEmpty ? '选择模型' : _currentModelId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: _openDrawer,
          ),
          Expanded(
            child: Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _showModelPicker,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(modelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const Icon(Icons.keyboard_arrow_down, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: "新对话",
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newConversation,
          ),
        ],
      ),
    );
  }

  /// 空对话欢迎页：厂商标识 + 当前模型介绍 + 今日推荐
  Widget _buildGreeting() {
    final media = _currentMediaModel;
    final catalog = _currentCatalogModel;
    final modelId = _currentModelId;
    final modelName = media?.name ??
        catalog?.name ??
        (modelId.isEmpty ? 'OmniHub AI' : modelId);
    final providerName = media?.provider ?? catalog?.provider ?? '';
    final providerSlug = AiModels.keySlugOf(providerName) ??
        _conv?.providerSlug ??
        AiStore.instance.selectedProvider;
    final provider = AiProviders.get(providerSlug);
    final typeLabel = media?.type == 'image'
        ? '图片'
        : media?.type == 'video'
            ? '视频'
            : '聊天';
    final desc = media?.desc ??
        catalog?.desc ??
        '支持文本对话、图片生成、视频生成与阅读辅助。';
    final prompts = media?.type == 'image'
        ? const [
            '画一张赛博朋克风格的城市夜景',
            '生成一个极简扁平风的 App 图标',
            '做一张夏季饮品的电商促销主图',
          ]
        : media?.type == 'video'
            ? const [
                '生成一段海边日落延时视频',
                '做一个小行星环绕的科幻短片',
                '生成一个未来城市飞行镜头',
              ]
            : const [
                '帮我写一封礼貌的请假邮件',
                '用简单的话解释一个复杂概念',
                '给我制定一份三天学习计划',
              ];

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (provider != null)
                BrandIcon(
                  lobe: provider.iconLobe,
                  simple: provider.iconSimple,
                  color: provider.color,
                  letter: provider.name,
                  size: 76,
                )
              else
                Icon(Icons.smart_toy_outlined,
                    size: 76, color: context.colorScheme.primary),
              const SizedBox(height: 22),
              Text(
                '你好，我是 $modelName',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                desc,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: context.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider != null) ...[
                      BrandIcon(
                        lobe: provider.iconLobe,
                        simple: provider.iconSimple,
                        color: provider.color,
                        letter: provider.name,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        '正在使用 $modelName · $typeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '今日推荐',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final prompt in prompts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      _input.text = prompt;
                      _input.selection = TextSelection.collapsed(
                          offset: _input.text.length);
                      _inputFocus.requestFocus();
                      refresh();
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 13),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: context.colorScheme.outlineVariant),
                      ),
                      child: Text(prompt,
                          style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
