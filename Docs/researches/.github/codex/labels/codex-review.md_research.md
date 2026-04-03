# codex-review.md 深度研究文档

## 场景与职责

`codex-review.md` 是 OpenAI Codex 项目的 GitHub Action 自动化代码审查提示词模板，位于 `.github/codex/labels/` 目录下。当 Pull Request 被标记为 `codex-review` 标签时，该文件定义了 Codex AI Agent 执行代码审查的指令和行为规范。

**核心职责**：
- 指导 AI Agent 对 PR 进行代码审查
- 生成简洁的 Markdown 格式审查报告
- 提供变更摘要（1-2 句话）和审查意见（1-2 句话加要点）
- 通过 GitHub API 发布审查评论

## 功能点目的

### 1. 自动化代码审查
为项目提供一致的、AI 驱动的代码审查能力：
- **变更摘要**：快速理解 PR 的核心改动
- **友好审查**：以建设性语气提供反馈
- **格式规范**：标准化的 Markdown 输出

### 2. 审查触发机制
通过 GitHub Label 机制灵活控制审查时机：
- 维护者可选择性标记需要 AI 审查的 PR
- 避免对所有 PR 都执行 AI 审查（节省成本）
- 可作为人工审查的补充或预审

### 3. 上下文感知
通过 `{CODEX_ACTION_GITHUB_EVENT_PATH}` 变量获取完整的 GitHub Webhook 事件数据，包括：
- `base` 和 `head` refs：定义 PR 的代码范围
- PR 标题、描述、作者信息
- 变更文件列表
- 评论和审查历史

## 具体技术实现

### 关键流程

```
Pull Request 被标记 codex-review
    ↓
触发 GitHub Action 工作流
    ↓
加载 .github/codex/labels/codex-review.md 作为 prompt
    ↓
注入 CODEX_ACTION_GITHUB_EVENT_PATH 环境变量
    ↓
Codex AI 读取 GitHub Event JSON 文件
    ↓
分析 base..head 之间的代码变更
    ↓
生成审查报告（摘要 + 审查意见）
    ↓
发布评论到 PR
```

### 数据结构

**模板变量**：
- `{CODEX_ACTION_GITHUB_EVENT_PATH}`: GitHub Event JSON 文件的文件系统路径

**GitHub Event Payload 关键字段**：
```json
{
  "pull_request": {
    "base": {
      "ref": "main",
      "sha": "abc123..."
    },
    "head": {
      "ref": "feature-branch",
      "sha": "def456..."
    },
    "title": "PR 标题",
    "body": "PR 描述",
    "changed_files": 3,
    "additions": 100,
    "deletions": 50
  }
}
```

### 协议与命令

**依赖的 GitHub Action**：
- `openai/codex-action@main`: OpenAI 官方 Codex Action

**输出格式规范**：
```markdown
## 摘要
1-2 句话描述变更内容

## 审查
1-2 句话总体评价，友好语气

- 要点 1：具体建议
- 要点 2：改进建议
- 要点 3：可选的表扬
```

**Git 操作**：
- `git diff base..head` - 获取变更内容
- `git show` - 查看具体提交详情

## 关键代码路径与文件引用

### 直接相关文件
- **当前文件**: `.github/codex/labels/codex-review.md`
- **配置文件**: `.github/codex/home/config.toml`

### 相关标签文件（同目录）
| 文件 | 用途 | 大小 |
|------|------|------|
| `codex-attempt.md` | 自动解决 Issue | 275 bytes |
| `codex-rust-review.md` | Rust 专用审查（详细版） | 5951 bytes |
| `codex-triage.md` | Issue 分类 | 177 bytes |

### 工作流参考
- `.github/workflows/issue-labeler.yml` - 使用相同 codex-action 的示例
- `.github/workflows/issue-deduplicator.yml` - 复杂工作流示例

### 外部依赖
- `openai/codex-action@main` - GitHub Action 执行引擎
- GitHub API - 读取 PR 数据和发布评论
- Git - 获取代码变更

## 依赖与外部交互

