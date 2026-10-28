import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class UsagePage extends StatefulWidget {
  const UsagePage({
    super.key,
    required this.data,
    required this.onSync,
    required this.onBudget,
  });
  final Map<String, dynamic> data;
  final VoidCallback onSync;
  final Future<void> Function(double, double) onBudget;
  @override
  State<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends State<UsagePage> {
  String device = '全部';
  static Map<String, dynamic> map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static double number(dynamic value) => value is num ? value.toDouble() : 0;
  static String money(dynamic value) => '¥${number(value).toStringAsFixed(2)}';
  String time(dynamic value) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      (number(value) * 1000).round(),
    ).toLocal();
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data, colors = Theme.of(context).colorScheme;
    if (data.isEmpty) return const Center(child: CupertinoActivityIndicator());
    final week = map(data['week']), month = map(data['month']);
    final allCalls = (data['calls'] as List? ?? [])
        .whereType<Map>()
        .map(map)
        .toList();
    final initialEmpty =
        number(data['lastSync']) <= 0 &&
        number(data['macCalls']) + number(data['phoneCalls']) == 0;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
        children: [
          const Text(
            '用量与费用',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['status'] as String? ?? '等待同步',
                      style: TextStyle(color: colors.primary),
                    ),
                    Text(
                      number(data['lastSync']) > 0
                          ? '最近成功 ${time(data['lastSync'])}'
                          : '首次同步尚未完成 · 当前仅显示本机缓存',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '立即同步',
                onPressed: data['syncing'] == true ? null : widget.onSync,
                icon: const Icon(CupertinoIcons.arrow_clockwise),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (initialEmpty)
            card(const Text('等待首次同步。尚未收到用量记录，暂不显示费用或剩余额度。'))
          else
            card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '表达额度 · CNY',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => editBudget(week, month),
                        child: const Text('调整预算'),
                      ),
                    ],
                  ),
                  budget(week, 7),
                  const SizedBox(height: 26),
                  budget(month, 30),
                  if (number(month['unknown']) >= 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: Text(
                        '${month['unknown']} 次调用金额未知，暂未计入估算。',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          if (!initialEmpty)
            card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '近 30 天 · 设备与用途',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Mac ${money(month['mac'])} · iPhone ${money(month['phone'])}',
                  ),
                  Text(
                    '听写 ${money(month['dictation'])} · 会议 ${money(month['meeting'])}',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '已收到 Mac ${data['macCalls'] ?? 0} 次 · iPhone ${data['phoneCalls'] ?? 0} 次调用',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (number(data['macCalls']) == 0)
                    const Text(
                      '尚未收到 Mac 记录；不能据此判断 Mac 没有消费。',
                      style: TextStyle(fontSize: 12),
                    ),
                  const SizedBox(height: 12),
                  if (month['perThousand'] != null)
                    Text('听写每千字 · ${money(month['perThousand'])} 估算'),
                  if (month['meetingPerHour'] != null)
                    Text('会议每小时 · ${money(month['meetingPerHour'])} 估算'),
                ],
              ),
            ),
          const SizedBox(height: 24),
          card(
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('调用明细'),
              subtitle: const Text('最近 50 次 · 可按设备筛选'),
              trailing: const Icon(CupertinoIcons.chevron_forward),
              onTap: () => showDetails(allCalls),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '共享预算只作提醒，不是供应商余额。仅汇总 CNY 已知估算；调用明细显示最近 50 次，筛选只作用于明细。手机记录从此版本开始累计。只同步用量与预算，录音、正文和 API Key 留在本机。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> showDetails(List<Map<String, dynamic>> calls) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) {
          final rows = calls
              .where(
                (call) =>
                    device == '全部' ||
                    call['device'] == (device == '手机' ? 'iPhone' : 'Mac'),
              )
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheet).height * 0.72,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '调用明细',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: ['全部', 'Mac', '手机']
                          .map(
                            (name) => ChoiceChip(
                              label: Text(name),
                              selected: device == name,
                              onSelected: (_) => update(() => device = name),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: rows.isEmpty
                          ? const Center(child: Text('当前没有已记录的调用。'))
                          : ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (_, index) {
                                final call = rows[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${call['provider']} · ${call['device']}',
                                  ),
                                  subtitle: Text(
                                    '${time(call['started'])} · ${status(call['status'])}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Text(
                                    call['amount'] == null
                                        ? '金额未知'
                                        : '${call['currency'] == 'CNY' ? money(call['amount']) : '${call['amount']} ${call['currency']}'}\n估算',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String status(dynamic value) => switch (value) {
    'succeeded' => '成功',
    'pending' => '处理中',
    'cancelled' => '已取消',
    'interrupted' => '已中断',
    _ => '失败',
  };
  Widget card(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
  Widget budget(Map<String, dynamic> value, int days) {
    final fraction = number(value['remainingFraction']).clamp(0.0, 1.0),
        colors = Theme.of(context).colorScheme;
    final usedDictation = number(value['dictationFraction']).clamp(0.0, 1.0),
        usedMeeting = number(value['meetingFraction']).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('最近 $days 天', style: const TextStyle(fontSize: 18)),
            ),
            Text(
              '剩余 ${(fraction * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                color: fraction <= 0.2 ? Colors.orange : colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          label: '最近 $days 天剩余 ${(fraction * 100).toStringAsFixed(1)}%',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LayoutBuilder(
              builder: (_, constraints) => Row(
                children: [
                  Container(
                    height: 9,
                    width: constraints.maxWidth * fraction,
                    color: fraction <= 0.2 ? Colors.orange : colors.primary,
                  ),
                  Container(
                    height: 9,
                    width: constraints.maxWidth * usedDictation,
                    color: const Color(0xFF365D47),
                  ),
                  Container(
                    height: 9,
                    width: constraints.maxWidth * usedMeeting,
                    color: const Color(0xFF466F55),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '已用 ${money(value['spent'])} · 预算 ${money(value['budget'])}',
          style: const TextStyle(fontSize: 13),
        ),
        Text(
          '已写 ${number(value['written']).toInt()} 字${value['remainingCharacters'] == null ? '' : ' · 预计还能写 ${(number(value['remainingCharacters']) / 1000).toStringAsFixed(1)} 千字'}',
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  Future<void> editBudget(
    Map<String, dynamic> week,
    Map<String, dynamic> month,
  ) async {
    final weekly = TextEditingController(
          text: number(week['budget']).toString(),
        ),
        monthly = TextEditingController(
          text: number(month['budget']).toString(),
        );
    bool saving = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            MediaQuery.viewInsetsOf(sheet).bottom + 28,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '共享预算',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: weekly,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '7 天预算 · CNY'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: monthly,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '30 天预算 · CNY',
                    ),
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.orange)),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final a = double.tryParse(weekly.text),
                                b = double.tryParse(monthly.text);
                            if (a == null ||
                                b == null ||
                                !a.isFinite ||
                                !b.isFinite ||
                                a <= 0 ||
                                b <= 0 ||
                                a > 1000000 ||
                                b > 1000000) {
                              update(
                                () => error = '请输入大于 0、不超过 1,000,000 的金额。',
                              );
                              return;
                            }
                            update(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              await widget.onBudget(a, b);
                              if (sheet.mounted) {
                                Navigator.pop(sheet);
                              }
                            } catch (_) {
                              if (sheet.mounted) {
                                update(() {
                                  saving = false;
                                  error = '预算保存失败，请重试。';
                                });
                              }
                            }
                          },
                    child: Text(saving ? '正在保存…' : '保存预算'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    weekly.dispose();
    monthly.dispose();
  }
}
