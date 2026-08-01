part of 'settings_page.dart';

/// OmniHub AI 设置页（BYOK）：填 Key、选模型、测试连接
/// provider 注册表与网页版 js/ai-providers.js 对齐
class AiSettings extends StatefulWidget {
  const AiSettings({super.key});

  @override
  State<AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<AiSettings> {
  final Set<String> _expanded = {};
  final Map<String, TextEditingController> _controllers = {};
  final TextEditingController _customBaseController = TextEditingController();
  final Map<String, String> _testStatus = {};
  final Set<String> _testing = {};
  final Map<String, Timer> _autoTestTimers = {};

  @override
  void initState() {
    super.initState();
    AiStore.instance.load().then((_) {
      _customBaseController.text = AiStore.instance.customBase;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final t in _autoTestTimers.values) {
      t.cancel();
    }
    _customBaseController.dispose();
    super.dispose();
  }

  /// 输入 Key 后 1s 防抖自动测试（红绿灯）
  void _onKeyChanged(AiProvider p, String v) {
    AiStore.instance.setKey(p.keySlug, v);
    _autoTestTimers[p.keySlug]?.cancel();
    if (v.trim().length < 8) {
      setState(() => _testStatus.remove(p.keySlug));
      return;
    }
    _autoTestTimers[p.keySlug] =
        Timer(const Duration(seconds: 1), () => _test(p));
  }

  /// 智能识别批量导入：粘贴一堆 Key，自动识别厂商并配置
  Future<void> _smartImport() async {
    final controller = TextEditingController();
    final keys = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("智能识别导入".tl),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "把一堆 API Key 粘贴进来（每行一个或用逗号/空格分隔），会自动识别厂商并配置到对应位置，识别不了的会自动实测归属。"
                    .tl,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'sk-ant-...\nsk-or-...\nAIza...\nsk-...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("取消".tl)),
          FilledButton(
            onPressed: () {
              final raw = controller.text
                  .split(RegExp(r'[\s,;，；]+'))
                  .map((e) => e.trim())
                  .where((e) => e.length >= 8)
                  .toSet()
                  .toList();
              Navigator.pop(ctx, raw);
            },
            child: Text("开始识别".tl),
          ),
        ],
      ),
    );
    if (keys == null || keys.isEmpty || !mounted) return;

