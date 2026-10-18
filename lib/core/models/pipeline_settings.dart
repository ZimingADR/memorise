import 'category_schema.dart';

enum ProviderPreset {
  xiaomi,
  siliconflow,
  deepseek,
  openai,
  gemini,
  ollama,
  custom,
}

/// 4 段式高自由度 AI 管线配置模型
class PipelineSettings {
  // --- Stage 1: 视觉与 OCR ---
  String stage1Mode; // "native_ocr_only" | "smart_hybrid" | "always_vlm"
  int vlmTriggerCharThreshold;
  String vlmBaseUrl;
  String vlmApiKey;
  String vlmModel;

  // --- Stage 2: 结构化提取与打标 ---
  String stage2BaseUrl;
  String stage2ApiKey;
  String stage2Model;
  double stage2Temperature;

  // --- Stage 3: 向量化 Embedding ---
  String stage3Mode; // "disabled" | "remote_api"
  String stage3BaseUrl;
  String stage3ApiKey;
  String stage3Model;
  int stage3Dim;

  // --- Stage 4: Ask AI / RAG 问答 ---
  String stage4BaseUrl;
  String stage4ApiKey;
  String stage4Model;
  int stage4TopK;
  double stage4VectorWeight;
  String ragMode; // "remote_api" | "local_offline"

  // --- 自定义分类 Schema 列表 ---
  List<CategorySchema> customSchemas;

  // --- WebDAV 同步配置 ---
  bool webdavEnabled;
  String webdavUrl;
  String webdavUser;
  String webdavPassword;
  String webdavSyncPolicy; // "full" | "lazy_image" | "text_only"

  PipelineSettings({
    this.stage1Mode = "always_vlm",
    this.vlmTriggerCharThreshold = 20,
    this.vlmBaseUrl = "https://api.xiaomimimo.com/v1",
    this.vlmApiKey = "",
    this.vlmModel = "mimo-v2.6-flash",
    this.stage2BaseUrl = "https://api.xiaomimimo.com/v1",
    this.stage2ApiKey = "",
    this.stage2Model = "mimo-v2.6-flash",
    this.stage2Temperature = 0.1,
    this.stage3Mode = "disabled",
    this.stage3BaseUrl = "https://api.xiaomimimo.com/v1",
    this.stage3ApiKey = "",
    this.stage3Model = "mimo-v2.6-flash",
    this.stage3Dim = 1024,
    this.stage4BaseUrl = "https://api.xiaomimimo.com/v1",
    this.stage4ApiKey = "",
    this.stage4Model = "mimo-v2.6-flash",
    this.stage4TopK = 8,
    this.stage4VectorWeight = 0.6,
    this.ragMode = "remote_api",
    List<CategorySchema>? customSchemas,
    this.webdavEnabled = false,
    this.webdavUrl = "",
    this.webdavUser = "",
    this.webdavPassword = "",
    this.webdavSyncPolicy = "lazy_image",
  }) : customSchemas = customSchemas ?? [];

  /// 一键应用服务商预设
  void applyPreset(ProviderPreset preset, String key) {
    switch (preset) {
      case ProviderPreset.xiaomi:
        vlmBaseUrl = "https://api.xiaomimimo.com/v1";
        vlmApiKey = key;
        vlmModel = "mimo-v2.6-flash";

        stage2BaseUrl = "https://api.xiaomimimo.com/v1";
        stage2ApiKey = key;
        stage2Model = "mimo-v2.6-flash";

        stage3Mode = "disabled"; // 使用纯本地 SQLite FTS5 全文搜索

        stage4BaseUrl = "https://api.xiaomimimo.com/v1";
        stage4ApiKey = key;
        stage4Model = "mimo-v2.6-flash";
        ragMode = "remote_api";
        break;

      case ProviderPreset.siliconflow:
        vlmBaseUrl = "https://api.siliconflow.cn/v1";
        vlmApiKey = key;
        vlmModel = "Qwen/Qwen2.5-VL-72B-Instruct";

        stage2BaseUrl = "https://api.siliconflow.cn/v1";
        stage2ApiKey = key;
        stage2Model = "deepseek-ai/DeepSeek-V3";

        stage3Mode = "remote_api";
        stage3BaseUrl = "https://api.siliconflow.cn/v1";
        stage3ApiKey = key;
        stage3Model = "BAAI/bge-m3";
        stage3Dim = 1024;

        stage4BaseUrl = "https://api.siliconflow.cn/v1";
        stage4ApiKey = key;
        stage4Model = "deepseek-ai/DeepSeek-V3";
        ragMode = "remote_api";
        break;

      case ProviderPreset.deepseek:
        vlmBaseUrl = "https://api.deepseek.com/v1";
        vlmApiKey = key;
        vlmModel = "deepseek-chat";

        stage2BaseUrl = "https://api.deepseek.com/v1";
        stage2ApiKey = key;
        stage2Model = "deepseek-chat";

        stage3Mode = "disabled"; // DeepSeek 官方暂未开放 embedding，自动降级为纯全文检索

        stage4BaseUrl = "https://api.deepseek.com/v1";
        stage4ApiKey = key;
        stage4Model = "deepseek-chat";
        ragMode = "remote_api";
        break;

      case ProviderPreset.openai:
        vlmBaseUrl = "https://api.openai.com/v1";
        vlmApiKey = key;
        vlmModel = "gpt-4o-mini";

        stage2BaseUrl = "https://api.openai.com/v1";
        stage2ApiKey = key;
        stage2Model = "gpt-4o-mini";

        stage3Mode = "remote_api";
        stage3BaseUrl = "https://api.openai.com/v1";
        stage3ApiKey = key;
        stage3Model = "text-embedding-3-small";
        stage3Dim = 1536;

        stage4BaseUrl = "https://api.openai.com/v1";
        stage4ApiKey = key;
        stage4Model = "gpt-4o";
        ragMode = "remote_api";
        break;

      case ProviderPreset.gemini:
        vlmBaseUrl = "https://generativelanguage.googleapis.com/v1beta/openai/";
        vlmApiKey = key;
        vlmModel = "gemini-1.5-flash";

        stage2BaseUrl = "https://generativelanguage.googleapis.com/v1beta/openai/";
        stage2ApiKey = key;
        stage2Model = "gemini-1.5-flash";

        stage3Mode = "remote_api";
        stage3BaseUrl = "https://generativelanguage.googleapis.com/v1beta/openai/";
        stage3ApiKey = key;
        stage3Model = "text-embedding-004";
        stage3Dim = 768;

        stage4BaseUrl = "https://generativelanguage.googleapis.com/v1beta/openai/";
        stage4ApiKey = key;
        stage4Model = "gemini-1.5-pro";
        ragMode = "remote_api";
        break;

      case ProviderPreset.ollama:
        vlmBaseUrl = "http://localhost:11434/v1";
        vlmApiKey = "ollama";
        vlmModel = "llava";

        stage2BaseUrl = "http://localhost:11434/v1";
        stage2ApiKey = "ollama";
        stage2Model = "qwen2.5:7b";

        stage3Mode = "remote_api";
        stage3BaseUrl = "http://localhost:11434/v1";
        stage3ApiKey = "ollama";
        stage3Model = "nomic-embed-text";
        stage3Dim = 768;

        stage4BaseUrl = "http://localhost:11434/v1";
        stage4ApiKey = "ollama";
        stage4Model = "qwen2.5:7b";
        ragMode = "remote_api";
        break;

      case ProviderPreset.custom:
        break;
    }
  }

