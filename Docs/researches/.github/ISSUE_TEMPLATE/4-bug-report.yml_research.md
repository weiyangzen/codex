# 4-bug-report.yml 研究文档

## 场景与职责

此文件是 GitHub Issue 表单模板，用于收集 **通用 Bug 报告**，主要针对 Codex Web、集成组件或其他不属于 App、Extension、CLI 特定分类的 Bug。它是 OpenAI Codex 项目 Issue 模板体系中的第四个模板（编号 4），作为前三类特定产品模板的补充和兜底。

### 定位与上下文

Codex 项目包含多个产品形态：
- **Codex CLI**: 命令行工具
- **Codex App**: 桌面应用程序
- **IDE Extension**: VS Code/Cursor/Windsurf 插件
- **Codex Web**: 云端 Web 界面（https://chatgpt.com/codex）
- **GitHub Action**: 自动化工作流集成
- **其他集成**: 第三方工具、SDK 等

本模板 (`4-bug-report.yml`) 的定位是：
- **兜底模板**: 当问题不属于 App、Extension、CLI 时使用
- **Web 界面专用**: 主要针对 Codex Web 的 Bug
- **集成组件**: 其他 Codex 相关组件的问题

### 模板选择决策树

```
用户要报告 Bug
    ↓
是 Codex 桌面应用问题？ → 使用 1-codex-app.yml
    ↓ 否
是 IDE 扩展问题？ → 使用 2-extension.yml
    ↓ 否
是 CLI 工具问题？ → 使用 3-cli.yml
    ↓ 否
其他问题（Web、集成等）→ 使用 4-bug-report.yml（本模板）
```

## 功能点目的

### 核心目标

1. **提供通用 Bug 报告入口**: 覆盖不属于特定产品的 Bug
2. **简化报告流程**: 相比特定产品模板，字段更精简
3. **引导用户使用 Discussions**: 对于非 Bug 报告（求助、支持）引导到正确渠道

### 收集的关键信息维度

| 字段 ID | 类型 | 必填 | 目的 |
|---------|------|------|------|
| `actual` | textarea | ✅ | 实际观察到的问题现象 |
| `steps` | textarea | ✅ | 复现步骤 |
| `expected` | textarea | ❌ | 预期行为 |
| `notes` | textarea | ❌ | 补充信息 |

### 与特定产品模板的差异

| 维度 | 4-bug-report.yml | 1/2/3-*.yml |
|------|------------------|-------------|
| 字段数量 | 4 个 | 7-9 个 |
| 版本信息 | ❌ 不收集 | ✅ 必填 |
| 平台信息 | ❌ 不收集 | ✅ 部分模板收集 |
| 订阅信息 | ❌ 不收集 | ✅ 必填 |
| 标签 | `bug` | `app`/`extension`/`bug`+`needs triage` |

## 具体技术实现

### GitHub Issue 表单结构

```yaml
name: 🪲 Other Bug
description: Report an issue in Codex Web, integrations, or other Codex components
labels:
  - bug
body:
  - type: markdown
    attributes:
      value: |
        Before submitting...
        
        If you need help or support...
  - type: textarea
    id: actual
    # ...
```

### 关键设计决策

#### 1. 精简字段设计

相比其他模板，本模板去掉了：
- `version` (版本号)
- `plan` (订阅类型)
- `platform` (平台信息)
- `model` (模型信息)
- `terminal` (终端信息)
- `ide` (IDE 类型)

**原因**:
- 通用 Bug 可能涉及多个产品，难以定义统一的版本字段
- Web 界面的版本对用户透明
- 集成组件的版本由集成方控制

#### 2. 支持渠道引导

```yaml
- type: markdown
  attributes:
    value: |
      If you need help or support using Codex and are not reporting a bug, 
      please post on [codex/discussions](https://github.com/openai/codex/discussions)...
```

这是所有模板中唯一明确引导用户到 Discussions 的模板，因为：
- 通用分类更容易收到非 Bug 报告（使用问题、配置求助等）
- 需要明确区分 Bug 报告和支持请求

#### 3. 单标签策略

```yaml
labels:
  - bug
```

仅使用 `bug` 标签，因为：
- 问题类型尚不明确，不适合添加产品分类标签
- 需要人工 triage 后添加更具体的标签

## 关键代码路径与文件引用

### 模板文件位置
```
.github/ISSUE_TEMPLATE/
├── 1-codex-app.yml
├── 2-extension.yml
├── 3-cli.yml
├── 4-bug-report.yml         # 本文件
├── 5-feature-request.yml
└── 6-docs-issue.yml
```

### 关联工作流

**Issue 标签自动分类** (`.github/workflows/issue-labeler.yml`):

对于使用本模板创建的 Issue，AI 标签器可能添加的标签：