    // 识别进度对话框
    final results = <String, String?>{}; // key -> slug
    var done = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          if (!done) {
            done = true;
            Future(() async {
              for (final key in keys) {
                // 前缀可确定的直接识别
                final guessed = AiProviders.guessKeyProvider(key);
                final ambiguous = !RegExp(
                        r'^(sk-ant-|AIza|AQ\.|gsk_|xai-|sk-or-)',
                        caseSensitive: false)
                    .hasMatch(key);
                if (!ambiguous) {
                  results[key] = guessed;
                  setDlg(() {});
                  continue;
                }
                // 裸 sk- 等：并发实测候选厂商，取第一个验证通过的
                const candidates = [
                  'deepseek', 'kimi', 'zhipu', 'qwen', 'siliconflow',
                  'openrouter', 'openai', 'volcengine', 'minimax',
                ];
                String? hit;
                await Future.wait(candidates.map((slug) async {
                  if (hit != null) return;
                  final p = AiProviders.get(slug)!;
                  try {
                    await AiApi.validateKey(p, key,
                        customBase: AiStore.instance.customBase);
                    hit ??= slug;
                  } catch (_) {}
                }));
                results[key] = hit;
                setDlg(() {});
              }
            });
          }
          final finished = results.length >= keys.length;
          return AlertDialog(
            title: Text(finished ? "识别完成".tl : "正在识别…".tl),
            content: SizedBox(
              width: double.maxFinite,
              height: 260,
              child: ListView(
                children: [
                  for (final key in keys)
                    ListTile(
                      dense: true,
                      leading: results.containsKey(key)
                          ? (results[key] != null
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green, size: 18)
                              : const Icon(Icons.cancel,
                                  color: Colors.red, size: 18))
                          : const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                      title: Text(
                        key.length > 16
                            ? '${key.substring(0, 8)}…${key.substring(key.length - 4)}'
                            : key,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        results.containsKey(key)
                            ? (results[key] != null
                                ? AiProviders.get(results[key]!)!.name
                                : "无法识别，未导入".tl)
                            : "识别中…".tl,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (finished)
                FilledButton(
                  onPressed: () async {
                    var n = 0;
                    results.forEach((key, slug) {
                      if (slug != null) {
                        AiStore.instance.setKey(slug, key);
                        _controllerFor(slug).text = key;
                        n++;
                      }
                    });
                    await AiStore.instance.save();
                    if (context.mounted) {
                      Navigator.pop(context);
                      setState(() {});
                      context.showMessage(
                          message: "已自动配置 @n 个 Key".tlParams({'n': n}));
                    }
                  },
                  child: Text("导入并配置".tl),
                ),
            ],
          );
        },
      ),
    );
  }

  /// API 使用教程
  void _showApiTutorial() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("API 使用教程".tl),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text("1. 什么是 API Key？".tl,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  "API Key 是厂商发给你的访问凭证，类似密码。本应用采用 BYOK（自带 Key）模式，Key 只保存在你的手机本机，不会上传任何服务器。"
                      .tl,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
              const SizedBox(height: 10),
              Text("2. 如何注册并获取 Key？".tl,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  "① 点开对应厂商卡片右下角的「没有 API？去生成」，跳转到厂商控制台；\n② 注册/登录厂商账号（部分厂商需要实名或充值）；\n③ 在控制台的「API Keys / 密钥管理」里创建新 Key 并复制；\n④ 回到本应用粘贴到输入框，绿灯亮起即配置成功。"
                      .tl,
                  style: const TextStyle(fontSize: 13, height: 1.6)),
              const SizedBox(height: 10),
              Text("3. 推荐入门选择".tl,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  "DeepSeek、智谱、SiliconFlow 都有免费额度，注册即可用；Kimi、通义千问适合中文长文本；OpenRouter 一个 Key 可用 200+ 模型。"
                      .tl,
                  style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: Text("知道了".tl)),
        ],
      ),
    );
  }

  /// 厂商控制台列表
  void _showConsoles() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text("各厂商控制台（去这里生成 API Key）".tl,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final e in AiProviders.keyUrls.entries)
              ListTile(
                dense: true,
                leading: const Icon(Icons.open_in_new, size: 18),
                title: Text(AiProviders.get(e.key)?.name ?? e.key),
                subtitle: Text(e.value,
                    style: const TextStyle(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                onTap: () => launchUrlString(e.value),
              ),
          ],
        ),
      ),
    );
  }

  TextEditingController _controllerFor(String slug) {
    return _controllers.putIfAbsent(
        slug, () => TextEditingController(text: AiStore.instance.getKey(slug)));
  }

  Future<void> _test(AiProvider p) async {
    final key = AiStore.instance.getKey(p.keySlug);
    if (key.isEmpty) {
      setState(() => _testStatus[p.keySlug] = 'fail:请先填写 Key');
      return;
    }
    setState(() {
      _testing.add(p.keySlug);
      _testStatus.remove(p.keySlug);
    });
    try {
      final models = await AiApi.validateKey(p, key,
          customBase: AiStore.instance.customBase);
      setState(() {
        _testStatus[p.keySlug] =
            models.isEmpty ? 'ok' : 'ok:${models.take(3).join(' / ')}';
      });
    } catch (e) {
      setState(() => _testStatus[p.keySlug] = 'fail:$e');
    } finally {
      setState(() => _testing.remove(p.keySlug));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AiStore.instance;
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: Text("AI Settings".tl),
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: "智能识别导入".tl,
              onPressed: _smartImport,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'tutorial') _showApiTutorial();
                if (v == 'consoles') _showConsoles();
                if (v == 'import') _smartImport();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.auto_awesome),
                        title: Text("智能识别导入 Key".tl),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'tutorial',
                    child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.school_outlined),
                        title: Text("API 使用教程".tl),
                        contentPadding: EdgeInsets.zero)),
                PopupMenuItem(
                    value: 'consoles',
                    child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.open_in_new),
                        title: Text("厂商控制台".tl),
                        contentPadding: EdgeInsets.zero)),
              ],
            ),
          ],
        ),
        // 说明 + 打开对话
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            "AI 使用你自己的 API Key（BYOK），Key 仅保存在本机，不会上传服务器。".tl,
            style: TextStyle(color: context.colorScheme.outline, fontSize: 13),
          ),
        ).toSliver(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.icon(
            onPressed: () => context.to(() => const AiChatListPage()),
            icon: const Icon(Icons.smart_toy_outlined),
            label: Text("Open AI Chat".tl),
          ),
        ).toSliver(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.to(() => const AiModelsPage()).then((_) {
                    if (mounted) setState(() {});
                  }),
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: Text("Model Catalog".tl),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.to(() => const AiLeaderboardPage()),
                  icon: const Icon(Icons.leaderboard_outlined, size: 18),
                  label: Text("Leaderboard".tl),
                ),
              ),
            ],
          ),
        ).toSliver(),
        _buildGroup("Domestic Providers".tl, AiProviders.domestic),
        _buildGroup("聚合平台（单 Key 可用 200+ 模型）".tl, AiProviders.aggregators),
        _buildGroup("International Providers".tl, AiProviders.foreign),
        _buildCustom(store),
        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }

  Widget _buildGroup(String title, List<String> slugs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title,
              style:
                  TextStyle(fontSize: 13, color: context.colorScheme.primary)),
        ),
        for (final slug in slugs)
          _buildProviderBlock(AiProviders.get(slug)!),
      ],
    ).toSliver();
  }

  Widget _buildProviderBlock(AiProvider p) {
    final configured = AiStore.instance.getKey(p.keySlug).isNotEmpty;
    final open = _expanded.contains(p.keySlug);
    final selected = AiStore.instance.selectedProvider == p.keySlug;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: BrandIcon(
              lobe: p.iconLobe,
              simple: p.iconSimple,
              color: p.color,
              letter: p.name,
              size: 40,
            ),
            title: Text(p.name),
            subtitle: Text(
                "${AiModels.forProvider(p.keySlug).isNotEmpty ? AiModels.forProvider(p.keySlug).length : p.models.length} models",
                style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  Icon(Icons.check_circle,
                      size: 18, color: context.colorScheme.primary),
                const SizedBox(width: 4),
                if (_testing.contains(p.keySlug))
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_testStatus[p.keySlug]?.startsWith('ok') == true)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.circle, color: Colors.green, size: 12),
                  )
                else if (_testStatus[p.keySlug]?.startsWith('fail') == true)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.circle, color: Colors.red, size: 12),
                  ),
                Chip(
                  padding: EdgeInsets.zero,
                  label: Text(
                    configured ? "已配置".tl : "未配置".tl,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() {
              open
                  ? _expanded.remove(p.keySlug)
                  : _expanded.add(p.keySlug);
            }),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _controllerFor(p.keySlug),
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: "API Key",
                      hintText: "粘贴 ${p.name} 的 API Key".tl,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => _onKeyChanged(p, v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              context.to(() => const AiModelsPage()).then((_) {
                            if (mounted) setState(() {});
                          }),
                          child: Text(
                            AiStore.instance.selectedProvider == p.keySlug
                                ? AiStore.instance.effectiveModel
                                : "Select from catalog".tl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _testing.contains(p.keySlug)
                            ? null
                            : () => _test(p),
                        child: _testing.contains(p.keySlug)
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text("Test".tl),
                      ),
                    ],
                  ),
                  if (_testStatus.containsKey(p.keySlug))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _testStatus[p.keySlug]!.startsWith('ok')
                            ? "✓ 连接成功 ${_testStatus[p.keySlug]!.replaceFirst('ok:', '').replaceFirst('ok', '')}"
                            : "✗ 连接失败：${_testStatus[p.keySlug]!.replaceFirst('fail:', '')}",
                        style: TextStyle(
                          fontSize: 12,
                          color: _testStatus[p.keySlug]!.startsWith('ok')
                              ? Colors.green
                              : context.colorScheme.error,
                        ),
                      ),
                    ),
                  if (AiProviders.keyUrls.containsKey(p.keySlug))
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: () =>
                          launchUrlString(AiProviders.keyUrls[p.keySlug]!),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text("没有 API？去生成".tl,
                          style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustom(AiStore store) {
    final p = AiProviders.get('custom')!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text("Custom Provider".tl,
              style:
                  TextStyle(fontSize: 13, color: context.colorScheme.primary)),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _customBaseController,
                  decoration: InputDecoration(
                    labelText: "Base URL",
                    hintText: "https://your-api.example.com",
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    store.customBase = v.trim();
                    store.save();
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controllerFor('custom'),
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "API Key",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => store.setKey('custom', v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: store.selectedProvider == 'custom'
                      ? store.selectedModel
                      : '',
                  decoration: InputDecoration(
                    labelText: "Model Name".tl,
                    hintText: "gpt-4o / deepseek-chat …",
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => store.select('custom', v.trim()),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed:
                        _testing.contains('custom') ? null : () => _test(p),
                    child: _testing.contains('custom')
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text("Test".tl),
                  ),
                ),
                if (_testStatus.containsKey('custom'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _testStatus['custom']!.startsWith('ok')
                          ? "✓ 连接成功".tl
                          : "✗ 连接失败：${_testStatus['custom']!.replaceFirst('fail:', '')}",
                      style: TextStyle(
                        fontSize: 12,
                        color: _testStatus['custom']!.startsWith('ok')
                            ? Colors.green
                            : context.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ).toSliver();
  }
}
