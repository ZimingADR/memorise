import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/category_schema.dart';
import '../models/memory_item.dart';
import '../models/pipeline_settings.dart';
import '../search/hybrid_search_engine.dart';
import 'settings_service.dart';

/// 4 段式 AI 核心处理管线服务
class PipelineService {
  static final PipelineService instance = PipelineService._();
  PipelineService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// 执行完整的 4 段式记忆入库管线
  Future<MemoryItem> processNewMemory({
    String? id,
    String? rawImagePath,
    String rawOcrText = '',
    String userNote = '',
    String sourcePlatform = 'manual',
  }) async {
    final memoryId = id ?? const Uuid().v4();
    final settings = SettingsService.instance.settings;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    // --- 阶段一：图片压缩与智能视觉补充 (Stage 1) ---
    String assetRelPath = '';
    String vlmDescription = '';

    if (rawImagePath != null && rawImagePath.isNotEmpty && File(rawImagePath).existsSync()) {
      assetRelPath = await _compressAndSaveImage(memoryId, rawImagePath);

      final trimmedOcr = rawOcrText.trim();
      final shouldTriggerVlm = (settings.stage1Mode == 'always_vlm') ||
          (settings.stage1Mode == 'smart_hybrid' && trimmedOcr.length < settings.vlmTriggerCharThreshold);

      if (shouldTriggerVlm && settings.vlmApiKey.isNotEmpty) {
        try {
          vlmDescription = await _callVlm(rawImagePath, settings);
        } catch (_) {
          // VLM 失败不中断主流程
        }
      }
    }

    // --- 阶段二：结构化提取与分类打标 (Stage 2) ---
    Map<String, dynamic> extracted;
    if (settings.stage2ApiKey.isNotEmpty) {
      try {
        extracted = await _callStructuredExtraction(
          ocrText: rawOcrText,
          vlmDesc: vlmDescription,
          userNote: userNote,
          now: now,
          settings: settings,
        );
      } catch (_) {
        extracted = _offlineFallbackExtraction(rawOcrText, userNote, now);
      }
    } else {
      extracted = _offlineFallbackExtraction(rawOcrText, userNote, now);
    }

    final category = extracted['category'] as String? ?? 'inspiration';
    final title = extracted['title'] as String? ?? '未命名记忆';
    final status = extracted['status'] as String? ?? 'pending';
    final summaryPoints = (extracted['summary_points'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [];
    final structuredData = extracted['structured_data'] as Map<String, dynamic>? ?? {};
    final tags = (extracted['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final searchKeywords = extracted['search_keywords'] as String? ?? '';

    // --- 阶段三：向量化 Embedding (Stage 3) ---
    String embeddingModel = '';
    int embeddingDim = 0;
    String embeddingB64 = '';

    if (settings.stage3Mode == 'remote_api' && settings.stage3ApiKey.isNotEmpty) {
      try {
        final textToEmbed = '$title\n${summaryPoints.join('\n')}\n$searchKeywords\n$rawOcrText';
        final vector = await _callEmbedding(textToEmbed, settings);
        if (vector.isNotEmpty) {
          embeddingModel = settings.stage3Model;
          embeddingDim = vector.length;
          embeddingB64 = HybridSearchEngine.encodeVectorToBase64(vector);
        }
      } catch (_) {
        // Embedding 失败时降级纯全文检索
      }
    }

    // 组装最终 MemoryItem
    final memoryItem = MemoryItem(
      schemaVersion: 1,
      id: memoryId,
      createdAt: nowMs,
      updatedAt: nowMs,
      isDeleted: false,
      sourcePlatform: sourcePlatform,
      status: status,
      category: category,
      title: title,
      summaryPoints: summaryPoints,
      structuredData: structuredData,
      tags: tags,
      searchKeywords: searchKeywords,
      rawOcrText: rawOcrText,
      vlmDescription: vlmDescription,
      userNote: userNote,
      assetRelPath: assetRelPath,
      embeddingModel: embeddingModel,
      embeddingDim: embeddingDim,
      embeddingB64: embeddingB64,
    );

    // 落地保存 JSON 文件（与 WebDAV 增量协议对齐）
    await _saveMemoryJson(memoryItem);

    return memoryItem;
  }

  /// 压缩图片为 WebP / JPEG，存入 `assets/<uuid>.webp`
  Future<String> _compressAndSaveImage(String uuid, String originalPath) async {
    final docs = await getApplicationDocumentsDirectory();
    final assetsDir = Directory(p.join(docs.path, 'assets'));
    if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);

    final targetFile = File(p.join(assetsDir.path, '$uuid.webp'));

    try {
      final bytes = await File(originalPath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) {
        // 等比缩小大图，长边上限 1920
        img.Image resized = image;
        if (image.width > 1920 || image.height > 1920) {
          if (image.width > image.height) {
            resized = img.copyResize(image, width: 1920);
          } else {
            resized = img.copyResize(image, height: 1920);
          }
        }
        // 编码为 WebP 或高质量 JPEG
        final webpBytes = img.encodePng(resized); // fallback safe png/webp
        await targetFile.writeAsBytes(webpBytes);
        return 'assets/$uuid.webp';
      }
    } catch (_) {}

    // 若图片处理失败，复制原文件作为兜底
    final fallbackFile = File(p.join(assetsDir.path, '$uuid.img'));
    await File(originalPath).copy(fallbackFile.path);
    return 'assets/$uuid.img';
  }

  /// 将记忆保存为 `memories/<uuid>.json`
  Future<void> _saveMemoryJson(MemoryItem item) async {
    final docs = await getApplicationDocumentsDirectory();
    final memDir = Directory(p.join(docs.path, 'memories'));
    if (!memDir.existsSync()) memDir.createSync(recursive: true);

    final file = File(p.join(memDir.path, '${item.id}.json'));
    await file.writeAsString(jsonEncode(item.toJson()));
  }

  /// 阶段一：调用多模态 VLM
  Future<String> _callVlm(String imagePath, PipelineSettings settings) async {
    final bytes = await File(imagePath).readAsBytes();
    final b64 = base64Encode(bytes);

    final response = await _dio.post(
      '${settings.vlmBaseUrl}/chat/completions',
      options: Options(headers: {
        'Authorization': 'Bearer ${settings.vlmApiKey}',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': settings.vlmModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': '请用一两句话简明客观地描述该图中的主要视觉内容、画面主体及关键场景（用于辅助记忆检索）。'
              },
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$b64'}
              }
            ]
          }
        ],
        'max_tokens': 200,
      },
    );

