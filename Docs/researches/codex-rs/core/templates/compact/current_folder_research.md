# Codex-RS Core Templates Compact 深度研究文档

## 1. 场景与职责

### 1.1 目录定位
`codex-rs/core/templates/compact/` 是 Codex CLI 核心库中的**上下文压缩（Context Compaction）提示模板目录**，负责存放用于对话历史摘要生成的 LLM 提示词模板。

### 1.2 核心职责
该目录服务于**上下文窗口管理**这一关键系统功能：

1. **对话历史压缩**：当对话历史超过模型上下文窗口限制时，将冗长的多轮对话压缩为简洁的摘要
2. **跨会话状态传递**：支持将压缩后的摘要作为"交接文档"，使新的 LLM 实例能够无缝继续任务
3. **内存优化**：通过摘要替换原始历史，显著减少 token 消耗，延长有效对话长度

### 1.3 业务场景
- **自动压缩**：当 `model_auto_compact_token_limit` 配置的阈值被触发时自动执行
- **手动压缩**：用户通过 `/compact` 命令主动触发
- **预采样压缩**：在模型切换前执行的压缩，确保新模型获得精简的上下文
- **中轮压缩（Mid-turn Compaction）**：在工具调用循环中实时压缩，防止上下文溢出

---

## 2. 功能点目的

### 2.1 模板文件功能

| 文件 | 用途 |
|------|------|
| `prompt.md` | 主提示词模板，指导 LLM 生成上下文摘要 |
| `summary_prefix.md` | 摘要消息前缀，用于标识压缩摘要消息 |

### 2.2 prompt.md 内容解析
```markdown
You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM that will resume the task.

Include:
- Current progress and key decisions made
- Important context, constraints, or user preferences
- What remains to be done (clear next steps)
- Any critical data, examples, or references needed to continue

Be concise, structured, and focused on helping the next LLM seamlessly continue the work.
```

**设计意图**：
- 明确告知 LLM 当前任务是"上下文检查点压缩"
- 要求生成"交接摘要（handoff summary）"，强调这是为了其他 LLM 继续工作
- 指定必须包含的四个关键要素：进度与决策、约束与偏好、待办事项、关键数据
- 强调简洁性和结构化，确保摘要高效可用

### 2.3 summary_prefix.md 内容解析
```markdown
Another language model started to solve this problem and produced a summary of its thinking process. You also have access to the state of the tools that were used by that language model. Use this to build on the work that has already been done and avoid duplicating work. Here is the summary produced by the other language model, use the information in this summary to assist with your own analysis:
```

**设计意图**：
- 作为摘要消息的前缀文本，向接收方 LLM 解释摘要来源
- 强调这是"另一个语言模型"生成的思维过程摘要
- 提醒接收方利用工具状态信息，避免重复工作
- 建立上下文连续性，使对话交接自然流畅

---

## 3. 具体技术实现

### 3.1 核心常量定义

在 `codex-rs/core/src/compact.rs` 中，模板被编译为常量：

```rust
pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");
const COMPACT_USER_MESSAGE_MAX_TOKENS: usize = 20_000;
```

### 3.2 本地压缩流程（Local Compaction）

**入口函数**：`run_compact_task_inner`

```rust
async fn run_compact_task_inner(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
    input: Vec<UserInput>,
    initial_context_injection: InitialContextInjection,
) -> CodexResult<()>
```

**执行流程**：
1. **创建压缩项**：生成 `ContextCompactionItem` 并发送 `ItemStarted` 事件
2. **准备输入**：将用户输入转换为 `ResponseInputItem` 并记录到历史
3. **流式请求**：通过 `drain_to_completed` 向模型发送压缩请求
4. **提取摘要**：从模型响应中提取最后一条助手消息作为摘要
5. **构建新历史**：
   - 收集历史中的真实用户消息（过滤掉系统前缀）
   - 使用 `build_compacted_history` 构建压缩后的历史
   - 限制用户消息总 token 数不超过 20,000
6. **注入初始上下文**：根据 `InitialContextInjection` 策略决定是否注入
7. **替换历史**：调用 `replace_compacted_history` 更新会话状态
8. **发送警告**：提示用户"长线程和多次压缩可能降低模型准确性"

### 3.3 远程压缩流程（Remote Compaction）

**触发条件**：`should_use_remote_compact_task(provider: &ModelProviderInfo) -> bool`
- 仅当 provider 是 OpenAI 时返回 `true`

**入口函数**：`run_remote_compact_task_inner`

**与本地压缩的区别**：
1. 调用远程 API 端点 `/v1/responses/compact` 而非本地模型
2. 远程返回的是已压缩的 `ResponseItem` 列表
3. 通过 `process_compacted_history` 处理远程返回：
   - 过滤掉 `developer` 角色的消息（避免陈旧指令）
   - 仅保留真实用户消息（通过 `parse_turn_item` 识别）
   - 保留 `assistant` 消息和 `Compaction` 项
