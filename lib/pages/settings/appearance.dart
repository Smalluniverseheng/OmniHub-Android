part of 'settings_page.dart';

/// 应用图标切换（默认 / 星球），通过原生 activity-alias 实现
class AppIconSwitcher {
  static const _channel = MethodChannel('omnihub/app_icon');

  static Future<bool> setIcon(String alias) async {
    try {
      final r = await _channel.invokeMethod<bool>('setIcon', {'alias': alias});
      return r == true;
    } catch (_) {
      return false;
    }
  }
}

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key});

  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  static const _presetColors = <int>[
    0xFFF44336, 0xFFE91E63, 0xFF9C27B0, 0xFF6366F1,
    0xFF3F51B5, 0xFF2196F3, 0xFF03A9F4, 0xFF00BCD4,
    0xFF009688, 0xFF4CAF50, 0xFF8BC34A, 0xFFCDDC39,
    0xFFFFC107, 0xFFFF9800, 0xFFFF5722, 0xFF795548,
    0xFF607D8B, 0xFF000000,
  ];

  Future<void> _applyTheme() async {
    await App.init();
    App.forceRebuild();
  }

  void _setCustomColor(int value) {
    appdata.settings['color'] = 'custom';
    appdata.settings['customColor'] = value;
    appdata.saveData();
    setState(() {});
    _applyTheme();
  }

  /// 自定义颜色选择弹窗：预设色板 + 十六进制输入
  void _pickCustomColor() {
    final hexController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("自定义颜色".tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _presetColors)
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      Navigator.pop(ctx);
                      _setCustomColor(c);
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: context.colorScheme.outlineVariant),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hexController,
              decoration: InputDecoration(
                labelText: "十六进制颜色（如 6366F1）".tl,
                prefixText: '#',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("取消".tl),
          ),
          FilledButton(
            onPressed: () {
              final t = hexController.text.trim();
              final v = int.tryParse(t, radix: 16);
              if (v != null && t.length == 6) {
                Navigator.pop(ctx);
                _setCustomColor(0xFF000000 | v);
              }
            },
            child: Text("确定".tl),
          ),
        ],
      ),
    );
  }

  /// 应用图标选择弹窗
  void _pickAppIcon() {
    final current = (appdata.settings['appIcon'] as String?) ?? 'default';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("应用图标".tl),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _iconOption(ctx, 'default', 'assets/app_icon.png', "默认", current),
            _iconOption(
                ctx, 'planet', 'assets/app_icon_planet.png', "星球", current),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("关闭".tl),
          ),
        ],
      ),
    );
  }

  Widget _iconOption(BuildContext ctx, String alias, String asset,
      String label, String current) {
    final selected = current == alias;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final ok = await AppIconSwitcher.setIcon(alias);
        if (ok) {
          appdata.settings['appIcon'] = alias;
          appdata.saveData();
        }
        if (ctx.mounted) Navigator.pop(ctx);
        if (mounted) {
          setState(() {});
          context.showMessage(
              message: ok ? "图标已切换，返回桌面查看".tl : "图标切换失败".tl);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? context.colorScheme.primary
                : context.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(asset, width: 56, height: 56),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
            if (selected)
              Icon(Icons.check_circle,
                  size: 14, color: context.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = appdata.settings['color'] == 'custom';
    final customColor =
        (appdata.settings['customColor'] as num?)?.toInt() ?? 0xFF6366F1;
    final appIcon = (appdata.settings['appIcon'] as String?) ?? 'default';
    final fontScale =
        (appdata.settings['fontScale'] as num?)?.toDouble() ?? 1.0;

    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("主题设置".tl)),
        SelectSetting(
          title: "Theme Mode".tl,
          settingKey: "theme_mode",
          optionTranslation: {
            "system": "System".tl,
            "light": "Light".tl,
            "dark": "Dark".tl,
          },
          onChanged: () async {
            App.forceRebuild();
          },
        ).toSliver(),
        SelectSetting(
          title: "Theme Color".tl,
          settingKey: "color",
          optionTranslation: {
            "system": "System".tl,
            "red": "Red".tl,
            "pink": "Pink".tl,
            "purple": "Purple".tl,
            "green": "Green".tl,
            "orange": "Orange".tl,
            "blue": "Blue".tl,
            "custom": "自定义".tl,
          },
          onChanged: () async {
            setState(() {});
            await _applyTheme();
          },
        ).toSliver(),
        if (isCustom)
          ListTile(
            title: Text("自定义颜色".tl),
            subtitle: Text(
                '#${customColor.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'),
            trailing: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(customColor),
                shape: BoxShape.circle,
                border:
                    Border.all(color: context.colorScheme.outlineVariant),
              ),
            ),
            onTap: _pickCustomColor,
          ).toSliver(),
        ListTile(
          title: Text("应用图标".tl),
          subtitle: Text(appIcon == 'planet' ? "星球" : "默认"),
          trailing: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              appIcon == 'planet'
                  ? 'assets/app_icon_planet.png'
                  : 'assets/app_icon.png',
              width: 28,
              height: 28,
            ),
          ),
          onTap: _pickAppIcon,
        ).toSliver(),
        ListTile(
          title: Text("字体大小".tl),
          subtitle: Slider(
            value: fontScale.clamp(0.85, 1.3),
            min: 0.85,
            max: 1.3,
            divisions: 9,
            label: '${(fontScale * 100).round()}%',
            onChanged: (v) {
              setState(() {
                appdata.settings['fontScale'] = v;
              });
            },
            onChangeEnd: (v) {
              appdata.saveData();
              App.forceRebuild();
            },
          ),
        ).toSliver(),
        _SwitchSetting(
          title: "沉浸式状态栏".tl,
          settingKey: "immersiveStatusBar",
          subtitle: "页面内容延伸到状态栏下方".tl,
          onChanged: () => App.forceRebuild(),
        ).toSliver(),
        _SwitchSetting(
          title: "导航栏阴影".tl,
          settingKey: "navbarShadow",
          onChanged: () => App.forceRebuild(),
        ).toSliver(),
      ],
    );
  }
}
