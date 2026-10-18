import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'core/database/memory_database.dart';
import 'core/models/memory_item.dart';
import 'core/services/pending_inbox_service.dart';
import 'core/services/settings_service.dart';
import 'features/home/presentation/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化本地数据库与 FTS5 引擎
  await MemoryDatabase.instance.init();

  // 2. 初始化设置与安全密钥区
  await SettingsService.instance.init();

  // 3. 消费 iOS AppIntent / pending_inbox 缓冲队列
  await PendingInboxService.instance.init();

  // 4. 初次启动植入示例数据与图片资产
  await _insertSeedDataIfNeeded();

  runApp(
    const ProviderScope(
      child: MemoriseApp(),
    ),
  );
}

Future<void> _insertSeedDataIfNeeded() async {
  final docs = await getApplicationDocumentsDirectory();
  final assetsDir = Directory(p.join(docs.path, 'assets'));
  if (!assetsDir.existsSync()) {
    assetsDir.createSync(recursive: true);
  }

  Future<String> ensureSampleImage(String filename, int r1, int g1, int b1, int r2, int g2, int b2) async {
    final file = File(p.join(assetsDir.path, filename));
    if (!file.existsSync()) {
      final banner = img.Image(width: 600, height: 280);
      for (int y = 0; y < banner.height; y++) {
        for (int x = 0; x < banner.width; x++) {
          final t = (x / banner.width * 0.4) + (y / banner.height * 0.6);
          final r = (r1 + (r2 - r1) * t).toInt().clamp(0, 255);
          final g = (g1 + (g2 - g1) * t).toInt().clamp(0, 255);
          final b = (b1 + (b2 - b1) * t).toInt().clamp(0, 255);
          banner.setPixelRgb(x, y, r, g, b);
        }
      }
      await file.writeAsBytes(img.encodeJpg(banner, quality: 88));
    }
    return 'assets/$filename';
  }

  final img1 = await ensureSampleImage('demo-voucher-1.jpg', 245, 158, 11, 217, 119, 6);
  final img2 = await ensureSampleImage('demo-schedule-1.jpg', 37, 99, 235, 30, 64, 175);
  final img3 = await ensureSampleImage('demo-article-1.jpg', 16, 185, 129, 5, 150, 105);

  final items = MemoryDatabase.instance.getAll(includeArchived: true);
  if (items.isEmpty) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 示例 1: 瞬时取件码 (置顶进入行动看板)
    MemoryDatabase.instance.save(
      MemoryItem(
        id: 'demo-voucher-1',
        createdAt: now - 3600000,
        updatedAt: now - 3600000,
        status: 'pending',
        category: 'voucher',
        title: '菜鸟驿站包裹待取：34-2-1088',
        assetRelPath: img1,
        summaryPoints: [
          '取件码：34-2-1088（中通快递）',
          '驿站位置：阳光花园南门菜鸟驿站',
          '营业时间：09:00 - 21:00',
        ],
        structuredData: {
          'code': '34-2-1088',
          'location': '阳光花园南门菜鸟驿站',
          'provider': '中通快递',
        },
        tags: ['取件码', '中通', '菜鸟驿站'],
        searchKeywords: '34-2-1088 菜鸟驿站 中通快递 快递 取件码',
        rawOcrText: '【菜鸟驿站】您的中通包裹已到阳光花园南门驿站，请凭34-2-1088取件...',
        userNote: '下班顺路取',
      ),
    );

    // 示例 2: 瞬时日程待办 (置顶进入行动看板)
    MemoryDatabase.instance.save(
      MemoryItem(
        id: 'demo-schedule-1',
        createdAt: now - 7200000,
        updatedAt: now - 7200000,
        status: 'pending',
        category: 'schedule',
        title: '周五下午 15:00 团队产品架构评审会',
        assetRelPath: img2,
        summaryPoints: [
          '时间：本周五下午 15:00 - 16:30',
          '参会人：核心开发组成员',
          '地点：2号会议室 / 腾讯会议',
        ],
        structuredData: {
          'event_title': '团队产品架构评审会',
          'location': '2号会议室',
          'priority': 'high',
        },
        tags: ['工作', '会议', '评审'],
        searchKeywords: '团队 产品 架构 评审 会议 周五',
        rawOcrText: '各位同学，本周五下午3点召开记忆助手产品架构评审会，请准时出席...',
        userNote: '提前整理演示文稿',
      ),
    );

    // 示例 3: 灵感与稍后读攻略 (进入瀑布流)
    MemoryDatabase.instance.save(
      MemoryItem(
        id: 'demo-article-1',
        createdAt: now - 86400000,
        updatedAt: now - 86400000,
        status: 'archived',
        category: 'article',
        title: '小红书收藏：川西四姑娘山双桥沟拍照攻略',
        assetRelPath: img3,
        summaryPoints: [
          '最佳拍摄点：红杉林与布达拉峰公路中间段',
          '穿搭建议：早晚温差大，备冲锋衣及鲜艳帽子',
          '避坑提示：景区观光车末班车为 17:30',
        ],
        structuredData: {
          'source_app': '小红书',
          'entities': '四姑娘山、双桥沟、布达拉峰',
        },
        tags: ['旅游', '川西', '自驾', '攻略'],
        searchKeywords: '川西 四姑娘山 双桥沟 旅游 自驾 拍照 攻略',
        rawOcrText: '四姑娘山双桥沟保姆级旅游攻略！绝美公路机位在布达拉峰路段...',
        userNote: '国庆休假备选目的地',
      ),
    );
  } else {
    // 补齐存量卡片可能缺失的图片路径
    for (final it in items) {
      if (it.assetRelPath.isEmpty) {
        if (it.id == 'demo-voucher-1') {
          MemoryDatabase.instance.save(it.copyWith(assetRelPath: img1));
        } else if (it.id == 'demo-schedule-1') {
          MemoryDatabase.instance.save(it.copyWith(assetRelPath: img2));
        } else if (it.id == 'demo-article-1') {
          MemoryDatabase.instance.save(it.copyWith(assetRelPath: img3));
        }
      }
    }
  }
}

class MemoriseApp extends StatelessWidget {
  const MemoriseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memorise',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
