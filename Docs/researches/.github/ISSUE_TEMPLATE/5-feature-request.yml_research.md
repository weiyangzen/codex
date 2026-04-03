# 5-feature-request.yml 研究文档

## 场景与职责

此文件是 GitHub Issue 表单模板，专门用于收集 **功能请求 (Feature Request)**。它是 OpenAI Codex 项目 Issue 模板体系中的第五个模板（编号 5），也是唯一的非 Bug 报告模板，用于收集用户对新功能、改进建议的反馈。

### 定位与上下文

Codex 项目采用 **邀请制贡献模式**（参见 `docs/contributing.md`）：

> "External contributions are by invitation only"
> "If you would like to propose a new feature or a change in behavior, please open an issue describing the proposal..."

本模板是用户提出功能建议的官方渠道，对于产品路线图规划具有重要价值。

### 与其他模板的区别

| 模板 | 用途 | 标签 | 性质 |
|------|------|------|------|
| `1-codex-app.yml` | App Bug | `app` | Bug 报告 |
| `2-extension.yml` | Extension Bug | `extension` | Bug 报告 |
| `3-cli.yml` | CLI Bug | `bug` + `needs triage` | Bug 报告 |
| `4-bug-report.yml` | 通用 Bug | `bug` | Bug 报告 |
| `5-feature-request.yml` | 功能请求 | `enhancement` | **功能建议** |
| `6-docs-issue.yml` | 文档问题 | `docs` | 文档改进 |

## 功能点目的

### 核心目标

1. **标准化功能请求流程**: 确保功能建议包含必要的上下文信息
2. **收集产品形态信息**: 明确功能请求针对哪个 Codex 产品
3. **管理用户期望**: 明确说明并非所有功能都会被接受
4. **防止重复请求**: 引导用户搜索现有 Issue 并点赞支持

### 收集的关键信息维度

| 字段 ID | 类型 | 必填 | 目的 |
|---------|------|------|------|
| `variant` | input | ✅ | 目标 Codex 产品形态 |
| `feature` | textarea | ✅ | 功能描述 |
| `notes` | textarea | ❌ | 补充信息 |

### 精简设计哲学

相比 Bug 报告模板，功能请求模板字段更精简（仅 3 个），原因：

1. **不需要环境信息**: 功能请求不依赖于特定环境
2. **不需要版本信息**: 功能请求针对未来版本
3. **聚焦核心诉求**: 减少填写负担，鼓励提交

## 具体技术实现

### GitHub Issue 表单结构

```yaml
name: 🎁 Feature Request
description: Propose a new feature for Codex
labels:
  - enhancement
body:
  - type: markdown
    attributes:
      value: |
        Is Codex missing a feature that you'd like to see? ...
        
        Before you submit a feature:
        1. Search existing issues...
        2. The Codex team will try to balance...
  - type: input
    id: variant
    # ...
  - type: textarea
    id: feature
    # ...
  - type: textarea
    id: notes
    # ...
```

### 关键字段详解

#### 产品形态字段

```yaml
- type: input
  id: variant
  attributes:
    label: What variant of Codex are you using?
    description: (e.g., App, IDE Extension, CLI, Web)
  validations:
    required: true
```

此字段使用 `variant`（变体）而非 `product`，强调：
- Codex 是统一品牌，不同形态是同一产品的不同表现形式
- 某些功能可能需要在多个形态中同步实现

#### 功能描述字段

```yaml
- type: textarea
  id: feature
  attributes:
    label: What feature would you like to see?
  validations:
    required: true
```

开放式文本输入，允许用户：
- 描述功能场景
- 提供使用案例
- 建议实现方式
- 参考竞品功能

### 期望管理说明

```yaml
- type: markdown
  attributes:
    value: |
      Before you submit a feature:
      1. Search existing issues for similar features. 
         If you find one, 👍 it rather than opening a new one.
      2. The Codex team will try to balance the varying needs 
         of the community when prioritizing or rejecting new features. 
         Not all features will be accepted. 
         See [Contributing](https://github.com/openai/codex#contributing) 
         for more details.
```

这是所有模板中最详细的"前置说明"，目的：
- **减少重复 Issue**: 鼓励用户点赞现有请求
- **设定期望**: 明确说明功能请求可能被拒绝
- **引导阅读贡献指南**: 链接到详细的贡献文档

### 标签策略

```yaml
labels:
  - enhancement
```

使用 `enhancement` 标签而非 `feature-request`，因为：
- `enhancement` 是 GitHub 标准标签
- 与 issue-labeler.yml 中的分类一致

## 关键代码路径与文件引用

### 模板文件位置
```
.github/ISSUE_TEMPLATE/
├── 1-codex-app.yml
├── 2-extension.yml
├── 3-cli.yml
├── 4-bug-report.yml
├── 5-feature-request.yml      # 本文件
└── 6-docs-issue.yml
```

### 关联文档

**贡献指南** (`docs/contributing.md`):

