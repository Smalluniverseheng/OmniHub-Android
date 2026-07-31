import 'package:app_links/app_links.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/pages/comic_details_page/comic_page.dart';
import 'package:venera/pages/novel/novel_pages.dart';

void handleLinks() {
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    handleAppLink(uri);
  });
}

Future<bool> handleAppLink(Uri uri) async {
  // Legado 书源导入协议：legado://import/{path}?src={url}
  if (uri.scheme == 'legado') {
    var ctx = App.mainNavigatorKey?.currentContext;
    var tries = 0;
    while (ctx == null && tries < 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      ctx = App.mainNavigatorKey?.currentContext;
      tries++;
    }
    if (ctx != null && ctx.mounted) {
      NovelSourcesPage.importLegadoUrl(uri.toString(), ctx);
    }
    return true;
  }
  for(var source in ComicSource.all()) {
    if(source.linkHandler != null) {
      if(source.linkHandler!.domains.contains(uri.host)) {
        var id = source.linkHandler!.linkToId(uri.toString());
        if(id != null) {
          if(App.mainNavigatorKey == null) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
          App.mainNavigatorKey!.currentContext?.to(() {
            return ComicPage(id: id, sourceKey: source.key);
          });
          return true;
        }
        return false;
      }
    }
  }
  return false;
}