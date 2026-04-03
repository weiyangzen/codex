# codex-attempt.md 深度研究文档

## 场景与职责

`codex-attempt.md` 是 OpenAI Codex 项目的 GitHub Action 自动化工作流中使用的提示词模板文件，位于 `.github/codex/labels/` 目录下。该文件定义了当 GitHub Issue 被标记为 `codex-attempt` 标签时，Codex AI Agent 应该执行的任务和遵循的指令。

**核心职责**：
- 指导 AI Agent 尝试解决报告的 Issue
- 在需要代码变更时，创建新分支、提交修复并打开 Pull Request
- 提供原始 Issue 的上下文信息（标题和正文）

## 功能点目的

### 1. 自动化 Issue 解决流程
当社区成员或维护者给 Issue 打上 `codex-attempt` 标签时，触发 GitHub Action 工作流，Codex AI 将：
- 分析 Issue 描述，理解问题本质
- 探索代码库，定位相关问题根源
- 尝试实现修复方案
- 创建 PR 并关联到原 Issue

### 2. 标准化提示词模板
通过模板变量 `{CODEX_ACTION_ISSUE_TITLE}` 和 `{CODEX_ACTION_ISSUE_BODY}`，将具体的 Issue 内容注入到提示词中，使 AI 获得完整的上下文。

## 具体技术实现

### 关键流程

```
GitHub Issue 被标记 codex-attempt
    ↓
触发 GitHub Action 工作流 (openai/codex-action@main)
    ↓
读取 .github/codex/labels/codex-attempt.md 作为 prompt
    ↓
注入环境变量 CODEX_ACTION_ISSUE_TITLE 和 CODEX_ACTION_ISSUE_BODY
    ↓
Codex AI 分析问题并尝试解决
    ↓
如需代码变更 → 创建分支 → 提交修复 → 打开 PR
```

### 数据结构

**模板变量**：
- `{CODEX_ACTION_ISSUE_TITLE}`: 触发工作流的 Issue 标题
- `{CODEX_ACTION_ISSUE_BODY}`: 触发工作流的 Issue 正文内容

**环境变量来源**：
这些变量由 `openai/codex-action` GitHub Action 自动从 GitHub Event Payload 中提取并注入。

### 协议与命令

**依赖的 GitHub Action**：
- `openai/codex-action@main`: OpenAI 官方 Codex Action，负责运行 AI Agent

**所需权限**：
- `contents: write` - 创建分支和提交代码
- `pull-requests: write` - 创建 Pull Request

**配置参数**（在调用工作流中设置）：
```yaml
with:
  openai-api-key: ${{ secrets.CODEX_OPENAI_API_KEY }}
  allow-users: "*"
  prompt: ${{ steps.load-prompt.outputs.content }}
```

## 关键代码路径与文件引用

### 直接相关文件
- **当前文件**: `.github/codex/labels/codex-attempt.md`
- **配置文件**: `.github/codex/home/config.toml` - 定义 AI 模型配置（gpt-5.1）

### 相关标签文件
- `.github/codex/labels/codex-review.md` - PR 审查提示词
- `.github/codex/labels/codex-rust-review.md` - Rust 专用 PR 审查提示词
- `.github/codex/labels/codex-triage.md` - Issue 分类提示词

### 工作流参考
- `.github/workflows/issue-labeler.yml` - Issue 自动标签工作流（使用相同 codex-action）
- `.github/workflows/issue-deduplicator.yml` - Issue 去重工作流

### 外部依赖
- `openai/codex-action@main` - GitHub Action 仓库
- GitHub Secrets: `CODEX_OPENAI_API_KEY`

## 依赖与外部交互

### 上游依赖
1. **GitHub Actions 平台** - 工作流执行环境
2. **openai/codex-action** - AI Agent 执行引擎
3. **OpenAI API** - 提供 GPT 模型能力

### 下游交互
1. **GitHub Issues API** - 读取 Issue 内容
2. **GitHub Git API** - 创建分支和提交
3. **GitHub Pull Requests API** - 创建 PR

### 配置依赖
```toml
# .github/codex/home/config.toml
model = "gpt-5.1"
```

## 风险、边界与改进建议

### 风险

1. **权限风险**
   - AI 自动创建分支和 PR 需要写权限，可能存在安全风险
   - 建议：限制 `allow-users` 配置，只允许特定用户触发

2. **代码质量风险**
   - AI 生成的代码可能未经充分测试
   - 建议：强制要求 CI 检查通过后才能合并

3. **API 成本风险**
   - 复杂 Issue 可能消耗大量 Token
   - 建议：设置超时和 Token 限制

4. **上下文限制**
   - 当前模板仅提供 Issue 标题和正文，缺少代码库上下文
   - 建议：增加相关文件路径或标签信息

### 边界

1. **触发条件**
   - 仅当 Issue 被标记 `codex-attempt` 时触发
   - 不会自动处理未标记的 Issue

2. **执行范围**
   - 仅限于当前仓库
   - 不处理跨仓库依赖问题

3. **模板变量**
   - 仅支持 `CODEX_ACTION_ISSUE_TITLE` 和 `CODEX_ACTION_ISSUE_BODY`
   - 缺少 Issue 标签、作者、创建时间等元数据

### 改进建议

1. **增强上下文**
   ```markdown
   ### 附加信息
   - Issue 作者: {CODEX_ACTION_ISSUE_AUTHOR}
   - 创建时间: {CODEX_ACTION_ISSUE_CREATED_AT}
   - 标签: {CODEX_ACTION_ISSUE_LABELS}
   - 相关文件（如有）: {CODEX_ACTION_ISSUE_MENTIONED_FILES}
   ```

2. **增加约束条件**
   ```markdown
   ### 约束条件
   - 仅修改与 Issue 直接相关的文件
   - 保持现有代码风格
   - 确保所有测试通过
   - 如果问题无法解决，请说明原因并请求人工介入
   ```

3. **添加测试要求**
   ```markdown
   ### 测试要求
   - 如可能，为修复添加单元测试
   - 运行现有测试套件确保无回归
   - 在 PR 描述中说明测试覆盖情况
   ```

4. **工作流集成**
   - 建议创建专门的 `codex-attempt.yml` 工作流文件
   - 集成 CI 检查，确保 AI 生成的 PR 通过自动化测试
   - 添加人工审查门槛，防止自动合并

---

**文件元数据**
- 路径: `.github/codex/labels/codex-attempt.md`
- 大小: 275 bytes
- 最后修改: 2025-03-19
- 关联系统: GitHub Actions + OpenAI Codex
