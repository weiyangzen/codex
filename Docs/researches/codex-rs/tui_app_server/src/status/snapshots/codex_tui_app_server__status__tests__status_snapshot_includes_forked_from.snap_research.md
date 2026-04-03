# 研究文档: codex_tui_app_server__status__tests__status_snapshot_includes_forked_from.snap

## 场景与职责

此快照文件是 `codex-tui-app-server` crate 中状态显示功能的 insta 快照测试结果，测试用例为 `status_snapshot_includes_forked_from`。该测试验证当会话是从另一个会话 fork 而来时，状态显示能正确展示原始会话 ID。

## 功能点目的

### 测试目标
验证以下场景的状态显示行为：
1. **Session ID 显示**: 显示当前会话 UUID
2. **Forked From 显示**: 显示父会话 UUID
3. **Limits 数据不可用提示**: 当速率限制数据缺失时显示默认提示

### Fork 功能背景
Fork 允许用户从现有会话创建新会话，保留上下文但独立发展，显示 fork 来源有助于用户追踪会话关系。

## 具体技术实现

### 关键数据结构

```rust
pub struct ThreadId(String);  // UUID 格式
```

### 关键流程

1. **Session 和 Forked From 渲染** (`card.rs:518-525`):
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

3. **测试数据** (`tests.rs:236-287`):
```rust
let session_id = ThreadId::from_string("0f0f3c13-6cf9-4aa4-8b80-7d49c2f1be2e").expect("session id");
let forked_from = ThreadId::from_string("e9f18a88-8081-4e51-9d4e-8af5cde2d8dd").expect("forked id");

let composite = new_status_output(
    &config,
    account_display.as_ref(),  // tui_app_server 使用 StatusAccountDisplay
    Some(&token_info),
    &usage,
    &Some(session_id),
    None,
    Some(forked_from),
    None,  // 无速率限制数据
    None,
    captured_at,
    &model_slug,
    None,
    None,
);
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `tui_app_server/src/status/tests.rs:236-287` | 测试用例定义 |
| `tui_app_server/src/status/card.rs:455-460` | 标签收集 |
| `tui_app_server/src/status/card.rs:518-525` | Session 和 Forked from 渲染 |

## 依赖与外部交互

### 依赖模块
- `codex_protocol::ThreadId` - 会话 ID 类型

### 显示逻辑
- Session ID 仅在 `session_id.is_some()` 时显示
- Forked From 仅在两者都有值时显示

## 风险、边界与改进建议

### 当前风险
1. **ID 可读性**: UUID 较长，在窄终端可能被截断
2. **会话关系追踪**: 仅显示直接父会话

### 改进建议
1. **会话链接**: 使 Session ID 可选择/可复制
2. **缩短显示**: 在窄终端显示缩短的 UUID

### 测试覆盖
- ✅ Session ID 显示
- ✅ Forked From 显示
- ✅ Limits 数据缺失提示