    return response.data['choices'][0]['message']['content'] as String? ?? '';
  }

  /// 阶段二：动态 Schema 结构化提取
  Future<Map<String, dynamic>> _callStructuredExtraction({
    required String ocrText,
    required String vlmDesc,
    required String userNote,
    required DateTime now,
    required PipelineSettings settings,
  }) async {
    final allSchemas = [
      ...DefaultCategories.all,
      ...settings.customSchemas,
    ].map((s) => s.toPromptSchema()).toList();

    final systemPrompt = '''
你是一个精准的个人记忆结构化提取引擎。请根据用户提供的【OCR 提取文本】、【画面视觉描述】、【用户补充备注】以及【当前系统时间】，将该条信息归类并提取为严格的 JSON 格式。

### 当前系统时间
${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(now)}

### 可选分类与对应 structured_data 必填字段定义
${jsonEncode(allSchemas)}

### 提取规则
1. **分类判定**：优先判断是否为具有时效性的 voucher（取件码/核销码/停车位）或 schedule（明确的时间待办）；若涉及付款金额归为 bill；长篇图文攻略归为 article；其余归为 inspiration 或用户自定义分类。
2. **相对时间换算**：如果文本中出现“明天下午三点”、“下周五”等相对时间，请结合【当前系统时间】换算为准确的 ISO-8601 时间字符串。
3. **检索同义词扩写 (search_keywords)**：为了提升本地全文检索召回率，请在 search_keywords 字段中补充该记忆的同义词、上下位概念及拼音首字母/中英文对照。
4. **输出格式**：必须且只能输出合法的 JSON 对象，不加 markdown 标记，包含顶层键：category, title, status ("pending" 或 "archived"), summary_points (最多3条字符串数组), structured_data (对应字段字典), tags (3-6个标签数组), search_keywords (空格分隔字符串)。
''';

    final userContent = '''
【OCR 提取文本】：$ocrText
【画面视觉描述】：$vlmDesc
【用户补充备注】：$userNote
''';

    final response = await _dio.post(
      '${settings.stage2BaseUrl}/chat/completions',
      options: Options(headers: {
        'Authorization': 'Bearer ${settings.stage2ApiKey}',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': settings.stage2Model,
        'temperature': settings.stage2Temperature,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
      },
    );

    final rawContent = response.data['choices'][0]['message']['content'] as String;
    // 去除 ```json 代码块包裹
    String cleaned = rawContent.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    }
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }

    return jsonDecode(cleaned.trim()) as Map<String, dynamic>;
  }

  /// 阶段三：获取向量 Embedding
  Future<List<double>> _callEmbedding(String text, PipelineSettings settings) async {
    final response = await _dio.post(
      '${settings.stage3BaseUrl}/embeddings',
      options: Options(headers: {
        'Authorization': 'Bearer ${settings.stage3ApiKey}',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': settings.stage3Model,
        'input': text.length > 2000 ? text.substring(0, 2000) : text,
      },
    );

    final dataList = response.data['data'] as List<dynamic>;
    final rawVec = dataList[0]['embedding'] as List<dynamic>;
    return rawVec.map((e) => (e as num).toDouble()).toList();
  }

  /// 阶段四：Ask AI / RAG 智能问答
  Future<String> askAi({
    required String query,
    required List<MemoryItem> recalledMemories,
  }) async {
    final settings = SettingsService.instance.settings;
    if (settings.stage4ApiKey.isEmpty) {
      return '请先在「设置」中配置 API Key，即可开启基于个人知识库的智能对话与跨卡片问答。';
    }

    final buffer = StringBuffer();
    for (int i = 0; i < recalledMemories.length; i++) {
      final item = recalledMemories[i];
      buffer.writeln('【卡片 [${i + 1}]】');
      buffer.writeln('标题：${item.title}');
      buffer.writeln('分类：${item.category}');
      if (item.summaryPoints.isNotEmpty) {
        buffer.writeln('核心要点：${item.summaryPoints.join('；')}');
      }
      if (item.structuredData.isNotEmpty) {
        buffer.writeln('结构化数据：${jsonEncode(item.structuredData)}');
      }
      if (item.userNote.isNotEmpty) {
        buffer.writeln('用户备注：${item.userNote}');
      }
      if (item.rawOcrText.isNotEmpty) {
        buffer.writeln('原始文本：${item.rawOcrText}');
      }
      buffer.writeln('-----------------------------------');
    }

    final systemPrompt = '''
你是一个强大的个人记忆助手。请依据用户检索出的以下【相关记忆卡片】回答用户的问题。
回答要求：
1. 态度温和、准确、条理清晰。
2. 引用某张卡片的事实或取件码时，务必在对应语句后带上角标，如 [1]、[2]，方便用户回溯溯源。
3. 若卡片中未提及，请诚实告知用户未记录。

### 检索到的候选记忆卡片：
$buffer
''';

    final response = await _dio.post(
      '${settings.stage4BaseUrl}/chat/completions',
      options: Options(headers: {
        'Authorization': 'Bearer ${settings.stage4ApiKey}',
        'Content-Type': 'application/json',
      }),
      data: {
        'model': settings.stage4Model,
        'temperature': 0.3,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': query},
        ],
      },
    );

    return response.data['choices'][0]['message']['content'] as String? ?? '未能生成回答';
  }

  /// 离线 Heuristic 兜底提取规则（未配 API Key 或断网时秒级生效）
  Map<String, dynamic> _offlineFallbackExtraction(String ocrText, String userNote, DateTime now) {
    final fullText = '$ocrText $userNote';

    // 1. 取件码检测正则 (如 34-2-1088, 3-4-1024, A12-34)
    final voucherRegex = RegExp(r'(\b\d{1,3}[-\s]\d{1,2}[-\s]\d{2,6}\b|[A-Za-z0-9]{6,12})');
    final voucherMatch = voucherRegex.firstMatch(fullText);

    if (fullText.contains('取件') || fullText.contains('驿站') || fullText.contains('快递') || fullText.contains('包裹')) {
      final code = voucherMatch?.group(0) ?? '待确认号码';
      return {
        'category': 'voucher',
        'title': '快递待取包裹：$code',
        'status': 'pending',
        'summary_points': [
          '取件码：$code',
          '来源：快递驿站通知',
        ],
        'structured_data': {
          'code': code,
          'provider': '快递服务',
          'location': fullText.contains('驿站') ? '快递驿站' : '自提柜',
        },
        'tags': ['取件码', '快递', '待办'],
        'search_keywords': '快递 包裹 取件码 $code 驿站',
      };
    }

    // 2. 日程待办检测 (如 明天、周五、开会、截止)
    if (fullText.contains('开会') || fullText.contains('截止') || fullText.contains('提醒') || fullText.contains('周') || fullText.contains('月')) {
      return {
        'category': 'schedule',
        'title': userNote.isNotEmpty ? userNote : '日程提醒待办',
        'status': 'pending',
        'summary_points': [
          '事项：${userNote.isNotEmpty ? userNote : '日程安排'}',
          '创建时间：${DateFormat('yyyy-MM-dd HH:mm').format(now)}',
        ],
        'structured_data': {
          'event_title': userNote.isNotEmpty ? userNote : '日程提醒',
          'start_time': DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(now.add(const Duration(hours: 2))),
        },
        'tags': ['日程', '待办', '提醒'],
        'search_keywords': '日程 待办 会议 提醒',
      };
    }

    // 3. 默认通用灵感/备忘
    final firstLine = ocrText.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '新记忆');
    final title = userNote.isNotEmpty ? userNote : (firstLine.length > 25 ? '${firstLine.substring(0, 25)}...' : firstLine);

    return {
      'category': 'inspiration',
      'title': title,
      'status': 'pending',
      'summary_points': [
        ocrText.length > 50 ? '${ocrText.substring(0, 50)}...' : ocrText,
      ],
      'structured_data': {
        'context_summary': ocrText,
      },
      'tags': ['记忆', '备忘'],
      'search_keywords': '$title $ocrText $userNote',
    };
  }
}