  Map<String, dynamic> toJson({bool includeKeys = true}) {
    return {
      'stage1_mode': stage1Mode,
      'vlm_trigger_char_threshold': vlmTriggerCharThreshold,
      'vlm_base_url': vlmBaseUrl,
      'vlm_api_key': includeKeys ? vlmApiKey : '',
      'vlm_model': vlmModel,
      'stage2_base_url': stage2BaseUrl,
      'stage2_api_key': includeKeys ? stage2ApiKey : '',
      'stage2_model': stage2Model,
      'stage2_temperature': stage2Temperature,
      'stage3_mode': stage3Mode,
      'stage3_base_url': stage3BaseUrl,
      'stage3_api_key': includeKeys ? stage3ApiKey : '',
      'stage3_model': stage3Model,
      'stage3_dim': stage3Dim,
      'stage4_base_url': stage4BaseUrl,
      'stage4_api_key': includeKeys ? stage4ApiKey : '',
      'stage4_model': stage4Model,
      'stage4_top_k': stage4TopK,
      'stage4_vector_weight': stage4VectorWeight,
      'rag_mode': ragMode,
      'custom_schemas': customSchemas.map((e) => e.toJson()).toList(),
      'webdav_enabled': webdavEnabled,
      'webdav_url': webdavUrl,
      'webdav_user': webdavUser,
      'webdav_password': includeKeys ? webdavPassword : '',
      'webdav_sync_policy': webdavSyncPolicy,
    };
  }

  factory PipelineSettings.fromJson(Map<String, dynamic> json) {
    return PipelineSettings(
      stage1Mode: json['stage1_mode'] as String? ?? 'always_vlm',
      vlmTriggerCharThreshold: json['vlm_trigger_char_threshold'] as int? ?? 20,
      vlmBaseUrl: json['vlm_base_url'] as String? ?? 'https://api.xiaomimimo.com/v1',
      vlmApiKey: json['vlm_api_key'] as String? ?? '',
      vlmModel: json['vlm_model'] as String? ?? 'mimo-v2.6-flash',
      stage2BaseUrl: json['stage2_base_url'] as String? ?? 'https://api.xiaomimimo.com/v1',
      stage2ApiKey: json['stage2_api_key'] as String? ?? '',
      stage2Model: json['stage2_model'] as String? ?? 'mimo-v2.6-flash',
      stage2Temperature: (json['stage2_temperature'] as num?)?.toDouble() ?? 0.1,
      stage3Mode: json['stage3_mode'] as String? ?? 'disabled',
      stage3BaseUrl: json['stage3_base_url'] as String? ?? 'https://api.xiaomimimo.com/v1',
      stage3ApiKey: json['stage3_api_key'] as String? ?? '',
      stage3Model: json['stage3_model'] as String? ?? 'mimo-v2.6-flash',
      stage3Dim: json['stage3_dim'] as int? ?? 1024,
      stage4BaseUrl: json['stage4_base_url'] as String? ?? 'https://api.xiaomimimo.com/v1',
      stage4ApiKey: json['stage4_api_key'] as String? ?? '',
      stage4Model: json['stage4_model'] as String? ?? 'mimo-v2.6-flash',
      stage4TopK: json['stage4_top_k'] as int? ?? 8,
      stage4VectorWeight: (json['stage4_vector_weight'] as num?)?.toDouble() ?? 0.6,
      ragMode: json['rag_mode'] as String? ?? 'remote_api',
      customSchemas: (json['custom_schemas'] as List<dynamic>?)
          ?.map((e) => CategorySchema.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      webdavEnabled: json['webdav_enabled'] as bool? ?? false,
      webdavUrl: json['webdav_url'] as String? ?? '',
      webdavUser: json['webdav_user'] as String? ?? '',
      webdavPassword: json['webdav_password'] as String? ?? '',
      webdavSyncPolicy: json['webdav_sync_policy'] as String? ?? 'lazy_image',
    );
  }
}
