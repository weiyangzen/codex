# reasons.rs 深度研究文档

## 场景与职责

`reasons.rs` 是 Codex 网络代理中定义策略拒绝原因的常量模块。该模块集中管理所有网络请求被拒绝的原因标识，确保：

1. **原因标识一致性**：所有拒绝原因使用统一的字符串常量
2. **审计日志标准化**：审计事件中的拒绝原因字段使用预定义值
3. **错误消息映射**：将内部原因映射为用户友好的错误消息
4. **跨模块共享**：在策略决策、响应生成、审计日志等模块间共享

该模块虽然代码量小（仅 8 行），但在整个网络代理的安全策略体系中起到关键的"语言标准化"作用。

## 功能点目的

### 1. 拒绝原因常量定义

定义 8 种策略拒绝原因，覆盖所有策略决策场景：

| 常量 | 值 | 使用场景 |
|------|-----|----------|
| `REASON_DENIED` | `"denied"` | 主机在拒绝列表中 |
| `REASON_METHOD_NOT_ALLOWED` | `"method_not_allowed"` | 网络模式限制（Limited 模式下使用非安全方法） |
| `REASON_MITM_REQUIRED` | `"mitm_required"` | Limited 模式下 HTTPS CONNECT 需要 MITM |
| `REASON_NOT_ALLOWED` | `"not_allowed"` | 主机不在允许列表中 |
| `REASON_NOT_ALLOWED_LOCAL` | `"not_allowed_local"` | 本地/私有地址不允许 |
| `REASON_POLICY_DENIED` | `"policy_denied"` | 通用策略拒绝（默认原因） |
| `REASON_PROXY_DISABLED` | `"proxy_disabled"` | 代理被禁用 |
| `REASON_UNIX_SOCKET_UNSUPPORTED` | `"unix_socket_unsupported"` | 平台不支持 Unix Socket |

## 具体技术实现

### 常量定义

```rust
pub(crate) const REASON_DENIED: &str = "denied";
pub(crate) const REASON_METHOD_NOT_ALLOWED: &str = "method_not_allowed";
pub(crate) const REASON_MITM_REQUIRED: &str = "mitm_required";
pub(crate) const REASON_NOT_ALLOWED: &str = "not_allowed";
pub(crate) const REASON_NOT_ALLOWED_LOCAL: &str = "not_allowed_local";
pub(crate) const REASON_POLICY_DENIED: &str = "policy_denied";
pub(crate) const REASON_PROXY_DISABLED: &str = "proxy_disabled";
pub(crate) const REASON_UNIX_SOCKET_UNSUPPORTED: &str = "unix_socket_unsupported";
```

### 设计决策

1. **字符串而非枚举**：
   - 使用字符串常量而非 Rust 枚举
   - 便于序列化到 JSON 审计日志
   - 便于与外部系统（如 TUI）交互

2. **snake_case 命名**：
   - 原因值使用 snake_case 格式
   - 与 OpenTelemetry 语义约定保持一致
   - 便于日志查询和分析

3. `pub(crate)` 可见性：
   - 限制在 crate 内部使用
   - 通过 `responses.rs` 中的函数暴露给用户

## 关键代码路径与文件引用

### 常量定义位置

| 常量 | 行号 | 值 |
|------|------|-----|
| `REASON_DENIED` | 1 | `"denied"` |
| `REASON_METHOD_NOT_ALLOWED` | 2 | `"method_not_allowed"` |
| `REASON_MITM_REQUIRED` | 3 | `"mitm_required"` |
| `REASON_NOT_ALLOWED` | 4 | `"not_allowed"` |
| `REASON_NOT_ALLOWED_LOCAL` | 5 | `"not_allowed_local"` |
| `REASON_POLICY_DENIED` | 6 | `"policy_denied"` |
| `REASON_PROXY_DISABLED` | 7 | `"proxy_disabled"` |
| `REASON_UNIX_SOCKET_UNSUPPORTED` | 8 | `"unix_socket_unsupported"` |

## 依赖与外部交互

### 被引用位置

| 引用模块 | 使用场景 |
|----------|----------|
| `network_policy.rs` | `REASON_POLICY_DENIED` 作为默认拒绝原因 |
| `runtime.rs` | `REASON_DENIED`、`REASON_NOT_ALLOWED`、`REASON_NOT_ALLOWED_LOCAL` 用于 `HostBlockReason` |
| `responses.rs` | 所有原因用于错误消息映射和 HTTP 头生成 |
| `http_proxy.rs` | 所有原因用于各种阻塞场景 |
| `socks5.rs` | `REASON_METHOD_NOT_ALLOWED`、`REASON_PROXY_DISABLED` 用于 SOCKS5 阻塞 |

