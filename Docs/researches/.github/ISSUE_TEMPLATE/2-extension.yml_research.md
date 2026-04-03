# 2-extension.yml 研究文档

## 场景与职责

此文件是 GitHub Issue 表单模板，专门用于收集 **IDE 扩展 (IDE Extension)** 相关的 Bug 报告。它是 OpenAI Codex 项目 Issue 模板体系中的第二个模板（编号 2），针对 IDE 插件特有的问题场景设计。

### 定位与上下文

Codex 项目提供多种使用形态：
- **Codex CLI**: 命令行工具
- **Codex App**: 桌面应用程序
- **IDE Extension**: VS Code/Cursor/Windsurf 等编辑器的插件（本文档重点）
- **Codex Web**: 云端版本

IDE 扩展是 Codex 生态的重要组成部分，允许开发者直接在熟悉的编辑器环境中使用 Codex 功能。本模板专门针对 IDE 扩展特有的环境复杂性（多 IDE 支持、编辑器版本兼容性等）设计。

### 与其他模板的关系

- `1-codex-app.yml` → 桌面应用 Bug
- `2-extension.yml` → IDE 扩展 Bug（本文档）
- `3-cli.yml` → CLI 工具 Bug
- `4-bug-report.yml` → 其他通用 Bug
- `5-feature-request.yml` → 功能请求
- `6-docs-issue.yml` → 文档问题

## 功能点目的

### 核心目标

1. **捕获 IDE 环境信息**: IDE 扩展的问题往往与特定编辑器及其版本强相关
2. **区分多 IDE 支持**: Codex 扩展支持多种 IDE（VS Code、Cursor、Windsurf 等），需要明确识别
3. **标准化扩展 Bug 报告**: 确保收集插件版本、IDE 版本、平台信息等关键诊断数据

### 收集的关键信息维度

| 字段 ID | 类型 | 必填 | 目的 |
|---------|------|------|------|
| `version` | input | ✅ | 扩展版本号 |
| `plan` | input | ✅ | 用户订阅类型 |
| `ide` | input | ✅ | 使用的 IDE（VS Code、Cursor、Windsurf 等） |
| `platform` | input | ❌ | 操作系统平台信息 |
| `actual` | textarea | ✅ | 实际观察到的问题现象 |
| `steps` | textarea | ✅ | 复现步骤 |
| `expected` | textarea | ❌ | 预期行为 |
| `notes` | textarea | ❌ | 补充信息 |

### 与 App/CLI 模板的差异

| 维度 | 2-extension.yml | 1-codex-app.yml | 3-cli.yml |
|------|-----------------|-----------------|-----------|
| 版本号 | 扩展版本 | App 版本 | CLI 版本 (`codex --version`) |
| 特有字段 | `ide` (IDE 类型) | 无 | `model`, `terminal` |
| 平台信息 | 可选 | 可选 | 可选 |
| 标签 | `extension` | `app` | `bug`, `needs triage` |

## 具体技术实现

### GitHub Issue 表单语法

```yaml
name: 🧑‍💻 IDE Extension Bug
description: Report an issue with the IDE extension
labels:
  - extension
body:
  - type: markdown
    attributes:
      value: |
        Before submitting...
  - type: input
    id: version
    # ...
```

### 关键字段详解

#### IDE 字段 (id: ide)

```yaml
- type: input
  id: ide
  attributes:
    label: Which IDE are you using?
    description: Like `VS Code`, `Cursor`, `Windsurf`, etc.
  validations:
    required: true
```

这是 Extension 模板最核心的差异化字段。Codex 官方支持：
- **VS Code**: Visual Studio Code（主要支持平台）
- **Cursor**: AI-first 代码编辑器
- **Windsurf**: Codeium 推出的编辑器
- 可能还有其他兼容 VS Code 扩展 API 的编辑器

#### 平台信息收集

与 App 模板使用相同的命令：

**macOS/Linux:**
```bash
uname -mprs
```

**Windows PowerShell:**
```powershell
"$([Environment]::OSVersion | ForEach-Object VersionString) $(if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" })"
```

## 关键代码路径与文件引用

### 模板文件位置
```
.github/ISSUE_TEMPLATE/
├── 1-codex-app.yml
├── 2-extension.yml          # 本文件
├── 3-cli.yml
├── 4-bug-report.yml
├── 5-feature-request.yml
└── 6-docs-issue.yml
```

