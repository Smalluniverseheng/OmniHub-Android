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
      var msg = e is Exception ? e.toString() : '$e';
      msg = msg.replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (msg.trim().isEmpty) msg = OmniSync.friendlyAuthError(e);
      setState(() => _message = '失败：$msg');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// 登录：未验证邮箱时自动弹验证码框
  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await OmniSync.instance.signIn(email, password);
      setState(() => _message = '登录成功');
    } catch (e) {
      var msg = e is Exception ? e.toString() : '$e';
      msg = msg.replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (msg == 'NEED_VERIFICATION') {
        setState(() {
          _busy = false;
          _message = '邮箱尚未验证，验证码已发送至 $email';
        });
        if (mounted) _showVerifyDialog(email, password);
        return;
      }
      if (msg.trim().isEmpty) msg = OmniSync.friendlyAuthError(e);
      setState(() => _message = '失败：$msg');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 注册：返回 verify 时弹出验证码输入框
  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final result = await OmniSync.instance.signUp(email, password);
      if (result == 'verify') {
        setState(() {
          _busy = false;
          _message = '验证码已发送至 $email，请查收邮件';
        });
        if (mounted) _showVerifyDialog(email, password);
      } else {
        setState(() => _message = '注册成功');
      }
    } catch (e) {
      var msg = e is Exception ? e.toString() : '$e';
      msg = msg.replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (msg.trim().isEmpty) msg = OmniSync.friendlyAuthError(e);
      setState(() => _message = '失败：$msg');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 验证码输入对话框
  void _showVerifyDialog(String email, String password) {
    final codeController = TextEditingController();
    String? error;
    bool verifying = false;
    bool resending = false;
    // 60 秒重发倒计时，归零后才可再次点击
    int cooldown = 60;
    Timer? cooldownTimer;
    void startCooldown(void Function(void Function()) setDlg) {
      cooldownTimer?.cancel();
      cooldown = 60;
      cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (cooldown <= 1) {
          t.cancel();
          setDlg(() => cooldown = 0);
        } else {
          setDlg(() => cooldown--);
        }
      });
    }

    var cooldownStarted = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          if (!cooldownStarted) {
            cooldownStarted = true;
            startCooldown(setDlg);
          }
          return AlertDialog(
          title: Text("邮箱验证".tl),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("验证码已发送至".tl + ' $email',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: "6 位验证码".tl,
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
              TextButton(
                onPressed: (resending || verifying || cooldown > 0)
                    ? null
                    : () async {
                        setDlg(() => resending = true);
                        try {
                          await OmniSync.instance.resendVerificationCode(email);
                          setDlg(() {
                            resending = false;
                            error = null;
                          });
                          startCooldown(setDlg);
                          if (mounted) {
                            setState(() => _message = '验证码已重新发送');
                          }
                        } catch (e) {
                          setDlg(() {
                            resending = false;
                            error = e.toString().replaceFirst(
                                RegExp(r'^Exception:\s*'), '');
                          });
                        }
                      },
                child: resending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(cooldown > 0
                        ? '${"重新发送".tl}（${cooldown}s）'
                        : "重新发送".tl),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: verifying ? null : () => Navigator.pop(ctx),
              child: Text("取消".tl),
            ),
            FilledButton(
              onPressed: verifying
                  ? null
                  : () async {
                      final code = codeController.text.trim();
                      if (code.length != 6) {
                        setDlg(() => error = '请输入 6 位验证码');
                        return;
                      }
                      setDlg(() {
                        verifying = true;
                        error = null;
                      });
                      try {
                        await OmniSync.instance
                            .verifyEmailAndSignIn(email, code, password);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() => _message = '注册成功，已登录');
                      } catch (e) {
                        setDlg(() {
                          verifying = false;
                          error = e.toString().replaceFirst(
                              RegExp(r'^Exception:\s*'), '');
                        });
                      }
                    },
              child: verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text("验证并登录".tl),
            ),
          ],
          );
        },
      ),
    ).then((_) => cooldownTimer?.cancel());
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
                  onPressed: _busy ? null : _signIn,
                  child: Text("登录".tl),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _busy ? null : _signUp,
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
