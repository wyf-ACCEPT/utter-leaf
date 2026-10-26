import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utterleaf_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('network.utterleaf/dictation');
  late Map<String, dynamic> snapshot;
  late List<String> commands;
  setUp(() {
    snapshot = {
      'phase': 'idle',
      'doubaoConfigured': true,
      'deepseekConfigured': true,
    };
    commands = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          if (call.method == 'snapshot') return snapshot;
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
}
