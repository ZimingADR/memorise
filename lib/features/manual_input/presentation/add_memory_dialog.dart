import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/memory_database.dart';
import '../../../core/services/pipeline_service.dart';
import '../../home/domain/memory_providers.dart';

class AddMemoryDialog extends ConsumerStatefulWidget {
  const AddMemoryDialog({super.key});

  @override
  ConsumerState<AddMemoryDialog> createState() => _AddMemoryDialogState();
}

class _AddMemoryDialogState extends ConsumerState<AddMemoryDialog> {
  final _ocrController = TextEditingController();
  final _noteController = TextEditingController();
  String? _selectedImagePath;
  bool _isProcessing = false;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedImagePath = result.files.single.path;
      });
    }
  }

  Future<void> _submit() async {
    if (_ocrController.text.trim().isEmpty &&
        _noteController.text.trim().isEmpty &&
        _selectedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一张截图或输入文本内容')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      String? imagePath = _selectedImagePath;
      if (imagePath == null) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(p.join(tempDir.path, 'banner_${DateTime.now().millisecondsSinceEpoch}.jpg'));
        final banner = img.Image(width: 600, height: 260);
        for (int y = 0; y < banner.height; y++) {
          for (int x = 0; x < banner.width; x++) {
            final t = (x / banner.width * 0.4) + (y / banner.height * 0.6);
            final r = (37 + 50 * t).toInt().clamp(0, 255);
            final g = (99 + 80 * t).toInt().clamp(0, 255);
            final b = (235 - 30 * t).toInt().clamp(0, 255);
            banner.setPixelRgb(x, y, r, g, b);
          }
        }
        await tempFile.writeAsBytes(img.encodeJpg(banner, quality: 90));
        imagePath = tempFile.path;
      }

      final item = await PipelineService.instance.processNewMemory(
        rawImagePath: imagePath,
        rawOcrText: _ocrController.text.trim(),
        userNote: _noteController.text.trim(),
        sourcePlatform: 'manual_desktop',
      );

      MemoryDatabase.instance.save(item);
      ref.read(refreshTriggerProvider.notifier).state++;

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功录入记忆：${item.title}'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('处理失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '⚡ 快速闪记 / 导入测试',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 选取图片预览区域
              InkWell(
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: _selectedImagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(_selectedImagePath!), fit: BoxFit.cover),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_rounded, size: 40, color: Colors.blueAccent),
                            SizedBox(height: 8),
                            Text('点击选择截图 / 照片', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ocrController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'OCR 文本 / 聊天记录 / 链接',
                  hintText: '如：【菜鸟驿站】您的包裹已到达阳光花园，请凭 34-2-1088 取件...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: '补充备注（意图 / 想法）',
                  hintText: '如：下班顺路去拿、周五前报销',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _isProcessing ? 'AI 管线解析处理中...' : '开始结构化解析并存入',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
