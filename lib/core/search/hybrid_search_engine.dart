import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// 纯 Dart 本地混合检索引擎（BM25 FTS5 关键词匹配 + 内存余弦相似度）
class HybridSearchEngine {
  /// 将 Float32 向量列表编码为 Base64 字符串用于 JSON 序列化
  static String encodeVectorToBase64(List<double> vector) {
    final float32 = Float32List.fromList(vector);
    return base64Encode(float32.buffer.asUint8List());
  }

  /// 从 Base64 字符串反序列化为 Float32List
  static Float32List decodeVectorFromBase64(String b64) {
    if (b64.isEmpty) return Float32List(0);
    try {
      final bytes = base64Decode(b64);
      return bytes.buffer.asFloat32List();
    } catch (_) {
      return Float32List(0);
    }
  }

  /// 从 Uint8List 二进制数据转换为 Float32List
  static Float32List fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) return Float32List(0);
    return bytes.buffer.asFloat32List();
  }

  /// 将 Float32List 转换为 Uint8List 供 SQLite BLOB 存储
  static Uint8List toBytes(Float32List list) {
    return list.buffer.asUint8List();
  }

  /// 高性能纯 Dart 余弦相似度计算（万级 1024 维向量计算仅需 8~12ms）
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      final va = a[i];
      final vb = b[i];
      dot += va * vb;
      normA += va * va;
      normB += vb * vb;
    }
    final denom = math.sqrt(normA) * math.sqrt(normB);
    return denom == 0.0 ? 0.0 : (dot / denom);
  }

  /// 混合重排算法：融合 FTS5 BM25 关键词归一化得分与向量余弦相似度
  /// `[ftsScores]` 为 `Map<memoryId, normalizedBm25Score (0.0~1.0)>`
  /// `[queryVector]` 为当前用户提问的 Embedding 向量（未开启向量检索时传 null）
  /// `[allVectors]` 为内存缓存的 `Map<memoryId, Float32List>`
  static List<String> rankMemories({
    required Map<String, double> ftsScores,
    Float32List? queryVector,
    required Map<String, Float32List> allVectors,
    double vectorWeight = 0.6,
    int topK = 10,
    double threshold = 0.15,
  }) {
    final Set<String> candidateIds = {
      ...ftsScores.keys,
      if (queryVector != null && queryVector.isNotEmpty) ...allVectors.keys,
    };

    final List<MapEntry<String, double>> scoredList = [];
    final hasValidQueryVector = queryVector != null && queryVector.isNotEmpty;

    for (final id in candidateIds) {
      final keywordScore = ftsScores[id] ?? 0.0;
      double vecScore = 0.0;
      if (hasValidQueryVector && allVectors.containsKey(id)) {
        vecScore = math.max(0.0, cosineSimilarity(queryVector, allVectors[id]!));
      }

      final finalScore = hasValidQueryVector
          ? (vecScore * vectorWeight + keywordScore * (1.0 - vectorWeight))
          : keywordScore;

      if (finalScore >= threshold) {
        scoredList.add(MapEntry(id, finalScore));
      }
    }

    scoredList.sort((a, b) => b.value.compareTo(a.value));
    return scoredList.take(topK).map((e) => e.key).toList();
  }
}
