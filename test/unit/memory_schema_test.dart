import 'package:flutter_test/flutter_test.dart';
import 'package:memorise/core/models/category_schema.dart';
import 'package:memorise/core/models/memory_item.dart';

void main() {
  group('MemoryItem & CategorySchema Tests', () {
    test('MemoryItem serialization roundtrip', () {
      final item = MemoryItem(
        id: 'test-uuid-1',
        createdAt: 1760000000000,
        updatedAt: 1760000010000,
        status: 'pending',
        category: 'voucher',
        title: '丰巢取件码：34-2-1088',
        summaryPoints: ['取件码 34-2-1088', '阳光花园柜机'],
        structuredData: {'code': '34-2-1088', 'provider': '丰巢'},
        tags: ['快递', '取件码'],
        searchKeywords: '丰巢 快递 34-2-1088',
        rawOcrText: '取件码 34-2-1088',
        userNote: '下班顺路拿',
        assetRelPath: 'assets/test-uuid-1.webp',
        embeddingModel: 'BAAI/bge-m3',
        embeddingDim: 1024,
      );

      final json = item.toJson();
      final restored = MemoryItem.fromJson(json);

      expect(restored.id, equals(item.id));
      expect(restored.category, equals('voucher'));
      expect(restored.status, equals('pending'));
      expect(restored.isActionBoardItem, isTrue);
      expect(restored.structuredData['code'], equals('34-2-1088'));
      expect(restored.summaryPoints.length, equals(2));
    });

    test('Default 5 categories are well-defined', () {
      final categories = DefaultCategories.all;
      expect(categories.length, equals(5));

      final voucher = DefaultCategories.findById('voucher');
      expect(voucher.enterActionBoard, isTrue);
      expect(voucher.fields.any((f) => f.name == 'code'), isTrue);

      final schedule = DefaultCategories.findById('schedule');
      expect(schedule.enterActionBoard, isTrue);
      expect(schedule.fields.any((f) => f.name == 'start_time'), isTrue);

      final bill = DefaultCategories.findById('bill');
      expect(bill.enterActionBoard, isFalse);
    });
  });
}
