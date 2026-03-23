# mitm_tests.rs 深度研究文档

## 场景与职责

`mitm_tests.rs` 是 `mitm.rs` 的**配套单元测试模块**，采用 Rust 的 `#[cfg(test)]` + `#[path]` 模式组织。该文件专注于测试 MITM 模块的**策略检查逻辑**，确保在 TLS 终止后的内部请求阶段，各种安全策略能够正确执行。

### 核心测试场景

1. **方法限制验证**：Limited 模式下非安全 HTTP 方法被阻止
2. **Host 头一致性**：防止请求走私和主机伪造
3. **DNS 重绑定防护**：验证本地/私有地址在 MITM 阶段被正确阻止
4. **审计日志记录**：确保策略违规被正确记录

---

## 功能点目的

### 1. 测试模块组织

```rust
#[cfg(test)]
#[path = "mitm_tests.rs"]
mod tests;
```

**设计模式**：
- 测试代码与实现代码分离，保持主文件整洁
- 使用 `#[path]` 属性明确指定测试文件位置
- 测试模块仅在测试编译时包含（`#[cfg(test)]`）

### 2. 测试辅助函数

```rust
fn policy_ctx(
    app_state: Arc<NetworkProxyState>,
    mode: NetworkMode,
    target_host: &str,
    target_port: u16,
) -> MitmPolicyContext
```

**用途**：
- 快速构建测试用的策略上下文
- 统一测试数据构造，减少重复代码

---

## 具体技术实现

### 1. 方法限制测试

```rust
#[tokio::test]
async fn mitm_policy_blocks_disallowed_method_and_records_telemetry()
```

**测试逻辑**：
1. 创建 `NetworkProxyState`，配置 `allowed_domains: ["example.com"]`
2. 构建 `MitmPolicyContext`，模式为 `Limited`，目标为 `example.com:443`
3. 构造 POST 请求（Limited 模式下不允许）
4. 调用 `mitm_blocking_response()`
5. 验证：
   - 返回 `Some(Response)`（表示被阻止）
   - 状态码为 403 Forbidden
   - `x-proxy-error` 头为 `blocked-by-method-policy`
   - 阻塞请求被记录到 `app_state.blocked`

**关键断言**：
```rust
assert_eq!(response.status(), StatusCode::FORBIDDEN);
assert_eq!(
    response.headers().get("x-proxy-error").unwrap(),
    "blocked-by-method-policy"
);
let blocked = app_state.drain_blocked().await.unwrap();
assert_eq!(blocked[0].reason, REASON_METHOD_NOT_ALLOWED);
```

### 2. Host 头不匹配测试

```rust
#[tokio::test]
async fn mitm_policy_rejects_host_mismatch()
```

**测试逻辑**：
1. 配置目标主机为 `example.com`
2. 构造请求，但 Host 头设置为 `evil.example`
3. 验证请求被阻止（400 Bad Request）
4. 验证该请求**未被记录**为阻塞（因为不是策略违规，而是协议错误）

**安全意义**：
- 防止客户端在 CONNECT 到 `example.com` 后，发送针对 `evil.example` 的请求
- 这是 HTTP 请求走私的一种变体防护

### 3. DNS 重绑定防护测试

```rust
#[tokio::test]
async fn mitm_policy_rechecks_local_private_target_after_connect()
```

**测试逻辑**：
1. 配置 `allow_local_binding: false`（默认安全设置）
2. 配置目标为私有 IP `10.0.0.1`
3. 构造正常 GET 请求
4. 验证：
   - 请求被阻止（403 Forbidden）
   - 阻塞原因为 `REASON_NOT_ALLOWED_LOCAL`
   - 阻塞记录包含正确的主机和端口

**安全机制**：
- CONNECT 阶段可能通过域名（解析到公网 IP）检查
- 但在 MITM 阶段，重新检查目标 IP 是否为本地/私有
- 防止 DNS 在 CONNECT 和 MITM 之间重绑定到本地地址

---

## 关键代码路径与文件引用

### 测试依赖链

