import 'package:flutter/material.dart';
import '../../../core/models/pipeline_settings.dart';
import '../../../core/services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late PipelineSettings _settings;
  bool _isGeekMode = false;
  final _presetKeyController = TextEditingController();
  final _masterPasswordController = TextEditingController();

  // Stage 1
  late final TextEditingController _vlmBaseUrl;
  late final TextEditingController _vlmKey;
  late final TextEditingController _vlmModel;

  // Stage 2
  late final TextEditingController _s2BaseUrl;
  late final TextEditingController _s2Key;
  late final TextEditingController _s2Model;

  // Stage 3
  late final TextEditingController _s3BaseUrl;
  late final TextEditingController _s3Key;
  late final TextEditingController _s3Model;

  // Stage 4
  late final TextEditingController _s4BaseUrl;
  late final TextEditingController _s4Key;
  late final TextEditingController _s4Model;

  // WebDAV
  late final TextEditingController _webdavUrl;
  late final TextEditingController _webdavUser;
  late final TextEditingController _webdavPwd;

  @override
  void initState() {
    super.initState();
    _settings = SettingsService.instance.settings;

    _vlmBaseUrl = TextEditingController(text: _settings.vlmBaseUrl);
    _vlmKey = TextEditingController(text: _settings.vlmApiKey);
    _vlmModel = TextEditingController(text: _settings.vlmModel);

    _s2BaseUrl = TextEditingController(text: _settings.stage2BaseUrl);
    _s2Key = TextEditingController(text: _settings.stage2ApiKey);
    _s2Model = TextEditingController(text: _settings.stage2Model);

    _s3BaseUrl = TextEditingController(text: _settings.stage3BaseUrl);
    _s3Key = TextEditingController(text: _settings.stage3ApiKey);
    _s3Model = TextEditingController(text: _settings.stage3Model);

    _s4BaseUrl = TextEditingController(text: _settings.stage4BaseUrl);
    _s4Key = TextEditingController(text: _settings.stage4ApiKey);
    _s4Model = TextEditingController(text: _settings.stage4Model);

    _webdavUrl = TextEditingController(text: _settings.webdavUrl);
    _webdavUser = TextEditingController(text: _settings.webdavUser);
    _webdavPwd = TextEditingController(text: _settings.webdavPassword);
  }

  void _applyPreset(ProviderPreset preset) {
    final key = _presetKeyController.text.trim();
    if (key.isEmpty && preset != ProviderPreset.ollama) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入该服务商的 API Key')),
      );
      return;
    }

    setState(() {
      _settings.applyPreset(preset, key);
      _vlmBaseUrl.text = _settings.vlmBaseUrl;
      _vlmKey.text = _settings.vlmApiKey;
      _vlmModel.text = _settings.vlmModel;

      _s2BaseUrl.text = _settings.stage2BaseUrl;
      _s2Key.text = _settings.stage2ApiKey;
      _s2Model.text = _settings.stage2Model;

      _s3BaseUrl.text = _settings.stage3BaseUrl;
      _s3Key.text = _settings.stage3ApiKey;
      _s3Model.text = _settings.stage3Model;

      _s4BaseUrl.text = _settings.stage4BaseUrl;
      _s4Key.text = _settings.stage4ApiKey;
      _s4Model.text = _settings.stage4Model;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已一键应用预设配置并填充至 4 个管线阶段')),
    );
  }

  Future<void> _save() async {
    _settings.vlmBaseUrl = _vlmBaseUrl.text.trim();
    _settings.vlmApiKey = _vlmKey.text.trim();
    _settings.vlmModel = _vlmModel.text.trim();

    _settings.stage2BaseUrl = _s2BaseUrl.text.trim();
    _settings.stage2ApiKey = _s2Key.text.trim();
    _settings.stage2Model = _s2Model.text.trim();

    _settings.stage3BaseUrl = _s3BaseUrl.text.trim();
    _settings.stage3ApiKey = _s3Key.text.trim();
    _settings.stage3Model = _s3Model.text.trim();

    _settings.stage4BaseUrl = _s4BaseUrl.text.trim();
    _settings.stage4ApiKey = _s4Key.text.trim();
    _settings.stage4Model = _s4Model.text.trim();

    _settings.webdavUrl = _webdavUrl.text.trim();
    _settings.webdavUser = _webdavUser.text.trim();
    _settings.webdavPassword = _webdavPwd.text.trim();

    await SettingsService.instance.saveSettings(_settings);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('配置已成功保存至本地硬件安全区'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 管线与多端同步设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存设置',
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模式切换条 (一键预设 vs 极客路由)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('🚀 新手一键预设')),
                ButtonSegment(value: true, label: Text('🛠️ 极客 4 段式独立路由')),
              ],
              selected: {_isGeekMode},
              onSelectionChanged: (val) {
                setState(() => _isGeekMode = val.first);
              },
            ),
            const SizedBox(height: 20),

            if (!_isGeekMode) ...[
              // 一键预设区域
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '快速绑定服务商',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '填入单个服务商的 API Key，将自动为视觉、提取、向量与问答 4 个阶段一键装配最佳模型组合：',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _presetKeyController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'API Key (如 sk-...)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.flash_on_rounded, size: 16),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6900),
                              foregroundColor: Colors.white,
                              elevation: 2,
                            ),
                            onPressed: () => _applyPreset(ProviderPreset.xiaomi),
                            label: const Text('小米 MiMo (默认推荐)'),
                          ),
                          ElevatedButton(
                            onPressed: () => _applyPreset(ProviderPreset.siliconflow),
                            child: const Text('硅基流动'),
                          ),
                          ElevatedButton(
                            onPressed: () => _applyPreset(ProviderPreset.deepseek),
                            child: const Text('DeepSeek 官方'),
                          ),
                          ElevatedButton(
                            onPressed: () => _applyPreset(ProviderPreset.openai),
                            child: const Text('OpenAI'),
                          ),
                          ElevatedButton(
                            onPressed: () => _applyPreset(ProviderPreset.gemini),
                            child: const Text('Google Gemini'),
                          ),
                          ElevatedButton(
                            onPressed: () => _applyPreset(ProviderPreset.ollama),
                            child: const Text('本地 Ollama'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // 极客 4 段式独立路由
              _buildGeekStageCard(
                title: 'Stage 1: 视觉与文字提取层',
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _settings.stage1Mode,
                    decoration: const InputDecoration(labelText: '提取策略'),
                    items: const [
                      DropdownMenuItem(value: 'native_ocr_only', child: Text('纯系统原生 OCR (零成本)')),
                      DropdownMenuItem(value: 'smart_hybrid', child: Text('智能混合 (字数少于阈值时调 VLM)')),
                      DropdownMenuItem(value: 'always_vlm', child: Text('始终调用多模态 VLM')),
                    ],
                    onChanged: (v) => setState(() => _settings.stage1Mode = v!),
                  ),
                  const SizedBox(height: 8),
                  Text('VLM 触发字数阈值: ${_settings.vlmTriggerCharThreshold} 字'),
                  Slider(
                    value: _settings.vlmTriggerCharThreshold.toDouble(),
                    min: 5,
                    max: 100,
                    divisions: 19,
                    label: '${_settings.vlmTriggerCharThreshold}',
                    onChanged: (v) => setState(() => _settings.vlmTriggerCharThreshold = v.toInt()),
                  ),
                  TextField(controller: _vlmBaseUrl, decoration: const InputDecoration(labelText: 'VLM Base URL')),
                  TextField(controller: _vlmKey, obscureText: true, decoration: const InputDecoration(labelText: 'VLM API Key')),
                  TextField(controller: _vlmModel, decoration: const InputDecoration(labelText: 'VLM Model')),
                ],
              ),
              const SizedBox(height: 16),

              _buildGeekStageCard(
                title: 'Stage 2: 结构化提取与打标层 (LLM)',
                children: [
                  TextField(controller: _s2BaseUrl, decoration: const InputDecoration(labelText: 'LLM Base URL')),
                  TextField(controller: _s2Key, obscureText: true, decoration: const InputDecoration(labelText: 'LLM API Key')),
                  TextField(controller: _s2Model, decoration: const InputDecoration(labelText: 'LLM Model (如 deepseek-chat)')),
                  const SizedBox(height: 8),
                  Text('Temperature: ${_settings.stage2Temperature}'),
                  Slider(
                    value: _settings.stage2Temperature,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    label: '${_settings.stage2Temperature}',
                    onChanged: (v) => setState(() => _settings.stage2Temperature = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildGeekStageCard(
                title: 'Stage 3: 向量化 Embedding 层',
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _settings.stage3Mode,
                    decoration: const InputDecoration(labelText: 'Embedding 模式'),
                    items: const [
                      DropdownMenuItem(value: 'remote_api', child: Text('远程 API 向量计算')),
                      DropdownMenuItem(value: 'disabled', child: Text('关闭 (纯 FTS5 全文搜索)')),
                    ],
                    onChanged: (v) => setState(() => _settings.stage3Mode = v!),
                  ),
                  TextField(controller: _s3BaseUrl, decoration: const InputDecoration(labelText: 'Embedding Base URL')),
                  TextField(controller: _s3Key, obscureText: true, decoration: const InputDecoration(labelText: 'Embedding API Key')),
                  TextField(controller: _s3Model, decoration: const InputDecoration(labelText: 'Embedding Model (如 BAAI/bge-m3)')),
                ],
              ),
              const SizedBox(height: 16),

              _buildGeekStageCard(
                title: 'Stage 4: Ask AI / RAG 智能问答层',
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _settings.ragMode,
                    decoration: const InputDecoration(labelText: 'RAG 推理引擎模式'),
                    items: const [
                      DropdownMenuItem(value: 'remote_api', child: Text('远程 API 大模型 (如 Xiaomi MiMo / DeepSeek)')),
                      DropdownMenuItem(value: 'local_offline', child: Text('纯本地离线 RAG (基于 FTS5 索引，无需网络与 Key)')),
                    ],
                    onChanged: (v) => setState(() => _settings.ragMode = v!),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: _s4BaseUrl, decoration: const InputDecoration(labelText: 'RAG Base URL')),
                  TextField(controller: _s4Key, obscureText: true, decoration: const InputDecoration(labelText: 'RAG API Key')),
                  TextField(controller: _s4Model, decoration: const InputDecoration(labelText: 'RAG Model (如 mimo-v2.6-flash)')),
                  const SizedBox(height: 8),
                  Text('向量 vs 关键词 融合权重比: ${(_settings.stage4VectorWeight * 10).round() / 10} : ${(10 - (_settings.stage4VectorWeight * 10).round()) / 10}'),
                  Slider(
                    value: _settings.stage4VectorWeight,
                    min: 0.0,
                    max: 1.0,
                    divisions: 10,
                    onChanged: (v) => setState(() => _settings.stage4VectorWeight = v),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // iOS 快捷指令配置指引
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bolt_rounded, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Text('iOS 快捷指令极速闪记配置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '配合 iOS 16+ AppIntent，通过 iPhone 操作按钮 (Action Button) 或轻点背面实现零打断入库：',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '1. 打开 iPhone「快捷指令」App 新建快捷指令；\n2. 添加动作「截屏」(获取当前屏幕)；\n3. 添加动作「从图像中提取文本」(系统原生 Vision OCR)；\n4. 添加动作「存入 AI 记忆」(输入截图与 OCR 文本)；\n5. 默认搭载小米 MiMo 多模态模型 (mimo-v2.6-flash)，强制融合图像与文字！',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // WebDAV 同步配置
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('启用 WebDAV 多端增量同步', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('一卡一 JSON + 压缩图，支持坚果云或自建 WebDAV'),
                      value: _settings.webdavEnabled,
                      onChanged: (v) => setState(() => _settings.webdavEnabled = v),
                    ),
                    if (_settings.webdavEnabled) ...[
                      const Divider(),
                      TextField(controller: _webdavUrl, decoration: const InputDecoration(labelText: 'WebDAV 服务器 URL')),
                      TextField(controller: _webdavUser, decoration: const InputDecoration(labelText: '用户名 / 账号')),
                      TextField(controller: _webdavPwd, obscureText: true, decoration: const InputDecoration(labelText: '应用密码 / Token')),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _settings.webdavSyncPolicy,
                        decoration: const InputDecoration(labelText: '图片同步策略'),
                        items: const [
                          DropdownMenuItem(value: 'lazy_image', child: Text('按需懒加载 (推荐，仅同步文字与向量)')),
                          DropdownMenuItem(value: 'full', child: Text('全量同步 (上传与下载全部 WebP 图片)')),
                          DropdownMenuItem(value: 'text_only', child: Text('仅同步文字 (图片仅保存在本机)')),
                        ],
                        onChanged: (v) => setState(() => _settings.webdavSyncPolicy = v!),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 主密码 AES-256-GCM 跨端同步 Key
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🔑 API Key 同步与主密码加密', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text(
                      '设置自定义主密码，将以 AES-256-GCM 高强度加密所有 API Key 并随 settings.json 写入网盘，在另一台设备输入相同主密码即可一键解密还原：',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _masterPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: '同步主密码 (Master Password)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('加密导出密文'),
                          onPressed: () async {
                            final pwd = _masterPasswordController.text;
                            if (pwd.length < 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('主密码长度需不少于 6 位')),
                              );
                              return;
                            }
                            final cipher = await SettingsService.instance.exportEncryptedKeys(pwd);
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('已生成加密密文'),
                                  content: SelectableText(cipher),
                                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeekStageCard({required String title, required List<Widget> children}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueAccent)),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}
