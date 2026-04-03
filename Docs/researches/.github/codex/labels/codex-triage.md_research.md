# codex-triage.md 深度研究文档

## 场景与职责

`codex-triage.md` 是 OpenAI Codex 项目的 GitHub Action 自动化 Issue 分类（Triage）提示词模板，位于 `.github/codex/labels/` 目录下。当 GitHub Issue 被标记为 `codex-triage` 标签时，该文件定义了 Codex AI Agent 执行 Issue 初步分析和分类的指令。

**核心职责**：
- 指导 AI Agent 判断报告的 Issue 是否有效
- 对 Issue 进行初步分析和分类
- 生成简洁、尊重的总结评论
- 帮助维护者快速筛选和处理 Issue

## 功能点目的

### 1. Issue 初步筛选
在维护者投入时间深入调查之前，快速评估 Issue：
- **有效性判断**：是否是真实的问题？是否有足够信息？
- **重复检测**：是否与已知问题重复？
- **分类建议**：应该分配给哪个组件或标签？

### 2. 降低维护负担
- 自动识别低质量或无效的 Issue
- 为有效 Issue 提供初步分析
- 生成标准化的回复模板

### 3. 提升响应速度
- 即时反馈报告者（即使只是确认收到）
- 快速标记需要更多信息的问题
- 加速有效问题的路由

## 具体技术实现

### 关键流程

```
GitHub Issue 被创建或标记 codex-triage
    ↓
触发 GitHub Action 工作流
    ↓
加载 .github/codex/labels/codex-triage.md 作为 prompt
    ↓
注入环境变量：
  - CODEX_ACTION_ISSUE_TITLE
  - CODEX_ACTION_ISSUE_BODY
    ↓
Codex AI 分析 Issue
    ↓
生成分类报告：
  - 有效性评估
  - 初步分析
  - 建议标签/分配
    ↓
发布评论到 Issue
```

### 数据结构

**模板变量**：
- `{CODEX_ACTION_ISSUE_TITLE}`: Issue 标题
- `{CODEX_ACTION_ISSUE_BODY}`: Issue 正文

**输出预期结构**（未在模板中明确定义，但可从上下文推断）：
```markdown
## 初步评估
- 有效性：[有效/无效/需要更多信息]
- 类型：[Bug/功能请求/问题/其他]
- 优先级建议：[高/中/低]

## 分析摘要
1-2 句话总结 Issue 核心内容

## 建议
- 标签建议：label1, label2
- 分配建议：@maintainer
- 后续行动：[需要报告者提供信息/可直接处理/需要讨论]
```

### 协议与命令

**依赖的 GitHub Action**：
- `openai/codex-action@main`: OpenAI 官方 Codex Action

**触发方式**：
- Issue 被标记 `codex-triage` 标签
- 可能还包括 Issue 创建时自动触发

**输出要求**：
- 简洁（concise）
- 尊重（respectful）
- Markdown 格式

## 关键代码路径与文件引用

### 直接相关文件
- **当前文件**: `.github/codex/labels/codex-triage.md` (177 bytes)
- **配置文件**: `.github/codex/home/config.toml`

### 相关标签文件对比

| 文件 | 大小 | 用途 | 复杂度 |
|------|------|------|--------|
| `codex-triage.md` | 177 bytes | Issue 分类 | 极简 |
| `codex-attempt.md` | 275 bytes | Issue 自动解决 | 简单 |
| `codex-review.md` | 443 bytes | PR 通用审查 | 中等 |
| `codex-rust-review.md` | 5951 bytes | Rust 深度审查 | 详细 |

### 相关工作流
- `.github/workflows/issue-labeler.yml` - Issue 自动标签
- `.github/workflows/issue-deduplicator.yml` - Issue 去重检测

**与去重工作流的关系**：
`issue-deduplicator.yml` 提供了更复杂的 Issue 分析流程（两阶段去重检测），而 `codex-triage.md` 专注于单个 Issue 的初步评估。两者可以互补：
1. `codex-triage` - 快速初步评估
2. `codex-deduplicate` - 深度去重分析

### 外部依赖
- `openai/codex-action@main` - GitHub Action 执行引擎
- GitHub API - 读取 Issue 和发布评论

## 依赖与外部交互

### 上游依赖
1. **GitHub Actions 平台** - 工作流执行
2. **openai/codex-action** - AI Agent 执行
3. **OpenAI API** - GPT 模型

### 下游交互
1. **GitHub Issues API** - 读取 Issue 详情
2. **GitHub Issues API** - 发布分类评论
3. **GitHub Labels API** - 可能自动添加标签

