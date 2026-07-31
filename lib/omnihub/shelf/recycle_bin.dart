/// 书架最近删除（回收站）
///
/// 从书架多选删除的书先进入回收站，30 天内可恢复。
library recycle_bin;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';

class RecycleItem {
  final FavoriteItem item;
  final String folder;
  final int deletedAt; // 毫秒时间戳

  RecycleItem(
      {required this.item, required this.folder, required this.deletedAt});

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'folder': folder,
        'deletedAt': deletedAt,
      };

  factory RecycleItem.fromJson(Map<String, dynamic> j) {
    final c = j['item'] as Map<String, dynamic>;
    return RecycleItem(
      item: FavoriteItem(
        id: c['id'] as String,
        name: c['name'] as String,
        coverPath: c['coverPath'] as String,
        author: c['author'] as String,
        type: ComicType((c['type'] as num).toInt()),
        tags: (c['tags'] as List).map((e) => e.toString()).toList(),
      ),
      folder: j['folder'] as String,
      deletedAt: (j['deletedAt'] as num).toInt(),
    );
  }
}

class ShelfRecycleBin extends ChangeNotifier {
  ShelfRecycleBin._();
  static final ShelfRecycleBin instance = ShelfRecycleBin._();

  final List<RecycleItem> items = [];
  File? _file;
  bool _loaded = false;

  static const retention = Duration(days: 30);

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/omnihub_recycle_bin.json');
    return _file!;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _ensureFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as List;
        items.addAll(j.map((e) => RecycleItem.fromJson(e)));
        _purge();
      }
    } catch (_) {}
  }

  void _purge() {
    final limit = DateTime.now().subtract(retention).millisecondsSinceEpoch;
    items.removeWhere((e) => e.deletedAt < limit);
  }

  Future<void> save() async {
    final f = await _ensureFile();
    await f.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  /// 删除收藏时调用：先移入回收站，再从收藏夹移除
  Future<void> delete(String folder, FavoriteItem item) async {
    items.insert(
        0,
        RecycleItem(
            item: item,
            folder: folder,
            deletedAt: DateTime.now().millisecondsSinceEpoch));
    LocalFavoritesManager().deleteComicWithId(folder, item.id, item.type);
    await save();
    notifyListeners();
  }

  /// 恢复到原分组（分组不存在则自动创建）
  Future<void> restore(RecycleItem r) async {
    final mgr = LocalFavoritesManager();
    if (!mgr.existsFolder(r.folder)) {
      mgr.createFolder(r.folder, true);
    }
    mgr.addComic(r.folder, r.item);
    items.remove(r);
    await save();
    notifyListeners();
  }

  Future<void> removeForever(RecycleItem r) async {
    items.remove(r);
    await save();
    notifyListeners();
  }
}
