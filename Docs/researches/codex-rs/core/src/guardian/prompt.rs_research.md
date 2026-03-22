# prompt.rs 研究文档

## 场景与职责

`prompt.rs` 是 Guardian 子代理系统的提示词构建和解析模块，负责：
1. 从 Codex 会话历史中提取和构建 Guardian 审查所需的转录内容
2. 构建完整的 Guardian 提示词（包含转录、动作描述、输出格式要求）
3. 实现智能文本截断，确保提示词在 Token 预算内
4. 解析 Guardian 的 JSON 响应，支持容错解析
5. 定义强制性的 JSON Schema 输出约束

**核心定位：**
该模块是 Guardian 与主 Codex 系统之间的"翻译层"，将复杂的会话历史和操作请求转换为 Guardian 可理解的、结构化的评估提示。

## 功能点目的

### 1. 转录条目收集（collect_guardian_transcript_entries）

从 `ResponseItem` 历史中提取 Guardian 需要的信息：

**保留的内容：**
- 用户消息（排除上下文脚手架）
- Assistant 消息
- 工具调用（FunctionCall, CustomToolCall, LocalShellCall, WebSearchCall）
- 工具输出（FunctionCallOutput, CustomToolCallOutput）

**过滤的内容：**
- 上下文用户消息（`is_contextual_user_message_content` 返回 true）
- 空内容条目
- 其他非相关事件

**工具名称追踪：**
使用 `tool_names_by_call_id` HashMap 追踪 call_id 到工具名称的映射，确保工具输出能正确标注来源。

### 2. 转录渲染（render_guardian_transcript_entries）

实现智能的 Token 预算管理：

**预算分配策略：**
- 消息预算：`GUARDIAN_MAX_MESSAGE_TRANSCRIPT_TOKENS` (10,000)
- 工具预算：`GUARDIAN_MAX_TOOL_TRANSCRIPT_TOKENS` (10,000)
- 单条限制：消息 2,000，工具 1,000

**保留策略：**
1. 始终保留所有用户消息（授权和意图来源）
2. 从最新到最旧遍历非用户条目
3. 仅在预算允许时保留
4. 最多保留 `GUARDIAN_RECENT_ENTRY_LIMIT` (40) 条非用户条目

**输出格式：**
```
[1] user: 用户消息
[2] assistant: Assistant 回复
[3] tool read_file call: {"path": "..."}
[4] tool read_file result: 文件内容
```

### 3. 提示词构建（build_guardian_prompt_items）

组装完整的 Guardian 提示词，包含多个 `UserInput::Text` 条目：

**提示词结构：**
```
1. 警告头：说明转录和动作为不可信证据
2. TRANSCRIPT START/END：包裹转录内容
3. 省略说明（如有）
4. APPROVAL REQUEST START/END：包裹动作请求
   - 重试原因（如有）
   - 动作 JSON
5. 输出格式要求（JSON schema）
```

**设计考量：**
- 使用多个独立的 Text 条目而非单个长字符串
- 便于在 Responses API 请求快照中显示清晰的边界
- 保留尾部换行符以维持格式

### 4. 文本截断（guardian_truncate_text）

智能文本截断实现：

**算法：**
1. 计算 Token 对应的字节预算：`approx_bytes_for_tokens(token_cap)`
2. 如果内容在预算内，直接返回
3. 计算省略的 Token 数量
4. 生成 XML 标记：`<truncated omitted_approx_tokens="N" />`
5. 将剩余预算平分给前缀和后缀
6. 使用 UTF-8 安全的方式分割

**示例：**
```
原始："这是一个非常长的文本内容...（10,000 字）"
截断后："这是一个非常<truncated omitted_approx_tokens="8000" />文本内容"
```

### 5. 评估解析（parse_guardian_assessment）

容错 JSON 解析：

