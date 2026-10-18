import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/memory_database.dart';
import '../../../core/models/memory_item.dart';
import '../../../core/services/sync_service.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedCategoryProvider = StateProvider<String>((ref) => 'all');
final syncStatusProvider = StateProvider<bool>((ref) => false);

/// 瞬时行动看板（取件码与待办日程）
final actionBoardProvider = Provider<List<MemoryItem>>((ref) {
  // 监听搜索词或状态刷新
  ref.watch(searchQueryProvider);
  return MemoryDatabase.instance.getActionBoardItems();
});

/// 记忆主列表（响应关键词搜索与分类筛选）
final memoryListProvider = Provider<List<MemoryItem>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final category = ref.watch(selectedCategoryProvider);

  if (query.trim().isNotEmpty) {
    final results = MemoryDatabase.instance.hybridSearch(
      query: query.trim(),
      topK: 50,
    );
    if (category == 'archived') {
      return results.where((item) => item.status == 'archived').toList();
    }
    final activeResults = results.where((item) => item.status == 'pending').toList();
    if (category != 'all') {
      return activeResults.where((item) => item.category == category).toList();
    }
    return activeResults;
  }

  return MemoryDatabase.instance.getAll(
    category: category,
  );
});

/// 触发全局数据刷新
final refreshTriggerProvider = StateProvider<int>((ref) => 0);

/// 触发 WebDAV 同步
Future<bool> triggerSync(WidgetRef ref) async {
  ref.read(syncStatusProvider.notifier).state = true;
  final success = await SyncService.instance.syncNow();
  ref.read(syncStatusProvider.notifier).state = false;
  ref.read(refreshTriggerProvider.notifier).state++;
  return success;
}
