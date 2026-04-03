# codex-rs/core/gpt-5.1-codex-max_prompt.md 研究文档

## 场景与职责

`gpt-5.1-codex-max_prompt.md` 是 Codex CLI 中 GPT-5.1-codex-max 模型的系统提示词（System Prompt）文件。该文件定义了 AI 编程助手的行为准则、编辑约束、工具使用规范以及与用户交互的风格指南。

该提示词在以下场景使用：
- 用户选择 `gpt-5.1-codex-max` 模型时
- 作为 `developer` 角色的消息注入到对话上下文
- 指导模型如何执行代码编辑、文件操作和工具调用

## 功能点目的

### 1. 身份定义

```markdown
You are Codex, based on GPT-5. You are running as a coding agent in the Codex CLI on a user's computer.
```

- **模型身份**：基于 GPT-5 的 Codex
- **运行环境**：Codex CLI（命令行界面）
- **角色定位**：编码代理（coding agent）

### 2. 通用准则 (General)

#### 2.1 搜索工具偏好

```markdown
- When searching for text or files, prefer using `rg` or `rg --files` respectively because `rg` is much faster than alternatives like `grep`.
```

- **推荐工具**：`rg` (ripgrep)
- **原因**：性能优于 `grep`
- **回退**：如果 `rg` 不可用，使用替代方案

### 3. 编辑约束 (Editing constraints)

#### 3.1 字符编码

```markdown
- Default to ASCII when editing or creating files. Only introduce non-ASCII or other Unicode characters when there is a clear justification and the file already uses them.
```

- **默认编码**：ASCII
- **例外条件**：
  - 有明确理由
  - 文件已使用非 ASCII 字符

#### 3.2 代码注释

```markdown
- Add succinct code comments that explain what is going on if code is not self-explanatory. You should not add comments like "Assigns the value to the variable", but a brief comment might be useful ahead of a complex code block...
```

- **注释风格**：简洁、解释性
- **避免**：显而易见的注释（如 "Assigns the value to the variable"）
- **适用场景**：复杂代码块前

#### 3.3 编辑工具选择

```markdown
- Try to use apply_patch for single file edits, but it is fine to explore other options to make the edit if it does not work well.
```

- **首选工具**：`apply_patch`（单文件编辑）
- **灵活性**：如果效果不好，可以探索其他选项

#### 3.4 自动化命令限制

```markdown
- Do not use apply_patch for changes that are auto-generated (i.e. generating package.json or running a lint or format command like gofmt) or when scripting is more efficient (such as search and replacing a string across a codebase).
```

- **不使用 apply_patch 的场景**：
  - 自动生成文件（如 `package.json`）
  - 运行 lint/format 命令（如 `gofmt`）
  - 跨代码库的搜索替换更高效时

#### 3.5 Git 工作树处理

```markdown
- You may be in a dirty git worktree.
    * NEVER revert existing changes you did not make unless explicitly requested...
    * If asked to make a commit or code edits and there are unrelated changes...
```

- **核心原则**：不主动回滚未请求的更改
- **具体规则**：
  - 绝不回滚非自己做出的更改（除非明确请求）
  - 提交时保留不相关的更改
  - 仔细阅读最近修改的文件，理解如何配合工作
  - 忽略不相关文件的更改

#### 3.6 提交规范

```markdown
- Do not amend a commit unless explicitly requested to do so.
```

- 不主动修改提交（`git commit --amend`）

#### 3.7 意外更改处理

```markdown
- While you are working, you might notice unexpected changes that you didn't make. If this happens, STOP IMMEDIATELY and ask the user how they would like to proceed.
```

- **安全措施**：发现意外更改立即停止
- **处理方式**：询问用户如何继续

#### 3.8 破坏性命令禁用

```markdown
- **NEVER** use destructive commands like `git reset --hard` or `git checkout --` unless specifically requested or approved by the user.
```

- **禁止命令**：`git reset --hard`, `git checkout --`
- **例外**：用户明确请求或批准

### 4. 计划工具 (Plan tool)