```
mitm_tests.rs
├── 使用 mitm.rs 的内部函数
│   ├── mitm_blocking_response()
│   ├── MitmPolicyContext
│   └── MitmRequestContext
├── 使用 runtime.rs 的测试工具
│   └── network_proxy_state_for_policy()
├── 使用 config.rs 的配置类型
│   ├── NetworkMode
│   └── NetworkProxySettings
└── 使用 reasons.rs 的常量
    └── REASON_*
```

### 测试覆盖范围

| 测试函数 | 覆盖功能 | 断言数量 |
|----------|----------|----------|
| `mitm_policy_blocks_disallowed_method_and_records_telemetry` | Limited 模式方法限制 | 6+ |
| `mitm_policy_rejects_host_mismatch` | Host 头验证 | 2+ |
| `mitm_policy_rechecks_local_private_target_after_connect` | DNS 重绑定防护 | 4+ |

---

## 依赖与外部交互

### 测试框架

| 依赖 | 用途 |
|------|------|
| `tokio::test` | 异步测试运行时 |
| `pretty_assertions` | 友好的断言输出 |

### 内部依赖

| 模块 | 使用项 |
|------|--------|
| `super` (mitm.rs) | `MitmPolicyContext`, `mitm_blocking_response` |
| `config.rs` | `NetworkProxySettings`, `NetworkMode` |
| `reasons.rs` | `REASON_METHOD_NOT_ALLOWED`, `REASON_NOT_ALLOWED_LOCAL` |
| `runtime.rs` | `network_proxy_state_for_policy` |

### 测试数据构造

```rust
// 标准测试配置
let app_state = Arc::new(network_proxy_state_for_policy(NetworkProxySettings {
    allowed_domains: vec!["example.com".to_string()],
    ..NetworkProxySettings::default()
}));

// 标准请求构造
let req = Request::builder()
    .method(Method::POST)
    .uri("/v1/responses?api_key=secret")
    .header(HOST, "example.com")
    .body(Body::empty())
    .unwrap();
```

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **未覆盖的功能**：
   - 嵌套 CONNECT 拒绝
   - 请求体检查（`inspect_body`）
   - 正常请求转发（非阻止场景）
   - 上游连接失败处理

2. **边界条件未测试**：
   - 空 Host 头
   - 无效 URI
   - 并发 MITM 请求
   - 大请求体

### 测试改进建议

1. **正向流程测试**
   ```rust
   #[tokio::test]
   async fn mitm_allows_valid_get_request() {
       // 验证正常 GET 请求被允许并正确转发
   }
   ```

2. **并发测试**
   ```rust
   #[tokio::test]
   async fn mitm_handles_concurrent_requests() {
       // 验证多个并发 MITM 连接不会互相干扰
   }
   ```

3. **错误场景测试**
   ```rust
   #[tokio::test]
   async fn mitm_handles_upstream_failure() {
       // 验证上游连接失败返回 502
   }
   ```

4. **证书相关测试**
   ```rust
   #[tokio::test]
   async fn mitm_generates_valid_certificate() {
       // 验证生成的证书可被标准 TLS 客户端接受
   }
   ```

5. **使用参数化测试**
   ```rust
   #[test_case("GET", true)]
   #[test_case("POST", false)]
   #[test_case("HEAD", true)]
   #[tokio::test]
   async fn mitm_method_policy(method: &str, allowed: bool) {
       // 使用 test-case crate 减少重复代码
   }
   ```

### 测试代码质量

1. **辅助函数扩展**
   ```rust
   // 添加更多辅助函数
   fn build_request(method: Method, host: &str, path: &str) -> Request { ... }
   fn assert_blocked(response: &Response, reason: &str) { ... }
   fn assert_allowed(response: &Response) { ... }
   ```

2. **测试数据外部化**
   ```rust
   // 使用测试固件（fixture）
   const TEST_HOST: &str = "example.com";
   const TEST_PORT: u16 = 443;
   ```

3. **日志验证**
   ```rust
   // 验证正确的日志被记录
   let logs = capture_logs(|| async {
       mitm_blocking_response(...).await
   }).await;
   assert!(logs.contains("MITM blocked by method policy"));
   ```