4. 重新注入当前会话的规范初始上下文

### 3.4 初始上下文注入策略

```rust
pub(crate) enum InitialContextInjection {
    BeforeLastUserMessage,  // 在最后一个用户消息前注入（中轮压缩）
    DoNotInject,            // 不注入（预轮/手动压缩）
}
```

**策略差异**：
- `DoNotInject`：压缩后清除 `reference_context_item`，下次常规轮次会完全重新注入初始上下文
- `BeforeLastUserMessage`：压缩后立即注入，因为模型训练期望压缩摘要作为历史最后一项

### 3.5 关键数据结构

#### CompactedItem（压缩项）
```rust
pub struct CompactedItem {
    pub message: String,                    // 摘要文本
    pub replacement_history: Option<Vec<ResponseItem>>, // 替换后的历史
}
```

#### ContextCompactionItem（上下文压缩项）
```rust
pub struct ContextCompactionItem {
    pub id: String,  // UUID 标识
}
```

### 3.6 历史构建算法

**`build_compacted_history_with_limit`**：
1. 从最近的用户消息开始，倒序选择消息
2. 每条消息计算近似 token 数（`approx_token_count`）
3. 累计不超过 `max_tokens`（默认 20,000）
4. 超长消息使用 `truncate_text` 截断
5. 最后追加摘要消息（带 `SUMMARY_PREFIX` 前缀）

**`insert_initial_context_before_last_real_user_or_summary`**：
1. 倒序遍历压缩后的历史
2. 定位最后一个真实用户消息（非摘要）
3. 或定位最后一个摘要/压缩项作为备选
4. 在该位置前插入初始上下文

---

## 4. 关键代码路径与文件引用

### 4.1 模板文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/templates/compact/prompt.md` | 压缩提示词模板 |
| `codex-rs/core/templates/compact/summary_prefix.md` | 摘要前缀模板 |

### 4.2 核心实现文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/compact.rs` | 本地压缩逻辑主实现（442行） |
| `codex-rs/core/src/compact_remote.rs` | 远程压缩逻辑实现（300行） |
| `codex-rs/core/src/compact_tests.rs` | 压缩模块单元测试（561行） |
| `codex-rs/core/src/tasks/compact.rs` | 压缩任务定义与调度（49行） |

### 4.3 调用方代码路径

**手动压缩命令**：
- `codex-rs/core/src/codex.rs` → `Op::Compact` 处理分支
- 调用 `run_compact_task` 或 `run_remote_compact_task`

**自动压缩触发**：
- `codex-rs/core/src/codex.rs` → `maybe_trigger_auto_compact`
- 检查 `model_auto_compact_token_limit` 阈值
- 调用 `run_inline_auto_compact_task` 或 `run_inline_remote_auto_compact_task`

**任务调度**：
- `codex-rs/core/src/tasks/compact.rs` → `CompactTask::run`
- 根据 provider 类型选择本地或远程压缩

### 4.4 配置相关文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/config/mod.rs` | `compact_prompt: Option<String>` 配置项 |
| `codex-rs/core/src/config/types.rs` | 配置类型定义 |
| `codex-rs/core/config.schema.json` | JSON Schema 配置验证 |

### 4.5 测试文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/suite/compact.rs` | 本地压缩集成测试（3300+行） |
| `codex-rs/core/tests/suite/compact_remote.rs` | 远程压缩集成测试（1000+行） |
| `codex-rs/core/tests/suite/compact_resume_fork.rs` | 压缩+恢复+分叉集成测试（708行） |

### 4.6 依赖协议文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/protocol/src/items.rs` | `ContextCompactionItem` 定义 |
| `codex-rs/protocol/src/protocol.rs` | `CompactedItem`, `ContextCompactedEvent` 定义 |
| `codex-rs/codex-api/src/endpoint/compact.rs` | 远程压缩 API 客户端 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖模块

```
compact/compact_remote
├── context_manager/          # 历史管理
│   └── history.rs           # ContextManager, 历史操作
├── truncate.rs              # 文本截断工具
├── event_mapping.rs         # 事件映射与解析
├── codex.rs                 # Session/TurnContext
├── client.rs                # ModelClient 模型客户端
└── tasks/                   # 任务调度
    └── compact.rs
```

### 5.2 外部 API 交互

**远程压缩端点**：
- **端点**：`POST /v1/responses/compact`
- **客户端**：`codex_api::CompactClient`
- **请求体**：包含完整对话历史、工具定义、推理配置
- **响应**：`{ "output": Vec<ResponseItem> }` 压缩后的历史项

**请求头**：
```rust
const RESPONSES_COMPACT_ENDPOINT: &str = "/responses/compact";
// 包含 session_id, authorization, chatgpt-account-id 等
```