### 关联工作流

**Issue 标签自动分类** (`.github/workflows/issue-labeler.yml`):

```yaml
# issue-labeler.yml 中定义的相关标签
- extension — VS Code (or other IDE) extension-specific issues.
- windows-os — Bugs specific to Windows environments
- mcp — Topics involving Model Context Protocol servers/clients
```

**触发条件**:
```yaml
on:
  issues:
    types: [opened, labeled]
```

### 扩展代码位置

IDE 扩展代码位于：
- `codex-cli/` 目录可能包含 VS Code 扩展相关代码
- 官方文档: https://developers.openai.com/codex/ide

### 标签体系

本模板自动应用 `extension` 标签，与 `issue-labeler.yml` 中的产品分类对应：

```yaml
# 产品分类标签（互斥）
- CLI
- extension
- app
- codex-web
- github-action
- iOS
```

## 依赖与外部交互

### 依赖的 GitHub 功能

1. **GitHub Issue Forms**: YAML 格式的结构化表单
2. **自动标签应用**: `labels: [extension]`
3. **工作流集成**: 触发 issue-labeler 和 issue-deduplicator

### 与 IDE 生态的关联

| IDE | 扩展市场 | 扩展 ID | 备注 |
|-----|----------|---------|------|
| VS Code | VS Code Marketplace | `openai.codex` | 主要平台 |
| Cursor | Cursor 内置扩展市场 | - | 兼容 VS Code 扩展 |
| Windsurf | Windsurf 扩展市场 | - | 兼容 VS Code 扩展 |

### 数据流向

```
用户在 IDE 中遇到 Codex 扩展问题
    ↓
访问 GitHub Issues → 选择 "IDE Extension Bug" 模板
    ↓
填写表单（扩展版本、IDE 类型、平台等）
    ↓
提交 Issue，自动打上 "extension" 标签
    ↓
issue-labeler.yml 触发 → AI 分析添加标签
    ↓
issue-deduplicator.yml 触发 → 检测重复
```

## 风险、边界与改进建议

### 潜在风险

1. **IDE 版本信息缺失**: 当前模板只询问 IDE 名称，不收集 IDE 版本号，而扩展问题常与 IDE 版本相关
2. **扩展版本获取困难**: 用户可能不知道如何查看已安装扩展的版本
3. **多 IDE 混淆**: 用户可能同时使用多个 IDE，不清楚问题发生在哪个环境

### 边界情况

1. **VS Code 与 VS Code Insiders**: 两者是不同的应用程序，但用户可能不区分
2. **远程开发环境**: WSL、SSH Remote、Dev Containers 等环境下的扩展行为可能不同
3. **扩展冲突**: 与其他 AI 编码助手扩展的冲突问题

### 改进建议

1. **添加 IDE 版本字段**:
   ```yaml
   - type: input
     id: ide_version
     attributes:
       label: IDE Version
       description: |
         VS Code: Help > About
         Cursor: Cursor > About Cursor
   ```

2. **扩展版本获取指引**:
   ```yaml
   description: |
     VS Code: Extensions view → search "Codex" → version shown below extension name
   ```

3. **添加远程环境检测**:
   ```yaml
   - type: dropdown
     id: remote_env
     attributes:
       label: Are you using a remote development environment?
       options:
         - No (local)
         - WSL
         - SSH Remote
         - Dev Containers
         - GitHub Codespaces
   ```

4. **添加扩展 Host 信息**:
   ```yaml
   - type: textarea
     id: extension_host
     attributes:
       label: Extension Host Logs
       description: |
         VS Code: Output panel → select "Extension Host" from dropdown
   ```

5. **与其他模板的交叉引用**:
   - 在描述中添加链接到 CLI 和 App 模板，帮助用户选择正确的模板
   - 例如："Not sure if this is an extension issue? Check the CLI template if the issue persists in terminal."

### 维护建议

- 当新增 IDE 支持时（如 JetBrains 系列），更新 `ide` 字段的示例列表
- 定期分析 Extension Issue 的常见问题，考虑添加针对性的字段
- 与 IDE 扩展开发团队同步，确保收集的信息足以支持调试
- 考虑添加 "Last working version" 字段，帮助识别回归问题