**解析策略：**
1. 首先尝试直接解析整个文本为 JSON
2. 如果失败，尝试提取 `{...}` 包裹的内容
3. 如果仍失败，返回错误

**容错原因：**
- 模型有时会添加周围的解释性文本
- 这种容错减少了因格式问题导致的审查失败

### 6. JSON Schema 定义（guardian_output_schema）

强制结构化输出：

```json
{
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "risk_level": {"enum": ["low", "medium", "high"]},
    "risk_score": {"type": "integer", "minimum": 0, "maximum": 100},
    "rationale": {"type": "string"},
    "evidence": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "message": {"type": "string"},
          "why": {"type": "string"}
        },
        "required": ["message", "why"]
      }
    }
  },
  "required": ["risk_level", "risk_score", "rationale", "evidence"]
}
```

**设计要点：**
- `additionalProperties: false` 防止意外字段
- 所有字段都是必需的，确保完整性
- 风险分数范围 0-100

## 具体技术实现

### 转录条目类型定义

```rust
pub(crate) struct GuardianTranscriptEntry {
    pub(crate) kind: GuardianTranscriptEntryKind,
    pub(crate) text: String,
}

pub(crate) enum GuardianTranscriptEntryKind {
    User,
    Assistant,
    Tool(String),  // 工具名称
}
```

### 关键算法：转录渲染

```rust
pub(crate) fn render_guardian_transcript_entries(
    entries: &[GuardianTranscriptEntry],
) -> (Vec<String>, Option<String>) {
    // 1. 渲染所有条目并计算 token 数
    let rendered_entries: Vec<_> = entries.iter().map(|entry| {
        let token_cap = if entry.kind.is_tool() { 
            GUARDIAN_MAX_TOOL_ENTRY_TOKENS 
        } else { 
            GUARDIAN_MAX_MESSAGE_ENTRY_TOKENS 
        };
        let text = guardian_truncate_text(&entry.text, token_cap);
        let rendered = format!("[{}] {}: {}", index + 1, entry.kind.role(), text);
        let token_count = approx_token_count(&rendered);
        (rendered, token_count)
    }).collect();

    // 2. 首先包含所有用户消息
    for (index, entry) in entries.iter().enumerate() {
        if entry.kind.is_user() {
            // 检查消息预算...
            included[index] = true;
        }
    }

    // 3. 逆序包含非用户条目（最新优先）
    for index in (0..entries.len()).rev() {
        // 检查预算和条目限制...
    }
}
```

### 关键算法：UTF-8 安全分割

```rust
fn split_guardian_truncation_bounds(
    content: &str,
    prefix_bytes: usize,
    suffix_bytes: usize,
) -> (&str, &str) {
    let suffix_start_target = content.len().saturating_sub(suffix_bytes);
    
    for (index, ch) in content.char_indices() {
        let char_end = index + ch.len_utf8();
        
        if char_end <= prefix_bytes {
            prefix_end = char_end;
        }
        
        if index >= suffix_start_target {
            if !suffix_started {
                suffix_start = index;
                suffix_started = true;
            }
        }
    }
    
    // 确保前缀和后缀不重叠
    if suffix_start < prefix_end {
        suffix_start = prefix_end;
    }
    
    (&content[..prefix_end], &content[suffix_start..])
}
```

## 关键代码路径与文件引用

### 调用关系图

```
review.rs::run_guardian_review()
├── build_guardian_prompt_items()
│   ├── session.clone_history()
│   ├── collect_guardian_transcript_entries()
│   ├── format_guardian_action_pretty()
│   └── render_guardian_transcript_entries()
│       └── guardian_truncate_text()
│           └── split_guardian_truncation_bounds()
└── parse_guardian_assessment()  // 响应解析
```

### 外部调用方

| 文件 | 函数 | 场景 |
|------|------|------|
| `review.rs` | `build_guardian_prompt_items` | 构建审查提示词 |
| `review.rs` | `parse_guardian_assessment` | 解析审查结果 |
| `review.rs` | `guardian_output_schema` | 获取输出 schema |
| `review_session.rs` | `guardian_policy_prompt` | 获取策略提示词 |

