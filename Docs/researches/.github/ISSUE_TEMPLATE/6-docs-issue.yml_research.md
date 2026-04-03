# 6-docs-issue.yml 研究文档

## 场景与职责

此文件是 GitHub Issue 表单模板，专门用于收集 **文档相关问题 (Documentation Issue)**。它是 OpenAI Codex 项目 Issue 模板体系中的第六个模板（编号 6），也是字段最少的模板，针对文档质量改进的轻量级反馈设计。

### 定位与上下文

Codex 项目包含多种文档：
- **README.md**: 项目入口文档，安装和快速开始
- **docs/**: 详细文档目录
  - `contributing.md`: 贡献指南
  - `install.md`: 安装说明
  - `config.md`: 配置文档
  - `authentication.md`: 认证指南
  - `sandbox.md`: 沙箱说明
  - `skills.md`: Skills 系统文档
  - `slash_commands.md`: 斜杠命令文档
  - 等等
- **AGENTS.md**: AI 代理的上下文文档
- **API 文档**: 开发者文档 (https://developers.openai.com/codex)

本模板为文档问题提供专门的反馈渠道，与 Bug 报告和功能请求并列。

### 与其他模板的关系

| 模板 | 用途 | 标签 | 字段数 |
|------|------|------|--------|
| `1-codex-app.yml` | App Bug | `app` | 7 |
| `2-extension.yml` | Extension Bug | `extension` | 8 |
| `3-cli.yml` | CLI Bug | `bug` + `needs triage` | 9 |
| `4-bug-report.yml` | 通用 Bug | `bug` | 4 |
| `5-feature-request.yml` | 功能请求 | `enhancement` | 3 |
| `6-docs-issue.yml` | 文档问题 | `docs` | 3 |

## 功能点目的

### 核心目标

1. **降低文档反馈门槛**: 简化流程，鼓励用户报告文档问题
2. **分类文档问题类型**: 通过下拉框区分缺失、错误、混淆等不同问题
3. **收集问题位置信息**: 获取文档 URL 或文件路径
4. **与代码问题分离**: 文档问题通常不需要环境信息，字段设计反映这一差异

### 收集的关键信息维度

| 字段 ID | 类型 | 必填 | 目的 |
|---------|------|------|------|
| `type` (dropdown) | dropdown | ❌ | 问题类型（可多选） |
| `issue` | textarea | ✅ | 具体问题描述 |
| `location` | textarea | ❌ | 问题所在位置 |

### 极简设计哲学

本模板是六个模板中字段最少的（3 个），设计原则：

1. **无需版本信息**: 文档问题通常与版本无关
2. **无需环境信息**: 文档问题不依赖于用户环境
3. **快速反馈**: 降低填写成本，鼓励更多用户参与

## 具体技术实现

### GitHub Issue 表单结构

```yaml
name: 📗 Documentation Issue
description: Tell us if there is missing or incorrect documentation
labels: [docs]
body:
  - type: markdown
    attributes:
      value: |
        Thank you for submitting a documentation request...
  - type: dropdown
    attributes:
      label: What is the type of issue?
      multiple: true
      options:
        - Documentation is missing
        - Documentation is incorrect
        - Documentation is confusing
        - Example code is not working
        - Something else
  - type: textarea
    attributes:
      label: What is the issue?
    validations:
      required: true
  - type: textarea
    attributes:
      label: Where did you find it?
      description: If possible, please provide the URL(s)...
```

### 关键字段详解

#### 问题类型下拉框

```yaml
- type: dropdown
  attributes:
    label: What is the type of issue?
    multiple: true
    options:
      - Documentation is missing      # 缺失文档
      - Documentation is incorrect    # 错误文档
      - Documentation is confusing    # 混淆文档
      - Example code is not working   # 示例代码无效
      - Something else                # 其他
```

**设计要点**:
- `multiple: true`: 允许一个问题属于多种类型
- 覆盖主要文档问题场景
- "Example code is not working" 特别针对技术文档

#### 问题描述字段

```yaml
- type: textarea
  attributes:
    label: What is the issue?
  validations:
    required: true
```

唯一必填字段，收集：
- 具体问题描述
- 建议的改进方案
- 用户遇到的困惑

#### 位置信息字段

```yaml
- type: textarea
  attributes:
    label: Where did you find it?
    description: If possible, please provide the URL(s)...
```

可选字段，但强烈建议提供：
- 文档 URL
- 文件路径
- 章节标题

### 标签语法差异

注意本模板的标签语法与其他模板不同：

```yaml
# 本模板
labels: [docs]

# 其他模板
labels:
  - bug
  - needs triage
```

两种语法在 YAML 中等价，但本模板使用了内联数组格式，可能是为了简洁。

## 关键代码路径与文件引用

### 模板文件位置
```
.github/ISSUE_TEMPLATE/
├── 1-codex-app.yml
├── 2-extension.yml
├── 3-cli.yml
├── 4-bug-report.yml
├── 5-feature-request.yml
└── 6-docs-issue.yml           # 本文件
```

### 项目文档结构

```
docs/
├── contributing.md          # 贡献指南（PR 模板引用）
├── install.md              # 安装说明
├── config.md               # 配置文档
├── authentication.md       # 认证指南
├── sandbox.md              # 沙箱说明
├── exec.md                 # exec 命令文档
├── execpolicy.md           # 执行策略
├── skills.md               # Skills 系统
├── slash_commands.md       # 斜杠命令
├── prompts.md              # Prompts 系统
├── getting-started.md      # 入门指南
├── agents_md.md            # AGENTS.md 说明
├── tui-*.md                # TUI 相关技术文档
└── ...

AGENTS.md                   # AI 代理上下文
README.md                   # 项目入口文档
```

### 关联工作流

**Issue 标签自动分类** (`.github/workflows/issue-labeler.yml`):

```yaml
# 问题类型标签
- documentation — Updates or corrections needed in docs/README/config 
  references (broken links, missing examples, outdated keys, clarification requests).
```

由于本模板已预置 `docs` 标签，AI 标签器会：
- 不再重复添加 `documentation`
- 可能添加其他相关标签（如 `bug` 如果示例代码确实有问题）

**Issue 重复检测** (`.github/workflows/issue-deduplicator.yml`):
- 同样适用于文档 Issue
- 帮助识别重复的文档反馈

### 与 Pull Request 的关联

根据 `docs/contributing.md`：

> "Document behavior. If your change affects user-facing behavior, 
> update the README, inline help (`codex --help`), or relevant example projects."

文档 Issue 可能直接转化为文档 PR，特别是：
- 拼写错误修正
- 链接修复
- 示例代码更新

## 依赖与外部交互

### 依赖的 GitHub 功能

1. **GitHub Issue Forms**: YAML 结构化表单
2. **下拉框多选**: `multiple: true` 选项
3. **标签自动应用**: `labels: [docs]`
4. **工作流触发**: issues opened/labeled 事件

### 文档问题处理流程

```
用户发现文档问题
    ↓
使用 Documentation Issue 模板
    ↓
选择问题类型（可多选）
    ↓
描述问题并提供位置信息
    ↓
提交 Issue，自动打上 "docs" 标签
    ↓
issue-labeler.yml 触发（可选添加其他标签）
    ↓
维护者评估并处理
    ├── 简单修复 → 直接提交 PR
    ├── 需要讨论 → 标记并分配
    └── 重复问题 → 关闭并引用已有 Issue
```

### 外部文档引用

模板用户可能报告的文档位置包括：
- GitHub 仓库内的 Markdown 文件
- https://developers.openai.com/codex（官方开发者文档）
- https://help.openai.com（帮助中心）
- 应用内帮助文本

## 风险、边界与改进建议

### 潜在风险

1. **范围模糊**: "Documentation is confusing" 主观性强，难以量化处理
2. **与 Bug 重叠**: "Example code is not working" 可能是代码 Bug 而非文档问题
3. **外部文档**: 用户可能报告 OpenAI 官方文档（非本仓库）的问题
4. **多语言文档**: 项目可能有非英语文档，但模板为英文

### 边界情况

1. **README vs docs/**: README 问题是否属于文档 Issue？
2. **AGENTS.md**: AI 代理上下文文档的问题是否适用？
3. **代码注释**: 源代码中的文档字符串问题是否适用？
4. **网站文档**: https://developers.openai.com/codex 的问题如何处理？

### 改进建议

1. **添加文档位置下拉框**:
   ```yaml
   - type: dropdown
     id: doc_location
     attributes:
       label: Documentation Location
       options:
         - README.md
         - docs/ folder
         - AGENTS.md
         - API Documentation (developers.openai.com)
         - In-app help
         - Other
   ```

2. **添加建议修复字段**:
   ```yaml
   - type: textarea
     id: suggestion
     attributes:
       label: Suggested Improvement
       description: How would you like to see this documented?
   ```

3. **区分技术 vs 非技术文档**:
   ```yaml
   - type: dropdown
     id: doc_type
     attributes:
       label: Documentation Type
       options:
         - User guide/Getting started
         - API reference
         - Configuration reference
         - Troubleshooting
         - Contributing/Development
   ```

4. **添加愿意贡献选项**:
   ```yaml
   - type: checkboxes
     id: contribution
     attributes:
       label: Contribution
       options:
         - label: I am willing to submit a PR to fix this documentation
   ```

5. **改进问题类型描述**:
   ```yaml
   - type: dropdown
     id: issue_type
     attributes:
       label: Issue Type
       multiple: true
       options:
         - Missing documentation (feature not documented)
         - Factual error (information is wrong)
         - Unclear explanation (hard to understand)
         - Broken example (code doesn't work)
         - Outdated content (refers to old version)
         - Broken link
         - Typo/Grammar
   ```

6. **添加截图上传**:
   ```yaml
   - type: markdown
     attributes:
       value: |
         You can attach screenshots by dragging and dropping them into the comment box.
   ```

### 维护建议

- **快速响应**: 文档 Issue 通常处理成本低，建议快速响应
- **标签细分**: 考虑添加 `docs-typo`, `docs-missing`, `docs-outdated` 等子标签
- **定期审查**: 定期检查文档 Issue，识别文档结构的系统性问题
- **与代码 PR 同步**: 要求功能 PR 同时更新相关文档，减少后续文档 Issue
- **外部文档反馈**: 对于非本仓库文档的问题，提供反馈渠道指引

### 与 AGENTS.md 的协调

`AGENTS.md` 是 Codex 项目特有的文档类型，用于向 AI 代理提供上下文。文档模板应考虑：
- AGENTS.md 的变更可能影响 AI 行为
- AGENTS.md 的问题可能需要更谨慎处理
- 考虑在模板中明确提及 AGENTS.md 作为可选文档位置
