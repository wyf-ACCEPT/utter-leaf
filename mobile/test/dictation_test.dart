import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utterleaf_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('network.utterleaf/dictation');
  late Map<String, dynamic> snapshot;
  late List<String> commands;
  late Map<String, dynamic> usage;
  setUp(() {
    snapshot = {
      'phase': 'idle',
      'doubaoConfigured': true,
      'deepseekConfigured': true,
    };
    usage = {
      'status': '离线记录已保留',
      'lastSync': 0,
      'syncing': false,
      'macCalls': 0,
      'phoneCalls': 1,
      'week': {
        'spent': 0.2,
        'budget': 5,
        'remainingFraction': 0.96,
        'dictationFraction': 0.04,
        'meetingFraction': 0,
        'written': 12,
      },
      'month': {
        'spent': 0.2,
        'budget': 20,
        'remainingFraction': 0.99,
        'dictationFraction': 0.01,
        'meetingFraction': 0,
      },
      'calls': [],
    };
    commands = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          if (call.method == 'snapshot') return snapshot;
          if (call.method == 'usage') return usage;
          commands.add(call.method);
          if (call.method == 'start') {
            snapshot = {...snapshot, 'phase': 'starting'};
          }
          if (call.method == 'stop') {
            snapshot = {...snapshot, 'phase': 'processing'};
          }
          if (call.method == 'cancel') {
            snapshot = {...snapshot, 'phase': 'cancelled'};
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null),
  );
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const UtterLeafApp());
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'start blocks duplicate submission and cancellation remains reachable',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('开始说话'));
      await tester.pump();
      expect(find.text('准备麦克风'), findsOneWidget);
      await tester.tap(find.text('取消这次录音'));
      await tester.pump();
      expect(commands, ['start', 'cancel']);
      await close(tester);
    },
  );
  testWidgets(
    'recording exposes stop and five minute warning without result text',
    (tester) async {
      snapshot = {
        ...snapshot,
        'phase': 'recording',
        'seconds': 280,
        'level': 0.7,
      };
      await open(tester);
      expect(find.text('结束并整理'), findsOneWidget);
      expect(find.text('即将到 5 分钟，将自动结束并整理'), findsOneWidget);
      await tester.tap(find.text('结束并整理'));
      await tester.pump();
      expect(find.text('正在转写与整理'), findsOneWidget);
      expect(find.byType(SoundWave), findsNothing);
      await close(tester);
    },
  );
  testWidgets('failed cleanup retains raw result and offers retry', (
    tester,
  ) async {
    snapshot = {
      ...snapshot,
      'phase': 'error',
      'raw': 'This is a synthetic test.',
      'error': '整理未完成',
    };
    await open(tester);
    expect(find.text('This is a synthetic test.'), findsOneWidget);
    expect(find.text('重新整理原始文字'), findsOneWidget);
    await close(tester);
  });
  testWidgets(
    'missing credentials opens masked settings without exposing saved values',
    (tester) async {
      snapshot = {...snapshot, 'doubaoConfigured': false};
      await open(tester);
      await tester.tap(find.text('配置个人 Key'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('个人 API'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.every((field) => field.obscureText), isTrue);
      expect(fields.length, 2);
      await close(tester);
    },
  );
  testWidgets(
    'narrow display keeps result and keyboard instructions scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      snapshot = {
        ...snapshot,
        'phase': 'ready',
        'text': 'Synthetic result. ' * 150,
        'fromKeyboard': true,
      };
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(SelectableText), findsOneWidget);
      await close(tester);
    },
  );
  testWidgets('return action exposes pending feedback and failure reason', (
    tester,
  ) async {
    snapshot = {
      ...snapshot,
      'phase': 'recording',
      'fromKeyboard': true,
      'returnStatus': 'returning',
    };
    await open(tester);
    expect(find.text('正在返回…'), findsOneWidget);
    final returning = find.widgetWithText(TextButton, '正在返回…');
    expect(tester.widget<TextButton>(returning).onPressed, isNull);
    snapshot = {
      ...snapshot,
      'returnStatus': 'manual',
      'returnMessage': '未能识别原 App。',
    };
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('未能识别原 App。'), findsOneWidget);
    expect(find.text('返回原 App'), findsOneWidget);
    await close(tester);
  });
  testWidgets(
    'navigation preserves recording and pending cloud usage is not zero spend',
    (tester) async {
      snapshot = {
        ...snapshot,
        'phase': 'recording',
        'seconds': 12,
        'level': 0.6,
      };
      await open(tester);
      await tester.tap(find.text('用量'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('离线记录已保留'), findsOneWidget);
      expect(find.text('首次同步尚未完成 · 当前仅显示本机缓存'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pump();
      expect(find.text('个人 API'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.ancestor(
                of: find.text('个人 API'),
                matching: find.byType(ListTile),
              ),
            )
            .onTap,
        isNull,
      );
      await tester.tap(find.text('主页'));
      await tester.pump();
      expect(find.text('结束并整理'), findsOneWidget);
      expect(commands, isEmpty);
      await close(tester);
    },
  );
  testWidgets(
    'offline dashboard shows cached totals and requests synchronization',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('用量'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('离线记录已保留'), findsOneWidget);
      expect(find.textContaining('已用 ¥0.2000'), findsWidgets);
      await tester.tap(find.byTooltip('立即同步'));
      await tester.pump();
      expect(commands, ['syncUsage']);
      await close(tester);
    },
  );
  testWidgets('empty unsynchronized cache never shows unused allowance', (
    tester,
  ) async {
    usage = {...usage, 'macCalls': 0, 'phoneCalls': 0};
    await open(tester);
    await tester.tap(find.text('用量'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('等待首次同步。尚未收到用量记录，暂不显示费用或剩余额度。'), findsOneWidget);
    expect(find.textContaining('剩余 100'), findsNothing);
    expect(find.textContaining('已用 ¥0'), findsNothing);
    await close(tester);
  });
}
