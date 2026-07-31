part of 'settings_page.dart';

/// OmniHub 云同步设置页：登录 + 书架同步（与网页版数据互通）
class OmniSyncSettings extends StatefulWidget {
  const OmniSyncSettings({super.key});

  @override
  State<OmniSyncSettings> createState() => _OmniSyncSettingsState();
}

class _OmniSyncSettingsState extends State<OmniSyncSettings> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    OmniSync.instance.restore().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await action();
      setState(() => _message = okMsg);
    } catch (e) {
      setState(() => _message = '失败：$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _syncBookshelf() async {
    setState(() {
      _busy = true;
      _message = '';
    });
    final res = await BookshelfSync.instance.sync();
    setState(() {
      _busy = false;
      _message = res.ok
          ? '同步完成：上传 ${res.pushed} 条，下载 ${res.pulled} 条'
          : '同步失败：${res.error}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = OmniSync.instance.isLoggedIn;
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(title: Text("Cloud Sync".tl)),
        if (!loggedIn) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              "登录 OmniHub 账号后，书架可与网页版互通同步".tl,
              style: TextStyle(color: context.colorScheme.outline),
            ),
          ).toSliver(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: "邮箱".tl,
                border: const OutlineInputBorder(),
              ),
            ),
          ).toSliver(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "密码".tl,
                border: const OutlineInputBorder(),
              ),
            ),
          ).toSliver(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => OmniSync.instance.signIn(
                                _emailController.text.trim(),
                                _passwordController.text),
                            '登录成功',
                          ),
                  child: Text("登录".tl),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => OmniSync.instance.signUp(
                                _emailController.text.trim(),
                                _passwordController.text),
                            '注册成功',
                          ),
                  child: Text("注册".tl),
                ),
              ],
            ),
          ).toSliver(),
        ] else ...[
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(OmniSync.instance.session?.email ?? ''),
            subtitle: Text("已登录，与网页版共用同一账号".tl),
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => OmniSync.instance.signOut(), '已退出登录'),
              child: Text("退出".tl),
            ),
          ).toSliver(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: Text("同步书架".tl),
            subtitle: Text("上传本地书架并从云端（含网页版）拉取新增".tl),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: _syncBookshelf,
                    child: Text("同步".tl),
                  ),
          ).toSliver(),
        ],
        if (_message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_message),
          ).toSliver(),
      ],
    );
  }
}