### 上游依赖
1. **GitHub Actions 平台** - 工作流执行环境
2. **openai/codex-action** - AI Agent 执行引擎
3. **OpenAI API** - GPT 模型服务

### 下游交互
1. **GitHub Pull Request API** - 读取 PR 详情和变更
2. **GitHub Issues API** - 发布审查评论
3. **Git 仓库** - 获取代码差异

### 数据流
```
GitHub Webhook Event
    ↓
写入文件系统 → CODEX_ACTION_GITHUB_EVENT_PATH
    ↓
Codex AI 读取并解析 JSON
    ↓
提取 base/head refs
    ↓
执行 git diff 获取变更
    ↓
生成审查报告
    ↓
调用 GitHub API 发布评论
```

## 风险、边界与改进建议

### 风险

1. **审查质量不一致**
   - AI 审查可能遗漏关键问题
   - 不同模型版本可能产生不同质量的审查
   - 建议：作为人工审查的补充，而非替代

2. **Token 成本**
   - 大型 PR 的 diff 可能非常长
   - 建议：设置 diff 大小限制，超大 PR 跳过或分段处理

3. **安全风险**
   - AI 可能无法识别所有安全漏洞
   - 建议：敏感代码变更仍需人工安全审查

4. **误报/漏报**
   - 可能产生不必要的审查意见
   - 可能遗漏架构层面的问题
   - 建议：明确 AI 审查的适用范围

### 边界

1. **通用性限制**
   - 当前模板是通用版本，无语言特定指导
   - 对比 `codex-rust-review.md`（5951 bytes）的详细程度，本文件较为简略

2. **输出格式约束**
   - 强制要求简洁输出（1-2 句话）
   - 可能无法充分表达复杂审查意见

3. **触发机制**
   - 依赖人工标记标签
   - 无法自动识别需要审查的 PR

### 改进建议

1. **增加审查维度**
   ```markdown
   ## 审查维度
   请从以下方面进行审查：
   - 代码正确性：逻辑是否正确，边界条件是否处理
   - 代码风格：是否符合项目规范
   - 测试覆盖：是否包含足够的测试
   - 文档：是否需要更新文档
   - 性能：是否有明显的性能问题
   ```

2. **增加语言检测**
   ```markdown
   ## 语言特定审查
   根据变更文件的语言类型，应用相应的审查标准：
   - Rust 文件 → 参考 codex-rust-review.md 的审查标准
   - TypeScript/JavaScript → 检查类型安全和异步处理
   - Python → 检查类型注解和异常处理
   ```

3. **增加严重性分级**
   ```markdown
   ## 严重程度标记
   请为每条审查意见标记严重程度：
   - 🔴 **阻塞**：必须修复才能合并
   - 🟡 **建议**：推荐修复，但非强制
   - 🟢 **提示**：信息性反馈，供参考
   ```

4. **与 codex-rust-review.md 的关系优化**
   - 当前项目有两个审查模板：通用版（本文件）和 Rust 专用版
   - 建议：在通用模板中增加检测逻辑，如果 PR 主要涉及 Rust 代码，自动引用 Rust 专用审查标准
   - 或合并为一个模板，根据文件类型动态调整审查深度

5. **增加审查历史感知**
   ```markdown
   ## 审查历史
   请检查 PR 是否已有其他审查意见：
   - 如果已有类似反馈，避免重复
   - 如果作者已回应之前的问题，确认是否已解决
   ```

6. **工作流建议**
   ```yaml
   # 建议创建 codex-review.yml 工作流
   name: Codex Review
   on:
     pull_request:
       types: [labeled]
   
   jobs:
     review:
       if: github.event.label.name == 'codex-review'
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v6
           with:
             fetch-depth: 0  # 需要完整历史进行 diff
         - uses: openai/codex-action@main
           with:
             openai-api-key: ${{ secrets.CODEX_OPENAI_API_KEY }}
             prompt: ${{ steps.load-prompt.outputs.content }}
   ```

---

**文件元数据**
- 路径: `.github/codex/labels/codex-review.md`
- 大小: 443 bytes
- 最后修改: 2025-03-19
- 关联系统: GitHub Actions + OpenAI Codex + PR Review
