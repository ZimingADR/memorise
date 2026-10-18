import 'package:flutter/material.dart';
import '../../../core/database/memory_database.dart';
import '../../../core/models/memory_item.dart';
import '../../../core/services/pipeline_service.dart';
import '../../../core/services/settings_service.dart';
import '../../memory_detail/presentation/memory_detail_screen.dart';

class AskAiSheet extends StatefulWidget {
  final String initialQuery;

  const AskAiSheet({super.key, this.initialQuery = ''});

  @override
  State<AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<AskAiSheet> {
  late final TextEditingController _queryController;
  bool _isLoading = false;
  String _answer = '';
  List<MemoryItem> _recalledCards = [];

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.trim().isNotEmpty) {
      _ask();
    }
  }

  Future<void> _ask() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _answer = '';
      _recalledCards = [];
    });

    try {
      // 1. 混合检索召回 Top-8 相关卡片
      final candidates = MemoryDatabase.instance.hybridSearch(
        query: query,
        topK: 8,
      );

      _recalledCards = candidates;

      // 2. 调用 RAG 问答模型
      final result = await PipelineService.instance.askAi(
        query: query,
        recalledMemories: candidates,
      );

      setState(() {
        _answer = result;
      });
    } catch (e) {
      setState(() {
        _answer = '问答请求失败: $e\n提示：请检查设置中的 Stage 4 模型配置与 API Key。';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部拖动条与标题
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
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 22),
              const SizedBox(width: 8),
              const Text(
                '✨ 问记忆 (Ask AI RAG)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // RAG 推理引擎模式切换（支持小米 MiMo 远程大模型与纯本地离线 RAG）
          Builder(
            builder: (context) {
              final settings = SettingsService.instance.settings;
              final isLocal = settings.ragMode == 'local_offline';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        setState(() {
                          settings.ragMode = isLocal ? 'remote_api' : 'local_offline';
                        });
                        await SettingsService.instance.saveSettings(settings);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isLocal
                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                              : const Color(0xFFFF6900).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isLocal
                                ? const Color(0xFF10B981).withValues(alpha: 0.5)
                                : const Color(0xFFFF6900).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isLocal ? Icons.offline_bolt_rounded : Icons.cloud_done_rounded,
                              size: 14,
                              color: isLocal ? const Color(0xFF10B981) : const Color(0xFFFF6900),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isLocal ? '纯本地离线 RAG (点击切换)' : '小米 MiMo 问答 (点击切换)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isLocal ? const Color(0xFF10B981) : const Color(0xFFFF6900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // 提问输入框
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: InputDecoration(
                    hintText: '如：我的快递单号是多少？或者 某某攻略里推荐了什么？',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onSubmitted: (_) => _ask(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isLoading ? null : _ask,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 内容区
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在混合检索并由 RAG 模型提炼回答...', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 召回卡片引用栏
                        if (_recalledCards.isNotEmpty) ...[
                          const Text(
                            '📚 召回的相关卡片证据：',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 38,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _recalledCards.length,
                              separatorBuilder: (context, index) => const SizedBox(width: 8),
                              itemBuilder: (ctx, i) {
                                final card = _recalledCards[i];
                                return ActionChip(
                                  avatar: CircleAvatar(
                                    backgroundColor: Colors.blueAccent,
                                    child: Text('${i + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                  ),
                                  label: Text(
                                    card.title.length > 12 ? '${card.title.substring(0, 12)}...' : card.title,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MemoryDetailScreen(item: card),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          const Divider(height: 24),
                        ],

                        // AI 回答结果
                        if (_answer.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                            ),
                            child: SelectableText(
                              _answer,
                              style: const TextStyle(fontSize: 15, height: 1.6),
                            ),
                          ),
                        ] else if (!_isLoading && _queryController.text.isEmpty) ...[
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 40),
                              child: Text(
                                '输入自然语言问题，AI 将跨卡片检索并汇总给出解答。',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