### 错误消息映射 (`responses.rs`)

```rust
pub fn blocked_message(reason: &str) -> &'static str {
    match reason {
        REASON_NOT_ALLOWED => {
            "Codex blocked this request: domain not in allowlist (this is not a denylist block)."
        }
        REASON_NOT_ALLOWED_LOCAL => {
            "Codex blocked this request: local/private addresses not allowed."
        }
        REASON_DENIED => "Codex blocked this request: domain denied by policy.",
        REASON_METHOD_NOT_ALLOWED => {
            "Codex blocked this request: method not allowed in limited mode."
        }
        REASON_MITM_REQUIRED => "Codex blocked this request: MITM required for limited HTTPS.",
        _ => "Codex blocked this request by network policy.",
    }
}

pub fn blocked_header_value(reason: &str) -> &'static str {
    match reason {
        REASON_NOT_ALLOWED | REASON_NOT_ALLOWED_LOCAL => "blocked-by-allowlist",
        REASON_DENIED => "blocked-by-denylist",
        REASON_METHOD_NOT_ALLOWED => "blocked-by-method-policy",
        REASON_MITM_REQUIRED => "blocked-by-mitm-required",
        _ => "blocked-by-policy",
    }
}
```

### 审计日志使用

在 `network_policy.rs` 中，原因被用于审计事件：

```rust
fn emit_policy_audit_event(state: &NetworkProxyState, args: PolicyAuditEventArgs<'_>) {
    tracing::event!(
        target: AUDIT_TARGET,
        tracing::Level::INFO,
        // ...
        network.policy.reason = args.reason,  // 使用 reasons.rs 中的常量
        // ...
    );
}
```

## 风险、边界与改进建议

### 潜在风险

1. **字符串拼写错误**：
   - 使用字符串常量而非枚举，编译器无法检查拼写错误
   - 建议：添加单元测试验证所有常量值唯一且符合预期

2. **原因值变更**：
   - 修改原因值会破坏现有的审计日志查询
   - 建议：将原因值视为 API 契约，遵循语义化版本控制

3. **扩展性**：
   - 当前只有 8 种原因，未来可能需要更多
   - 建议：建立原因命名规范（如 `reason_{category}_{detail}`）

### 边界情况

1. **默认原因**：
   - `REASON_POLICY_DENIED` 作为默认/备用原因
   - 在 `NetworkDecision::deny()` 和 `ask()` 中使用

2. **空原因处理**：
   - `NetworkDecision::deny_with_source()` 会检查空原因
   - 如果为空，使用 `REASON_POLICY_DENIED`

### 改进建议

1. **类型安全**：
   - 考虑使用 `const &'static str` 包装类型
   - 或添加编译时验证宏

2. **文档生成**：
   - 自动生成原因文档
   - 包含使用场景和示例

3. **国际化支持**：
   - 当前错误消息仅支持英文
   - 建议：添加错误消息的国际化支持

4. **原因分类**：
   - 添加原因分类（如 `Security`、`Configuration`、`Platform`）
   - 便于审计日志的聚合分析

5. **与 OpenTelemetry 对齐**：
   - 检查原因命名是否符合 OpenTelemetry 语义约定
   - 考虑添加标准化的属性键

### 测试建议

虽然该模块简单，但建议添加：

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reason_values_are_unique() {
        let reasons = vec![
            REASON_DENIED,
            REASON_METHOD_NOT_ALLOWED,
            REASON_MITM_REQUIRED,
            REASON_NOT_ALLOWED,
            REASON_NOT_ALLOWED_LOCAL,
            REASON_POLICY_DENIED,
            REASON_PROXY_DISABLED,
            REASON_UNIX_SOCKET_UNSUPPORTED,
        ];
        let unique: std::collections::HashSet<_> = reasons.iter().collect();
        assert_eq!(reasons.len(), unique.len());
    }

    #[test]
    fn reason_values_use_snake_case() {
        let reasons = vec![...];
        for reason in reasons {
            assert!(
                reason.chars().all(|c| c.is_lowercase() || c == '_'),
                "{reason} should be snake_case"
            );
        }
    }
}
```
