# 1-codex-app.yml 研究文档

## 场景与职责

此文件是 GitHub Issue 表单模板，专门用于收集 **Codex 桌面应用程序 (Codex App)** 相关的 Bug 报告。它是 OpenAI Codex 项目 Issue 模板体系中的第一个模板（编号 1），针对桌面应用特有的问题场景设计。

### 定位与上下文

Codex 项目提供多种使用形态：
- **Codex CLI**: 命令行工具 (`npm i -g @openai/codex`)
- **Codex App**: 桌面应用程序 (`codex app` 或从 https://chatgpt.com/codex 访问)
- **IDE Extension**: VS Code/Cursor/Windsurf 等编辑器的插件
- **Codex Web**: 云端版本 (chatgpt.com/codex)

本模板专门针对 **Codex App** 桌面应用的 Bug 报告，与其他模板形成互补：
- `1-codex-app.yml` → 桌面应用 Bug（本文档）
- `2-extension.yml` → IDE 扩展 Bug
- `3-cli.yml` → CLI 工具 Bug
- `4-bug-report.yml` → 其他通用 Bug
- `5-feature-request.yml` → 功能请求
- `6-docs-issue.yml` → 文档问题

## 功能点目的

### 核心目标

1. **标准化 Bug 报告流程**: 确保用户提交桌面应用 Bug 时提供完整、结构化的信息
2. **减少来回沟通成本**: 通过必填字段强制收集诊断所需的关键信息
3. **支持快速分类与路由**: 自动打上 `app` 标签，便于 issue-labeler 工作流处理

### 收集的关键信息维度

| 字段 ID | 类型 | 必填 | 目的 |
|---------|------|------|------|
| `version` | input | ✅ | 应用版本号（来自 "About Codex" 对话框） |
| `plan` | input | ✅ | 用户订阅类型（Plus/Pro/Team 等） |
| `platform` | input | ❌ | 操作系统平台信息 |
| `actual` | textarea | ✅ | 实际观察到的问题现象 |
| `steps` | textarea | ✅ | 复现步骤 |
| `expected` | textarea | ❌ | 预期行为 |
| `notes` | textarea | ❌ | 补充信息 |

## 具体技术实现

### GitHub Issue 表单语法

文件采用 **GitHub Issue Forms** 语法（YAML 格式），这是 GitHub 提供的结构化 Issue 创建方式：

```yaml
# 表单元数据
name: 🖥️ Codex App Bug           # 显示在模板选择界面的标题
description: Report an issue...   # 模板描述
labels: [app]                     # 自动应用的标签

# 表单主体
body:
  - type: markdown                # 静态说明文本
  - type: input                   # 单行文本输入
  - type: textarea                # 多行文本输入
```

### 平台信息收集指令

模板中提供了详细的平台信息获取命令：

**macOS/Linux:**
```bash
uname -mprs
```
输出示例: `Darwin 24.3.0 arm64 arm`

**Windows PowerShell:**
```powershell
"$([Environment]::OSVersion | ForEach-Object VersionString) $(if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" })"
```
输出示例: `Microsoft Windows NT 10.0.22631.0 x64`

### 验证规则

```yaml
validations:
  required: true    # 强制必填
```

## 关键代码路径与文件引用

### 模板文件位置
```
.github/ISSUE_TEMPLATE/
├── 1-codex-app.yml          # 本文件
├── 2-extension.yml          # IDE 扩展模板
├── 3-cli.yml                # CLI 模板
├── 4-bug-report.yml         # 通用 Bug 模板
├── 5-feature-request.yml    # 功能请求模板
└── 6-docs-issue.yml         # 文档问题模板
```

### 关联工作流

**Issue 标签自动分类** (`.github/workflows/issue-labeler.yml`):
- 当 Issue 被创建或标记为 `codex-label` 时触发
- 使用 `openai/codex-action@main` 分析 Issue 内容
- 可能添加的次级标签包括: `app`, `windows-os`, `auth`, `sandbox` 等

**Issue 重复检测** (`.github/workflows/issue-deduplicator.yml`):
- 当 Issue 被创建或标记为 `codex-deduplicate` 时触发
- 使用 AI 分析查找潜在重复 Issue
- 自动评论建议用户检查重复项

### 标签体系关联

本模板自动应用的 `app` 标签与 `issue-labeler.yml` 中定义的产品分类标签一致：

```yaml
# issue-labeler.yml 中的产品分类标签
- app — Issues related to the Codex desktop application.
- CLI — the Codex command line interface.
- extension — VS Code (or other IDE) extension-specific issues.
- codex-web — Issues targeting the Codex web UI/Cloud experience.
```

## 依赖与外部交互

### 依赖的 GitHub 功能

1. **GitHub Issue Forms**: 需要仓库启用 GitHub Issues 功能
2. **自动标签**: 依赖 GitHub 的 `labels` 自动应用机制
3. **工作流触发**: 依赖 `.github/workflows/` 中的自动化工作流

### 与 Codex App 的关联

Codex App 的代码位于：
- 可能涉及 `codex-rs/` 目录下的 Rust 代码（TUI/桌面应用相关）
- 应用版本号来自应用的 "About Codex" 对话框

### 数据流向

```
用户提交 Issue
    ↓
GitHub 使用 1-codex-app.yml 渲染表单
    ↓
用户填写并提交
    ↓
Issue 被创建，自动打上 "app" 标签
    ↓
trigger: issue-labeler.yml
    ↓
AI 分析并添加更细粒度标签 (windows-os, auth, etc.)
    ↓
trigger: issue-deduplicator.yml
    ↓
AI 检测重复 Issue 并评论
```

## 风险、边界与改进建议

### 潜在风险

1. **版本号获取门槛**: 用户可能不知道如何打开 "About Codex" 对话框获取版本号
2. **订阅信息敏感**: 要求提供订阅类型可能让部分用户感到隐私顾虑
3. **平台命令复杂度**: Windows PowerShell 命令较长，普通用户可能难以正确执行

### 边界情况

1. **与其他模板重叠**: 某些问题可能同时涉及 App 和 CLI（如 `codex app` 命令本身的问题）
2. **Web 与 App 混淆**: 用户可能混淆 Codex Web 和 Codex App
3. **版本号格式不统一**: 不同平台的版本号格式可能不一致

### 改进建议

1. **添加版本号获取指引**:
   ```yaml
   description: |
     From the menu: Codex → About Codex (macOS) or Help → About (Windows/Linux)
   ```

2. **考虑订阅字段的隐私性**:
   - 可将 `plan` 改为可选字段
   - 或提供下拉选项而非自由输入

3. **添加日志收集指引**:
   ```yaml
   - type: textarea
     id: logs
     attributes:
       label: Application Logs
       description: |
         Located at:
         - macOS: ~/Library/Logs/Codex/
         - Windows: %APPDATA%\Codex\logs\
         - Linux: ~/.config/Codex/logs/
   ```

4. **与 3-cli.yml 的协调**:
   - 考虑在 `codex app` 相关的问题处理上添加交叉引用说明
   - 明确区分 "App 内部功能" vs "App 启动/CLI 集成问题"

5. **国际化考虑**:
   - 当前模板为英文，对于非英语用户可能存在障碍
   - 可考虑添加多语言支持或翻译链接

### 维护建议

- 当 Codex App 新增重要诊断信息（如会话 ID、设备 ID）时，应及时更新模板
- 定期分析已关闭的 App Issue，检查是否有遗漏的关键信息字段
- 与 QA 团队同步，确保模板收集的信息足以支持复现流程
