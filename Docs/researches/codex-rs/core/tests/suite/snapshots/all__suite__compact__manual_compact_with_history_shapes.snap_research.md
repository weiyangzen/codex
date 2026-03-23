# Research: manual_compact_with_history_shapes.snap

## 场景与职责

该快照文件记录了**本地手动压缩（Manual /compact）**功能的测试场景，验证当有先前用户历史记录时，压缩操作如何工作以及后续对话轮次如何包含压缩摘要。

**测试场景**：用户先发送一条消息（"first manual turn"），收到助手回复（"FIRST_REPLY"），然后执行手动 `/compact` 命令，最后发送第二条消息（"second manual turn"）。

---

## 功能点目的

1. **历史记录压缩**：将多轮对话历史压缩为摘要，减少上下文窗口占用
2. **摘要注入**：压缩后的摘要以特定格式（`<COMPACTION_SUMMARY>\n{summary}`）注入到后续请求中
3. **上下文保留**：保留原始用户消息，但替换助手回复为摘要

---

## 具体技术实现

### 关键流程

```
用户输入 → 助手回复 → 手动/compact → 压缩请求 → 摘要生成 → 后续轮次使用摘要
```

### 数据结构

**压缩请求（Local Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:first manual turn
03:message/assistant:FIRST_REPLY
04:message/user:<SUMMARIZATION_PROMPT>
```

**压缩后历史布局（Local Post-Compaction History Layout）**:
```
00:message/user:first manual turn
01:message/user:<COMPACTION_SUMMARY>\nFIRST_MANUAL_SUMMARY
02:message/developer:<PERMISSIONS_INSTRUCTIONS>
03:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
04:message/user:second manual turn
```

### 关键观察

1. **压缩请求包含**：
   - 开发者指令（权限说明）
   - 环境上下文（当前工作目录）
   - 原始用户消息
   - 助手回复
   - 摘要提示词（`<SUMMARIZATION_PROMPT>`）

2. **压缩后布局特点**：
   - 原始用户消息保留（`first manual turn`）
   - 助手回复被替换为摘要（`<COMPACTION_SUMMARY>\nFIRST_MANUAL_SUMMARY`）
   - 开发者指令和环境上下文重新注入
   - 新用户消息追加到末尾

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact.rs`
- **测试函数**: `manual_compact_twice_preserves_latest_user_messages` (行 2282-2479)
- **快照生成**: 行 2422-2431

### 核心常量
```rust
pub(super) const FIRST_REPLY: &str = "FIRST_REPLY";
pub(super) const SUMMARY_TEXT: &str = "SUMMARY_ONLY_CONTEXT";
```

### 相关函数
- `format_labeled_requests_snapshot`: 格式化带标签的请求快照
- `summary_with_prefix`: 为摘要添加前缀（`<COMPACTION_SUMMARY>\n{summary}`）

### 依赖模块
- `core_test_support::context_snapshot`: 上下文快照工具
- `codex_core::compact::SUMMARIZATION_PROMPT`: 摘要提示词
- `codex_core::compact::SUMMARY_PREFIX`: 摘要前缀（`<COMPACTION_SUMMARY>`）

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: 使用 `wiremock::MockServer` 模拟 API 响应
2. **SSE 响应**: 通过 `mount_sse_sequence` 挂载模拟的 Server-Sent Events

### 配置依赖
- `config.compact_prompt`: 自定义压缩提示词
- `config.model_auto_compact_token_limit`: 自动压缩令牌限制（测试中设置为 200_000）

### 协议交互
- 使用 `/v1/responses` 端点进行正常对话
- 压缩请求作为普通请求发送，包含特殊摘要提示词

---

## 风险、边界与改进建议

### 风险点
1. **摘要质量依赖模型**：压缩效果完全依赖模型对摘要提示词的理解
2. **信息丢失**：助手回复的详细内容被压缩为摘要，可能丢失重要细节
3. **令牌计算误差**：本地令牌估算可能与实际 API 计算不一致

### 边界情况
1. **空历史压缩**：测试 `manual_compact_without_prev_user_shapes` 覆盖无历史时的压缩行为
2. **多次压缩**：连续压缩时，摘要会累积，测试验证历史正确性
3. **上下文窗口溢出**：压缩后仍可能超出上下文窗口，需要错误处理

### 改进建议
1. **摘要验证**：添加摘要质量评估机制，确保关键信息不被丢失
2. **增量压缩**：支持分层压缩，保留最近几轮完整对话，只压缩更早历史
3. **用户确认**：在压缩前向用户展示将被压缩的内容摘要
4. **压缩恢复**：提供查看/恢复压缩前历史的功能

### 相关测试覆盖
- `manual_compact_without_prev_user_shapes`: 无历史压缩
- `mid_turn_compaction_shapes`: 轮中压缩（工具调用后）
- `pre_turn_compaction_*`: 轮前压缩场景
- `multiple_auto_compact_per_task_runs_after_token_limit_hit`: 多次自动压缩
