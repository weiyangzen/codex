# ContextManager 研究文档

## 概述

`context_manager` 是 Codex Core 中负责管理对话历史（Conversation History）的核心模块。它维护着与模型交互的所有消息记录，负责历史记录的存储、规范化、截断和 Token 使用估算。

---

## 场景与职责

### 核心场景

1. **对话历史管理**：维护用户与 AI 助手之间的完整对话记录
2. **上下文窗口控制**：确保历史记录在模型上下文窗口限制内
3. **Token 使用估算**：实时估算当前历史记录的 Token 消耗
4. **历史规范化**：确保工具调用/输出配对完整，清理无效条目
5. **图像内容处理**：根据模型能力决定是否保留或剥离图像内容
6. **对话压缩支持**：为 `/compact` 命令提供历史记录裁剪和重建

### 主要职责

| 职责 | 说明 |
|------|------|
| 历史记录存储 | 按时间顺序存储 ResponseItem（最旧在前） |
| API 消息过滤 | 过滤掉系统消息，仅保留 API 相关的消息 |
| 工具调用配对 | 确保每个 FunctionCall/ToolCall 都有对应的 Output |
| 内容截断 | 根据策略截断过长的工具输出 |
| Token 估算 | 基于字节启发式方法估算 Token 数量 |
| 图像处理 | 根据模型输入模态决定是否保留图像 |

---

## 功能点目的

### 1. 历史记录存储 (`record_items`)

**目的**：将新的对话条目添加到历史记录中

**关键逻辑**：
- 只接受 API 消息（非系统消息）和 GhostSnapshot
- 对 FunctionCallOutput 和 CustomToolCallOutput 应用截断策略
- 使用 1.2 倍策略预算进行序列化截断

**代码位置**：`history.rs:91-106`

### 2. 提示词准备 (`for_prompt`)

**目的**：为模型调用准备干净的历史记录

**处理流程**：
1. 调用 `normalize_history` 规范化历史
2. 移除 GhostSnapshot 条目
3. 返回处理后的 ResponseItem 列表

**代码位置**：`history.rs:112-117`

### 3. 历史规范化 (`normalize_history`)

**目的**：维护历史记录的完整性约束

**三个核心不变量**：
1. **调用-输出配对**：每个 FunctionCall/ToolSearchCall/CustomToolCall/LocalShellCall 必须有对应的输出
2. **孤儿输出清理**：移除没有对应调用的输出条目
3. **图像模态处理**：当模型不支持图像时，将图像替换为占位文本

**代码位置**：`history.rs:342-351`

### 4. Token 估算 (`estimate_token_count`)

**目的**：估算当前历史记录的 Token 使用量

**估算方法**：
- 基础指令 Token：基于文本长度的启发式估算
- 历史条目 Token：对每个 ResponseItem 进行估算
- 图像 Token：使用固定估算值（RESIZED_IMAGE_BYTES_ESTIMATE = 7373 字节 ≈ 1844 tokens）
- Reasoning Token：对加密内容使用 `estimate_reasoning_length` 公式

**代码位置**：`history.rs:126-149`

### 5. 总 Token 使用统计 (`get_total_token_usage`)

**目的**：提供准确的 Token 使用统计，用于上下文窗口管理

**计算逻辑**：
```
总 Token = 上次 API 响应的 Token + 新增条目的估算 Token
```

**特殊处理**：
- 如果服务器已包含 reasoning tokens，则不再重复计算
- 区分模型生成的条目和 Codex 生成的条目

**代码位置**：`history.rs:290-308`

### 6. 历史条目删除 (`remove_first_item` / `remove_last_item`)

**目的**：在上下文窗口溢出时裁剪历史

**配对删除逻辑**：
- 删除 FunctionCall 时同时删除对应的 FunctionCallOutput
- 删除 LocalShellCall 时同时删除对应的 FunctionCallOutput
- 删除 CustomToolCall 时同时删除对应的 CustomToolCallOutput
- 反之亦然

**代码位置**：`history.rs:151-170`

### 7. 用户回合回滚 (`drop_last_n_user_turns`)

**目的**：实现 `/undo` 功能，回滚指定数量的用户回合

**识别用户回合边界**：
- 使用 `is_user_turn_boundary` 函数识别真正的用户消息
- 排除环境上下文、技能注入、子代理通知等系统级用户消息

**代码位置**：`history.rs:217-237`

### 8. 图像替换 (`replace_last_turn_images`)

**目的**：当工具输出的图像无效时，替换为占位文本

**代码位置**：`history.rs:178-206`

---

## 具体技术实现

### 关键数据结构

#### ContextManager

```rust
pub(crate) struct ContextManager {
    /// 历史条目（最旧在前）
    items: Vec<ResponseItem>,
    /// Token 使用信息
    token_info: Option<TokenUsageInfo>,
    /// 参考上下文快照（用于 diff）
    reference_context_item: Option<TurnContextItem>,
}
```

#### TotalTokenUsageBreakdown

