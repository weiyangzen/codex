# prompts.rs - 研究文档

## 场景与职责

`prompts.rs` 模块负责构建记忆系统使用的各种提示模板。它使用 Askama 模板引擎将动态数据渲染到预定义的 Markdown 模板中。

### 核心职责

1. **整合提示构建**: 为 Phase 2 整合子代理构建完整提示
2. **Stage 1 输入构建**: 为 Phase 1 模型构建用户输入消息
3. **开发者指令构建**: 为记忆工具构建开发者指令
4. **模板渲染**: 使用 Askama 模板引擎渲染模板

## 功能点目的

### 模板结构

```rust
// 整合提示模板
#[derive(Template)]
#[template(path = "memories/consolidation.md", escape = "none")]
struct ConsolidationPromptTemplate<'a> {
    memory_root: &'a str,
    phase2_input_selection: &'a str,
}

// Stage 1 输入模板
#[derive(Template)]
#[template(path = "memories/stage_one_input.md", escape = "none")]
struct StageOneInputTemplate<'a> {
    rollout_path: &'a str,
    rollout_cwd: &'a str,
    rollout_contents: &'a str,
}

// 记忆工具开发者指令模板
#[derive(Template)]
#[template(path = "memories/read_path.md", escape = "none")]
struct MemoryToolDeveloperInstructionsTemplate<'a> {
    base_path: &'a str,
    memory_summary: &'a str,
}
```

### 主要函数

#### 1. `build_consolidation_prompt`

**目的**: 构建 Phase 2 整合子代理的完整提示

**输入**:
- `memory_root`: 记忆根目录路径
- `selection`: Phase 2 输入选择（包含当前选择、之前选择、保留/添加/移除信息）

**输出**: 渲染后的提示字符串

**实现**:
```rust
pub(super) fn build_consolidation_prompt(
    memory_root: &Path,
    selection: &Phase2InputSelection,
) -> String {
    let memory_root = memory_root.display().to_string();
    let phase2_input_selection = render_phase2_input_selection(selection);
    let template = ConsolidationPromptTemplate {
        memory_root: &memory_root,
        phase2_input_selection: &phase2_input_selection,
    };
    template.render().unwrap_or_else(|err| {
        warn!("failed to render memories consolidation prompt template: {err}");
        // 回退到简单格式
        format!("## Memory Phase 2 (Consolidation)\nConsolidate Codex memories in: {memory_root}\n\n{phase2_input_selection}")
    })
}
```

#### 2. `render_phase2_input_selection`

**目的**: 渲染 Phase 2 输入选择的 diff 摘要

**输出格式**:
```markdown
- selected inputs this run: {n}
- newly added since the last successful Phase 2 run: {added}
- retained from the last successful Phase 2 run: {retained}
- removed from the last successful Phase 2 run: {removed}

Current selected Phase 1 inputs:
- [added/retained] thread_id={id}, rollout_summary_file={file}
...

Removed from the last successful Phase 2 selection:
- thread_id={id}, rollout_summary_file={file}
...
```

**实现**:
```rust
fn render_phase2_input_selection(selection: &Phase2InputSelection) -> String {
    let retained = selection.retained_thread_ids.len();
    let added = selection.selected.len().saturating_sub(retained);
    
    let selected = if selection.selected.is_empty() {
        "- none".to_string()
    } else {
        selection.selected.iter()
            .map(|item| render_selected_input_line(item, selection.retained_thread_ids.contains(&item.thread_id)))
            .collect::<Vec<_>>()
            .join("\n")
    };
    
    let removed = if selection.removed.is_empty() {
        "- none".to_string()
    } else {
        selection.removed.iter()
            .map(render_removed_input_line)
            .collect::<Vec<_>>()
            .join("\n")
    };

    format!("...", selection.selected.len(), added, retained, selection.removed.len(), selected, removed)
}

fn render_selected_input_line(item: &Stage1Output, retained: bool) -> String {
    let status = if retained { "retained" } else { "added" };
    let rollout_summary_file = format!("rollout_summaries/{}.md", rollout_summary_file_stem_from_parts(...));
    format!("- [{status}] thread_id={}, rollout_summary_file={rollout_summary_file}", item.thread_id)
}

fn render_removed_input_line(item: &Stage1OutputRef) -> String {
    let rollout_summary_file = format!("rollout_summaries/{}.md", rollout_summary_file_stem_from_parts(...));
    format!("- thread_id={}, rollout_summary_file={rollout_summary_file}", item.thread_id)
}
```

#### 3. `build_stage_one_input_message`

**目的**: 构建 Phase 1 的用户输入消息，包含 rollout 元数据和内容

**特点**:
- 根据模型上下文窗口自动截断内容
- 保留头部和尾部上下文（中间截断）

