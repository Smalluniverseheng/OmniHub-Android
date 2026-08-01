part of 'settings_page.dart';

class AboutSettings extends StatefulWidget {
  const AboutSettings({super.key});

  @override
  State<AboutSettings> createState() => _AboutSettingsState();
}

class _AboutSettingsState extends State<AboutSettings> {
  bool isCheckingUpdate = false;

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("About".tl)),
        SizedBox(
          height: 112,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(136),
              ),
              clipBehavior: Clip.antiAlias,
              child: const Image(
                image: AssetImage("assets/app_icon.png"),
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ).paddingTop(16).toSliver(),
        Column(
          children: [
            const SizedBox(height: 8),
            Text(
              "V${App.version}",
              style: const TextStyle(fontSize: 16),
            ),
            Text("OmniHub is a free and open-source app for comic and novel reading.".tl),
            const SizedBox(height: 8),
          ],
        ).toSliver(),
        ListTile(
          title: Text("Check for updates".tl),
          trailing: Button.filled(
            isLoading: isCheckingUpdate,
            child: Text("Check".tl),
            onPressed: () {
              setState(() {
                isCheckingUpdate = true;
              });
              checkUpdateUi().then((value) {
                setState(() {
                  isCheckingUpdate = false;
                });
              });
            },
          ).fixHeight(32),
        ).toSliver(),
        _SwitchSetting(
          title: "Check for updates on startup".tl,
          settingKey: "checkUpdateOnStart",
        ).toSliver(),
        ListTile(
          title: const Text("Github"),
          trailing: const Icon(Icons.open_in_new),
          onTap: () {
            launchUrlString("https://github.com/Smalluniverseheng/OmniHub-Android");
          },
        ).toSliver(),
        ListTile(
          title: const Text("OmniHub Web"),
          trailing: const Icon(Icons.open_in_new),
          onTap: () {
            launchUrlString("https://smalluniverseheng.github.io/OmniHub/");
          },
        ).toSliver(),
      ],
    );
  }
}

/// 应用内更新：版本信息 + 公告，来自专用更新仓库 OmniHub-Update
class AppUpdateInfo {
  final String version;
  final int build;
  final String notes;
  final Map<String, String> apks;
  final String releasePage;

  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.notes,
    required this.apks,
    required this.releasePage,
  });
}

/// 更新清单：优先走 Cloudflare Worker 反代（速度快、无 raw 缓存），失败回退 raw
const String _kGateway = 'https://ai-gateway.1829487897.workers.dev';
const String _kUpdateManifest = "$_kGateway/update/latest.json";
const String _kUpdateManifestFallback =
    "https://raw.githubusercontent.com/Smalluniverseheng/OmniHub-Update/main/latest.json";

Future<AppUpdateInfo?> fetchUpdateInfo() async {
  dynamic data;
  for (final url in [_kUpdateManifest, _kUpdateManifestFallback]) {
    try {
      final res = await AppDio().get(url);
      if (res.statusCode != 200) continue;
      data = res.data;
      break;
    } catch (_) {
      continue;
    }
  }
  if (data == null) return null;
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {
      return null;
    }
  }
  if (data is! Map) return null;
  final apks = <String, String>{};
  if (data['apks'] is Map) {
    (data['apks'] as Map).forEach((k, v) {
      apks[k.toString()] = v.toString();
    });
  }
  return AppUpdateInfo(
    version: data['version']?.toString() ?? '',
    build: data['build'] is int
        ? data['build'] as int
        : int.tryParse(data['build']?.toString() ?? '') ?? 0,
    notes: data['notes']?.toString() ?? '',
    apks: apks,
    releasePage: data['releasePage']?.toString() ??
        'https://github.com/Smalluniverseheng/OmniHub-Android/releases',
  );
}

Future<bool> checkUpdate() async {
  final info = await fetchUpdateInfo();
  return info != null && info.build > App.buildNumber;
}

Future<void> checkUpdateUi(
    [bool showMessageIfNoUpdate = true, bool delay = false]) async {
  try {
    final info = await fetchUpdateInfo();
    if (info != null && info.build > App.buildNumber) {
      if (delay) {
        await Future.delayed(const Duration(seconds: 2));
      }
      _showUpdateDialog(info);
    } else if (showMessageIfNoUpdate) {
      App.rootContext.showMessage(message: "No new version available".tl);
    }
  } catch (e, s) {
    Log.error("Check Update", e.toString(), s);
  }
}