```rust
pub(crate) struct TotalTokenUsageBreakdown {
    pub last_api_response_total_tokens: i64,
    pub all_history_items_model_visible_bytes: i64,
    pub estimated_tokens_of_items_added_since_last_successful_api_response: i64,
    pub estimated_bytes_of_items_added_since_last_successful_api_response: i64,
}
```

### 关键流程

#### 1. 规范化流程 (normalize.rs)

**ensure_call_outputs_present**：
- 遍历所有条目，识别没有对应输出的调用
- 为缺失输出的调用插入合成输出（内容为 "aborted"）
- 在 Debug 模式下，CustomToolCall 和 LocalShellCall 缺失输出会触发 panic

**remove_orphan_outputs**：
- 收集所有调用 ID（FunctionCall、ToolSearchCall、LocalShellCall、CustomToolCall）
- 移除没有对应调用的输出条目
- 在 Debug 模式下，孤儿输出会触发 panic

**remove_corresponding_for**：
- 根据被删除的条目类型，找到并删除对应的配对条目
- 支持双向查找（调用→输出，输出→调用）

**strip_images_when_unsupported**：
- 检查模型输入模态是否包含 Image
- 如果不支持，将 ContentItem::InputImage 替换为 InputText（占位文本）
- 同样处理 FunctionCallOutput 和 CustomToolCallOutput 中的图像

#### 2. 设置更新项构建 (updates.rs)

**build_settings_update_items**：
构建以下类型的开发者消息更新：
- 环境上下文更新（build_environment_update_item）
- 模型指令更新（build_model_instructions_update_item）
- 权限更新（build_permissions_update_item）
- 协作模式更新（build_collaboration_mode_update_item）
- 实时对话更新（build_realtime_update_item）
- 人格设置更新（build_personality_update_item）

#### 3. Token 估算算法

**图像 Token 估算**：
```rust
const RESIZED_IMAGE_BYTES_ESTIMATE: i64 = 7373; // ≈ 1844 tokens
```

**原始图像 Token 估算**（detail: "original"）：
- 解码 base64 图像数据
- 使用 `image` crate 加载图像获取尺寸
- 按 32px 分块计算 patch 数量
- 每 patch 估算为 1 token

**Reasoning Token 估算**：
```rust
fn estimate_reasoning_length(encoded_len: usize) -> usize {
    encoded_len
        .saturating_mul(3)
        .checked_div(4)
        .unwrap_or(0)
        .saturating_sub(650)
}
```

### 协议与接口

#### 输入协议

**TruncationPolicy**：
```rust
pub enum TruncationPolicy {
    Bytes(usize),
    Tokens(usize),
}
```

**InputModality**：
```rust
pub enum InputModality {
    Text,
    Image,
}
```

#### 输出协议

**ResponseItem**（来自 codex_protocol）：
- Message：用户/助手消息
- Reasoning：推理内容（可能加密）
- FunctionCall/FunctionCallOutput：工具调用和输出
- ToolSearchCall/ToolSearchOutput：工具搜索
- CustomToolCall/CustomToolCallOutput：自定义工具
- LocalShellCall：本地 shell 调用
- WebSearchCall：网络搜索
- ImageGenerationCall：图像生成
- GhostSnapshot：幽灵提交快照
- Compaction：压缩摘要

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/core/src/context_manager/
├── mod.rs           # 模块导出
├── history.rs       # ContextManager 主实现（654 行）
├── history_tests.rs # 单元测试（1500+ 行）
├── normalize.rs     # 历史规范化逻辑（345 行）
└── updates.rs       # 设置更新项构建（218 行）
```

### 关键代码路径

#### 1. 历史记录添加
```
codex.rs:3271
  state.record_items(items.iter(), turn_context.truncation_policy)
    → session.rs:63
      history.record_items(items, policy)
        → history.rs:91-106
```

#### 2. 提示词准备
```
codex.rs:5680
  history.for_prompt(&turn_context.model_info.input_modalities)
    → history.rs:112-117
      → normalize_history
        → normalize.rs:14-120 (ensure_call_outputs_present)
        → normalize.rs:122-195 (remove_orphan_outputs)
        → normalize.rs:295-345 (strip_images_when_unsupported)
```

#### 3. 远程压缩
```
compact_remote.rs:98
  history.for_prompt(&turn_context.model_info.input_modalities)
compact_remote.rs:273-300
  trim_function_call_history_to_fit_context_window
    → remove_last_item (循环直到符合窗口)
```

#### 4. 本地压缩
```
compact.rs:118-120
  history.clone().for_prompt(&turn_context.model_info.input_modalities)
