import 'dart:async';
import 'usage_page.dart';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const UtterLeafApp());

abstract final class Leaf {
  static const background = Color(0xFF141C18),
      surface = Color(0xFF1E2922),
      green = Color(0xFF9FD6B5),
      ink = Color(0xFFE7F0EA),
      muted = Color(0xFFA8BBB0),
      border = Color(0xFF35463C);
}

class UtterLeafApp extends StatelessWidget {
  const UtterLeafApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '言叶',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Leaf.background,
      colorScheme: const ColorScheme.dark(
        primary: Leaf.green,
        surface: Leaf.surface,
        onPrimary: Color(0xFF102A1C),
        onSurface: Leaf.ink,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 16, height: 1.6, color: Leaf.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Leaf.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      useMaterial3: true,
    ),
    home: const DictationPage(),
  );
}

class DictationPage extends StatefulWidget {
  const DictationPage({super.key});
  @override
  State<DictationPage> createState() => _DictationPageState();
}

class _DictationPageState extends State<DictationPage>
    with WidgetsBindingObserver {
  static const bridge = MethodChannel('network.utterleaf/dictation');
  Timer? timer;
  Map<String, dynamic> state = {'phase': 'idle'};
  String? bridgeError;
  bool refreshing = false, sending = false;
  int selectedTab = 0;
  Map<String, dynamic> usage = {};
  int? usageVersion;
  String get phase => state['phase'] as String? ?? 'idle';
  bool get busy => ['starting', 'recording', 'processing'].contains(phase);
  bool get configured =>
      state['doubaoConfigured'] == true && state['deepseekConfigured'] == true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    timer?.cancel();
    if (lifecycle == AppLifecycleState.resumed) {
      refresh();
      timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => refresh(),
      );
    }
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    try {
      final next = await bridge.invokeMapMethod<String, dynamic>('snapshot');
      Map<String, dynamic>? nextUsage;
      if (next != null &&
          selectedTab == 1 &&
          (usage.isEmpty || usageVersion != next['usageVersion'])) {
        nextUsage = await bridge.invokeMapMethod<String, dynamic>('usage');
      }
      if (mounted && next != null) {
        setState(() {
          final wasBusy = busy;
          state = next;
          if (nextUsage != null) {
            usage = nextUsage;
            usageVersion = next['usageVersion'] as int?;
          }
          if (!wasBusy && busy && next['fromKeyboard'] == true) selectedTab = 0;
          bridgeError = null;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => bridgeError = '设备连接未就绪，请重新打开言叶。');
    } on MissingPluginException {
      if (mounted) setState(() => bridgeError = '请使用 iOS 构建版本。');
    } finally {
      refreshing = false;
    }
  }

  Future<void> action(String name) async {
    if (sending) return;
    setState(() => sending = true);
    try {
      await bridge.invokeMethod<void>(name);
      await refresh();
    } on PlatformException catch (e) {
      if (mounted) setState(() => bridgeError = e.message ?? '操作失败，请重试。');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = state['seconds'] as int? ?? 0;
    final text = state['text'] as String? ?? '',
        raw = state['raw'] as String? ?? '';
    final error = bridgeError ?? state['error'] as String? ?? '';
    final status = switch (phase) {
      'starting' => '准备麦克风',
      'recording' => '正在倾听',
      'processing' => '正在转写与整理',
      'ready' => '文字已就绪',
      'cancelled' => '已取消录音',
      'error' => '需要再试一次',
      _ => '给表达一点空间',
    };
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Leaf.background,
        title: Row(
          children: [
            Image.asset(
              'assets/leaf.png',
              width: 28,
              height: 28,
              semanticLabel: '言叶标志',
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'UtterLeaf · 言叶',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => selectedTab = 2),
            icon: const Icon(CupertinoIcons.slider_horizontal_3),
            tooltip: '设置',
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: SizedBox(
          height: 70,
          child: GlassNavigation(
            selected: selectedTab,
            onSelected: (index) => setState(() => selectedTab = index),
          ),
        ),
      ),
      body: selectedTab == 1
          ? UsagePage(
              data: usage,
              onSync: () => action('syncUsage'),
              onBudget: (week, month) async {
                await bridge.invokeMethod<void>('saveBudget', {
                  'week': week,
                  'month': month,
                });
                usageVersion = null;
                await refresh();
              },
            )
          : selectedTab == 2
          ? settingsPage()
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '说出来，\n自然落成文字。',
                      style: TextStyle(
                        fontSize: 34,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state['fromKeyboard'] == true
                          ? '录音期间可以返回原 App，在言叶键盘上结束。'
                          : '个人语音输入 · 豆包转写 + DeepSeek 整理',
                      style: const TextStyle(color: Leaf.muted, fontSize: 14),
                    ),
                    if (state['fromKeyboard'] == true && phase == 'recording')
                      TextButton.icon(
                        onPressed: state['returnStatus'] == 'returning'
                            ? null
                            : () => action('return'),
                        icon: state['returnStatus'] == 'returning'
                            ? const CupertinoActivityIndicator()
                            : const Icon(CupertinoIcons.arrow_turn_up_left),
                        label: Text(
                          state['returnStatus'] == 'returning'
                              ? '正在返回…'
                              : '返回原 App',
                        ),
                      ),
                    if (state['returnStatus'] == 'manual')
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          state['returnMessage'] as String? ??
                              '系统未能自动返回。请轻点屏幕左上角的返回入口，或从底部切回原 App。',
                          style: const TextStyle(
                            color: Leaf.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Leaf.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Leaf.border),
                      ),
                      child: Column(
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              status,
                              style: const TextStyle(
                                color: Leaf.green,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 86,
                            width: double.infinity,
                            child: phase == 'recording'
                                ? SoundWave(
                                    level:
                                        (state['level'] as num?)?.toDouble() ??
                                        0,
                                  )
                                : Center(
                                    child:
                                        [
                                          'starting',
                                          'processing',
                                        ].contains(phase)
                                        ? const CupertinoActivityIndicator(
                                            radius: 15,
                                            color: Leaf.green,
                                          )
                                        : Text(
                                            '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
                                            style: const TextStyle(
                                              fontSize: 52,
                                              fontWeight: FontWeight.w300,
                                              fontFeatures: [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                  ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: FilledButton.icon(
                              onPressed:
                                  sending ||
                                      ['starting', 'processing'].contains(phase)
                                  ? null
                                  : () => phase == 'recording'
                                        ? action('stop')
                                        : configured
                                        ? action('start')
                                        : settings(),
                              icon: Icon(
                                phase == 'recording'
                                    ? CupertinoIcons.stop_fill
                                    : CupertinoIcons.mic_fill,
                              ),
                              label: Text(
                                phase == 'recording'
                                    ? '结束并整理'
                                    : configured
                                    ? '开始说话'
                                    : '配置个人 Key',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (busy)
                            TextButton(
                              onPressed: () => action('cancel'),
                              child: const Text('取消这次录音'),
                            )
                          else
                            const Text(
                              '单次最长 5 分钟',
                              style: TextStyle(fontSize: 13, color: Leaf.muted),
                            ),
                          if (phase == 'recording' && seconds >= 270)
                            const Text(
                              '即将到 5 分钟，将自动结束并整理',
                              style: TextStyle(color: Colors.orange),
                            ),
                        ],
                      ),
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                error,
                                style: const TextStyle(
                                  color: Color(0xFFFFB4A9),
                                ),
                              ),
                            ),
                            if (raw.isNotEmpty)
                              TextButton(
                                onPressed: busy ? null : () => action('retry'),
                                child: const Text('重新整理原始文字'),
                              ),
                            if (error.contains('权限'))
                              TextButton(
                                onPressed: () => action('settings'),
                                child: const Text('打开系统设置'),
                              ),
                          ],
                        ),
                      ),
                    if (text.isNotEmpty || raw.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              text.isEmpty ? '原始文字 · 整理未完成' : '整理好的文字',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: text.isEmpty ? raw : text),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制')),
                                );
                              }
                            },
                            icon: const Icon(
                              CupertinoIcons.doc_on_doc,
                              size: 18,
                            ),
                            label: const Text('复制'),
                          ),
                        ],
                      ),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Leaf.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(text.isEmpty ? raw : text),
                        ),
                      ),
                      if (state['fromKeyboard'] == true)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            '返回原输入框，言叶键盘会尝试自动插入。若输入位置有变化，请点“插入文字”。',
                            style: TextStyle(color: Leaf.green, fontSize: 14),
                          ),
                        ),
                    ],
                    const SizedBox(height: 28),
                    if (!busy)
                      OutlinedButton.icon(
                        onPressed: setup,
                        icon: const Icon(CupertinoIcons.keyboard),
                        label: const Text('添加言叶输入法'),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      '音频和口述文字仅发送到你配置的个人 API。\n个人 Key 保存在手机内，键盘不上传其他输入内容。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Leaf.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> setup() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '把言叶放进输入框',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            const Text(
              '1. 打开“设置 → 通用 → 键盘 → 键盘 → 添加新键盘”，选择言叶。\n\n2. 点“言叶”，开启“允许完全访问”，让键盘与主 App 共享这次口述结果。\n\n3. 回到输入框，长按地球图标切换言叶，点击“开始说话”。\n\n4. 在言叶开始录音后，可手动返回原 App；在键盘点“结束并整理”，完成后插入文字。',
              style: TextStyle(color: Leaf.muted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                action('settings');
              },
              child: const Text('打开设置'),
            ),
          ],
        ),
      ),
    ),
  );
  Widget settingsPage() => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
      children: [
        const Text(
          '设置',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('个人 API'),
          subtitle: Text(
            configured ? '豆包与 DeepSeek 已配置 · 保存在本机钥匙串' : '需要配置豆包与 DeepSeek',
          ),
          trailing: const Icon(CupertinoIcons.chevron_forward),
          onTap: busy ? null : settings,
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('键盘与麦克风'),
          subtitle: const Text('在 iOS 设置中管理键盘、完全访问与麦克风权限'),
          trailing: const Icon(CupertinoIcons.arrow_up_right),
          onTap: () => action('settings'),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('iCloud 用量同步'),
          subtitle: Text(state['cloudMessage'] as String? ?? '等待 iCloud 配置'),
          trailing: const Icon(CupertinoIcons.chevron_forward),
          onTap: () => setState(() => selectedTab = 1),
        ),
        const SizedBox(height: 24),
        const Text(
          '个人版 · 录音最长 5 分钟。API 凭证保存在本机；会议功能暂不包含在 iOS 版本中。',
          style: TextStyle(color: Leaf.muted),
        ),
      ],
    ),
  );
  Future<void> settings() async {
    final doubao = TextEditingController(), deepseek = TextEditingController();
    String? failure;
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 28,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '个人 API',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '留空保留已有 Key。凭证存入本机钥匙串。',
                    style: TextStyle(color: Leaf.muted),
                  ),
                  const SizedBox(height: 22),
                  KeyField(
                    label: '豆包 API Key',
                    controller: doubao,
                    configured: state['doubaoConfigured'] == true,
                  ),
                  const SizedBox(height: 16),
                  KeyField(
                    label: 'DeepSeek API Key',
                    controller: deepseek,
                    configured: state['deepseekConfigured'] == true,
                  ),
                  const SizedBox(height: 12),
                  if (failure != null)
                    Text(
                      failure!,
                      style: const TextStyle(color: Colors.orange),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            update(() {
                              saving = true;
                              failure = null;
                            });
                            try {
                              await bridge.invokeMethod<void>('saveKeys', {
                                'DOUBAO_API_KEY': doubao.text,
                                'DEEPSEEK_API_KEY': deepseek.text,
                              });
                              if (context.mounted) Navigator.pop(context);
                              await refresh();
                            } on PlatformException {
                              if (context.mounted) {
                                update(() {
                                  saving = false;
                                  failure = '保存失败，请重试。';
                                });
                              }
                            }
                          },
                    child: Text(saving ? '正在保存…' : '保存到手机'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    doubao.dispose();
    deepseek.dispose();
  }
}

