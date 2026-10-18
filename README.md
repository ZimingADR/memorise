# Memorise (跨端本地优先 AI 记忆助手)

对标并超越「小布记忆 / 小爱记忆」的跨平台、本地优先（Local-First）、零服务器成本的个人瞬时生活助手与第二大脑（RAG 知识库）。

---

## 🌟 核心特性

1. **瞬时生活行动看板 + 知识库 RAG 双擎合一**：
   - **顶层行动看板**：自动置顶未核销的取件码（📦）与日程待办（📅），提供一键复制单号、一键核销打勾、一键写入日历。
   - **多模态记忆瀑布流**：自动提炼一句话标题、3 条核心干货要点与彩色标签。
   - **底层混合检索与 Ask AI**：SQLite FTS5 全文搜索 + 纯 Dart 内存 Float32 向量余弦相似度混合重排，弹出半屏抽屉智能问答并带引用角标。
2. **纯本地无服务器 + WebDAV 增量同步**：
   - 采用「一卡一 JSON (`memories/<uuid>.json`) + WebP 压缩图」增量同步状态机，杜绝整库冲突。
   - API Key 支持本地硬件安全区存储或 AES-256-GCM 主密码加密随网盘同步。
3. **无 Mac + 个人免费 Apple 账号破局**：
   - 避开付费专属的 `App Groups`，主工程内置 iOS 16+ `AppIntent`（`CaptureMemoryIntent`），快捷指令后台静默写入沙盒 `pending_inbox/` 缓冲队列，零打断闪记。
   - GitHub Actions 免费 macOS 虚拟机自动编译无签名 `.ipa`，支持 SideStore / AltStore / TrollStore 自签。
4. **高自由度 4 段式 AI 路由**：
   - Stage 1: 视觉与 OCR（原生 OCR / 智能混合 VLM / 始终 VLM）
   - Stage 2: 动态 Schema 结构化提取（兼容 DeepSeek / 硅基流动 / OpenAI / Gemini / 本地 Ollama）
   - Stage 3: 向量化 Embedding（纯 Dart 内存检索或远程 Embedding API）
   - Stage 4: Ask AI / RAG 问答（跨卡片引用与证据溯源）

---

## 📱 iOS 快捷指令配置指南（仅需 4 个动作）

打开 iPhone 自带的「快捷指令」App，新建以下两条指令：

### 快捷指令一：【极速闪记（零打断）】
1. **截屏**（获取当前屏幕画面）
2. **从图像中提取文本**（输入：截屏；使用 iOS 原生离线 Vision OCR）
3. **存入 AI 记忆**（调用 `CaptureMemoryIntent`）：
   - `截图或图片`：截屏
   - `OCR 提取文本`：来自图像的文本
   - `补充备注`：留空
> 💡 *推荐将此指令绑定至 iPhone 操作按钮 (Action Button) 或「设置 ➔ 辅助功能 ➔ 触控 ➔ 轻点背面两下」。*

### 快捷指令二：【批注闪记（带意图备注）】
1. **截屏**
2. **从图像中提取文本**（输入：截屏）
3. **要求输入**（提示文字：“补充备注：”，默认留空）
4. **存入 AI 记忆**：
   - `截图或图片`：截屏
   - `OCR 提取文本`：来自图像的文本
   - `补充备注`：提供的输入

---

## 🚀 自动化构建与 GitHub Release 自动发布

本项目已配置 GitHub Actions 自动化云端流水线 ([`.github/workflows/build_and_release.yml`](.github/workflows/build_and_release.yml))：

每次代码推送到 `main` 分支或打上版本 Tag 时，云端自动编译并直接发布到 GitHub Releases：
- 📱 **iOS 无签名 IPA**：`AI_Memory_Unsigned.ipa`（可直接通过 SideStore / AltStore / TrollStore 安装与无限期续签）
- 💻 **Windows 桌面版**：`AI_Memory_Windows.zip`（解压即可在 Windows 本地直接双击运行）
- 📲 **SideStore 软件源**：`sidestore.json`

---

## 📲 SideStore 订阅源与一键安装

通过 SideStore 订阅源，您可以直接在 iPhone 上一键安装 Memorise 并获取后续版本的无感自动更新推送！

### 方式一：在 iPhone Safari 中一键添加（推荐）
点击以下链接唤起 SideStore 并添加软件源：
> [📲 点击添加 Memorise 到 SideStore](sidestore://source?url=https://raw.githubusercontent.com/ZimingADR/memorise/main/sidestore.json)

```text
sidestore://source?url=https://raw.githubusercontent.com/ZimingADR/memorise/main/sidestore.json
```

### 方式二：手动复制订阅链接
在 SideStore App 中切换到 **Sources** ➔ 点击右上角 **+** ➔ 粘贴以下链接：
```text
https://raw.githubusercontent.com/ZimingADR/memorise/main/sidestore.json
```

---

## 💻 本地开发运行

```bash
# 获取依赖
flutter pub get

# 运行单元测试
flutter test

# 启动 Windows 桌面版
flutter run -d windows
```
