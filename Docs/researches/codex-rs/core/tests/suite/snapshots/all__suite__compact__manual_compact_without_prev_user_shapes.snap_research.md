# Research: manual_compact_without_prev_user_shapes.snap

## 场景与职责

该快照文件记录了**无先前用户历史时的手动压缩**场景，验证当用户在没有对话历史的情况下执行 `/compact` 命令时的系统行为。

**测试场景**：用户直接执行手动 `/compact` 命令，没有任何先前的用户输入或助手回复。

---

## 功能点目的

1. **空历史压缩处理**：定义当没有对话历史时压缩操作的行为
2. **回退机制**：确保即使没有历史，后续对话仍能正常进行
3. **上下文注入**：压缩后确保标准上下文（权限指令、环境信息）正确注入

---

## 具体技术实现

### 关键流程

```
手动/compact（无历史）→ 压缩请求（仅含摘要提示词）→ 空摘要生成 → 后续轮次正常进行
```

### 数据结构

**压缩请求（Local Compaction Request）**:
```
00:message/user:<SUMMARIZATION_PROMPT>
```

**压缩后历史布局（Local Post-Compaction History Layout）**:
```
00:message/user:<COMPACTION_SUMMARY>\nMANUAL_EMPTY_SUMMARY
01:message/developer:<PERMISSIONS_INSTRUCTIONS>
02:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
03:message/user:AFTER_MANUAL_EMPTY_COMPACT
```

### 关键观察

1. **压缩请求极简**：当没有历史时，压缩请求仅包含摘要提示词
2. **空摘要生成**：即使无历史，仍会生成一个空摘要（`MANUAL_EMPTY_SUMMARY`）
3. **标准上下文恢复**：压缩后重新注入开发者指令和环境上下文
4. **后续对话正常**：新用户消息（`AFTER_MANUAL_EMPTY_COMPACT`）正常追加

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact.rs`
- **测试函数**: `snapshot_request_shape_manual_compact_without_previous_user_messages` (行 3298-3357)
- **快照生成**: 行 3347-3356

### 核心常量
```rust
const FINAL_REPLY: &str = "FINAL_REPLY";
```

### 测试流程
1. 启动 Mock Server
2. 挂载 SSE 响应序列（压缩轮次 + 后续轮次）
3. 直接提交 `Op::Compact`
4. 等待 `TurnComplete` 事件
5. 提交后续用户输入
6. 验证请求结构

### 依赖模块
- `core_test_support::responses`: Mock 响应工具
- `codex_protocol::protocol::Op`: 操作类型定义

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer` 模拟 API
2. **SSE 响应**: 模拟助手回复（`MANUAL_EMPTY_SUMMARY` 和 `FINAL_REPLY`）

### 配置
- `config.model_provider`: 模型提供者配置
- `config.compact_prompt`: 压缩提示词

### 协议交互
- 压缩请求发送到 `/v1/responses`
- 请求体仅包含摘要提示词作为用户消息

---

## 风险、边界与改进建议

### 风险点
1. **无意义压缩**：空历史压缩可能浪费 API 调用
2. **用户困惑**：用户可能不理解为什么空历史也能压缩
3. **资源浪费**：生成空摘要消耗令牌但无实际价值

### 边界情况
1. **首次对话压缩**：用户可能在首次对话前误操作压缩
2. **连续空压缩**：多次空压缩可能产生多个空摘要条目

### 改进建议
1. **空历史跳过**：检测到无历史时，跳过压缩请求，直接返回成功
2. **用户提示**：空历史时提示用户"没有可压缩的历史记录"
3. **客户端优化**：在客户端层面阻止无历史时的压缩操作
4. **文档说明**：明确说明压缩功能的最佳使用时机

### 相关测试
- `manual_compact_with_history_shapes`: 有历史时的压缩行为
- `remote_manual_compact_without_prev_user_shapes`: 远程压缩的空历史处理
