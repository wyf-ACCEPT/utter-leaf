import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utterleaf_mobile/vocabulary_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('network.utterleaf/dictation');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          if (call.method == 'vocabulary') {
            return {
              'status': '已同步',
              'entries': [
                {
                  'id': 'fixture',
                  'term': 'SyntheticTerm',
                  'aliases': ['SyntheticAlias'],
                  'note': 'Synthetic context',
                  'enabled': true,
                },
              ],
            };
          }
          if (call.method == 'saveVocabulary') {
            throw PlatformException(
              code: 'vocabulary',
              message: '该词条已存在，请编辑已有词条。',
            );
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null),
  );
  testWidgets('search clear and failed save retain vocabulary draft', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: VocabularyPage()));
    await tester.pump();
    expect(find.text('SyntheticTerm'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '搜索词汇或易错写法'),
      'missing',
    );
    await tester.pump();
    expect(find.text('没有匹配的词条。'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();
    expect(find.text('SyntheticTerm'), findsOneWidget);
    await tester.tap(find.byTooltip('添加词条'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '首选拼写'),
      'SyntheticTerm',
    );
    await tester.ensureVisible(find.text('保存词条'));
    await tester.tap(find.text('保存词条'));
    await tester.pumpAndSettle();
    expect(find.text('该词条已存在，请编辑已有词条。'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '首选拼写'))
          .controller!
          .text,
      'SyntheticTerm',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('successful edit closes without losing the saved row', (
    tester,
  ) async {
    var term = 'SyntheticTerm';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          if (call.method == 'vocabulary') {
            return {
              'status': '已同步',
              'entries': [
                {
                  'id': 'fixture',
                  'term': term,
                  'aliases': [],
                  'note': '',
                  'enabled': true,
                },
              ],
            };
          }
          if (call.method == 'saveVocabulary') {
            term = (call.arguments as Map)['term'] as String;
          }
          return null;
        });
    await tester.pumpWidget(const MaterialApp(home: VocabularyPage()));
    await tester.pump();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '首选拼写'),
      'ChangedTerm',
    );
    await tester.ensureVisible(find.text('保存词条'));
    await tester.tap(find.text('保存词条'));
    await tester.pumpAndSettle();
    expect(find.text('ChangedTerm'), findsOneWidget);
    expect(find.widgetWithText(TextField, '首选拼写'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