```markdown
If you would like to propose a new feature or a change in behavior, 
please open an issue describing the proposal or upvote an existing 
enhancement request. We prioritize new features based on:
- community feedback
- alignment with our roadmap
- consistency across all Codex surfaces (CLI, IDE extensions, web, etc.)
```

**Pull Request 模板** (`.github/pull_request_template.md`):

```markdown
Include a link to a bug report or enhancement request.
```

说明功能请求 Issue 是 PR 的前提条件。

### 关联工作流

**Issue 标签自动分类** (`.github/workflows/issue-labeler.yml`):

```yaml
# 问题类型标签（互斥）
- enhancement — Feature requests or usability improvements that ask 
  for new capabilities, better ergonomics, or quality-of-life tweaks.
```

由于本模板已预置 `enhancement` 标签，AI 标签器会：
- 不再重复添加 `enhancement`
- 可能添加产品分类标签（基于 `variant` 字段内容）
- 可能添加其他相关标签（`mcp`, `azure`, `custom-model` 等）

## 依赖与外部交互

### 依赖的 GitHub 功能

1. **GitHub Issue Forms**: YAML 结构化表单
2. **标签自动应用**: `labels: [enhancement]`
3. **工作流触发**: issues opened/labeled 事件
4. **投票机制**: 👍 反应用于社区需求排序

### 功能请求处理流程

```
用户有功能想法
    ↓
搜索现有 Issue，如有则点赞
    ↓
无现有 Issue → 使用 Feature Request 模板
    ↓
填写表单（产品形态、功能描述）
    ↓
提交 Issue，自动打上 "enhancement" 标签
    ↓
issue-labeler.yml 触发 → AI 添加产品标签
    ↓
社区通过 👍 投票表达支持
    ↓
产品团队定期评审高票功能请求
    ↓
决策：接受/拒绝/暂缓
```

### 与产品规划的关系

功能请求模板收集的数据支持：

1. **需求优先级排序**: 通过 👍 数量衡量社区需求强度
2. **跨产品一致性**: `variant` 字段帮助识别需要在多形态实现的功能
3. **路线图规划**: 高频请求的功能类型影响产品方向

## 风险、边界与改进建议

### 潜在风险

1. **功能请求泛滥**: 开源项目常面临大量功能请求，可能淹没 Bug 报告
2. **实现承诺误解**: 用户可能误解 "enhancement" 标签为接受承诺
3. **跨产品重复**: 同一功能可能在多个产品形态中重复请求
4. **缺乏技术细节**: 模板不收集技术约束信息，可能导致不可实现的功能请求

### 边界情况

1. **Bug vs Feature 模糊**: 某些"缺失功能"可能被用户视为 Bug
2. **多形态功能**: 一个功能可能同时适用于 CLI 和 App
3. **第三方集成请求**: 请求支持与第三方工具集成

### 改进建议

1. **添加使用场景字段**:
   ```yaml
   - type: textarea
     id: use_case
     attributes:
       label: Use Case
       description: Describe the specific scenario where this feature would help
   ```

2. **添加优先级自评**:
   ```yaml
   - type: dropdown
     id: priority
     attributes:
       label: How important is this to you?
       options:
         - Nice to have
         - Would improve my workflow
         - Blocking my use of Codex
   ```

3. **添加替代方案字段**:
   ```yaml
   - type: textarea
     id: alternatives
     attributes:
       label: Alternatives Considered
       description: What workarounds or alternatives have you tried?
   ```

4. **添加愿意贡献选项**:
   ```yaml
   - type: checkboxes
     id: contribution
     attributes:
       label: Contribution
       options:
         - label: I am willing to contribute this feature if invited
   ```
   注意：根据贡献指南，外部贡献需邀请，但此选项可表达意愿。

5. **改进产品形态字段为下拉框**:
   ```yaml
   - type: dropdown
     id: variant
     attributes:
       label: Target Codex Variant
       multiple: true
       options:
         - CLI
         - IDE Extension (VS Code)
         - IDE Extension (Cursor)
         - IDE Extension (Windsurf)
         - Desktop App
         - Web Interface
         - GitHub Action
         - Multiple/All
   ```

6. **添加相关 Issue 引用**:
   ```yaml
   - type: input
     id: related
     attributes:
       label: Related Issues
       description: Issue numbers of related requests (e.g., #123, #456)
   ```

### 维护建议

- **定期分类**: 定期审查功能请求，关闭明显超出范围或重复的请求
- **标签细化**: 考虑添加 `feature-request-reviewed` 标签标识已评审的请求
- **社区反馈**: 对于高票但暂不实现的功能，添加解释性评论
- **路线图同步**: 将接受的功能请求与公开路线图关联
- **模板迭代**: 分析功能请求的质量，迭代模板字段设计

### 与贡献流程的协调

根据 `docs/contributing.md`：

> "The Codex team may invite an external contributor to submit a pull request when:
> - the problem is well understood,
> - the proposed approach aligns with the team's intended solution, and
> - the issue is deemed high-impact and high-priority."

功能请求模板应支持这一流程：
- 收集足够信息供团队评估
- 允许社区表达支持（👍）
- 为受邀贡献者提供清晰的起点
