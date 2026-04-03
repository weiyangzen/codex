# 研究文档: status_snapshot_includes_forked_from.snap

## 场景与职责

此快照文件是 `codex-tui` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_includes_forked_from`。该测试验证当会话是从另一个会话 fork（分支）而来时，状态显示能正确展示原始会话 ID（forked from）。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **Session ID 显示**: 显示当前会话的唯一标识符
2. **Forked From 显示**: 显示父会话的 ID，表明当前会话是从哪个会话分支而来
3. **Limits 数据不可用提示**: 当速率限制数据缺失时显示 "data not available yet"

### 业务逻辑
- Fork 功能允许用户从现有会话创建新会话，保留上下文但独立发展
- 显示 fork 来源有助于用户追踪会话关系
- 速率限制数据可能在会话初期不可用

## 具体技术实现

### 关键数据结构

```rust
pub struct ThreadId(String);  // UUID 格式的会话 ID

pub struct RateLimitSnapshot {
    pub primary: None,      // 本测试中无限制数据
    pub secondary: None,
    pub credits: None,
}
```

### 关键流程

1. **Session ID 和 Forked From 渲染** (`card.rs:519-526`):
```rust
if let Some(session) = self.session_id.as_ref() {
    lines.push(formatter.line("Session", vec![Span::from(session.clone())]));
}
if self.session_id.is_some()
    && let Some(forked_from) = self.forked_from.as_ref()
{
    lines.push(formatter.line("Forked from", vec![Span::from(forked_from.clone())]));
}
```

2. **标签收集** (`card.rs:455-460`):
```rust
if self.session_id.is_some() {
    push_label(&mut labels, &mut seen, "Session");
}
if self.session_id.is_some() && self.forked_from.is_some() {
    push_label(&mut labels, &mut seen, "Forked from");
}
```

3. **测试数据设置** (`tests.rs:240-291`):
```rust
let session_id = ThreadId::from_string("0f0f3c13-6cf9-4aa4-8b80-7d49c2f1be2e").expect("session id");
let forked_from = ThreadId::from_string("e9f18a88-8081-4e51-9d4e-8af5cde2d8dd").expect("forked id");

let composite = new_status_output(
    &config,
    &auth_manager,
    Some(&token_info),
    &usage,
    &Some(session_id),      // 提供 session_id
    None,
    Some(forked_from),      // 提供 forked_from
    None,                   // 无速率限制数据
    None,
    captured_at,
    &model_slug,
    None,
    None,
);
```

4. **Limits 缺失处理** (`card.rs:330-333`):
```rust
StatusRateLimitData::Missing => {
    vec![formatter.line("Limits", vec![Span::from("data not available yet").dim()])]
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui/src/status/tests.rs:240-291` | 测试用例定义 |
| `tui/src/status/card.rs:455-460` | 标签收集（Session/Forked from） |
| `tui/src/status/card.rs:519-526` | Session 和 Forked from 渲染 |
| `tui/src/status/card.rs:306-334` | `rate_limit_lines` - 限制数据渲染（含 Missing 状态） |
| `codex_protocol/src/lib.rs` | `ThreadId` 定义 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::ThreadId` - 会话 ID 类型
- `uuid` - UUID 解析和验证

### 显示逻辑
- **Session ID**: 仅在 `session_id.is_some()` 时显示
- **Forked From**: 仅在 `session_id.is_some() && forked_from.is_some()` 时显示
- 两个字段存在依赖关系：没有 Session ID 时不会显示 Forked From

## 风险、边界与改进建议

### 当前风险
1. **ID 可读性**: UUID 格式较长，在窄终端可能被截断
2. **会话关系追踪**: 仅显示直接父会话，不显示完整会话树

### 边界情况
1. **无 Session ID**: 如果 `session_id` 为 None，即使 `forked_from` 有值也不会显示
2. **循环 Fork**: 如果系统允许，可能存在 A→B→A 的循环 fork 关系
3. **父会话删除**: 父会话被删除后，forked_from 仍显示原 ID 但无法访问

### 改进建议
1. **会话链接**: 考虑使 Session ID 可点击/可选择，方便复制
2. **会话树显示**: 对于复杂场景，考虑显示简化的会话关系图
3. **截断处理**: 在窄终端考虑显示缩短的 UUID（如前 8 位）
4. **验证提示**: 如果父会话不存在，考虑显示警告或不同颜色

### 测试覆盖
此快照测试覆盖了以下场景：
- ✅ Session ID 显示
- ✅ Forked From 显示
- ✅ Limits 数据缺失提示
- ✅ 模型详细信息显示（reasoning, summaries）

### 相关测试
- `status_snapshot_includes_reasoning_details` - 测试模型详细信息显示
- `status_snapshot_shows_missing_limits_message` - 测试 limits 缺失场景