```markdown
When using the planning tool:
- Skip using the planning tool for straightforward tasks (roughly the easiest 25%).
- Do not make single-step plans.
- When you made a plan, update it after having performed one of the sub-tasks...
```

- **使用门槛**：跳过最简单的 25% 任务
- **计划复杂度**：不做单步计划
- **计划维护**：执行子任务后更新计划

### 5. 特殊用户请求 (Special user requests)

#### 5.1 简单请求

```markdown
- If the user makes a simple request (such as asking for the time) which you can fulfill by running a terminal command (such as `date`), you should do so.
```

- 简单请求（如询问时间）直接执行命令

#### 5.2 代码审查

```markdown
- If the user asks for a "review", default to a code review mindset: prioritise identifying bugs, risks, behavioural regressions, and missing tests.
```

- **审查重点**：Bug、风险、行为回归、缺失测试
- **输出结构**：
  1. 发现项（按严重性排序，带文件/行引用）
  2. 开放问题或假设
  3. 变更摘要（次要）

### 6. 前端任务 (Frontend tasks)

#### 6.1 设计原则

```markdown
When doing frontend design tasks, avoid collapsing into "AI slop" or safe, average-looking layouts.
Aim for interfaces that feel intentional, bold, and a bit surprising.
```

- **避免**："AI slop"（平庸、安全的布局）
- **追求**：有意图、大胆、令人惊喜的界面

#### 6.2 具体指南

| 方面 | 要求 |
|------|------|
| 排版 | 使用有表现力的字体，避免默认栈（Inter, Roboto, Arial） |
| 颜色 | 清晰的视觉方向，定义 CSS 变量，避免紫/白默认 |
| 动画 | 有意义的动画（页面加载、交错显示），而非通用微动效 |
| 背景 | 不使用单一颜色，使用渐变、形状或微妙图案 |
| 整体 | 避免样板布局，跨输出变化主题和视觉语言 |
| 响应式 | 确保桌面和移动端正确加载 |

#### 6.3 例外

```markdown
Exception: If working within an existing website or design system, preserve the established patterns, structure, and visual language.
```

- 在现有网站或设计系统中工作时，保持既定模式

### 7. 工作呈现与最终消息

#### 7.1 格式规则

```markdown
- Default: be very concise; friendly coding teammate tone.
- Ask only when needed; suggest ideas; mirror the user's style.
- For substantial work, summarize clearly; follow final‑answer formatting.
- Skip heavy formatting for simple confirmations.
- Don't dump large files you've written; reference paths only.
- No "save/copy this file" - User is on the same machine.
```

- **默认风格**：非常简洁，友好的队友语气
- **提问策略**：只在需要时提问
- **工作呈现**：引用路径而非转储大文件
- **假设**：用户在同一台机器上

#### 7.2 代码变更说明

```markdown
- Lead with a quick explanation of the change, and then give more details on the context covering where and why a change was made.
- If there are natural next steps the user may want to take, suggest them at the end...
```

- 先快速解释变更
- 然后提供上下文（在哪里、为什么做变更）
- 建议自然的后续步骤

#### 7.3 最终答案结构

```markdown
- Plain text; CLI handles styling. Use structure only when it helps scanability.
- Headers: optional; short Title Case (1-3 words) wrapped in **…**...
- Bullets: use - ; merge related points; keep to one line when possible...
```

- **纯文本**：CLI 处理样式
- **标题**：可选，1-3 个词，Title Case，`**标题**`
- **列表**：使用 `-`，合并相关点，每行一个
- **等宽**：反引号用于命令/路径/代码
- **代码块**：围栏代码块，带 info string

#### 7.4 文件引用规则

```markdown
- Use inline code to make file paths clickable.
- Each reference should have a stand alone path...
- Accepted: absolute, workspace‑relative, a/ or b/ diff prefixes, or bare filename/suffix.
- Optionally include line/column (1‑based): :line[:column] or #Lline[Ccolumn]
- Do not use URIs like file://, vscode://, or https://.
- Do not provide range of lines
```

