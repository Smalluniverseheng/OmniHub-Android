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
    _customBaseController.dispose();
    super.dispose();
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
        SliverAppBar.large(title: Text("AI Settings".tl)),
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
                    onChanged: (v) => AiStore.instance.setKey(p.keySlug, v),
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
                      label: Text("获取 Key".tl,
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
