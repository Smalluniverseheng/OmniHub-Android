/// OmniHub 阅读注释页
///
/// 某本书的注释列表（手写笔记 + AI 问答留痕），登录后可云端同步。
library ai_annotations_page;

import 'package:flutter/material.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/omnihub/ai/annotations.dart';
import 'package:venera/omnihub/sync/omni_sync.dart';
import 'package:venera/utils/translations.dart';

class AiAnnotationsPage extends StatefulWidget {
  final String bookRef;
  final String bookTitle;

  const AiAnnotationsPage(
      {super.key, required this.bookRef, required this.bookTitle});

  @override
  State<AiAnnotationsPage> createState() => _AiAnnotationsPageState();
}

class _AiAnnotationsPageState extends State<AiAnnotationsPage> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    AnnotationStore.instance.addListener(_onChange);
    AnnotationStore.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AnnotationStore.instance.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _sync() async {
    if (!OmniSync.instance.isLoggedIn) {
      context.showMessage(message: "请先在「云同步」中登录");
      return;
    }
    setState(() => _syncing = true);
    final res = await AnnotationStore.instance.sync();
    if (mounted) {
      setState(() => _syncing = false);
      context.showMessage(
          message: res.ok
              ? "同步完成：上传 ${res.pushed} 条，下载 ${res.pulled} 条"
              : "同步失败：${res.error}");
    }
  }

  void _addNote() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("新建笔记".tl),
        content: TextField(
          controller: controller,
          maxLines: 6,
          minLines: 3,
          decoration: InputDecoration(
            hintText: "记录你的想法…".tl,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("Cancel".tl),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                AnnotationStore.instance.add(AiAnnotation(
                  id: 'note-${DateTime.now().millisecondsSinceEpoch}',
                  bookRef: widget.bookRef,
                  bookTitle: widget.bookTitle,
                  type: 'note',
                  content: text,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ));
              }
              Navigator.of(dialogContext).pop();
            },
            child: Text("Save".tl),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = AnnotationStore.instance.forBook(widget.bookRef);
    return Scaffold(
      appBar: AppBar(
        title: Text("注释".tl),
        actions: [
          IconButton(
            tooltip: "Sync".tl,
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNote,
        child: const Icon(Icons.add),
      ),
      body: notes.isEmpty
          ? Center(
              child: Text(
                "还没有注释\n阅读时可「问 AI」并保存回答，或点右下角手写笔记".tl,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colorScheme.outline),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: notes.length,
              itemBuilder: (context, i) {
                final a = notes[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              a.type == 'ask'
                                  ? Icons.smart_toy_outlined
                                  : Icons.edit_note,
                              size: 16,
                              color: context.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              a.type == 'ask' ? "AI 问答".tl : "笔记".tl,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.colorScheme.primary),
                            ),
                            const Spacer(),
                            Text(
                              _fmtTime(a.updatedAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.colorScheme.outline),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () =>
                                  AnnotationStore.instance.remove(a.id),
                            ),
                          ],
                        ),
                        if (a.question.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            "问：${a.question}",
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: context.colorScheme.onSurface),
                          ),
                        ],
                        const SizedBox(height: 6),
                        SelectableText(a.content),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _fmtTime(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
