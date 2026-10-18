import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/memory_item.dart';
import '../search/hybrid_search_engine.dart';

/// SQLite + FTS5 本地数据库与全文检索管理
class MemoryDatabase {
  static final MemoryDatabase instance = MemoryDatabase._();
  MemoryDatabase._();

  Database? _db;
  bool _initialized = false;

  Database get db {
    if (_db == null) {
      throw StateError('MemoryDatabase is not initialized. Call init() first.');
    }
    return _db!;
  }

  Future<void> init({String? customPath}) async {
    if (_initialized) return;

    String dbPath;
    if (customPath != null) {
      dbPath = customPath;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      dbPath = p.join(docsDir.path, 'ai_memory.sqlite');
    }

    final parentDir = Directory(p.dirname(dbPath));
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    _db = sqlite3.open(dbPath);
    _createTables();
    _initialized = true;
  }

  void _createTables() {
    // 1. 记忆核心主表
    db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id TEXT PRIMARY KEY,
        schema_version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        source_platform TEXT NOT NULL,
        status TEXT NOT NULL,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        summary_points TEXT NOT NULL,
        structured_data TEXT NOT NULL,
        tags TEXT NOT NULL,
        search_keywords TEXT NOT NULL,
        raw_ocr_text TEXT NOT NULL,
        vlm_description TEXT NOT NULL,
        user_note TEXT NOT NULL,
        asset_rel_path TEXT NOT NULL,
        embedding_model TEXT NOT NULL,
        embedding_dim INTEGER NOT NULL,
        embedding_blob BLOB
      );
    ''');

    // 2. FTS5 全文索引虚拟表
    db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
        id UNINDEXED,
        title,
        summary_points,
        tags,
        search_keywords,
        raw_ocr_text,
        user_note,
        tokenize = 'unicode61'
      );
    ''');

    // 3. 辅助索引
    db.execute('CREATE INDEX IF NOT EXISTS idx_memories_status ON memories(status);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_memories_created_at ON memories(created_at);');
  }

  /// 插入或全量更新记忆记录
  void save(MemoryItem item) {
    Uint8List? blob;
    if (item.embeddingB64.isNotEmpty) {
      final vec = HybridSearchEngine.decodeVectorFromBase64(item.embeddingB64);
      blob = HybridSearchEngine.toBytes(vec);
    }

    db.execute('''
      INSERT OR REPLACE INTO memories (
        id, schema_version, created_at, updated_at, is_deleted,
        source_platform, status, category, title, summary_points,
        structured_data, tags, search_keywords, raw_ocr_text,
        vlm_description, user_note, asset_rel_path, embedding_model,
        embedding_dim, embedding_blob
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      item.id,
      item.schemaVersion,
      item.createdAt,
      item.updatedAt,
      item.isDeleted ? 1 : 0,
      item.sourcePlatform,
      item.status,
      item.category,
      item.title,
      jsonEncode(item.summaryPoints),
      jsonEncode(item.structuredData),
      jsonEncode(item.tags),
      item.searchKeywords,
      item.rawOcrText,
      item.vlmDescription,
      item.userNote,
      item.assetRelPath,
      item.embeddingModel,
      item.embeddingDim,
      blob,
    ]);

    // 同步更新 FTS5 虚拟表
    db.execute('DELETE FROM memories_fts WHERE id = ?;', [item.id]);
    if (!item.isDeleted) {
      db.execute('''
        INSERT INTO memories_fts (
          id, title, summary_points, tags, search_keywords, raw_ocr_text, user_note
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
      ''', [
        item.id,
        item.title,
        item.summaryPoints.join(' '),
        item.tags.join(' '),
        item.searchKeywords,
        item.rawOcrText,
        item.userNote,
      ]);
    }
  }

  /// 软删除或硬删除
  void delete(String id, {bool soft = true}) {
    if (soft) {
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute('UPDATE memories SET is_deleted = 1, updated_at = ? WHERE id = ?;', [now, id]);
      db.execute('DELETE FROM memories_fts WHERE id = ?;', [id]);
    } else {
      db.execute('DELETE FROM memories WHERE id = ?;', [id]);
      db.execute('DELETE FROM memories_fts WHERE id = ?;', [id]);
    }
  }

  /// 更新状态（如：pending -> archived 已核销）
  void updateStatus(String id, String newStatus) {
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute('UPDATE memories SET status = ?, updated_at = ? WHERE id = ?;', [newStatus, now, id]);
  }

  MemoryItem? getById(String id) {
    final ResultSet results = db.select('SELECT * FROM memories WHERE id = ? LIMIT 1;', [id]);
    if (results.isEmpty) return null;
    return _rowToItem(results.first);
  }

  /// 获取所有有效记忆（默认只展示未归档 pending 项，除非显式指定 status 或选择 archived 分类或 includeArchived = true）
  List<MemoryItem> getAll({String? category, String? status, bool includeArchived = false}) {
    String sql = 'SELECT * FROM memories WHERE is_deleted = 0';
    final params = <dynamic>[];

    if (includeArchived) {
      if (category != null && category != 'all') {
        sql += ' AND category = ?';
        params.add(category);
      }
    } else if (category == 'archived') {
      sql += " AND status = 'archived'";
    } else {
      final targetStatus = status ?? 'pending';
      sql += ' AND status = ?';
      params.add(targetStatus);

      if (category != null && category != 'all') {
        sql += ' AND category = ?';
        params.add(category);
      }
    }

    sql += ' ORDER BY created_at DESC;';
    final results = db.select(sql, params);
    return results.map(_rowToItem).toList();
  }

  /// 获取瞬时行动看板卡片（取件码与日程待办，状态为 pending）
  List<MemoryItem> getActionBoardItems() {
    final sql = '''
      SELECT * FROM memories 
      WHERE is_deleted = 0 
        AND status = 'pending' 
        AND category IN ('voucher', 'schedule')
      ORDER BY created_at DESC;
    ''';
    final results = db.select(sql);
    return results.map(_rowToItem).toList();
  }

  /// FTS5 全文搜索，返回 `Map<String, double>` (归一化得分 0.0~1.0)
  Map<String, double> searchFts(String query) {
    if (query.trim().isEmpty) return {};

    // 简单清洗特殊符号，防止 FTS5 语法报错
    final cleanQuery = query.replaceAll(RegExp(r'["\*\^]'), '').trim();
    if (cleanQuery.isEmpty) return {};

    try {
      // 拆分关键词使用通配符匹配
      final words = cleanQuery.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      final ftsQuery = words.map((w) => '"$w"*').join(' OR ');

      // 使用 bm25 计算分数，注意 bm25 分数越负越相关
      final results = db.select('''
        SELECT id, bm25(memories_fts) as score 
        FROM memories_fts 
        WHERE memories_fts MATCH ? 
        ORDER BY score ASC 
        LIMIT 50;
      ''', [ftsQuery]);

      if (results.isEmpty) return {};

      // 归一化分数到 0.0 ~ 1.0 (将越小的负数转换成更高的 0~1 分数)
      final scores = <String, double>{};
      double minScore = double.infinity;
      double maxScore = -double.infinity;

      for (final row in results) {
        final raw = (row['score'] as num).toDouble();
        if (raw < minScore) minScore = raw;
        if (raw > maxScore) maxScore = raw;
      }

      for (final row in results) {
        final id = row['id'] as String;
        final raw = (row['score'] as num).toDouble();
        if (maxScore == minScore) {
          scores[id] = 1.0;
        } else {
          // bm25 负得越多越匹配
          scores[id] = (maxScore - raw) / (maxScore - minScore + 0.0001);
        }
      }

      return scores;
    } catch (_) {
      // 容错降级为 LIKE 搜索
      final results = db.select('''
        SELECT id FROM memories 
        WHERE is_deleted = 0 AND (
          title LIKE ? OR raw_ocr_text LIKE ? OR tags LIKE ?
        ) LIMIT 30;
      ''', ['%$cleanQuery%', '%$cleanQuery%', '%$cleanQuery%']);
      return {for (var r in results) r['id'] as String: 0.8};
    }
  }

  /// 提取所有卡片的内存向量
  Map<String, Float32List> getAllVectors() {
    final results = db.select('''
      SELECT id, embedding_blob FROM memories 
      WHERE is_deleted = 0 AND embedding_blob IS NOT NULL;
    ''');
    final map = <String, Float32List>{};
    for (final row in results) {
      final blob = row['embedding_blob'] as Uint8List?;
      if (blob != null && blob.isNotEmpty) {
        map[row['id'] as String] = HybridSearchEngine.fromBytes(blob);
      }
    }
    return map;
  }

  /// 混合检索入口
  List<MemoryItem> hybridSearch({
    required String query,
    Float32List? queryVector,
    double vectorWeight = 0.6,
    int topK = 20,
  }) {
    if (query.trim().isEmpty && queryVector == null) {
      return getAll();
    }

    final ftsScores = searchFts(query);
    final allVectors = getAllVectors();

    final rankedIds = HybridSearchEngine.rankMemories(
      ftsScores: ftsScores,
      queryVector: queryVector,
      allVectors: allVectors,
      vectorWeight: vectorWeight,
      topK: topK,
    );

    if (rankedIds.isEmpty) return [];

    final itemMap = <String, MemoryItem>{};
    final placeholders = List.filled(rankedIds.length, '?').join(',');
    final results = db.select('SELECT * FROM memories WHERE id IN ($placeholders);', rankedIds);
    for (final row in results) {
      final item = _rowToItem(row);
      itemMap[item.id] = item;
    }

    return rankedIds.map((id) => itemMap[id]).whereType<MemoryItem>().toList();
  }

  MemoryItem _rowToItem(Row row) {
    final blob = row['embedding_blob'] as Uint8List?;
    String b64 = '';
    if (blob != null && blob.isNotEmpty) {
      final float32 = HybridSearchEngine.fromBytes(blob);
      b64 = HybridSearchEngine.encodeVectorToBase64(float32);
    }

    return MemoryItem(
      schemaVersion: row['schema_version'] as int,
      id: row['id'] as String,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      isDeleted: (row['is_deleted'] as int) == 1,
      sourcePlatform: row['source_platform'] as String,
      status: row['status'] as String,
      category: row['category'] as String,
      title: row['title'] as String,
      summaryPoints: (jsonDecode(row['summary_points'] as String) as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      structuredData: jsonDecode(row['structured_data'] as String) as Map<String, dynamic>,
      tags: (jsonDecode(row['tags'] as String) as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      searchKeywords: row['search_keywords'] as String,
      rawOcrText: row['raw_ocr_text'] as String,
      vlmDescription: row['vlm_description'] as String,
      userNote: row['user_note'] as String,
      assetRelPath: row['asset_rel_path'] as String,
      embeddingModel: row['embedding_model'] as String,
      embeddingDim: row['embedding_dim'] as int,
      embeddingB64: b64,
    );
  }

  void close() {
    _db?.dispose();
    _db = null;
    _initialized = false;
  }
}