### 测试覆盖

`tests.rs` 中的相关测试：

| 测试 | 验证内容 |
|------|----------|
| `build_guardian_transcript_keeps_original_numbering` | 条目编号保留 |
| `collect_guardian_transcript_entries_skips_contextual_user_messages` | 上下文消息过滤 |
| `collect_guardian_transcript_entries_includes_recent_tool_calls_and_output` | 工具调用/输出包含 |
| `guardian_truncate_text_keeps_prefix_suffix_and_xml_marker` | 文本截断格式 |
| `build_guardian_transcript_reserves_separate_budget_for_tool_evidence` | 工具预算分离 |
| `parse_guardian_assessment_extracts_embedded_json` | JSON 容错解析 |

## 依赖与外部交互

### 外部依赖

| Crate/模块 | 用途 |
|------------|------|
| `codex_protocol::models::ResponseItem` | 会话历史条目类型 |
| `codex_protocol::user_input::UserInput` | 提示词条目类型 |
| `serde_json::Value` | JSON 处理 |
| `crate::truncate` | Token 估算 |
| `crate::compact::content_items_to_text` | 内容转文本 |
| `crate::event_mapping::is_contextual_user_message_content` | 上下文消息检测 |

### 内部依赖

- `super::GUARDIAN_MAX_*` 常量（来自 `mod.rs`）
- `super::GuardianApprovalRequest` 和 `GuardianAssessment`
- `super::approval_request::format_guardian_action_pretty`

## 风险、边界与改进建议

### 已知风险

1. **Token 估算不准确**：
   - 使用基于字节的估算（`approx_bytes_for_tokens`）
   - 对于非英语内容或特殊字符可能不准确
   - 可能导致实际 Token 数超出预算

2. **转录信息丢失**：
   - 大量工具输出时，旧条目被丢弃
   - 可能丢失关键的上下文信息

3. **提示词注入**：
   - 用户消息中的特殊格式可能被误解为指令
   - 虽然策略要求 Guardian 不信任输入，但仍存在风险

4. **截断位置不当**：
   - 在关键信息中间截断可能导致误解
   - 例如：`rm -rf / important` 截断为 `rm -rf /`

### 边界情况

1. **空历史**：
   - 返回 `"<no retained transcript entries>"`

2. **超大单条内容**：
   - 单条内容超过 `max_entry_tokens` 时截断
   - 截断标记本身可能占用大量空间

3. **前缀/后缀重叠**：
   - `split_guardian_truncation_bounds` 处理了这种情况
   - 但可能导致内容比预期更短

4. **非 UTF-8 内容**：
   - 使用 `char_indices` 确保 UTF-8 安全
   - 但对于无效 UTF-8 可能 panic

### 改进建议

1. **精确 Token 计数**：
   - 集成 tiktoken 或类似库进行精确计数
   - 按模型类型使用不同的编码

2. **智能截断**：
   - 在句子或逻辑边界处截断
   - 保留关键信息（如命令中的 `-rf` 标志）

3. **转录优先级**：
   - 基于语义重要性而非仅时间排序
   - 使用嵌入模型计算相关性

4. **提示词结构优化**：
   - 考虑使用 XML 标签而非纯文本分隔
   - 更清晰的结构有助于 Guardian 理解

5. **多模态支持**：
   - 当前仅支持文本
   - 未来可能需要处理图像、音频等

6. **缓存优化**：
   - 转录渲染结果可以缓存
   - 仅在历史变更时重新计算

7. **可观测性**：
   - 记录实际使用的 Token 数
   - 记录截断发生的位置和原因

8. **测试增强**：
   - 添加模糊测试（fuzzing）
   - 测试各种边缘情况（空内容、极大内容、特殊字符）
