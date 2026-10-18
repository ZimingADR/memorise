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
import '../../home/domain/memory_providers.dart';

class MemoryDetailScreen extends ConsumerStatefulWidget {
  final MemoryItem item;

  const MemoryDetailScreen({super.key, required this.item});

  @override
  ConsumerState<MemoryDetailScreen> createState() => _MemoryDetailScreenState();
}

class _MemoryDetailScreenState extends ConsumerState<MemoryDetailScreen> {
  late MemoryItem _item;
  String? _resolvedImagePath;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _resolveImagePath();
  }

  Future<void> _resolveImagePath() async {
    if (_item.assetRelPath.isNotEmpty) {
      final docs = await getApplicationDocumentsDirectory();
      final fullPath = p.join(docs.path, _item.assetRelPath);
      if (File(fullPath).existsSync()) {
        setState(() => _resolvedImagePath = fullPath);
      }
    }
  }

  void _toggleStatus() {
    final newStatus = _item.status == 'pending' ? 'archived' : 'pending';
    MemoryDatabase.instance.updateStatus(_item.id, newStatus);
    setState(() {
      _item = _item.copyWith(status: newStatus);
    });
    ref.read(refreshTriggerProvider.notifier).state++;
  }

  void _deleteMemory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后该记忆将移入回收站，是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              MemoryDatabase.instance.delete(_item.id, soft: true);
              ref.read(refreshTriggerProvider.notifier).state++;
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final schema = DefaultCategories.findById(_item.category);
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(_item.createdAt),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(schema.name),
        actions: [
          IconButton(
            icon: Icon(
              _item.status == 'pending' ? Icons.check_circle_outline : Icons.check_circle,
              color: _item.status == 'pending' ? Colors.grey : const Color(0xFF10B981),
            ),
            tooltip: _item.status == 'pending' ? '标记已核销' : '已核销（点击恢复待办）',
            onPressed: _toggleStatus,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: '删除',
            onPressed: _deleteMemory,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部类别与状态标签
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: schema.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: schema.color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(schema.icon, size: 16, color: schema.color),
                      const SizedBox(width: 4),
                      Text(
                        schema.name,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: schema.color),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _item.status == 'pending' ? Colors.orange.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _item.status == 'pending' ? '待核销' : '已归档',
                    style: TextStyle(
                      fontSize: 12,
                      color: _item.status == 'pending' ? Colors.orange : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),

            // 标题
            SelectableText(
              _item.title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 图片预览
            if (_resolvedImagePath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: Image.file(
                    File(_resolvedImagePath!),
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 结构化卡片字段
            if (_item.structuredData.isNotEmpty) ...[
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.data_object, size: 18, color: Colors.blueAccent),
                          SizedBox(width: 6),
                          Text('结构化字段', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      const Divider(height: 20),
                      ..._item.structuredData.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 100,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  '${entry.value}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ),
                              if (entry.key == 'code' || entry.key == 'url')
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 16),
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: '${entry.value}'));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('已复制到剪贴板')),
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 核心要点 (Summary points)
            if (_item.summaryPoints.isNotEmpty) ...[
              const Text('核心要点', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._item.summaryPoints.map((point) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      Expanded(
                        child: SelectableText(point, style: const TextStyle(fontSize: 14, height: 1.4)),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],

            // 用户补充备注
            if (_item.userNote.isNotEmpty) ...[
              const Text('用户备注', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: SelectableText(_item.userNote, style: const TextStyle(fontSize: 14)),
              ),
              const SizedBox(height: 16),
            ],

            // 标签列表
            if (_item.tags.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _item.tags.map((tag) {
                  return Chip(
                    label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    padding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            // 原始 OCR 文本展开
            if (_item.rawOcrText.isNotEmpty) ...[
              ExpansionTile(
                title: const Text('查看原始 OCR 提取文本', style: TextStyle(fontSize: 14, color: Colors.grey)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(_item.rawOcrText, style: const TextStyle(fontSize: 13, height: 1.5)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