void _showUpdateDialog(AppUpdateInfo info) {
  showDialog(
    context: App.rootContext,
    builder: (context) {
      return ContentDialog(
        title: "发现新版本 V@v".tlParams({'v': info.version}),
        content: SingleChildScrollView(
          child: Text(
            info.notes.isNotEmpty ? info.notes : "修复已知问题，建议更新".tl,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ).paddingHorizontal(16),
        ),
        actions: [
          Button.text(
            onPressed: () => Navigator.pop(context),
            child: Text("稍后".tl),
          ),
          Button.filled(
            onPressed: () {
              Navigator.pop(context);
              downloadAndInstallUpdate(info);
            },
            child: Text("立即下载".tl),
          ),
        ],
      );
    },
  );
}

/// 后台下载 APK，完成后提示安装
Future<void> downloadAndInstallUpdate(AppUpdateInfo info) async {
  // 按设备 ABI 选择安装包；优先 Cloudflare Worker 加速通道
  var url = info.apks['universal'] ?? '';
  String abi = '';
  try {
    const channel = MethodChannel('omnihub/update');
    final abis = await channel.invokeMethod<List<dynamic>>('getAbis');
    for (final a in const ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      if ((abis?.contains(a) ?? false) && info.apks[a] != null) {
        url = info.apks[a]!;
        abi = a;
        break;
      }
    }
  } catch (_) {}
  if (url.isEmpty) {
    launchUrlString(info.releasePage);
    return;
  }
  // Worker 加速地址（GitHub 直连慢/失败的设备走这里），失败时回退原始链接
  final urls = <String>[
    if (abi.isNotEmpty) '$_kGateway/update/apk/$abi',
    url,
  ];

  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/OmniHub-${info.version}.apk';
  final progress = ValueNotifier<double>(0);
  final cancelToken = dio_pkg.CancelToken();
  var dialogOpen = true;

  // 下载进度对话框（可转后台）
  showDialog(
    context: App.rootContext,
    barrierDismissible: false,
    builder: (dialogContext) {
      return ContentDialog(
        title: "正在下载更新".tl,
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v == 0 ? null : v),
              const SizedBox(height: 8),
              Text("${(v * 100).clamp(0, 100).toStringAsFixed(0)}%"),
            ],
          ).paddingHorizontal(16),
        ),
        actions: [
          Button.text(
            onPressed: () {
              cancelToken.cancel();
              Navigator.pop(dialogContext);
              dialogOpen = false;
            },
            child: Text("Cancel".tl),
          ),
          Button.filled(
            onPressed: () {
              Navigator.pop(dialogContext);
              dialogOpen = false;
              App.rootContext.showMessage(message: "已在后台继续下载".tl);
            },
            child: Text("后台下载".tl),
          ),
        ],
      );
    },
  ).then((_) => dialogOpen = false);

  try {
    var downloaded = false;
    Object? lastError;
    for (final u in urls) {
      try {
        await dio_pkg.Dio().download(
          u,
          path,
          cancelToken: cancelToken,
          onReceiveProgress: (r, t) {
            if (t > 0) progress.value = r / t;
          },
        );
        downloaded = true;
        break;
      } catch (e) {
        if (e is dio_pkg.DioException &&
            e.type == dio_pkg.DioExceptionType.cancel) {
          rethrow; // 用户主动取消，不再尝试其他通道
        }
        lastError = e;
        progress.value = 0;
      }
    }
    if (!downloaded) throw lastError ?? Exception('下载失败');
    progress.value = 1;
    if (dialogOpen && App.rootContext.mounted) {
      Navigator.of(App.rootContext, rootNavigator: true).pop();
      dialogOpen = false;
    }
    // 下载完成：提示安装
    showDialog(
      context: App.rootContext,
      builder: (context) {
        return ContentDialog(
          title: "下载完成".tl,
          content: Text("新版本 V@v 已下载完成，是否立即安装？"
                  .tlParams({'v': info.version}))
              .paddingHorizontal(16),
          actions: [
            Button.text(
              onPressed: () => Navigator.pop(context),
              child: Text("稍后".tl),
            ),
            Button.filled(
              onPressed: () {
                Navigator.pop(context);
                OpenFilex.open(path);
              },
              child: Text("安装".tl),
            ),
          ],
        );
      },
    );
  } catch (e) {
    if (dialogOpen && App.rootContext.mounted) {
      Navigator.of(App.rootContext, rootNavigator: true).pop();
      dialogOpen = false;
    }
    if (!cancelToken.isCancelled) {
      App.rootContext.showMessage(message: "下载失败，请稍后重试".tl);
    }
  }
}