### 数据流
```
GitHub Issue Event
    ↓
提取 title 和 body
    ↓
注入 prompt 模板
    ↓
Codex AI 分析
    ↓
生成分类报告
    ↓
发布评论
    ↓
（可选）自动添加标签
```

## 风险、边界与改进建议

### 风险

1. **模板过于简洁**
   - 当前模板仅 177 bytes，是四个标签文件中最简短的
   - 可能缺乏足够的指导，导致 AI 输出不一致
   - 风险：不同运行产生质量差异较大的结果

2. **误判风险**
   - AI 可能错误地将有效 Issue 标记为无效
   - 可能误解技术细节导致错误分类
   - 建议：增加"不确定时标记为需要人工审查"的指导

3. **缺乏具体标准**
   - 没有定义什么是"有效"Issue 的具体标准
   - 缺少分类标签的映射关系
   - 建议：增加有效性检查清单

4. **与现有工作流重叠**
   - `issue-labeler.yml` 已经提供自动标签功能
   - `issue-deduplicator.yml` 提供去重功能
   - 需要明确 `codex-triage` 的独特价值

### 边界

1. **功能范围**
   - 仅做初步分类，不尝试解决问题
   - 与 `codex-attempt.md` 的区别：分析 vs 解决

2. **输出限制**
   - 要求"简洁"，可能限制详细分析
   - 不适合复杂 Issue 的深度评估

3. **触发依赖**
   - 需要人工标记标签才能触发
   - 无法自动识别需要分类的新 Issue

### 改进建议

1. **增加有效性检查清单**
   ```markdown
   ### 有效性检查清单
   评估 Issue 时检查以下方面：
   - [ ] 是否包含清晰的问题描述
   - [ ] 是否提供复现步骤（Bug 报告）
   - [ ] 是否说明期望行为 vs 实际行为
   - [ ] 是否包含环境信息（版本、操作系统等）
   - [ ] 是否已存在重复 Issue
   
   如果缺少必要信息，请礼貌地请求补充。
   ```

2. **增加分类标准**
   ```markdown
   ### 分类标准
   根据 Issue 内容，建议以下标签：
   - **类型**: bug / enhancement / question / documentation
   - **组件**: cli / extension / tui / core / docs
   - **优先级**: p0-critical / p1-high / p2-medium / p3-low
   - **状态**: needs-triage / needs-info / confirmed
   ```

3. **增加回复模板**
   ```markdown
   ### 回复模板
   
   **有效 Issue**：
   > 感谢报告！这个问题已被确认。我们将进一步调查，
   > 并建议标签：xxx，分配给：@maintainer
   
   **需要信息**：
   > 感谢报告！为了帮助我们更好地理解这个问题，
   > 能否请提供：1) ... 2) ... 3) ...
   
   **无效/重复**：
   > 感谢报告！这个问题似乎与 #123 重复，
   > 或者不是一个有效的问题，因为...
   ```

4. **与现有工作流整合**
   ```markdown
   ### 工作流程
   1. 首先检查是否与现有 Issue 重复（参考 codex-deduplicate 结果）
   2. 评估 Issue 质量和完整性
   3. 建议适当的标签
   4. 如果确定有效，可建议标记 codex-attempt 进行自动修复
   ```

5. **增加不确定性处理**
   ```markdown
   ### 不确定性处理
   如果不确定如何分类：
   - 标记为 `needs-triage` 等待人工审查
   - 不要猜测，承认不确定性
   - 建议维护者介入
   ```

6. **工作流配置建议**
   ```yaml
   # 建议创建 codex-triage.yml 工作流
   name: Codex Triage
   on:
     issues:
       types: [opened, labeled]
   
   jobs:
     triage:
       if: |
         github.event.action == 'opened' || 
         (github.event.action == 'labeled' && github.event.label.name == 'codex-triage')
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v6
         - uses: openai/codex-action@main
           with:
             openai-api-key: ${{ secrets.CODEX_OPENAI_API_KEY }}
             prompt: ${{ steps.load-prompt.outputs.content }}
         # 可选：自动应用建议的标签
         - name: Apply suggested labels
           run: |
             # 解析 AI 输出并应用标签
   ```

7. **与 codex-deduplicate 的协作**
   - 建议在 `codex-triage` 流程中先运行去重检测
   - 如果检测到重复，直接引用重复 Issue
   - 避免重复分析已知问题

---

**文件元数据**
- 路径: `.github/codex/labels/codex-triage.md`
- 大小: 177 bytes（四个标签文件中最小）
- 最后修改: 2025-03-19
- 关联系统: GitHub Actions + OpenAI Codex + Issue 管理
- 相关工作流: issue-labeler.yml, issue-deduplicator.yml