```yaml
# 产品分类（基于内容推断）
- codex-web — Issues targeting the Codex web UI/Cloud experience.
- github-action — Issues with the Codex GitHub action.

# 问题类型标签
- bug — Reproducible defects
- enhancement — Feature requests
- documentation — Documentation updates needed

# 其他可能标签
- azure — Azure OpenAI deployments
- auth — Authentication problems
- model-behavior — LLM behavior issues
```

**触发条件**:
```yaml
on:
  issues:
    types: [opened, labeled]
```

### 与 issue-labeler.yml 的集成

由于本模板不预置产品分类标签，issue-labeler 的 AI 分析尤为重要：

```yaml
prompt: |
  Your job is to choose the most appropriate labels for the issue...
  
  - Add one of: bug, enhancement, documentation
  - If applicable, add one product label: CLI, extension, app, codex-web, github-action, iOS
```

## 依赖与外部交互

### 依赖的 GitHub 功能

1. **GitHub Issue Forms**: YAML 结构化表单
2. **单标签自动应用**: `labels: [bug]`
3. **工作流触发**: issues opened/labeled 事件
4. **Discussions 集成**: 链接到 GitHub Discussions

### 可能涉及的产品组件

| 组件 | 说明 | 典型问题 |
|------|------|----------|
| Codex Web | 云端 Web 界面 | UI 渲染、会话同步、网络问题 |
| GitHub Action | 自动化工作流 | 配置、执行、输出解析 |
| SDK | 开发工具包 | API 调用、类型定义、文档 |
| 第三方集成 | 社区工具 | 兼容性、功能支持 |

### 数据流向

```
用户在 Codex Web 或其他组件遇到问题
    ↓
确认不属于 App/Extension/CLI 问题
    ↓
访问 GitHub Issues → 选择 "Other Bug" 模板
    ↓
填写精简表单（问题、复现步骤、预期行为）
    ↓
提交 Issue，自动打上 "bug" 标签
    ↓
issue-labeler.yml 触发 → AI 推断产品分类
    ↓
添加细分标签 (codex-web, github-action, etc.)
    ↓
issue-deduplicator.yml 触发 → 检测重复
```

## 风险、边界与改进建议

### 潜在风险

1. **误用率高**: 用户可能不清楚该用哪个模板，导致此模板被滥用
2. **信息不足**: 精简字段可能导致关键诊断信息缺失
3. **分类负担**: 所有使用此模板的 Issue 都需要人工/AI 分类

### 边界情况

1. **多产品交叉问题**: 一个问题可能同时涉及 Web 和 CLI
2. **版本信息缺失**: 对于 Web 界面，用户无法提供版本号
3. **第三方集成责任界定**: 难以区分是 Codex 问题还是集成方问题

### 改进建议

1. **添加产品类型下拉框**:
   ```yaml
   - type: dropdown
     id: product
     attributes:
       label: Which Codex product?
       options:
         - Codex Web (chatgpt.com/codex)
         - GitHub Action
         - SDK/API
         - Other/Not sure
   ```

2. **添加浏览器信息（针对 Web）**:
   ```yaml
   - type: input
     id: browser
     attributes:
       label: Browser (for Web issues)
       description: Chrome 120, Safari 17, Firefox 121, etc.
   ```

3. **添加上下文信息**:
   ```yaml
   - type: textarea
     id: context
     attributes:
       label: Additional Context
       description: |
         - For Web: session ID, approximate time of issue
         - For GitHub Action: workflow file snippet
         - For SDK: language and SDK version
   ```

4. **改进模板描述**:
   ```yaml
   description: |
     Report an issue in Codex Web, GitHub Action, SDK, or other components.
     For App/Extension/CLI issues, please use their respective templates.
   ```

5. **添加检查清单**:
   ```yaml
   - type: checkboxes
     id: checks
     attributes:
       label: Before submitting
       options:
         - label: I have searched for existing issues
           required: true
         - label: This is a bug report (not a support request)
           required: true
   ```

### 维护建议

- 监控使用此模板的 Issue 分类准确率，优化 AI 标签器的提示词
- 当新增 Codex 产品形态时，更新模板描述和选项
- 定期分析 "Other Bug" Issue，识别是否需要拆分新的专用模板
- 考虑为 Codex Web 创建独立模板，如果 Web 相关 Issue 数量显著增长
- 与社区管理团队同步，确保 Discussions 渠道能有效承接支持请求

### 与其他模板的协调

1. **避免重复**: 确保本模板的描述明确区分于 1/2/3 模板
2. **交叉引用**: 在模板描述中添加链接到其他三个产品模板
3. **升级路径**: 如果 Issue 创建后发现属于特定产品，维护者应协助重新标记
