/// OmniHub 书架同步（App ↔ 网页）
///
/// 把本地收藏（书架）上行到 Supabase `user_data` 表 module='bookshelf'，
/// 并拉取云端（含网页版添加的）记录合并回本地。
/// 记录 key: `{sourceKey}|{comicId}`，冲突按 updated_at last-write-wins。
library bookshelf_sync;

import 'dart:convert';

import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/omnihub/sync/omni_sync.dart';
import 'package:venera/omnihub/sync/profile.dart';

class BookshelfSyncResult {
  final int pushed;
  final int pulled;
  final String? error;
  const BookshelfSyncResult(this.pushed, this.pulled, [this.error]);
  bool get ok => error == null;
}

class BookshelfSync {
  BookshelfSync._();
  static final BookshelfSync instance = BookshelfSync._();

  static const String cloudFolder = '云端同步';

  DateTime? _lastSync;

  String _keyOf(FavoriteItemWithFolderInfo c) => '${c.sourceKey}|${c.id}';

  /// 全量推送本地书架 + 增量拉取云端并合并
  Future<BookshelfSyncResult> sync() async {
    if (!OmniSync.instance.isLoggedIn) {
      return const BookshelfSyncResult(0, 0, '未登录');
    }
    try {
      // 1. 上行本地全部收藏
      final all = LocalFavoritesManager().allComics();
      final records = <String, Map<String, dynamic>>{};
      for (final c in all) {
        records[_keyOf(c)] = {
          'kind': 'comic',
          'title': c.name,
          'author': c.author,
          'cover': c.coverPath,
          'sourceKey': c.sourceKey,
          'comicId': c.id,
          'comicType': c.type.value,
          'tags': c.tags,
          'folder': c.folder,
          'time': c.time,
          'platform': 'app',
        };
      }
      // 云同步为会员功能：普通/游客等级不同步（进阶500MB起）
      // 等级存储配额校验：进阶500MB/会员1GB/高级会员5GB
      try {
        final profile = await OmniProfileService.instance.fetch();
        final role = profile?.role ?? '';
        final isMember = profile?.isAdmin == true ||
            const ['advanced', 'vip', 'svip', 'agent'].contains(role);
        if (!isMember) {
          return const BookshelfSyncResult(
              0, 0, '云同步需进阶会员及以上等级，普通用户暂不支持');
        }
        final quotaMb = profile?.effectiveQuotaMb ?? 0;
        if (quotaMb > 0) {
          final approxBytes = jsonEncode(records).length;
          if (approxBytes > quotaMb * 1024 * 1024) {
            return BookshelfSyncResult(
                0, 0, '云存储空间不足（当前配额 ${OmniProfile.fmtMb(quotaMb)}），请升级会员');
          }
        }
      } catch (_) {
        // 配额查询失败不阻塞同步
      }
      await OmniSync.instance.pushRecords('bookshelf', records);

      // 2. 拉取云端（含网页端写入的），合并进本地
      final remote = await OmniSync.instance.pullModule('bookshelf');
      var pulled = 0;
      final existing = <String>{};
      for (final c in LocalFavoritesManager().allComics()) {
        existing.add(_keyOf(c));
      }
      final fav = LocalFavoritesManager();
      if (!fav.existsFolder(cloudFolder)) {
        fav.createFolder(cloudFolder);
      }
      for (final row in remote) {
        final v = row['value'] as Map<String, dynamic>;
        if (v['_deleted'] == true) continue;
        final key = row['key'] as String;
        if (existing.contains(key)) continue;
        if (v['kind'] != 'comic') continue; // 小说等留给 M3 小说模块处理
        final typeValue = v['comicType'];
        if (typeValue is! int) continue;
        try {
          fav.addComic(
            cloudFolder,
            FavoriteItem(
              id: (v['comicId'] ?? '') as String,
              name: (v['title'] ?? '未命名') as String,
              author: (v['author'] ?? '') as String,
              coverPath: (v['cover'] ?? '') as String,
              type: ComicType(typeValue),
              tags: (v['tags'] as List?)?.cast<String>() ?? const [],
            ),
          );
          pulled++;
        } catch (_) {
          // 单个条目失败不影响整体
        }
      }

      _lastSync = DateTime.now();
      return BookshelfSyncResult(records.length, pulled);
    } catch (e) {
      return BookshelfSyncResult(0, 0, e.toString());
    }
  }

  DateTime? get lastSync => _lastSync;
}
