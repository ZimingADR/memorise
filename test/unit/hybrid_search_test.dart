import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:memorise/core/search/hybrid_search_engine.dart';

void main() {
  group('HybridSearchEngine Tests', () {
    test('encode and decode vector to base64', () {
      final original = [0.1, 0.25, -0.5, 0.999];
      final b64 = HybridSearchEngine.encodeVectorToBase64(original);
      expect(b64.isNotEmpty, isTrue);

      final decoded = HybridSearchEngine.decodeVectorFromBase64(b64);
      expect(decoded.length, original.length);
      for (int i = 0; i < original.length; i++) {
        expect(decoded[i], closeTo(original[i], 0.0001));
      }
    });

    test('cosine similarity calculation', () {
      final v1 = Float32List.fromList([1.0, 0.0, 0.0]);
      final v2 = Float32List.fromList([1.0, 0.0, 0.0]);
      final v3 = Float32List.fromList([0.0, 1.0, 0.0]);
      final v4 = Float32List.fromList([-1.0, 0.0, 0.0]);

      // 相同向量余弦值为 1.0
      expect(HybridSearchEngine.cosineSimilarity(v1, v2), closeTo(1.0, 0.0001));
      // 正交向量余弦值为 0.0
      expect(HybridSearchEngine.cosineSimilarity(v1, v3), closeTo(0.0, 0.0001));
      // 反向向量余弦值为 -1.0
      expect(HybridSearchEngine.cosineSimilarity(v1, v4), closeTo(-1.0, 0.0001));
    });

    test('rankMemories merges FTS and vector scores', () {
      final ftsScores = {
        'doc-1': 0.9, // 关键词匹配极高
        'doc-2': 0.1, // 关键词匹配低
      };

      final allVectors = {
        'doc-1': Float32List.fromList([0.0, 1.0]), // 语义相似度低
        'doc-2': Float32List.fromList([1.0, 0.0]), // 语义相似度极高
      };

      final queryVector = Float32List.fromList([1.0, 0.0]);

      // 当向量权重为 0.8 时，语义相似度更高的 doc-2 应该排在前面
      final ranked = HybridSearchEngine.rankMemories(
        ftsScores: ftsScores,
        queryVector: queryVector,
        allVectors: allVectors,
        vectorWeight: 0.8,
        topK: 5,
        threshold: 0.1,
      );

      expect(ranked.first, equals('doc-2'));
    });
  });
}
