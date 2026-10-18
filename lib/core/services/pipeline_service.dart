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
    } else {
      // 满足用户要求：保存的内容必须包含图像，自动生成专属色调的视觉卡片
      assetRelPath = await _generateAndSaveFallbackBanner(memoryId, rawOcrText, userNote);
    }

    // --- 阶段二：结构化提取与分类打标 (Stage 2 - 强制融合 OCR 与 原图) ---
    Map<String, dynamic> extracted;
    if (settings.stage2ApiKey.isNotEmpty) {
      try {
        extracted = await _callStructuredExtraction(
          rawImagePath: rawImagePath,
          assetRelPath: assetRelPath,
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

  /// 压缩图片并规范化保存到 `assets/<uuid>.jpg`
  Future<String> _compressAndSaveImage(String uuid, String originalPath) async {
    final docs = await getApplicationDocumentsDirectory();
    final assetsDir = Directory(p.join(docs.path, 'assets'));
    if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);

    final targetFile = File(p.join(assetsDir.path, '$uuid.jpg'));

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
        // 编码为高质量 JPEG (体积缩减 80%+)
        final jpgBytes = img.encodeJpg(resized, quality: 85);
        await targetFile.writeAsBytes(jpgBytes);
        return 'assets/$uuid.jpg';
      }
    } catch (_) {}

    // 若图片处理失败，复制原文件作为兜底
    final fallbackFile = File(p.join(assetsDir.path, '$uuid.jpg'));
    await File(originalPath).copy(fallbackFile.path);
    return 'assets/$uuid.jpg';
  }

  /// 满足“保存的内容必须包含图像”：当无图片输入时，自动合成优雅专属渐变卡片
  Future<String> _generateAndSaveFallbackBanner(String uuid, String text, String note) async {
    final docs = await getApplicationDocumentsDirectory();
    final assetsDir = Directory(p.join(docs.path, 'assets'));
    if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);

    final targetFile = File(p.join(assetsDir.path, '$uuid.jpg'));
    try {
      final banner = img.Image(width: 640, height: 320);
      final seed = (text + note + uuid).hashCode.abs();

      final r1 = (90 + (seed % 90)).clamp(40, 240);
      final g1 = (80 + ((seed ~/ 7) % 90)).clamp(40, 240);
      final b1 = (140 + ((seed ~/ 13) % 90)).clamp(40, 240);

      for (int y = 0; y < banner.height; y++) {
        for (int x = 0; x < banner.width; x++) {
          final t = (x / banner.width * 0.45) + (y / banner.height * 0.55);
          final r = (r1 * (1.0 - t * 0.35)).toInt().clamp(0, 255);
          final g = (g1 * (1.0 - t * 0.25) + 30 * t).toInt().clamp(0, 255);
          final b = (b1 * (0.8 + t * 0.2)).toInt().clamp(0, 255);
          banner.setPixelRgb(x, y, r, g, b);
        }
      }
      final jpgBytes = img.encodeJpg(banner, quality: 88);
      await targetFile.writeAsBytes(jpgBytes);
      return 'assets/$uuid.jpg';
    } catch (_) {
      return '';
    }
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

  /// 阶段二：动态 Schema 结构化提取（强制融合原图画面与 OCR 文本）
  Future<Map<String, dynamic>> _callStructuredExtraction({
    String? rawImagePath,
    String assetRelPath = '',
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
你是MiMo，由小米公司研发的AI智能助手。你同时是一个精准的个人记忆结构化提取引擎。请综合用户传入的【图像画面】与【OCR 提取文本】、【用户补充备注】以及【当前系统时间】，将该条信息归类并提取为严格的 JSON 格式。

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

    dynamic userContent;
    File? imgToRead;
    if (rawImagePath != null && File(rawImagePath).existsSync()) {
      imgToRead = File(rawImagePath);
    } else if (assetRelPath.isNotEmpty) {
      final docs = await getApplicationDocumentsDirectory();
      final pth = p.join(docs.path, assetRelPath);
      if (File(pth).existsSync()) imgToRead = File(pth);
    }

    if (imgToRead != null) {
      try {
        final imgBytes = await imgToRead.readAsBytes();
        final b64 = base64Encode(imgBytes);
        userContent = [
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$b64'},
          },
          {
            'type': 'text',
            'text': '【OCR 提取文本】：$ocrText\n【画面视觉补充】：$vlmDesc\n【用户补充备注】：$userNote',
          },
        ];
      } catch (_) {
        userContent = '【OCR 提取文本】：$ocrText\n【画面视觉补充】：$vlmDesc\n【用户补充备注】：$userNote';
      }
    } else {
      userContent = '【OCR 提取文本】：$ocrText\n【画面视觉补充】：$vlmDesc\n【用户补充备注】：$userNote';
    }

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

  /// 阶段四：Ask AI / RAG 智能问答（支持纯本地离线 RAG 与远程模型）
  Future<String> askAi({
    required String query,
    required List<MemoryItem> recalledMemories,
  }) async {
    final settings = SettingsService.instance.settings;

    // --- 本地离线 RAG 模式 ---
    if (settings.ragMode == 'local_offline' || settings.stage4ApiKey.isEmpty) {
      if (recalledMemories.isEmpty) {
        return '【本地离线检索】在您的个人记忆库中暂未找到与“$query”匹配的卡片。';
      }
      final buffer = StringBuffer('【本地离线 RAG 检索解答】\n');
      buffer.writeln('根据本地 FTS5 全文索引，为您精准检索到以下 ${recalledMemories.length} 条记忆证据：\n');
      for (int i = 0; i < recalledMemories.length; i++) {
        final item = recalledMemories[i];
        final schema = DefaultCategories.findById(item.category);
        buffer.writeln('[${i + 1}] **${item.title}** (${schema.name})');
        if (item.structuredData.isNotEmpty) {
          final entries = item.structuredData.entries.map((e) => '${e.key}: ${e.value}').join('，');
          buffer.writeln('    • 详细信息：$entries');
        }
        for (final pt in item.summaryPoints) {
          buffer.writeln('    • $pt');
        }
        if (item.userNote.isNotEmpty) {
          buffer.writeln('    • 备注：${item.userNote}');
        }
        buffer.writeln();
      }
      buffer.writeln('💡 提示：您可点击上方卡片角标直接查看详情。如需生成跨卡片语义综合提炼，可在「设置」中切换为云端模型并填入 Key。');
      return buffer.toString().trim();
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
你是MiMo，由小米公司研发的AI智能助手。请依据用户检索出的以下【相关记忆卡片】回答用户的问题。
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
