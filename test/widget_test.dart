import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memorise/core/database/memory_database.dart';
import 'package:memorise/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // 使用内存临时数据库进行 UI 冒烟测试
    await MemoryDatabase.instance.init(customPath: ':memory:');
  });

  tearDown(() {
    MemoryDatabase.instance.close();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MemoriseApp(),
      ),
    );

    expect(find.text('Memorise'), findsOneWidget);
  });
}