class KeyField extends StatefulWidget {
  const KeyField({
    super.key,
    required this.label,
    required this.controller,
    required this.configured,
  });
  final String label;
  final TextEditingController controller;
  final bool configured;
  @override
  State<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<KeyField> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    obscureText: hidden,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.configured ? '已配置 · 输入可替换' : '尚未配置',
      suffixIcon: IconButton(
        onPressed: () => setState(() => hidden = !hidden),
        tooltip: hidden ? '显示 Key' : '隐藏 Key',
        icon: Icon(hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash),
      ),
    ),
  );
}

class SoundWave extends StatefulWidget {
  const SoundWave({super.key, required this.level});
  final double level;
  @override
  State<SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<SoundWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => TweenAnimationBuilder<double>(
      tween: Tween<double>(end: widget.level.clamp(0, 1)),
      duration: const Duration(milliseconds: 220),
      builder: (_, level, _) => CustomPaint(
        painter: _WavePainter(
          level,
          MediaQuery.disableAnimationsOf(context)
              ? 0
              : controller.value * 2 * math.pi,
        ),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.level, this.phase);
  final double level, phase;
  @override
  void paint(Canvas canvas, Size size) {
    for (var line = 0; line < 3; line++) {
      final path = Path();
      for (double x = 0; x <= size.width; x += 2) {
        final y =
            size.height / 2 +
            math.sin(x / size.width * math.pi * (4 + line) + phase + line) *
                math.pow(math.sin(math.pi * x / size.width), 2) *
                (0.5 + level * 38) *
                (1 - line * 0.2);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Leaf.green.withValues(alpha: 1 - line * 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      level != oldDelegate.level || phase != oldDelegate.phase;
}

class GlassNavigation extends StatefulWidget {
  const GlassNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  State<GlassNavigation> createState() => _GlassNavigationState();
}

class _GlassNavigationState extends State<GlassNavigation> {
  MethodChannel? channel;
  @override
  void didUpdateWidget(covariant GlassNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      channel?.invokeMethod<void>('select', widget.selected);
    }
  }

  @override
  void dispose() {
    channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'network.utterleaf/glass-navigation',
        gestureRecognizers: {
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        creationParams: {'selected': widget.selected},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          channel = MethodChannel('network.utterleaf/navigation/$id');
          channel!.setMethodCallHandler((call) async {
            if (call.method == 'select' && mounted && call.arguments is int) {
              widget.onSelected(call.arguments as int);
            }
          });
        },
      );
    }
    return CupertinoTabBar(
      currentIndex: widget.selected,
      onTap: widget.onSelected,
      backgroundColor: Leaf.surface.withValues(alpha: 0.92),
      activeColor: Leaf.green,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.waveform),
          label: '主页',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.chart_bar),
          label: '用量',
        ),
        BottomNavigationBarItem(
          icon: Icon(CupertinoIcons.slider_horizontal_3),
          label: '设置',
        ),
      ],
    );
  }
}