**实现**:
```rust
pub(super) fn build_stage_one_input_message(
    model_info: &ModelInfo,
    rollout_path: &Path,
    rollout_cwd: &Path,
    rollout_contents: &str,
) -> anyhow::Result<String> {
    // 计算 token 限制
    let rollout_token_limit = model_info
        .context_window
        .and_then(|limit| (limit > 0).then_some(limit))
        .map(|limit| limit.saturating_mul(model_info.effective_context_window_percent) / 100)
        .map(|limit| (limit.saturating_mul(phase_one::CONTEXT_WINDOW_PERCENT) / 100).max(1))
        .and_then(|limit| usize::try_from(limit).ok())
        .unwrap_or(phase_one::DEFAULT_STAGE_ONE_ROLLOUT_TOKEN_LIMIT);
    
    // 截断内容
    let truncated_rollout_contents = truncate_text(
        rollout_contents,
        TruncationPolicy::Tokens(rollout_token_limit),
    );

    // 渲染模板
    let rollout_path = rollout_path.display().to_string();
    let rollout_cwd = rollout_cwd.display().to_string();
    Ok(StageOneInputTemplate {
        rollout_path: &rollout_path,
        rollout_cwd: &rollout_cwd,
        rollout_contents: &truncated_rollout_contents,
    }.render()?)
}
```

#### 4. `build_memory_tool_developer_instructions`

**目的**: 构建记忆工具的开发者指令

**特点**:
- 异步读取 `memory_summary.md`
- 截断至 5000 tokens
- 如果摘要为空则返回 None

**实现**:
```rust
pub(crate) async fn build_memory_tool_developer_instructions(codex_home: &Path) -> Option<String> {
    let base_path = memory_root(codex_home);
    let memory_summary_path = base_path.join("memory_summary.md");
    let memory_summary = fs::read_to_string(&memory_summary_path).await.ok()?.trim().to_string();
    
    let memory_summary = truncate_text(
        &memory_summary,
        TruncationPolicy::Tokens(phase_one::MEMORY_TOOL_DEVELOPER_INSTRUCTIONS_SUMMARY_TOKEN_LIMIT),
    );
    
    if memory_summary.is_empty() {
        return None;
    }
    
    let base_path = base_path.display().to_string();
    let template = MemoryToolDeveloperInstructionsTemplate {
        base_path: &base_path,
        memory_summary: &memory_summary,
    };
    template.render().ok()
}
```

## 关键代码路径与文件引用

### 模板文件位置

| 模板 | 文件路径 | 用途 |
|------|----------|------|
| `consolidation.md` | `codex-rs/core/templates/memories/consolidation.md` | Phase 2 整合提示 |
| `stage_one_input.md` | `codex-rs/core/templates/memories/stage_one_input.md` | Phase 1 输入 |
| `stage_one_system.md` | `codex-rs/core/templates/memories/stage_one_system.md` | Phase 1 系统提示（在 mod.rs 中加载） |
| `read_path.md` | `codex-rs/core/templates/memories/read_path.md` | 记忆工具指令 |

### 函数映射

| 函数 | 行号 | 描述 |
|------|------|------|
| `build_consolidation_prompt` | 38 | 整合提示构建 |
| `render_phase2_input_selection` | 56 | 选择 diff 渲染 |
| `render_selected_input_line` | 92 | 选中项渲染 |
| `render_removed_input_line` | 108 | 移除项渲染 |
| `build_stage_one_input_message` | 127 | Stage 1 输入构建 |
| `build_memory_tool_developer_instructions` | 158 | 开发者指令构建 |

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::memories::memory_root` | 记忆根路径 |
| `crate::memories::phase_one` | Phase 1 常量 |
| `crate::memories::storage::rollout_summary_file_stem_from_parts` | 文件名生成 |
| `crate::truncate::TruncationPolicy` | 截断策略 |
| `crate::truncate::truncate_text` | 文本截断 |
| `codex_protocol::openai_models::ModelInfo` | 模型信息 |
| `codex_state::Phase2InputSelection` | 选择数据 |
| `codex_state::Stage1Output` | 输出数据 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `askama::Template` | 模板引擎 |
| `tokio::fs` | 异步文件读取 |
| `tracing::warn` | 警告日志 |

## 风险、边界与改进建议

### 已知风险

1. **模板渲染失败**:
   - 使用 `unwrap_or_else` 提供回退，但回退格式可能不完整
   - 没有记录渲染失败的具体原因

2. **文件读取失败**:
   - `build_memory_tool_developer_instructions` 使用 `.ok()` 静默忽略错误
   - 无法区分文件不存在和读取权限问题

3. **截断策略**:
   - 截断可能导致重要信息丢失
   - 当前策略保留头尾，但中间信息可能关键

### 边界条件

1. **空选择**: `render_phase2_input_selection` 处理空选择为 "- none"
2. **空摘要**: `build_memory_tool_developer_instructions` 返回 None
3. **超大内容**: 受 token 限制截断
4. **无效路径**: 依赖调用方提供有效路径

### 改进建议

1. **错误处理增强**:
```rust
// 使用 Result 而非 Option
pub(crate) async fn build_memory_tool_developer_instructions(
    codex_home: &Path
) -> Result<Option<String>, MemoryPromptError> {
    // 区分不同错误类型
}
```

2. **模板验证**:
   - 在编译时验证模板存在
   - 添加模板版本控制

3. **截断策略配置**:
   - 支持不同的截断策略（头优先、尾优先、中间截断）
   - 根据内容类型选择策略

4. **缓存机制**:
   - 缓存已渲染的模板
   - 避免重复 I/O 和渲染

5. **测试覆盖**:
   - 添加模板渲染测试
   - 添加截断边界测试
