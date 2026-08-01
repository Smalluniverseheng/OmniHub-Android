/// 编辑个人资料页（番茄小说风格）
///
/// - 头像/背景图：本地选择图片，复制到应用文档目录持久保存
/// - 昵称：同步到云端 profiles 表
/// - 其余偏好（性别/签名/书龄/内容/完结/字数/性别偏好）：本地 appdata 保存
library edit_profile;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/omnihub/sync/omni_sync.dart';
import 'package:venera/omnihub/sync/profile.dart';
import 'package:venera/utils/translations.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _nickname;
  late final TextEditingController _signature;

  String _gender = '保密';
  String _bookAge = '1 年以下';
  String _contentPref = '不限';
  String _finishPref = '不限';
  String _wordsPref = '不限';
  String _genderPref = '不限';
  String? _avatarPath;
  String? _bgPath;
  bool _saving = false;

  static const _genders = ['保密', '男', '女'];
  static const _bookAges = ['1 年以下', '1-3 年', '3-5 年', '5-10 年', '10 年以上'];
  static const _contentPrefs = ['不限', '男频', '女频', '出版', '漫画', '听书'];
  static const _finishPrefs = ['不限', '只看完结', '只看连载'];
  static const _wordsPrefs = ['不限', '50 万字以下', '50-100 万字', '100-200 万字', '200 万字以上'];
  static const _genderPrefs = ['不限', '男生小说', '女生小说'];

  @override
  void initState() {
    super.initState();
    final s = appdata.settings;
    final cloudNick = OmniProfileService.instance.cached?.nickname ?? '';
    _nickname = TextEditingController(
        text: (s['profileNickname'] as String?)?.isNotEmpty == true
            ? s['profileNickname'] as String
            : cloudNick);
    _signature =
        TextEditingController(text: (s['profileSignature'] as String?) ?? '');
    _gender = (s['profileGender'] as String?) ?? _gender;
    _bookAge = (s['profileBookAge'] as String?) ?? _bookAge;
    _contentPref = (s['profileContentPref'] as String?) ?? _contentPref;
    _finishPref = (s['profileFinishPref'] as String?) ?? _finishPref;
    _wordsPref = (s['profileWordsPref'] as String?) ?? _wordsPref;
    _genderPref = (s['profileGenderPref'] as String?) ?? _genderPref;
    _avatarPath = (s['profileAvatar'] as String?)?.isNotEmpty == true
        ? s['profileAvatar'] as String
        : null;
    _bgPath = (s['profileBg'] as String?)?.isNotEmpty == true
        ? s['profileBg'] as String
        : null;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _signature.dispose();
    super.dispose();
  }

  /// 选图并复制到应用私有目录（避免原图被删后失效）
  Future<String?> _pickAndStore(String prefix) async {
    const group = XTypeGroup(
        label: 'images', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
      final dest = File('${dir.path}/omnihub_${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await dest.writeAsBytes(await file.readAsBytes());
      return dest.path;
    } catch (_) {
      return file.path; // 复制失败则先用原路径
    }
  }

  Future<void> _pickAvatar() async {
    const group = XTypeGroup(
        label: 'images', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    // 圆形裁剪：用户可缩放/拖动调整，输出 256x256 JPEG
    final cropped = await showDialog<List<int>>(
      context: context,
      builder: (_) => _CircleCropDialog(bytes: bytes),
    );
    if (cropped == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dest = File(
          '${dir.path}/omnihub_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await dest.writeAsBytes(cropped);
      if (mounted) setState(() => _avatarPath = dest.path);
      // 后台上传云端，不阻塞界面
      _uploadAvatar(cropped);
    } catch (_) {}
  }

  /// 上传头像到 Supabase Storage 并回写 profiles.avatar_url
  Future<void> _uploadAvatar(List<int> bytes) async {
    final session = OmniSync.instance.session;
    if (session == null) return;
    try {
      final dio = Dio();
      final objectPath = '${session.userId}/avatar.jpg';
      await dio.post(
        '${OmniSyncConfig.supabaseUrl}/storage/v1/object/avatars/$objectPath',
        data: bytes,
        options: Options(headers: {
          'apikey': OmniSyncConfig.anonKey,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        }),
      );
      final url =
          '${OmniSyncConfig.supabaseUrl}/storage/v1/object/public/avatars/$objectPath'
          '?t=${DateTime.now().millisecondsSinceEpoch}';
      await dio.patch(
        '${OmniSyncConfig.supabaseUrl}/rest/v1/profiles?id=eq.${session.userId}',
        data: {'avatar_url': url},
        options: Options(headers: {
          'apikey': OmniSyncConfig.anonKey,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        }),
      );
      appdata.settings['profileAvatarUrl'] = url;
      appdata.saveData();
      OmniProfileService.instance.invalidate();
      OmniSync.instance.refresh();
    } catch (_) {}
  }

  Future<void> _pickBg() async {
    final p = await _pickAndStore('bg');
    if (p != null && mounted) setState(() => _bgPath = p);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final s = appdata.settings;
    s['profileNickname'] = _nickname.text.trim();
    s['profileSignature'] = _signature.text.trim();
    s['profileGender'] = _gender;
    s['profileBookAge'] = _bookAge;
    s['profileContentPref'] = _contentPref;
    s['profileFinishPref'] = _finishPref;
    s['profileWordsPref'] = _wordsPref;
    s['profileGenderPref'] = _genderPref;
    s['profileAvatar'] = _avatarPath ?? '';
    s['profileBg'] = _bgPath ?? '';
    appdata.saveData();

    // 昵称同步云端 profiles 表
    final session = OmniSync.instance.session;
    if (session != null && _nickname.text.trim().isNotEmpty) {
      try {
        await Dio().patch(
          '${OmniSyncConfig.supabaseUrl}/rest/v1/profiles?id=eq.${session.userId}',
          data: {'nickname': _nickname.text.trim()},
          options: Options(headers: {
            'apikey': OmniSyncConfig.anonKey,
            'Authorization': 'Bearer ${session.accessToken}',
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
          }),
        );
        OmniProfileService.instance.invalidate();
      } catch (_) {
        // 云端失败不阻塞本地保存
      }
    }
    OmniSync.instance.refresh(); // 让设置页立即刷新昵称/头像
    if (mounted) {
      setState(() => _saving = false);
      context.showMessage(message: "已保存".tl);
      context.pop();
    }
  }

  Widget _choiceRow(String title, String value, List<String> options,
      ValueChanged<String> onChanged) {
    return ListTile(
      title: Text(title.tl),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(color: context.colorScheme.outline)),
        const Icon(Icons.chevron_right, size: 20),
      ]),
      onTap: () async {
        final r = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(title.tl),
            children: options
                .map((o) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, o),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(o),
                      ),
                    ))
                .toList(),
          ),
        );
        if (r != null) onChanged(r);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final email = OmniSync.instance.session?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text("编辑个人资料".tl),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text("保存".tl),
          ),
        ],
      ),
      body: ListView(
        children: [
          // 背景图 + 头像（番茄风格头部）
          Stack(
            clipBehavior: Clip.none,
            children: [
              InkWell(
                onTap: _pickBg,
                child: Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    image: _bgPath != null && File(_bgPath!).existsSync()
                        ? DecorationImage(
                            image: FileImage(File(_bgPath!)), fit: BoxFit.cover)
                        : null,
                  ),
                  child: Center(
                    child: Icon(Icons.photo_camera_outlined,
                        color: colors.outline, size: 28),
                  ),
                ),
              ),
              Positioned(
                left: 0, right: 0, bottom: -40,
                child: Center(
                  child: InkWell(
                    onTap: _pickAvatar,
                    borderRadius: BorderRadius.circular(48),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: colors.primaryContainer,
                          backgroundImage:
                              _avatarPath != null && File(_avatarPath!).existsSync()
                                  ? FileImage(File(_avatarPath!))
                                  : null,
                          child: _avatarPath == null
                              ? Text(
                                  _nickname.text.isNotEmpty
                                      ? _nickname.text.characters.first.toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.bold,
                                      color: colors.onPrimaryContainer),
                                )
                              : null,
                        ),
                        Positioned(
                          right: 0, bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.photo_camera,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 52),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nickname,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: "昵称".tl,
                helperText: email,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          _choiceRow("性别", _gender, _genders, (v) => setState(() => _gender = v)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _signature,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: "签名".tl,
                hintText: "写一句话介绍自己".tl,
              ),
            ),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text("阅读偏好".tl,
                style: TextStyle(
                    fontSize: 13,
                    color: colors.primary,
                    fontWeight: FontWeight.bold)),
          ),
          _choiceRow("网文书龄", _bookAge, _bookAges,
              (v) => setState(() => _bookAge = v)),
          _choiceRow("内容偏好", _contentPref, _contentPrefs,
              (v) => setState(() => _contentPref = v)),
          _choiceRow("完结偏好", _finishPref, _finishPrefs,
              (v) => setState(() => _finishPref = v)),
          _choiceRow("字数偏好", _wordsPref, _wordsPrefs,
              (v) => setState(() => _wordsPref = v)),
          _choiceRow("性别偏好", _genderPref, _genderPrefs,
              (v) => setState(() => _genderPref = v)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// 圆形头像裁剪对话框：双指缩放、拖动调整，圆形视口预览
class _CircleCropDialog extends StatefulWidget {
  final List<int> bytes;
  const _CircleCropDialog({required this.bytes});

  @override
  State<_CircleCropDialog> createState() => _CircleCropDialogState();
}

class _CircleCropDialogState extends State<_CircleCropDialog> {
  static const double viewport = 260;
  final TransformationController _tc = TransformationController();
  img.Image? _src;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _src = img.decodeImage(widget.bytes is Uint8List
        ? widget.bytes as Uint8List
        : Uint8List.fromList(widget.bytes));
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitCover());
  }

  /// 初始缩放：短边铺满圆形视口
  void _fitCover() {
    final s = _src;
    if (s == null) return;
    final scale = viewport / math.min(s.width, s.height);
    final dx = (viewport - s.width * scale) / 2;
    final dy = (viewport - s.height * scale) / 2;
    _tc.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
    setState(() {});
  }

  /// 把圆形视口（内切正方形）映射回源图像素并裁剪
  List<int>? _crop() {
    final s = _src;
    if (s == null) return null;
    final inv = Matrix4.inverted(_tc.value);
    // 视口四角映射到场景坐标
    double sx(double x, double y) => inv.transform3(Vector3(x, y, 0)).x;
    double sy(double x, double y) => inv.transform3(Vector3(x, y, 0)).y;
    final x0 = sx(0, 0), y0 = sy(0, 0);
    final x1 = sx(viewport, viewport), y1 = sy(viewport, viewport);
    var left = math.min(x0, x1), top = math.min(y0, y1);
    var w = (x1 - x0).abs(), h = (y1 - y0).abs();
    final side = math.min(w, h);
    // 中心正方形
    left += (w - side) / 2;
    top += (h - side) / 2;
    final l = left.round().clamp(0, s.width - 1);
    final t = top.round().clamp(0, s.height - 1);
    final sw = side.round().clamp(1, s.width - l);
    final sh = side.round().clamp(1, s.height - t);
    final cropped =
        img.copyCrop(s, x: l, y: t, width: sw, height: sh);
    final resized = img.copyResize(cropped, width: 256, height: 256);
    return img.encodeJpg(resized, quality: 88);
  }

  @override
  Widget build(BuildContext context) {
    final s = _src;
    return AlertDialog(
      title: Text("调整头像".tl),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: viewport,
            height: viewport,
            child: s == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      ClipRect(
                        child: InteractiveViewer(
                          transformationController: _tc,
                          minScale: 0.2,
                          maxScale: 6,
                          child: Image.memory(
                            Uint8List.fromList(img.encodePng(s)),
                            width: s.width.toDouble(),
                            height: s.height.toDouble(),
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                      // 圆形裁剪范围指示（外圈暗化 + 圆环）
                      IgnorePointer(
                        child: CustomPaint(
                          size: const Size(viewport, viewport),
                          painter: _CircleMaskPainter(),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          Text('双指缩放、拖动调整位置'.tl,
              style: TextStyle(
                  fontSize: 12, color: context.colorScheme.outline)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("取消".tl),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  setState(() => _busy = true);
                  final out = _crop();
                  Navigator.pop(context, out);
                },
          child: Text("确定".tl),
        ),
      ],
    );
  }
}

/// 圆形遮罩：圆外半透明暗化，圆内清晰
class _CircleMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Rect.fromCircle(
        center: size.center(Offset.zero), radius: size.width / 2 - 1);
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = Colors.black54);
    canvas.drawOval(
        circle,
        Paint()
          ..blendMode = BlendMode.clear);
    canvas.restore();
    canvas.drawOval(
        circle,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white70);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