compact.rs:160
  history.remove_first_item()  # 当上下文窗口溢出时
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::truncate` | 文本和 Token 截断策略 |
| `crate::event_mapping` | 识别上下文用户消息内容 |
| `crate::codex::TurnContext` | 回合上下文信息 |
| `crate::environment_context` | 环境上下文构建 |
| `crate::shell::Shell` | Shell 信息获取 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | ResponseItem、ContentItem、TokenUsage 等类型 |
| `codex_protocol::openai_models` | InputModality、ModelInfo |
| `codex_utils_cache` | LRU 缓存（图像 Token 估算） |
| `base64` | Base64 图像数据解码 |
| `image` | 图像尺寸解析（原始图像 Token 估算） |

### 调用方

| 调用方 | 用途 |
|--------|------|
| `codex.rs` | 主会话逻辑，记录模型响应 |
| `state/session.rs` | SessionState 封装 ContextManager |
| `compact.rs` | 本地对话压缩 |
| `compact_remote.rs` | 远程对话压缩 |
| `codex/rollout_reconstruction.rs` | 回滚重建 |

---

## 风险、边界与改进建议

### 已知风险

#### 1. Debug/Release 行为差异

**风险**：规范化逻辑在 Debug 和 Release 模式下行为不同
- Debug 模式：缺失输出或孤儿输出会触发 panic
- Release 模式：自动修复（插入合成输出或删除孤儿）

**影响**：可能导致生产环境和开发环境行为不一致

**建议**：统一行为或明确文档化差异

#### 2. Token 估算不准确

**风险**：使用字节启发式方法（4 字节/token）估算，与真实 tokenizer 存在偏差

**代码**：`history.rs:440-442`
```rust
fn estimate_item_token_count(item: &ResponseItem) -> i64 {
    let model_visible_bytes = estimate_response_item_model_visible_bytes(item);
    approx_tokens_from_byte_count_i64(model_visible_bytes)
}
```

**影响**：可能导致上下文窗口溢出或过早裁剪

#### 3. 图像 Token 估算缓存

**风险**：原始图像 Token 估算使用 LRU 缓存（大小 32），可能缓存失效

**代码**：`history.rs:455-460`
```rust
static ORIGINAL_IMAGE_ESTIMATE_CACHE: LazyLock<BlockingLruCache<[u8; 20], Option<i64>>> =
    LazyLock::new(|| {
        BlockingLruCache::new(
            NonZeroUsize::new(ORIGINAL_IMAGE_ESTIMATE_CACHE_SIZE).unwrap_or(NonZeroUsize::MIN),
        )
    });
```

### 边界情况

#### 1. 空历史记录
- `remove_first_item` 和 `remove_last_item` 在空历史时安全返回
- `for_prompt` 在空历史时返回空 Vec

#### 2. 上下文窗口溢出
- `trim_function_call_history_to_fit_context_window` 只会删除 Codex 生成的条目
- 如果最旧条目是用户消息，可能无法充分裁剪

#### 3. 用户回合识别
- `is_user_turn_boundary` 依赖 `is_contextual_user_message_content`
- 可能错误识别某些系统级用户消息为真实用户回合

### 改进建议

#### 1. 统一规范化行为
```rust
// 建议：移除 cfg 条件编译，统一使用 Release 行为
pub(crate) fn ensure_call_outputs_present(items: &mut Vec<ResponseItem>) {
    // 始终自动修复，但记录警告日志
}
```

#### 2. 更精确的 Token 估算
- 考虑使用实际的 tokenizer（如 tiktoken）进行更精确的估算
- 或者根据模型类型使用不同的启发式系数

#### 3. 历史记录持久化
- 当前 ContextManager 仅维护内存中的历史
- 考虑添加可选的持久化机制，支持会话恢复

#### 4. 增量更新优化
- `build_settings_update_items` 每次构建完整更新列表
- 可考虑缓存上次结果，仅计算 diff

#### 5. 图像处理优化
- 当前图像替换使用固定占位文本
- 可考虑保留图像元数据（如尺寸、格式）供模型参考

#### 6. 测试覆盖
- 增加边界情况测试（空历史、极大历史、异常条目顺序）
- 增加并发测试（ContextManager 不是 Send/Sync，但调用方需要确保线程安全）

---

## 测试覆盖

### 单元测试（history_tests.rs）

| 测试类别 | 测试数量 | 关键测试 |
|----------|----------|----------|
| API 消息过滤 | 1 | `filters_non_api_messages` |
| Token 估算 | 4 | `non_last_reasoning_tokens_*`, `total_token_usage_*` |
| 图像处理 | 4 | `for_prompt_strips_images_*`, `for_prompt_preserves_image_*` |
| 规范化 | 10+ | `normalize_adds_missing_output_*`, `normalize_removes_orphan_*` |
| 条目删除 | 5 | `remove_first_item_*`, `remove_last_item_*` |
| 回合回滚 | 2 | `drop_last_n_user_turns_*` |
| 截断 | 4 | `record_items_truncates_*` |

### 集成测试

- `codex_tests.rs`：端到端会话测试，验证历史记录重建
- `rollout/recorder_tests.rs`：Rollout 记录测试

---

## 总结

ContextManager 是 Codex Core 中负责对话历史管理的核心模块，具有以下特点：

1. **职责清晰**：专注于历史记录的存储、规范化和 Token 估算
2. **设计稳健**：通过规范化确保工具调用配对的完整性
3. **性能考虑**：使用 LRU 缓存优化图像 Token 估算
4. **边界处理**：处理了多种边界情况（空历史、上下文溢出等）

主要改进方向：
- 统一 Debug/Release 行为
- 提升 Token 估算精度
- 增加持久化支持
