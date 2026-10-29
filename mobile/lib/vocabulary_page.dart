import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VocabularyPage extends StatefulWidget {
  const VocabularyPage({super.key});
  @override
  State<VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<VocabularyPage> {
  static const bridge = MethodChannel('network.utterleaf/dictation');
  final search = TextEditingController();
  Map<String, dynamic> data = {};
  Timer? timer;
  bool loading = false, saving = false;
  String? error;
  bool get locked => saving || data['busy'] == true;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final value = await bridge.invokeMapMethod<String, dynamic>('vocabulary');
      if (mounted && value != null) {
        setState(() {
          data = value;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => error = '词汇表暂时无法载入，请重试。');
    } finally {
      loading = false;
    }
  }

  Future<void> change(String method, dynamic args) async {
    if (locked) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await bridge.invokeMethod<void>(method, args);
      await load();
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message ?? '修改未保存，请重试。');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = search.text.toLowerCase();
    final all = (data['entries'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final rows = all
        .where(
          (e) => '${e['term']} ${e['aliases']} ${e['note']}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('词汇表'),
        actions: [
          IconButton(
            tooltip: '添加词条',
            onPressed: locked ? null : () => edit(null),
            icon: const Icon(CupertinoIcons.plus),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['status'] as String? ?? '正在载入…',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      IconButton(
                        tooltip: '同步词汇表',
                        onPressed: data['syncing'] == true || locked
                            ? null
                            : () => change('syncVocabulary', null),
                        icon: const Icon(CupertinoIcons.arrow_clockwise),
                      ),
                    ],
                  ),
                  TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: '搜索词汇或易错写法',
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: () {
                                search.clear();
                                setState(() {});
                              },
                              icon: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Mac 与 iPhone 自动同步。词条只用于整理文字，修改影响下一次听写。',
                    style: TextStyle(fontSize: 13),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: data.isEmpty
                  ? error == null
                        ? const Center(child: CupertinoActivityIndicator())
                        : Center(
                            child: TextButton(
                              onPressed: load,
                              child: const Text('重试载入词汇表'),
                            ),
                          )
                  : rows.isEmpty
                  ? Center(
                      child: Text(query.isEmpty ? '还没有词条，点右上角添加。' : '没有匹配的词条。'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final entry = rows[i];
                        final aliases = (entry['aliases'] as List? ?? []).join(
                          '、',
                        );
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry['term'] as String? ?? '',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    activeTrackColor: colors.primary,
                                    value: entry['enabled'] == true,
                                    onChanged: locked
                                        ? null
                                        : (value) => change('saveVocabulary', {
                                            ...entry,
                                            'enabled': value,
                                          }),
                                  ),
                                ],
                              ),
                              if (aliases.isNotEmpty) Text('易错写法：$aliases'),
                              if ((entry['note'] as String? ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    entry['note'] as String,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: locked
                                        ? null
                                        : () => edit(entry),
                                    child: const Text('编辑'),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: colors.error,
                                    ),
                                    onPressed: locked
                                        ? null
                                        : () => remove(entry),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> remove(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('删除“${entry['term']}”？'),
        content: const Text('删除会同步到 Mac 与 iPhone。已有听写文字不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialog).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除词条'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await change('deleteVocabulary', entry['id']);
    }
  }

  Future<void> edit(Map<String, dynamic>? entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (_) => _VocabularyEditor(entry: entry),
    );
    await load();
  }
}

class _VocabularyEditor extends StatefulWidget {
  const _VocabularyEditor({required this.entry});
  final Map<String, dynamic>? entry;
  @override
  State<_VocabularyEditor> createState() => _VocabularyEditorState();
}

class _VocabularyEditorState extends State<_VocabularyEditor> {
  static const bridge = MethodChannel('network.utterleaf/dictation');
  late final term = TextEditingController(
    text: widget.entry?['term'] as String? ?? '',
  );
  late final aliases = TextEditingController(
    text: (widget.entry?['aliases'] as List? ?? []).join('\n'),
  );
  late final note = TextEditingController(
    text: widget.entry?['note'] as String? ?? '',
  );
  late bool enabled = widget.entry?['enabled'] as bool? ?? true;
  bool working = false;
  String? failure;
  bool get dirty =>
      term.text != (widget.entry?['term'] ?? '') ||
      aliases.text != (widget.entry?['aliases'] as List? ?? []).join('\n') ||
      note.text != (widget.entry?['note'] ?? '') ||
      enabled != (widget.entry?['enabled'] ?? true);
  @override
  void dispose() {
    term.dispose();
    aliases.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> cancel() async {
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('放弃未保存的修改？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> save() async {
    if (working) return;
    setState(() {
      working = true;
      failure = null;
    });
    try {
      await bridge.invokeMethod<void>('saveVocabulary', {
        if (widget.entry != null) 'id': widget.entry!['id'],
        'term': term.text,
        'aliases': aliases.text.split('\n'),
        'note': note.text,
        'enabled': enabled,
      });
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          working = false;
          failure = e.message ?? '保存失败，请重试。';
        });
      }
    }
  }

  Widget counter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    int? maxLength,
  }) => Text(
    '$currentLength / $maxLength',
    semanticsLabel: '已输入 $currentLength 字，最多 $maxLength 字',
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.entry == null ? '添加词条' : '编辑词条',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: term,
              autofocus: true,
              maxLength: 100,
              buildCounter: counter,
              decoration: const InputDecoration(labelText: '首选拼写'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: aliases,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '易错写法 · 每行一个'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 500,
              buildCounter: counter,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '使用说明 · 可选'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: Theme.of(context).colorScheme.primary,
              title: const Text('启用此词条'),
              value: enabled,
              onChanged: working
                  ? null
                  : (value) => setState(() => enabled = value),
            ),
            if (failure != null)
              Text(
                failure!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: working ? null : cancel,
                  child: const Text('取消'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: working ? null : save,
                  child: Text(working ? '保存中…' : '保存词条'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
