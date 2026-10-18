import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/memory_database.dart';
import '../../../core/models/category_schema.dart';
import '../../../core/models/memory_item.dart';
import '../../manual_input/presentation/add_memory_dialog.dart';
import '../../memory_detail/presentation/memory_detail_screen.dart';
import '../../rag/presentation/ask_ai_sheet.dart';
import '../../settings/presentation/settings_screen.dart';
import '../domain/memory_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String? _docsPath;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    final docs = await getApplicationDocumentsDirectory();
    setState(() => _docsPath = docs.path);
  }

  @override
  Widget build(BuildContext context) {
    // 监听刷新触发器
    ref.watch(refreshTriggerProvider);

    final actionBoardItems = ref.watch(actionBoardProvider);
    final memoryList = ref.watch(memoryListProvider);
    final isSyncing = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bubble_chart_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text(
              'Memorise',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bolt_rounded, color: Colors.amber),
            tooltip: 'iOS 快捷指令指南',
            onPressed: () => _showShortcutsGuide(context),
          ),
          IconButton(
            icon: isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'WebDAV 增量同步',
            onPressed: isSyncing
                ? null
                : () async {
                    final ok = await triggerSync(ref);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? 'WebDAV 增量同步完成' : '同步未开启或连接失败，请在设置中检查配置'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // 1. 顶层：瞬时行动看板 (Action Board)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Text(
                              '⚡ 瞬时行动看板',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            if (actionBoardItems.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${actionBoardItems.length} 项待处理',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (actionBoardItems.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.task_alt_rounded, color: Color(0xFF10B981), size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '当前暂无待核销取件码与待办日程，生活井井有条 ✨',
                                    style: TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 135,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            scrollDirection: Axis.horizontal,
                            itemCount: actionBoardItems.length,
                            separatorBuilder: (context, index) => const SizedBox(width: 12),
                            itemBuilder: (ctx, i) {
                              return _buildActionBoardCard(actionBoardItems[i]);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 2. 主视图分类胶囊切换条
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: 38,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildCategoryChip('all', '全部', Icons.grid_view_rounded),
                        _buildCategoryChip('voucher', '凭证取件', Icons.inventory_2_outlined),
                        _buildCategoryChip('schedule', '日程待办', Icons.calendar_today_rounded),
                        _buildCategoryChip('bill', '账单消费', Icons.receipt_long_outlined),
                        _buildCategoryChip('article', '文章攻略', Icons.menu_book_outlined),
                        _buildCategoryChip('inspiration', '灵感备忘', Icons.lightbulb_outline_rounded),
                        _buildCategoryChip('archived', '已归档', Icons.archive_outlined),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. 多模态记忆瀑布流 / 卡片列表
              if (memoryList.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('还没有记录任何记忆', style: TextStyle(color: Colors.grey)),
                        SizedBox(height: 4),
                        Text('点击右下角 ➕ 导入截图或输入便签，体验一键归档', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildMemoryStreamCard(memoryList[index]),
                        );
                      },
                      childCount: memoryList.length,
                    ),
                  ),
                ),
            ],
          ),

          // 4. 底层悬浮搜索与问记忆 (Ask AI) 胶囊输入栏
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: '搜索快递号、地点、账单或语义内容...',
                        hintStyle: TextStyle(fontSize: 14),
                        border: InputBorder.none,
                      ),
                      onChanged: (text) {
                        ref.read(searchQueryProvider.notifier).state = text;
                      },
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                      },
                    ),
                  const VerticalDivider(indent: 14, endIndent: 14),
                  InkWell(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => AskAiSheet(initialQuery: _searchController.text),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text(
                            '问 AI',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70),
        child: FloatingActionButton(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          shape: const CircleBorder(),
          tooltip: '闪记 / 导入测试',
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => const AddMemoryDialog(),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  /// 构建分类胶囊筛选器
  Widget _buildCategoryChip(String categoryId, String label, IconData icon) {
    final selected = ref.watch(selectedCategoryProvider) == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(label),
        avatar: Icon(icon, size: 16, color: selected ? Colors.white : Colors.grey),
        selectedColor: Theme.of(context).colorScheme.primary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.white : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onSelected: (val) {
          ref.read(selectedCategoryProvider.notifier).state = categoryId;
        },
      ),
    );
  }

  /// 构建行动看板微卡片 (Action Board Card)
  Widget _buildActionBoardCard(MemoryItem item) {
    final isVoucher = item.category == 'voucher';
    final code = item.structuredData['code']?.toString() ?? '';
    final location = item.structuredData['location']?.toString() ?? '';
    final provider = item.structuredData['provider']?.toString() ?? '';

    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isVoucher
            ? const Color(0xFFFFFBEB)
            : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVoucher ? const Color(0xFFFDE68A) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVoucher ? Icons.inventory_2_rounded : Icons.calendar_month_rounded,
                size: 16,
                color: isVoucher ? const Color(0xFFD97706) : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isVoucher ? (provider.isNotEmpty ? provider : '待取快递') : '待办日程',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isVoucher ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 核销打勾按钮
              InkWell(
                onTap: () {
                  MemoryDatabase.instance.updateStatus(item.id, 'archived');
                  ref.read(refreshTriggerProvider.notifier).state++;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅已归档'), duration: Duration(seconds: 1)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.check, size: 16, color: Color(0xFF10B981)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 核心号码 / 标题
          Text(
            isVoucher && code.isNotEmpty ? code : item.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '📍 $location',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),
          // 底部快捷动作
          Row(
            children: [
              if (isVoucher && code.isNotEmpty)
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制取件码 📋'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('📋 复制取件码', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              const Spacer(),
              Text(
                DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.createdAt)),
                style: const TextStyle(fontSize: 10, color: Colors.black45),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建记忆流瀑布卡片 (Memory Stream Card)
  Widget _buildMemoryStreamCard(MemoryItem item) {
    final schema = DefaultCategories.findById(item.category);
    final dateStr = DateFormat('MM-dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.createdAt));

    String? fullImgPath;
    if (item.assetRelPath.isNotEmpty && _docsPath != null) {
      final pth = p.join(_docsPath!, item.assetRelPath);
      if (File(pth).existsSync()) fullImgPath = pth;
    }

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MemoryDetailScreen(item: item)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部小条：分类胶囊 + 状态 + 时间
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: schema.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(schema.icon, size: 12, color: schema.color),
                        const SizedBox(width: 4),
                        Text(
                          schema.name,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: schema.color),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item.status == 'archived')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('已归档', style: TextStyle(fontSize: 10, color: Colors.green)),
                    ),
                  const Spacer(),
                  Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final newStatus = item.status == 'pending' ? 'archived' : 'pending';
                      MemoryDatabase.instance.updateStatus(item.id, newStatus);
                      ref.read(refreshTriggerProvider.notifier).state++;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(newStatus == 'archived' ? '✅已归档' : '已恢复待办'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        item.status == 'pending' ? Icons.check_circle_outline : Icons.unarchive_outlined,
                        size: 16,
                        color: item.status == 'pending' ? Colors.grey : const Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 标题
              Text(
                item.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // 缩略图（若有）
              if (fullImgPath != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(fullImgPath),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],

              // 3 条核心要点摘要
              if (item.summaryPoints.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...item.summaryPoints.take(3).map((point) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 12, color: Colors.blueAccent)),
                        Expanded(
                          child: Text(
                            point,
                            style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],

              // 底部标签
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: item.tags.take(4).map((t) {
                    return Text(
                      '#$t',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showShortcutsGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.bolt_rounded, color: Colors.amber, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'iOS 快捷指令极速闪记指南',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '通过 iOS 16+ 原生 AppIntent，将截图与 OCR 文本静默录入记忆库，零弹窗零打断。',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    _buildGuideStep(
                      step: '1',
                      title: '打开 iPhone「快捷指令」App',
                      desc: '点击右上角「+」创建新的快捷指令，命名为「存入记忆」或「闪记」。',
                    ),
                    _buildGuideStep(
                      step: '2',
                      title: '添加动作「截屏」',
                      desc: '搜索「截屏」或「Take Screenshot」，动作将获取当前屏幕画面。',
                    ),
                    _buildGuideStep(
                      step: '3',
                      title: '添加动作「从图像中提取文本」',
                      desc: '输入选择上一步的「截屏」。该步骤调用 iOS 原生离线 Vision OCR，耗时仅约 0.3 秒。',
                    ),
                    _buildGuideStep(
                      step: '4',
                      title: '添加动作「存入 AI 记忆」',
                      desc: '搜索本 App 的 AppIntent 动作「存入 AI 记忆」，将「截屏」填入截图参数，将「来自图像的文本」填入 OCR 文本。',
                    ),
                    _buildGuideStep(
                      step: '💡',
                      title: '绑定 Action Button 或轻点背面',
                      desc: '前往 iPhone「设置 ➔ 操作按钮」或「辅助功能 ➔ 触控 ➔ 轻点背面」，绑定此快捷指令，即可在任意 App 内轻按即记！',
                    ),
                    _buildGuideStep(
                      step: '⚡',
                      title: '默认搭载小米 MiMo 多模态',
                      desc: '默认使用 mimo-v2.6-flash，强制使用 OCR 文本 + 图像 Base64 双通道解析，无论取件码、日程还是攻略，均可秒级归类入库！',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGuideStep({required String step, required String title, required String desc}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
            child: Text(
              step,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