### 5.3 配置项依赖

| 配置项 | 类型 | 说明 |
|-------|------|------|
| `compact_prompt` | `Option<String>` | 自定义压缩提示词 |
| `experimental_compact_prompt_file` | `Option<AbsolutePathBuf>` | 从文件加载提示词 |
| `model_auto_compact_token_limit` | `Option<i64>` | 自动压缩阈值 |
| `model_context_window` | `Option<i64>` | 模型上下文窗口大小 |

### 5.4 事件系统交互

**发出的事件**：
- `EventMsg::TurnStarted` - 压缩轮次开始
- `EventMsg::ItemStarted(TurnItem::ContextCompaction)` - 压缩项开始
- `EventMsg::ItemCompleted(TurnItem::ContextCompaction)` - 压缩项完成
- `EventMsg::ContextCompacted` - 压缩完成（遗留事件）
- `EventMsg::Warning` - 压缩警告（长线程准确性下降）
- `EventMsg::TurnComplete` - 压缩轮次完成

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 信息丢失风险
- **风险**：压缩过程会丢失详细的对话历史，可能导致模型遗忘关键细节
- **缓解**：保留所有真实用户消息（最多 20k tokens），仅压缩助手响应
- **警告**：系统已提示"Long threads and multiple compactions can cause the model to be less accurate"

#### 6.1.2 上下文窗口超限
- **风险**：压缩请求本身可能超出上下文窗口
- **处理**：`trim_function_call_history_to_fit_context_window` 会预先裁剪历史
- **回退**：若压缩失败，会记录错误并停止代理循环

#### 6.1.3 远程压缩失败
- **风险**：远程 `/responses/compact` 端点可能不可用或返回无效格式
- **处理**：`run_remote_compact_task_inner` 捕获错误并发送 `EventMsg::Error`
- **影响**：自动压缩失败会导致代理循环停止

### 6.2 边界情况

#### 6.2.1 空摘要处理
```rust
let summary_text = if summary_text.is_empty() {
    "(no summary available)".to_string()
} else {
    summary_text.to_string()
};
```

#### 6.2.2 无用户消息历史
- 若历史中没有真实用户消息，`insert_initial_context_before_last_real_user_or_summary` 会将初始上下文追加到末尾

#### 6.2.3 Ghost Snapshot 保留
- 压缩会保留 `GhostSnapshot` 项，用于支持 `/undo` 功能

### 6.3 改进建议

#### 6.3.1 模板可定制性
**现状**：模板是编译时嵌入的静态文件
**建议**：
- 支持多语言模板（i18n）
- 提供模板变量插值（如 `{{model_name}}`, `{{context_window}}`）
- 允许按任务类型选择不同模板（coding/planning/review）

#### 6.3.2 压缩质量评估
**现状**：无自动机制评估压缩后摘要的质量
**建议**：
- 添加压缩质量指标（如关键实体保留率）
- 支持压缩后摘要的置信度分数
- 低质量摘要时回退到完整历史

#### 6.3.3 增量压缩优化
**现状**：每次压缩都重新处理完整历史
**建议**：
- 支持增量压缩，仅处理新增部分
- 维护多级摘要（hierarchical summarization）
- 压缩摘要的缓存与复用

#### 6.3.4 可观测性增强
**现状**：压缩过程的可观测性有限
**建议**：
- 添加压缩前后 token 数的详细指标
- 记录压缩耗时和成功率
- 支持压缩摘要的可视化预览

#### 6.3.5 配置验证
**现状**：`compact_prompt` 配置无格式验证
**建议**：
- 验证自定义提示词是否包含必要占位符
- 提供提示词模板语法检查
- 支持提示词 A/B 测试

---

## 7. 附录：关键代码片段

### 7.1 模板嵌入
```rust
// codex-rs/core/src/compact.rs
pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");
```

### 7.2 压缩历史构建
```rust
pub(crate) fn build_compacted_history(
    initial_context: Vec<ResponseItem>,
    user_messages: &[String],
    summary_text: &str,
) -> Vec<ResponseItem> {
    build_compacted_history_with_limit(
        initial_context,
        user_messages,
        summary_text,
        COMPACT_USER_MESSAGE_MAX_TOKENS,
    )
}
```

### 7.3 任务调度决策
```rust
// codex-rs/core/src/tasks/compact.rs
async fn run(...) -> Option<String> {
    let _ = if crate::compact::should_use_remote_compact_task(&ctx.provider) {
        // 远程压缩（OpenAI）
        crate::compact_remote::run_remote_compact_task(session.clone(), ctx).await
    } else {
        // 本地压缩（其他 provider）
        crate::compact::run_compact_task(session.clone(), ctx, input).await
    };
    None
}
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/core/templates/compact/ 及其完整调用链*
