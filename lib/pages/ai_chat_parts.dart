/// ai_chat_page 的 UI 组件部分：气泡、输入栏、+ 面板、模型选择、历史抽屉
part of ai_chat_page;

extension _AiHomeUi on AiHomePageState {
  // ---------------- 消息气泡 ----------------

  Widget _buildBubble(AiMessage m, int index) {
    final isUser = m.role == 'user';
    final isLastAssistant =
        !isUser && index == (_conv?.messages.length ?? 0) - 1;
    final streaming = isLastAssistant && _sending && m.kind == 'text';

    return GestureDetector(
      onLongPress: () => _showMessageMenu(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? context.colorScheme.primaryContainer
                      : context.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.attachments.isNotEmpty)
                      _buildMessageAttachments(m),
                    if (m.kind == 'video')
                      _buildVideoContent(m)
                    else if (m.content.isEmpty && streaming)
                      const _ThinkingDots()
                    else
                      Text(
                        m.content + (streaming ? ' ▍' : ''),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: m.content.startsWith('⚠')
                              ? context.colorScheme.error
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 消息内附件：图片网格（点击放大/编辑/删除）、文件卡片
  Widget _buildMessageAttachments(AiMessage m) {
    final images = m.attachments
        .where((a) => a['type'] == 'image' || a['type'] == 'imageUrl')
        .toList();
    final files =
        m.attachments.where((a) => a['type'] == 'file').toList();
    final big = m.kind == 'image'; // AI 生图结果用大图展示
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < images.length; i++)
                  GestureDetector(
                    onTap: () => _showImageViewer(m, images, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: big ? 240 : 96,
                        height: big ? null : 96,
                        child: _attachmentImage(images[i]),
                      ),
                    ),
                  ),
              ],
            ),
          for (final f in files)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file_outlined,
                      size: 20, color: context.colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(f['name'] ?? '文件',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _attachmentImage(Map<String, String> a) {
    final path = a['path'] ?? '';
    if (a['type'] == 'imageUrl' || path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image));
    }
    return Image.file(File(path), fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image));
  }

  /// 视频消息：点击直接播放，长按复制链接
  Widget _buildVideoContent(AiMessage m) {
    final url = m.content;
    if (url.startsWith('http')) {
      return InkWell(
        onTap: () => context
            .to(() => VideoPlayerPage(title: 'AI 生成视频', url: url)),
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: url));
          context.showMessage(message: '视频链接已复制');
        },
        child: Container(
          width: 220,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_circle_fill,
                  size: 44, color: context.colorScheme.primary),
              const SizedBox(height: 6),
              const Text('点击播放生成视频',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    return Text(url);
  }

  /// 图片全屏查看：左上角返回，右上角 X 删除，支持旋转编辑
  void _showImageViewer(
      AiMessage m, List<Map<String, String>> images, int start) {
    var index = start;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final cur = images[index];
          final path = cur['path'] ?? '';
          final isLocal =
              cur['type'] == 'image' && !path.startsWith('http');
          return Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                PageView.builder(
                  controller: PageController(initialPage: start),
                  itemCount: images.length,
                  onPageChanged: (i) => setDlg(() => index = i),
                  itemBuilder: (_, i) => InteractiveViewer(
                    maxScale: 5,
                    child: Center(child: _attachmentImage(images[i])),
                  ),
                ),
                SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                      Row(
                        children: [
                          if (isLocal)
                            IconButton(
                              tooltip: '旋转',
                              icon: const Icon(Icons.rotate_right,
                                  color: Colors.white),
                              onPressed: () async {
                                await _rotateImage(path);
                                setDlg(() {});
                                refresh();
                              },
                            ),
                          IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.close,
                                color: Colors.white),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              m.attachments.removeWhere(
                                  (a) => a['path'] == path);
                              refresh();
                              if (_conv != null) {
                                AiStore.instance.updateConversation(_conv!);
                              }
                              if (isLocal) {
                                try {
                                  File(path).deleteSync();
                                } catch (_) {}
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ));
  }

  /// 旋转编辑图片（覆盖保存）
  Future<void> _rotateImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;
      final rotated = img.copyRotate(decoded, angle: 90);
      await File(path).writeAsBytes(img.encodePng(rotated));
      await FileImage(File(path)).evict();
    } catch (e) {
      if (mounted) context.showMessage(message: '编辑失败：$e');
    }
  }

  /// 长按消息菜单
  void _showMessageMenu(AiMessage m) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text("复制".tl),
              onTap: () {
                Clipboard.setData(ClipboardData(text: m.content));
                Navigator.pop(ctx);
                context.showMessage(message: '已复制');
              },
            ),
            if (m.role == 'assistant' &&
                m.content.isNotEmpty &&
                _conv?.bookRef != null)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text("保存为注释".tl),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveAsAnnotation(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _saveAsAnnotation(AiMessage m) {
    // 找上一条用户提问
    var question = '';
    final msgs = _conv!.messages;
    for (var i = msgs.indexOf(m) - 1; i >= 0; i--) {
      if (msgs[i].role == 'user') {
        question = msgs[i].content;
        break;
      }
    }
    AnnotationStore.instance.add(AiAnnotation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bookRef: _conv!.bookRef!,
      bookTitle: _conv!.title,
      type: 'ask',
      content: m.content,
      question: question,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    context.showMessage(message: '已保存为注释');
  }

  // ---------------- 输入栏 ----------------

  /// 生图/生视频参数栏：选中媒体模型时显示（比例 / 时长）
  Widget _buildMediaOptionsBar() {
    final media = _currentMediaModel;
    if (media == null) return const SizedBox.shrink();
    final isVideo = media.type == 'video';
    final ratios = isVideo
        ? const ['16:9', '9:16', '1:1']
        : const ['1:1', '16:9', '9:16', '4:3', '3:4'];
    final curRatio = isVideo ? _videoRatio : _mediaRatio;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 6),
            child: Text(isVideo ? '视频比例' : '图片比例',
                style:
                    TextStyle(fontSize: 12, color: context.colorScheme.outline)),
          ),
          for (final r in ratios)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(r, style: const TextStyle(fontSize: 12)),
                selected: curRatio == r,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  if (isVideo) {
                    _videoRatio = r;
                  } else {
                    _mediaRatio = r;
                  }
                  refresh();
                },
              ),
            ),
          if (isVideo) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8, left: 8, top: 6),
              child: Text('时长',
                  style: TextStyle(
                      fontSize: 12, color: context.colorScheme.outline)),
            ),
            for (final d in const ['5', '10'])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${d}s', style: const TextStyle(fontSize: 12)),
                  selected: _videoDuration == d,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    _videoDuration = d;
                    refresh();
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            if (_currentMediaModel != null) _buildMediaOptionsBar(),
            if (_pendingAttachments.isNotEmpty) _buildPendingChips(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: context.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _showPlusPanel,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: '问点什么…',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '粘贴',
                    icon: const Icon(Icons.content_paste_outlined, size: 20),
                    onPressed: _checkPaste,
                  ),
                  if (_hasText || _pendingAttachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _sending ? null : _send,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: context.colorScheme.primary,
                          child: Icon(Icons.arrow_upward,
                              size: 20,
                              color: context.colorScheme.onPrimary),
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onLongPressStart: (_) => _startVoice(),
                      onLongPressMoveUpdate: (d) {
                        // 上滑超过 100px 进入取消区域
                        final cancel = d.offsetFromOrigin.dy < -100;
                        if (cancel != _voiceCancel) {
                          setState(() => _voiceCancel = cancel);
                        }
                      },
                      onLongPressEnd: (_) =>
                          _stopVoice(cancel: _voiceCancel),
                      onLongPressCancel: () => _stopVoice(cancel: true),
                      onTap: () =>
                          context.showMessage(message: '长按语音输入'),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          _listening ? Icons.mic : Icons.mic_none,
                          color: _listening
                              ? context.colorScheme.error
                              : context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 待发送附件 chips（缩略图 + X 删除）
  Widget _buildPendingChips() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 6),
        itemCount: _pendingAttachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = _pendingAttachments[i];
          final isImg = a['type'] == 'image';
          return Stack(
            children: [
              Container(
                width: isImg ? 66 : 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: context.colorScheme.outlineVariant),
                  color: context.colorScheme.surface,
                ),
                clipBehavior: Clip.antiAlias,
                child: isImg
                    ? Image.file(File(a['path']!), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image))
                    : Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Icon(Icons.insert_drive_file_outlined,
                                size: 22,
                                color: context.colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(a['name'] ?? '文件',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () {
                    final path = a['path'];
                    _pendingAttachments.removeAt(i);
                    refresh();
                    if (path != null) {
                      try {
                        File(path).deleteSync();
                      } catch (_) {}
                    }
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- + 面板 ----------------

  void _showPlusPanel() {
    final vision = _modelSupportsVision;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            children: [
              // 不支持的入口置灰展示，点击提示「当前模型不支持」
              _plusItem(ctx, Icons.photo_camera_outlined, '拍照', () {
                _pickImage(ImageSource.camera);
              }, enabled: vision),
              _plusItem(ctx, Icons.photo_library_outlined, '照片', () {
                _pickImage(ImageSource.gallery);
              }, enabled: vision),
              _plusItem(ctx, Icons.insert_drive_file_outlined, '本地文件',
                  () {
                _pickFile();
              }, enabled: vision),
              _plusItem(ctx, Icons.bolt_outlined, '常用语', () async {
                final content = await Navigator.of(context, rootNavigator: true)
                    .push<String>(MaterialPageRoute(
                        builder: (_) => const PromptLibraryPage()));
                if (content != null && content.isNotEmpty) {
                  _input.text = _input.text + content;
                  _input.selection = TextSelection.collapsed(
                      offset: _input.text.length);
                  refresh();
                }
              }),
              _plusItem(ctx, Icons.travel_explore_outlined, '联网搜索', () {
                _showWebSearchPopup();
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plusItem(
      BuildContext sheetCtx, IconData icon, String label, VoidCallback onTap,
      {bool enabled = true}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (!enabled) {
          context.showMessage(message: "当前模型不支持".tl);
          return;
        }
        Navigator.pop(sheetCtx);
        onTap();
      },
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: context.colorScheme.surfaceContainerHighest,
              child: Icon(icon, color: context.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// 联网搜索设置：开关 + 搜索来源（厂商内置 / 独立搜索 API）
  void _showWebSearchPopup() {
    var mode = _webSearch;
    var provider = AiWebSearch.provider;
    final keyController =
        TextEditingController(text: AiWebSearch.apiKey);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('联网搜索'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioListTile<String>(
                  value: 'auto',
                  groupValue: mode,
                  title: const Text('自动'),
                  subtitle: const Text('对话时自动联网检索'),
                  onChanged: (v) => setDlg(() => mode = v!),
                ),
                RadioListTile<String>(
                  value: 'off',
                  groupValue: mode,
                  title: const Text('关闭'),
                  onChanged: (v) => setDlg(() => mode = v!),
                ),
                const Divider(),
                Text('搜索来源',
                    style: TextStyle(
                        fontSize: 13, color: ctx.colorScheme.primary)),
                RadioListTile<String>(
                  value: 'builtin',
                  groupValue: provider,
                  title: const Text('厂商内置'),
                  subtitle: const Text('使用模型厂商自带的联网能力'),
                  onChanged: (v) => setDlg(() => provider = v!),
                ),
                for (final e in AiWebSearch.providers.entries)
                  RadioListTile<String>(
                    value: e.key,
                    groupValue: provider,
                    title: Text(e.value.$1),
                    onChanged: (v) => setDlg(() => provider = v!),
                  ),
                if (provider != 'builtin') ...[
                  TextField(
                    controller: keyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '搜索 API Key',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () => launchUrlString(
                        AiWebSearch.providers[provider]!.$2),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('去申请搜索 Key',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                appdata.settings['aiWebSearch'] = mode;
                appdata.settings['aiSearchProvider'] = provider;
                appdata.settings['aiSearchKey'] = keyController.text.trim();
                appdata.saveData();
                refresh();
                Navigator.pop(ctx);
                context.showMessage(
                    message: mode == 'auto' ? '联网搜索已开启' : '联网搜索已关闭');
              },
              child: Text("确定".tl),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「思考中」三点动画
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> {
  int _n = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() => _n = (_n + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text('思考中${'.' * _n}',
        style: TextStyle(color: context.colorScheme.outline));
  }
}

// ============================================================
// 模型选择（厂商折叠树 + 聊天/图片/视频 Tab）
// ============================================================

extension _AiModelPicker on AiHomePageState {
  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: _ModelPickerSheet(
          currentId: _currentModelId,
          onPick: (slug, modelId) {
            final store = AiStore.instance;
            final changed = _currentModelId != modelId;
            store.select(slug, modelId);
            _conv ??= store.newConversation();
            _conv!.providerSlug = slug;
            _conv!.model = modelId;
            // 切换模型不再插入假对话；空会话由欢迎页展示厂商/模型介绍。
            if (changed) {
              _conv!.messages.removeWhere((m) =>
                  m.role == 'assistant' &&
                  m.content.startsWith('你好，我是') &&
                  m.content.contains('我能帮你'));
            }
            store.updateConversation(_conv!);
            refresh();
            Navigator.pop(ctx);
            _scrollToBottom();
          },
        ),
      ),
    );
  }
}

class _ModelPickerSheet extends StatefulWidget {
  final String currentId;
  final void Function(String providerSlug, String modelId) onPick;

  const _ModelPickerSheet({required this.currentId, required this.onPick});

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  int _tab = 0; // 0 聊天 1 图片 2 视频
  String _search = '';

  Map<String, List<AiModel>> _chatGroups() {
    final groups = <String, List<AiModel>>{};
    for (final m in AiModels.list()) {
      if (m.type != 'chat' || m.status == 'deprecated') continue;
      if (_search.isNotEmpty &&
          !m.name.toLowerCase().contains(_search.toLowerCase()) &&
          !m.id.toLowerCase().contains(_search.toLowerCase())) {
        continue;
      }
      groups.putIfAbsent(m.provider, () => []).add(m);
    }
    return groups;
  }

  Map<String, List<AiMediaModel>> _mediaGroups(String type) {
    final groups = <String, List<AiMediaModel>>{};
    for (final m in kAiMediaModels) {
      if (m.type != type || m.status == 'deprecated') continue;
      if (_search.isNotEmpty &&
          !m.name.toLowerCase().contains(_search.toLowerCase()) &&
          !m.id.toLowerCase().contains(_search.toLowerCase())) {
        continue;
      }
      groups.putIfAbsent(m.provider, () => []).add(m);
    }
    return groups;
  }

  Widget _vendorAvatar(String provider) {
    final slug = AiModels.keySlugOf(provider);
    final p = slug == null ? null : AiProviders.get(slug);
    if (p != null) {
      return BrandIcon(
          lobe: p.iconLobe, simple: p.iconSimple, color: p.color,
          letter: provider, size: 28);
    }
    return CircleAvatar(
        radius: 14,
        child: Text(provider.isEmpty ? '?' : provider[0],
            style: const TextStyle(fontSize: 12)));
  }

  String _slugOf(String provider) =>
      AiModels.keySlugOf(provider) ?? AiStore.instance.selectedProvider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: context.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索模型',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (final (i, label) in ['聊天', '图片', '视频'].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _tab == i,
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _tab == 0
              ? _buildChatList()
              : _buildMediaList(_tab == 1 ? 'image' : 'video'),
        ),
      ],
    );
  }

  Widget _buildChatList() {
    final groups = _chatGroups();
    if (groups.isEmpty) {
      return const Center(child: Text('没有匹配的模型'));
    }
    return ListView(
      children: [
        for (final e in groups.entries)
          ExpansionTile(
            leading: _vendorAvatar(e.key),
            title: Text(e.key),
            subtitle: Text('${e.value.length} 个模型',
                style: const TextStyle(fontSize: 12)),
            initiallyExpanded: _search.isNotEmpty,
            children: [
              for (final m in e.value)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  title: Text(m.name),
                  subtitle: Text(
                    [
                      if (m.vision) '视觉',
                      if (m.thinking) '思考',
                      if (m.ctx > 0) '${m.ctx}K',
                      if (m.status == 'new') '新',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: m.id == widget.currentId
                      ? Icon(Icons.check_circle,
                          color: context.colorScheme.primary, size: 20)
                      : null,
                  onTap: () => widget.onPick(_slugOf(e.key), m.id),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildMediaList(String type) {
    final groups = _mediaGroups(type);
    if (groups.isEmpty) {
      return Center(
          child: Text(type == 'image' ? '暂无图片模型' : '暂无视频模型'));
    }
    return ListView(
      children: [
        for (final e in groups.entries)
          ExpansionTile(
            leading: _vendorAvatar(e.key),
            title: Text(e.key),
            subtitle: Text('${e.value.length} 个模型',
                style: const TextStyle(fontSize: 12)),
            initiallyExpanded: _search.isNotEmpty,
            children: [
              for (final m in e.value)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  title: Text(m.name),
                  subtitle: m.desc == null
                      ? null
                      : Text(m.desc!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                  trailing: m.id == widget.currentId
                      ? Icon(Icons.check_circle,
                          color: context.colorScheme.primary, size: 20)
                      : null,
                  onTap: () => widget.onPick(_slugOf(e.key), m.id),
                ),
            ],
          ),
      ],
    );
  }
}

// ============================================================
// 常用语库（本地已添加 / 云端同步）
// ============================================================

class PromptLibraryPage extends StatefulWidget {
  const PromptLibraryPage({super.key});

  @override
  State<PromptLibraryPage> createState() => _PromptLibraryPageState();
}

class _PromptLibraryPageState extends State<PromptLibraryPage> {
  List<Map<String, dynamic>> _cloud = [];
  bool _cloudLoading = false;

  void _onStore() => setState(() {});

  @override
  void initState() {
    super.initState();
    AiStore.instance.addListener(_onStore);
  }

  @override
  void dispose() {
    AiStore.instance.removeListener(_onStore);
    super.dispose();
  }

  Future<void> _editDialog({AiPrompt? existing}) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final content = TextEditingController(text: existing?.content ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '添加常用语' : '编辑常用语'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '标题')),
            const SizedBox(height: 8),
            TextField(
                controller: content,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '内容')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("取消".tl)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text("保存".tl)),
        ],
      ),
    );
    if (ok == true && content.text.trim().isNotEmpty) {
      final store = AiStore.instance;
      if (existing == null) {
        store.addPrompt(
            title.text.trim().isEmpty ? '未命名' : title.text.trim(),
            content.text.trim());
      } else {
        store.updatePrompt(existing, title.text.trim(), content.text.trim());
      }
    }
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入常用语'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('粘贴 JSON（[{"title":"…","content":"…"}]），或从文件选择：'),
            const SizedBox(height: 8),
            TextField(controller: ctrl, maxLines: 5),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                const g = XTypeGroup(label: 'json', extensions: ['json']);
                final f = await openFile(acceptedTypeGroups: [g]);
                if (f != null) {
                  ctrl.text = await f.readAsString();
                }
              } catch (_) {}
            },
            child: const Text('从文件选择'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("取消".tl)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final list = (jsonDecode(ctrl.text) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final added = AiStore.instance.importPrompts(list);
      if (mounted) {
        context.showMessage(
            message: added > 0 ? '已导入 $added 条（重复自动跳过）' : '没有新内容，全部已存在');
      }
    } catch (e) {
      if (mounted) context.showMessage(message: '导入失败：格式不正确');
    }
  }

  Future<void> _export() async {
    final json = const JsonEncoder.withIndent('  ')
        .convert(AiStore.instance.exportPrompts());
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) context.showMessage(message: '已复制到剪贴板');
  }

  Future<void> _pushCloud() async {
    setState(() => _cloudLoading = true);
    try {
      final records = <String, Map<String, dynamic>>{
        for (final p in AiStore.instance.prompts) p.id: p.toJson(),
      };
      await OmniSync.instance.pushRecords('prompts', records);
      if (mounted) context.showMessage(message: '已上传 ${records.length} 条');
    } catch (e) {
      if (mounted) context.showMessage(message: '上传失败：$e');
    } finally {
      if (mounted) setState(() => _cloudLoading = false);
    }
  }

  Future<void> _pullCloud() async {
    setState(() => _cloudLoading = true);
    try {
      final rows = await OmniSync.instance.pullModule('prompts');
      setState(() {
        _cloud = rows
            .where((r) => r['value'] is Map && r['value']['_deleted'] != true)
            .map((r) => Map<String, dynamic>.from(r['value'] as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) context.showMessage(message: '拉取失败：$e');
    } finally {
      if (mounted) setState(() => _cloudLoading = false);
    }
  }

  Future<void> _mergeCloud() async {
    final added = AiStore.instance.importPrompts(_cloud);
    if (mounted) {
      context.showMessage(
          message: added > 0 ? '已合并 $added 条云端常用语' : '云端内容本地均已存在');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AiStore.instance;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('常用语'),
          bottom: const TabBar(tabs: [
            Tab(text: '本地已添加'),
            Tab(text: '云端同步'),
          ]),
          actions: [
            IconButton(
                tooltip: '导入', icon: const Icon(Icons.download_outlined),
                onPressed: _import),
            IconButton(
                tooltip: '导出', icon: const Icon(Icons.upload_outlined),
                onPressed: _export),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _editDialog(),
          child: const Icon(Icons.add),
        ),
        body: TabBarView(
          children: [
            // ---- 本地 ----
            store.prompts.isEmpty
                ? const Center(child: Text('还没有常用语，点右下角添加'))
                : ListView.builder(
                    itemCount: store.prompts.length,
                    itemBuilder: (_, i) {
                      final p = store.prompts[i];
                      return ListTile(
                        title: Text(p.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(p.content,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(context, p.content),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') {
                              _editDialog(existing: p);
                            } else if (v == 'del') {
                              store.deletePrompt(p.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'del', child: Text('删除')),
                          ],
                        ),
                      );
                    },
                  ),
            // ---- 云端 ----
            _buildCloudTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudTab() {
    if (!OmniSync.instance.isLoggedIn) {
      return const Center(child: Text('登录后可同步常用语到云端'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('上传到云端'),
                  onPressed: _cloudLoading ? null : _pushCloud,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('拉取云端'),
                  onPressed: _cloudLoading ? null : _pullCloud,
                ),
              ),
            ],
          ),
        ),
        if (_cloudLoading) const LinearProgressIndicator(),
        Expanded(
          child: _cloud.isEmpty
              ? const Center(child: Text('点「拉取云端」查看云端常用语'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: FilledButton.icon(
                        icon: const Icon(Icons.merge_outlined),
                        label: Text('全部合并到本地（${_cloud.length} 条）'),
                        onPressed: _mergeCloud,
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _cloud.length,
                        itemBuilder: (_, i) {
                          final p = _cloud[i];
                          return ListTile(
                            dense: true,
                            title: Text(p['title']?.toString() ?? '未命名',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(p['content']?.toString() ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ============================================================
// 历史对话抽屉（左 4/5）：搜索、新建、置顶、长按菜单、多选管理
// ============================================================

class AiHistoryDrawer extends StatefulWidget {
  final String? currentId;
  final void Function(String id) onOpen;
  final VoidCallback onNew;

  const AiHistoryDrawer(
      {super.key, this.currentId, required this.onOpen, required this.onNew});

  @override
  State<AiHistoryDrawer> createState() => _AiHistoryDrawerState();
}

class _AiHistoryDrawerState extends State<AiHistoryDrawer> {
  bool _searchMode = false;
  final _searchCtrl = TextEditingController();

  List<String> get _history {
    final raw = appdata.settings['aiSearchHistory'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return const [];
  }

  void _saveHistory(List<String> list) {
    appdata.settings['aiSearchHistory'] = list;
    appdata.saveData();
  }

  void _recordSearch(String q) {
    if (q.trim().isEmpty) return;
    final list = _history.toList()..remove(q);
    list.insert(0, q);
    if (list.length > 20) list.length = 20;
    _saveHistory(list);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AiStore.instance.addListener(_onStore);
  }

  @override
  void dispose() {
    AiStore.instance.removeListener(_onStore);
    _searchCtrl.dispose();
    super.dispose();
  }

  String _preview(AiConversation c) {
    if (c.messages.isEmpty) return '';
    final last = c.messages.last;
    if (last.kind == 'image') return '[生成的图片]';
    if (last.kind == 'video') return '[生成的视频]';
    if (last.content.isNotEmpty) {
      return last.content.replaceAll('\n', ' ');
    }
    if (last.attachments.any((a) => a['type'] == 'image')) return '[图片]';
    if (last.attachments.isNotEmpty) return '[文件]';
    return '';
  }

  /// 最近一条图片附件作为微缩图
  Map<String, String>? _thumb(AiConversation c) {
    for (var i = c.messages.length - 1; i >= 0; i--) {
      for (final a in c.messages[i].attachments) {
        if (a['type'] == 'image' || a['type'] == 'imageUrl') return a;
      }
    }
    return null;
  }

  String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${two(d.hour)}:${two(d.minute)}';
    }
    return '${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final store = AiStore.instance;
    return Material(
      color: context.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
              child: Row(
                children: [
                  const Text('历史对话',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    tooltip: '新对话',
                    icon: const Icon(Icons.add),
                    onPressed: widget.onNew,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _searchMode ? _buildSearchView(store) : _buildList(store),
            ),
            const Divider(height: 1),
            if (!_searchMode)
              Padding(
                padding: const EdgeInsets.all(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => setState(() => _searchMode = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: context.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search,
                            size: 20, color: context.colorScheme.outline),
                        const SizedBox(width: 8),
                        Text('搜索历史记录',
                            style: TextStyle(
                                color: context.colorScheme.outline)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(AiStore store) {
    final convs =
        store.conversations.where((c) => c.messages.isNotEmpty).toList();
    if (convs.isEmpty) {
      return const Center(child: Text('暂无历史对话'));
    }
    return ListView.builder(
      itemCount: convs.length,
      itemBuilder: (_, i) => _convTile(convs[i]),
    );
  }

  Widget _convTile(AiConversation c) {
    final thumb = _thumb(c);
    return ListTile(
      dense: true,
      selected: c.id == widget.currentId,
      leading: thumb != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 36,
                height: 36,
                child: (thumb['type'] == 'imageUrl' ||
                        (thumb['path'] ?? '').startsWith('http'))
                    ? Image.network(thumb['path']!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image_outlined))
                    : Image.file(File(thumb['path']!), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image_outlined)),
              ),
            )
          : const Icon(Icons.chat_bubble_outline, size: 22),
      title: Row(
        children: [
          if (c.pinned)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.push_pin,
                  size: 14, color: context.colorScheme.primary),
            ),
          Expanded(
            child:
                Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      subtitle: Text(_preview(c), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(_fmtTime(c.updatedAt),
          style: TextStyle(fontSize: 11, color: context.colorScheme.outline)),
      onTap: () => widget.onOpen(c.id),
      onLongPress: () => _showConvMenu(c),
    );
  }

  void _showConvMenu(AiConversation c) {
    final store = AiStore.instance;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(c.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin),
              title: Text(c.pinned ? '取消置顶' : '置顶'),
              onTap: () {
                Navigator.pop(ctx);
                if (!c.pinned && !store.togglePin(c.id)) {
                  context.showMessage(message: '最多置顶 3 个对话');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _renameDialog(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist_outlined),
              title: const Text('多选'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const HistoryManagePage()));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: context.colorScheme.error),
              title: Text('删除',
                  style: TextStyle(color: context.colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                store.deleteConversation(c.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDialog(AiConversation c) async {
    final ctrl = TextEditingController(text: c.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("取消".tl)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text("保存".tl)),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      AiStore.instance.renameConversation(c.id, ctrl.text.trim());
    }
  }

  Widget _buildSearchView(AiStore store) {
    final q = _searchCtrl.text.trim();
    final results = q.isEmpty
        ? const <AiConversation>[]
        : store.conversations.where((c) {
            if (c.title.contains(q)) return true;
            return c.messages.any((m) => m.content.contains(q));
          }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '搜索历史记录',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _recordSearch(q),
                ),
              ),
              IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _searchMode = false;
                  _searchCtrl.clear();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? (_history.isEmpty
                  ? const Center(child: Text('暂无搜索记录'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final h in _history)
                            InputChip(
                              label: Text(h),
                              onPressed: () {
                                _searchCtrl.text = h;
                                setState(() {});
                              },
                              onDeleted: () {
                                final list = _history.toList()..remove(h);
                                _saveHistory(list);
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                    ))
              : (results.isEmpty
                  ? const Center(child: Text('没有匹配的对话'))
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final c = results[i];
                        return ListTile(
                          dense: true,
                          leading:
                              const Icon(Icons.chat_bubble_outline, size: 22),
                          title: Text(c.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(_preview(c),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            _recordSearch(q);
                            widget.onOpen(c.id);
                          },
                        );
                      },
                    )),
        ),
      ],
    );
  }
}

// ============================================================
// 历史记录多选管理页
// ============================================================

class HistoryManagePage extends StatefulWidget {
  const HistoryManagePage({super.key});

  @override
  State<HistoryManagePage> createState() => _HistoryManagePageState();
}

class _HistoryManagePageState extends State<HistoryManagePage> {
  final Set<String> _sel = {};

  @override
  Widget build(BuildContext context) {
    final convs = AiStore.instance.conversations
        .where((c) => c.messages.isNotEmpty)
        .toList();
    final allSelected = _sel.length == convs.length && convs.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('管理历史记录（已选 ${_sel.length}）')),
      body: ListView.builder(
        itemCount: convs.length,
        itemBuilder: (_, i) {
          final c = convs[i];
          return CheckboxListTile(
            value: _sel.contains(c.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                _sel.add(c.id);
              } else {
                _sel.remove(c.id);
              }
            }),
            title: Row(
              children: [
                if (c.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.push_pin,
                        size: 14, color: context.colorScheme.primary),
                  ),
                Expanded(
                  child: Text(c.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            subtitle: Text(
                '${c.messages.length} 条消息',
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    _sel.clear();
                  } else {
                    _sel
                      ..clear()
                      ..addAll(convs.map((c) => c.id));
                  }
                }),
                child: Text(allSelected ? '取消全选' : '全选'),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: Text('删除（${_sel.length}）'),
                style: FilledButton.styleFrom(
                    backgroundColor: context.colorScheme.error),
                onPressed: _sel.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('删除 ${_sel.length} 个对话？'),
                            content: const Text('删除后无法恢复'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text("取消".tl)),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text("删除".tl)),
                            ],
                          ),
                        );
                        if (ok == true) {
                          final store = AiStore.instance;
                          for (final id in _sel) {
                            store.deleteConversation(id);
                          }
                          if (mounted) Navigator.pop(context);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 兼容旧入口：漫画详情页「问 AI」
// ============================================================

class AiChatPage extends AiChatListPage {
  const AiChatPage(
      {super.key, super.conversationId, super.bookContext, super.bookRef});
}
