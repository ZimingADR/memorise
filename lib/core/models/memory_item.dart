import 'dart:convert';

/// 单条记忆的核心领域模型，与 `memories/<uuid>.json` 协议完全对齐
class MemoryItem {
  final int schemaVersion;
  final String id;
  final int createdAt;
  final int updatedAt;
  final bool isDeleted;
  final String sourcePlatform;
  final String status; // "pending" | "archived"
  final String category; // "voucher" | "schedule" | "bill" | "article" | "inspiration" | custom
  final String title;
  final List<String> summaryPoints;
  final Map<String, dynamic> structuredData;
  final List<String> tags;
  final String searchKeywords;
  final String rawOcrText;
  final String vlmDescription;
  final String userNote;
  final String assetRelPath;
  final String embeddingModel;
  final int embeddingDim;
  final String embeddingB64;

  const MemoryItem({
    this.schemaVersion = 1,
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.sourcePlatform = "manual",
    this.status = "pending",
    required this.category,
    required this.title,
    this.summaryPoints = const [],
    this.structuredData = const {},
    this.tags = const [],
    this.searchKeywords = "",
    this.rawOcrText = "",
    this.vlmDescription = "",
    this.userNote = "",
    this.assetRelPath = "",
    this.embeddingModel = "",
    this.embeddingDim = 0,
    this.embeddingB64 = "",
  });

  /// 是否属于待核销瞬时卡片（常驻首屏顶层看板）
  bool get isActionBoardItem {
    return status == "pending" && (category == "voucher" || category == "schedule");
  }

  MemoryItem copyWith({
    int? schemaVersion,
    String? id,
    int? createdAt,
    int? updatedAt,
    bool? isDeleted,
    String? sourcePlatform,
    String? status,
    String? category,
    String? title,
    List<String>? summaryPoints,
    Map<String, dynamic>? structuredData,
    List<String>? tags,
    String? searchKeywords,
    String? rawOcrText,
    String? vlmDescription,
    String? userNote,
    String? assetRelPath,
    String? embeddingModel,
    int? embeddingDim,
    String? embeddingB64,
  }) {
    return MemoryItem(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      sourcePlatform: sourcePlatform ?? this.sourcePlatform,
      status: status ?? this.status,
      category: category ?? this.category,
      title: title ?? this.title,
      summaryPoints: summaryPoints ?? this.summaryPoints,
      structuredData: structuredData ?? this.structuredData,
      tags: tags ?? this.tags,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      vlmDescription: vlmDescription ?? this.vlmDescription,
      userNote: userNote ?? this.userNote,
      assetRelPath: assetRelPath ?? this.assetRelPath,
      embeddingModel: embeddingModel ?? this.embeddingModel,
      embeddingDim: embeddingDim ?? this.embeddingDim,
      embeddingB64: embeddingB64 ?? this.embeddingB64,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'id': id,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_deleted': isDeleted,
      'source_platform': sourcePlatform,
      'status': status,
      'category': category,
      'title': title,
      'summary_points': summaryPoints,
      'structured_data': structuredData,
      'tags': tags,
      'search_keywords': searchKeywords,
      'raw_ocr_text': rawOcrText,
      'vlm_description': vlmDescription,
      'user_note': userNote,
      'asset_rel_path': assetRelPath,
      'embedding_model': embeddingModel,
      'embedding_dim': embeddingDim,
      'embedding_b64': embeddingB64,
    };
  }

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    return MemoryItem(
      schemaVersion: json['schema_version'] as int? ?? 1,
      id: json['id'] as String? ?? '',
      createdAt: json['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: json['is_deleted'] as bool? ?? false,
      sourcePlatform: json['source_platform'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'pending',
      category: json['category'] as String? ?? 'inspiration',
      title: json['title'] as String? ?? '无标题记忆',
      summaryPoints: (json['summary_points'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      structuredData: json['structured_data'] as Map<String, dynamic>? ?? {},
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      searchKeywords: json['search_keywords'] as String? ?? '',
      rawOcrText: json['raw_ocr_text'] as String? ?? '',
      vlmDescription: json['vlm_description'] as String? ?? '',
      userNote: json['user_note'] as String? ?? '',
      assetRelPath: json['asset_rel_path'] as String? ?? '',
      embeddingModel: json['embedding_model'] as String? ?? '',
      embeddingDim: json['embedding_dim'] as int? ?? 0,
      embeddingB64: json['embedding_b64'] as String? ?? '',
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory MemoryItem.fromJsonString(String source) => MemoryItem.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
