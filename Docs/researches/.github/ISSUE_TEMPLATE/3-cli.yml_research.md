# 3-cli.yml 研究文档

## 场景与职责

此文件是 GitHub Issue 表单模板，专门用于收集 **Codex CLI (命令行界面)** 相关的 Bug 报告。它是 OpenAI Codex 项目 Issue 模板体系中的第三个模板（编号 3），针对 CLI 工具特有的问题场景设计。

### 定位与上下文

Codex CLI 是 Codex 项目的核心组件，也是最早开源的部分：

```
npm i -g @openai/codex
# 或
brew install --cask codex
```

CLI 是开发者与 Codex 交互的主要方式之一，支持：
- 交互式 TUI (Terminal User Interface)
- 非交互式命令执行 (`codex exec`)
- 多模型支持 (GPT-4, GPT-5.2 等)
- 沙箱执行环境

### 与其他模板的关系

| 模板 | 用途 | 自动标签 |
|------|------|----------|
| `1-codex-app.yml` | 桌面应用 Bug | `app` |
| `2-extension.yml` | IDE 扩展 Bug | `extension` |
| `3-cli.yml` | CLI 工具 Bug | `bug`, `needs triage` |
| `4-bug-report.yml` | 其他通用 Bug | `bug` |
| `5-feature-request.yml` | 功能请求 | `enhancement` |
| `6-docs-issue.yml` | 文档问题 | `docs` |

## 功能点目的

### 核心目标

1. **捕获 CLI 环境复杂性**: CLI 运行环境多样（不同终端、Shell、多路复用器），需要详细收集
2. **支持模型相关问题**: CLI 直接与模型交互，需要记录使用的模型版本
3. **标准化 CLI Bug 报告**: 确保收集版本、终端环境、复现步骤等关键信息

### 收集的关键信息维度

| 字段 ID | 类型 | 必填 | 目的 |
|---------|------|------|------|
| `version` | input | ✅ | CLI 版本 (`codex --version`) |
| `plan` | input | ✅ | 用户订阅类型 |
| `model` | input | ❌ | 使用的模型 (gpt-5.2, gpt-5.2-codex 等) |
| `platform` | input | ❌ | 操作系统平台 |
| `terminal` | input | ❌ | 终端模拟器及版本，多路复用器信息 |
| `actual` | textarea | ✅ | 实际观察到的问题 |
| `steps` | textarea | ✅ | 复现步骤 |
| `expected` | textarea | ❌ | 预期行为 |
| `notes` | textarea | ❌ | 补充信息 |

### 差异化字段详解

#### 版本获取指令

```yaml
- type: input
  id: version
  attributes:
    label: What version of Codex CLI is running?
    description: use `codex --version`
```

与其他模板不同，CLI 模板明确提供了获取版本的命令，因为：
- CLI 用户更熟悉命令行操作
- `codex --version` 是标准的版本查询方式

#### 模型字段

```yaml
- type: input
  id: model
  attributes:
    label: Which model were you using?
    description: Like `gpt-5.2`, `gpt-5.2-codex`, etc.
```

这是 CLI 模板特有的字段，因为：
- CLI 支持多种模型切换
- 模型行为差异可能导致问题
- 需要追踪特定模型的 Bug

#### 终端环境字段

```yaml
- type: input
  id: terminal
  attributes:
    label: What terminal emulator and version are you using (if applicable)?
    description: |
      Also note any multiplexer in use (screen / tmux / zellij)
      E.g, VSCode, Terminal.app, iTerm2, Ghostty, Windows Terminal (WSL / PowerShell)
```

这是 CLI 模板最详细的字段，涵盖：
- **终端模拟器**: VSCode, Terminal.app, iTerm2, Ghostty, Windows Terminal 等
- **多路复用器**: screen, tmux, zellij
- **Shell 环境**: WSL, PowerShell

### 预提交检查提示

```yaml
- type: markdown
  attributes:
    value: |
      Make sure you are running the [latest](https://npmjs.com/package/@openai/codex) version...
```

CLI 模板特别强调了版本更新检查，因为：
- CLI 发布频率较高
- 许多 Bug 在新版本中已修复
- 减少重复 Issue 报告

## 具体技术实现

### GitHub Issue 表单结构

```yaml
name: 💻 CLI Bug
description: Report an issue in the Codex CLI
labels:
  - bug
  - needs triage
body:
  - type: markdown
    attributes:
      value: |
        Before submitting...
        Make sure you are running the [latest]...
  # ... 字段定义
```

### 双标签策略

```yaml
labels:
  - bug
  - needs triage
```

CLI 模板是唯一使用双标签的模板：
- `bug`: 标识这是一个 Bug 报告
- `needs triage`: 标识需要维护者分类审查

这反映了 CLI 作为核心组件的重要性，以及需要更严格的质量控制。

## 关键代码路径与文件引用

### 模板文件位置
```
.github/ISSUE_TEMPLATE/
├── 1-codex-app.yml
├── 2-extension.yml
├── 3-cli.yml                # 本文件
├── 4-bug-report.yml
├── 5-feature-request.yml
└── 6-docs-issue.yml
```

