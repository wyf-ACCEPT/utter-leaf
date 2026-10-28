import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.data,
    required this.onSync,
    required this.onErase,
  });
  final Map<String, dynamic> data;
  final VoidCallback onSync;
  final Future<void> Function(String) onErase;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final search = TextEditingController();
  String device = '全部';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String date(dynamic value) {
    final d = DateTime.fromMillisecondsSinceEpoch(
      ((value as num? ?? 0) * 1000).round(),
    ).toLocal();
    return '${d.year}/${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final query = search.text.toLowerCase();
    final rows = (widget.data['rows'] as List? ?? [])
        .whereType<Map>()
        .where(
          (r) =>
              (device == '全部' || r['device'] == device) &&
              ('${r['raw'] ?? ''}\n${r['final'] ?? ''}'.toLowerCase().contains(
                query,
              )),
        )
        .toList();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '听写历史',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.data['status'] as String? ?? '正在载入历史…',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.data['syncing'] == true
                          ? null
                          : widget.onSync,
                      icon: const Icon(CupertinoIcons.arrow_clockwise),
                      tooltip: '同步听写历史',
                    ),
                  ],
                ),
                TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '搜索听写文字',
                    prefixIcon: const Icon(CupertinoIcons.search),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              search.clear();
                              setState(() {});
                            },
                            icon: const Icon(CupertinoIcons.xmark_circle_fill),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['全部', 'Mac', 'iPhone']
                      .map(
                        (d) => ChoiceChip(
                          label: Text(d),
                          selected: device == d,
                          onSelected: (_) => setState(() => device = d),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.data.isEmpty
                ? const Center(child: CupertinoActivityIndicator())
                : rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        query.isEmpty ? '还没有听写历史。\n录音完成后会保存在这里。' : '没有找到匹配的文字。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 110),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final finalText = row['final'] as String? ?? '',
                          raw = row['raw'] as String? ?? '';
                      return Material(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(22),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => detail(row),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        date(row['created']),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    Text(
                                      '${row['device']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  finalText.isNotEmpty ? finalText : raw,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  finalText.isEmpty ? '原始转录' : '整理后文字',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> detail(Map row) async {
    final finalText = row['final'] as String? ?? '',
        raw = row['raw'] as String? ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${row['device']} · ${date(row['created'])}',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectionArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '整理后文字',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(finalText.isEmpty ? '未保留整理后文字' : finalText),
                          const SizedBox(height: 24),
                          const Text(
                            '原始转录',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(raw.isEmpty ? '未保留原始转录' : raw),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: sheet,
                          builder: (dialog) => AlertDialog(
                            title: const Text('清除这条正文？'),
                            content: const Text(
                              '会同步清除到 iCloud 和其他设备，无法撤销。调用用量仍保留。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog, false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(dialog, true),
                                child: const Text('清除正文'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !sheet.mounted) return;
                        try {
                          await widget.onErase(row['id'] as String);
                          if (sheet.mounted) Navigator.pop(sheet);
                        } catch (_) {
                          if (sheet.mounted) {
                            ScaffoldMessenger.of(sheet).showSnackBar(
                              const SnackBar(content: Text('清除未完成，请重试。')),
                            );
                          }
                        }
                      },
                      child: const Text('清除正文'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: finalText.isNotEmpty ? finalText : raw,
                          ),
                        );
                        if (sheet.mounted) {
                          ScaffoldMessenger.of(sheet).showSnackBar(
                            const SnackBar(content: Text('已复制文字')),
                          );
                        }
                      },
                      icon: const Icon(CupertinoIcons.doc_on_clipboard),
                      label: const Text('复制'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