- **可点击路径**：使用行内代码
- **独立路径**：即使同一文件重复引用也要完整
- **格式示例**：
  - `src/app.ts`
  - `src/app.ts:42`
  - `b/server/index.js#L10`
  - `C:\repo\project\main.rs:12:5`
- **禁止**：URI 格式（`file://`, `vscode://`）
- **禁止**：行范围

## 关键代码路径与文件引用

### 提示词加载

| 文件 | 用途 |
|------|------|
| `src/instructions/mod.rs` | 指令系统入口 |
| `src/instructions/user_instructions.rs` | 用户指令加载 |
| `src/custom_prompts.rs` | 自定义提示处理 |
| `src/models_manager/` | 模型管理和提示选择 |

### 提示词模板

| 模板 | 路径 |
|------|------|
| 默认提示 | `prompt.md` |
| gpt-5.1-codex-max | `gpt-5.1-codex-max_prompt.md` |
| 协作模式模板 | `templates/collaboration_mode/` |

### 相关配置

```rust
// src/config/mod.rs
pub struct Config {
    pub model_instructions_file: Option<PathBuf>, // 覆盖内置指令
    pub base_instructions: Option<String>,        // 基础指令覆盖
    pub developer_instructions: Option<String>,   // 开发者指令覆盖
}
```

## 依赖与外部交互

### 提示词注入流程

```
用户选择模型
    ↓
models_manager 查找对应提示文件
    ↓
加载 gpt-5.1-codex-max_prompt.md
    ↓
与 AGENTS.md（项目指令）合并
    ↓
作为 developer 消息注入上下文
    ↓
发送给 OpenAI API
```

### 配置覆盖

| 配置项 | 说明 |
|--------|------|
| `model_instructions_file` | 完全替换内置提示 |
| `base_instructions` | 覆盖基础指令 |
| `developer_instructions` | 作为独立 developer 消息注入 |

### 相关文件

| 文件 | 关系 |
|------|------|
| `AGENTS.md` | 项目级指令，追加到系统提示 |
| `prompt.md` | 默认提示词 |
| `config.toml` | 用户配置，可指定指令覆盖 |

## 风险、边界与改进建议

### 维护风险

1. **提示词版本同步**：
   - 模型更新时可能需要调整提示词
   - 多个模型有各自的提示文件，需要分别维护

2. **指令冲突**：
   - 系统提示 + 项目 AGENTS.md + 用户覆盖
   - 可能出现矛盾指令

3. **长度限制**：
   - 系统提示占用上下文窗口
   - 需要平衡详细度和 token 效率

### 边界情况

1. **模型特定行为**：
   - 此提示针对 GPT-5.1-codex-max 优化
   - 其他模型可能需要不同提示

2. **工具可用性**：
   - 提示中提到的工具（如 `apply_patch`）可能因配置禁用
   - 模型需要处理工具不可用的情况

3. **前端任务检测**：
   - 提示要求检测前端任务并应用设计原则
   - 自动检测可能不准确

### 改进建议

1. **提示词版本化**：
   ```markdown
   <!-- 在文件顶部添加版本注释 -->
   <!-- Version: 1.2.3 -->
   <!-- Model: gpt-5.1-codex-max -->
   <!-- Last updated: 2026-03-23 -->
   ```

2. **模块化提示词**：
   - 将通用部分（编辑约束、Git 处理）提取为共享模块
   - 模型特定提示只包含差异部分

3. **动态指令**：
   - 根据启用的工具动态调整提示
   - 例如：如果 `apply_patch` 禁用，移除相关指令

4. **A/B 测试框架**：
   - 建立提示词效果评估机制
   - 跟踪不同提示版本的任务完成率

5. **用户自定义扩展**：
   - 提供钩子让用户在标准提示后追加指令
   - 而非完全替换（当前 `model_instructions_file` 行为）

6. **多语言支持**：
   - 当前提示为英文
   - 考虑为不同语言用户提供本地化提示

7. **指令优先级文档**：
   - 明确说明系统提示、AGENTS.md、用户覆盖的优先级
   - 帮助用户理解配置效果