### CLI 代码位置

Codex CLI 的主要代码位于：
- `codex-cli/`: TypeScript/Node.js CLI 实现
- `codex-rs/`: Rust 实现的 CLI 组件（TUI、核心逻辑）

### 关联工作流

**Issue 标签自动分类** (`.github/workflows/issue-labeler.yml`):

CLI 相关的自动标签包括：
```yaml
- CLI — the Codex command line interface.
- TUI — Problems with the terminal user interface
- codex-exec — Problems related to the "codex exec" command
- sandbox — Issues related to local sandbox environments
- tool-calls — Problems related to specific tool call invocations
- context-management — Problems related to compaction, context windows
- rate-limits — Problems related to token limits, rate limits
```

**触发条件**:
```yaml
if: github.repository == 'openai/codex' && 
    (github.event.action == 'opened' || 
     (github.event.action == 'labeled' && github.event.label.name == 'codex-label'))
```

### 与 issue-labeler.yml 的集成

CLI Issue 可能获得的额外标签：

| 标签 | 触发条件 | 说明 |
|------|----------|------|
| `windows-os` | PowerShell 提及、路径问题 | Windows 特定问题 |
| `TUI` | 键盘快捷键、复制粘贴、界面更新 | 终端用户界面问题 |
| `sandbox` | 沙箱环境、工具调用审批 | 沙箱相关问题 |
| `auth` | 认证、登录、访问令牌 | 认证问题 |
| `model-behavior` | LLM 行为异常 | 模型行为问题 |

## 依赖与外部交互

### 依赖的 GitHub 功能

1. **GitHub Issue Forms**: YAML 结构化表单
2. **多标签自动应用**: `labels: [bug, needs triage]`
3. **工作流触发**: issues opened/labeled 事件

### CLI 生态依赖

| 组件 | 说明 |
|------|------|
| Node.js/npm | CLI 的主要分发渠道 |
| Homebrew | macOS 用户的替代安装方式 |
| GitHub Releases | 二进制文件分发 |

### 数据流向

```
用户在终端使用 Codex CLI 遇到问题
    ↓
执行 codex --version 获取版本
    ↓
访问 GitHub Issues → 选择 "CLI Bug" 模板
    ↓
填写表单（版本、模型、终端环境等）
    ↓
提交 Issue，自动打上 "bug" + "needs triage" 标签
    ↓
issue-labeler.yml 触发 → AI 分析添加细分标签
    ↓
维护者根据标签分类处理
```

## 风险、边界与改进建议

### 潜在风险

1. **终端信息收集不完整**: 用户可能只填写终端名称，忽略版本和多路复用器信息
2. **模型信息遗漏**: `model` 字段为可选，但模型相关问题诊断需要此信息
3. **配置信息缺失**: CLI 行为受配置文件影响，但模板未收集配置信息

### 边界情况

1. **多版本共存**: 用户可能同时通过 npm 和 Homebrew 安装，存在版本混淆
2. **配置覆盖**: 环境变量、配置文件、命令行参数的优先级问题
3. **CI/CD 环境**: 在自动化环境中使用 CLI 的问题可能与交互式使用不同

### 改进建议

1. **添加配置收集指引**:
   ```yaml
   - type: textarea
     id: config
     attributes:
       label: Configuration
       description: |
         Output of `codex --config` or relevant ~/.codex/config.toml sections
   ```

2. **模型字段设为必填**:
   ```yaml
   validations:
     required: true
   ```
   理由：模型行为差异是 CLI Bug 的重要诊断线索

3. **添加执行模式区分**:
   ```yaml
   - type: dropdown
     id: execution_mode
     attributes:
       label: Execution Mode
       options:
         - Interactive TUI (default)
         - Non-interactive (codex exec)
         - MCP Server mode
   ```

4. **添加沙箱信息**:
   ```yaml
   - type: dropdown
     id: sandbox
     attributes:
       label: Sandbox Configuration
       options:
         - Default (full sandbox)
         - No sandbox (--no-sandbox)
         - Custom policy
   ```

5. **环境变量收集**:
   ```yaml
   - type: textarea
     id: env
     attributes:
       label: Relevant Environment Variables
       description: |
         Any CODEX_* or OPENAI_* environment variables set (redact API keys)
   ```

6. **添加日志收集**:
   ```yaml
   - type: textarea
     id: logs
     attributes:
       label: Debug Logs
       description: |
         Run with `--debug` or `DEBUG=codex*` and paste relevant logs
   ```

### 维护建议

- 当 CLI 新增重要功能（如新的执行模式、配置选项）时，更新模板收集相关信息
- 定期分析 `needs triage` 标签的 Issue，优化模板以减少分类工作量
- 与 CLI 开发团队同步，确保模板收集的信息覆盖常见调试场景
- 考虑添加 "Last working version" 字段，帮助识别回归问题
- 当新的终端模拟器流行时（如新的 GPU 加速终端），更新 terminal 字段的示例列表
