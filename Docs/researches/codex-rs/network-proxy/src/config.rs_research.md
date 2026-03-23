# config.rs 深度研究文档

## 场景与职责

`config.rs` 是 Codex 网络代理模块的**配置解析与运行时配置管理核心**，负责：
1. 定义网络代理的配置数据结构（TOML/JSON 序列化）
2. 解析和验证用户配置的网络地址（proxy_url, socks_url）
3. 处理地址绑定安全策略（非回环地址限制）
4. 管理 Unix Socket 路径验证
5. 提供运行时配置解析（`RuntimeConfig`）

### 核心使用场景

1. **配置加载**：从 `config.toml` 读取网络代理配置
2. **地址解析**：将用户输入的 URL/地址字符串解析为 `SocketAddr`
3. **安全加固**：确保代理仅监听在安全的网络接口上
4. **运行时初始化**：构建供代理服务使用的运行时配置

---

## 功能点目的

### 1. NetworkProxyConfig - 顶层配置结构

```rust
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq, Eq)]
pub struct NetworkProxyConfig {
    #[serde(default)]
    pub network: NetworkProxySettings,
}
```

**设计目的**：
- 作为配置文件的根结构，嵌套 `network` 键
- 支持序列化/反序列化（TOML/JSON）
- 提供默认配置生成

### 2. NetworkProxySettings - 详细配置项

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enabled` | `bool` | `false` | 代理是否启用 |
| `proxy_url` | `String` | `"http://127.0.0.1:3128"` | HTTP 代理监听地址 |
| `enable_socks5` | `bool` | `true` | 是否启用 SOCKS5 代理 |
| `socks_url` | `String` | `"http://127.0.0.1:8081"` | SOCKS5 代理监听地址 |
| `enable_socks5_udp` | `bool` | `true` | SOCKS5 是否支持 UDP |
| `allow_upstream_proxy` | `bool` | `true` | 是否允许使用上游代理 |
| `dangerously_allow_non_loopback_proxy` | `bool` | `false` | 允许非回环地址绑定（危险） |
| `dangerously_allow_all_unix_sockets` | `bool` | `false` | 允许所有 Unix Socket（危险） |
| `mode` | `NetworkMode` | `Full` | 网络访问模式 |
| `allowed_domains` | `Vec<String>` | `[]` | 允许访问的域名列表 |
| `denied_domains` | `Vec<String>` | `[]` | 拒绝访问的域名列表 |
| `allow_unix_sockets` | `Vec<String>` | `[]` | 允许的 Unix Socket 路径列表 |
| `allow_local_binding` | `bool` | `false` | 允许绑定到本地/私有地址 |
| `mitm` | `bool` | `false` | 启用 MITM 模式 |

### 3. NetworkMode - 网络访问模式

```rust
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "lowercase")]
pub enum NetworkMode {
    /// Limited (read-only) access: only GET/HEAD/OPTIONS are allowed for HTTP.
    /// HTTPS CONNECT is blocked unless MITM is enabled.
    Limited,
    /// Full network access: all HTTP methods are allowed.
    #[default]
    Full,
}
```

**方法限制**：
- `Limited`: 仅允许 `GET`, `HEAD`, `OPTIONS`
- `Full`: 允许所有 HTTP 方法

### 4. RuntimeConfig - 运行时配置

```rust
pub struct RuntimeConfig {
    pub http_addr: SocketAddr,
    pub socks_addr: SocketAddr,
}
```

**设计目的**：
- 将用户配置转换为可直接用于 `TcpListener::bind()` 的地址
- 包含安全策略处理后的最终地址

---

## 具体技术实现

### 1. 地址解析算法

```rust
fn parse_host_port(url: &str, default_port: u16) -> Result<SocketAddressParts>
```

**解析策略**（按优先级）：

1. **空字符串检查**：返回错误
2. **裸 IPv6 字面量检测**：
   ```rust
   if matches!(trimmed.parse::<IpAddr>(), Ok(IpAddr::V6(_))) && !trimmed.starts_with('[') {
       return Ok(SocketAddressParts { host: trimmed.to_string(), port: default_port });
   }
   ```
3. **URL 解析**：
   - 如果输入不含 `://`，前缀添加 `http://`
   - 使用 `url::Url` 解析
   - 提取 host 和 port
4. **回退解析** (`parse_host_port_fallback`)：
   - 去除 scheme（`://` 之后）
   - 去除路径（`/` 之后）
   - 去除用户认证信息（`@` 之后）
   - 处理方括号 IPv6 格式：`[::1]:8080`
   - 处理 `host:port` 格式（仅当包含单个 `:` 时）

### 2. 非回环地址限制

```rust
fn clamp_non_loopback(addr: SocketAddr, allow_non_loopback: bool, name: &str, override_setting_name: &str) -> SocketAddr
```

**安全策略**：
- 如果地址是回环地址（127.x.x.x, ::1）：直接允许
- 如果 `allow_non_loopback` 为 true：记录警告日志后允许
- 否则：将 IP 替换为 `127.0.0.1`，保留端口

**特殊处理**：当启用 Unix Socket 代理时，强制回环绑定：
```rust
if cfg.dangerously_allow_non_loopback_proxy && !http_addr.ip().is_loopback() {
    warn!("unix socket proxying is enabled; ignoring dangerously_allow_non_loopback_proxy...");
}
```

### 3. Unix Socket 路径验证

```rust
pub(crate) enum ValidatedUnixSocketPath {
    Native(AbsolutePathBuf),
    UnixStyleAbsolute(UnixStyleAbsolutePath),
}
```

**验证逻辑**：
1. 检查路径是否为绝对路径（以 `/` 开头）
2. 如果是绝对路径：使用 `AbsolutePathBuf::from_absolute_path` 规范化
3. 否则：尝试解析为 Unix 风格绝对路径
4. 相对路径被拒绝（返回错误）

**设计理由**：
- 相对路径相对于代理进程的 CWD，行为不确定
- 绝对路径确保行为可预测和安全

### 4. 地址解析与转换

```rust
pub fn resolve_runtime(cfg: &NetworkProxyConfig) -> Result<RuntimeConfig>
```

**流程**：
1. 验证 Unix Socket 白名单路径
2. 解析 HTTP 代理地址（默认端口 3128）
3. 解析 SOCKS 代理地址（默认端口 8081）
4. 应用非回环地址限制
5. 返回 `RuntimeConfig`

---

## 关键代码路径与文件引用

### 核心调用链

```
proxy.rs::NetworkProxy::build()
  └── config::resolve_runtime(&self.config)
      ├── validate_unix_socket_allowlist_paths()
      │   └── ValidatedUnixSocketPath::parse()
      ├── resolve_addr(&cfg.network.proxy_url, 3128)
      │   └── parse_host_port()
      ├── resolve_addr(&cfg.network.socks_url, 8081)
      │   └── parse_host_port()
      └── clamp_bind_addrs(http_addr, socks_addr, &cfg.network)
          └── clamp_non_loopback()

http_proxy.rs::run_http_proxy()
  └── 使用 RuntimeConfig.http_addr 绑定监听器

socks5.rs (implied)
  └── 使用 RuntimeConfig.socks_addr 绑定监听器
```

### 依赖关系

| 依赖 | 用途 |
|------|------|
| `codex_utils_absolute_path::AbsolutePathBuf` | Unix Socket 路径规范化 |
| `url::Url` | URL 解析 |
| `serde` | 配置序列化/反序列化 |

### 被调用方

- `proxy.rs`: 构建代理时使用 `resolve_runtime()`
- `state.rs`: `validate_policy_against_constraints()` 调用 `validate_unix_socket_allowlist_paths()`

---

## 依赖与外部交互

### 配置文件格式

```toml
[network]
enabled = true
proxy_url = "http://127.0.0.1:3128"
socks_url = "http://127.0.0.1:8081"
mode = "limited"
allowed_domains = ["*.openai.com", "api.github.com"]
denied_domains = ["internal.company.com"]
allow_unix_sockets = ["/tmp/docker.sock"]
mitm = true
```

### 支持的地址格式

| 输入格式 | 示例 | 解析结果 |
|----------|------|----------|
| 简单 host:port | `127.0.0.1:8080` | host=`127.0.0.1`, port=`8080` |
| 带 scheme | `http://example.com:8080/path` | host=`example.com`, port=`8080` |
| 带认证 | `http://user:pass@host:8080` | host=`host`, port=`8080` |
| IPv6 方括号 | `http://[::1]:8080` | host=`::1`, port=`8080` |
| 裸 IPv6 | `2001:db8::1` | host=`2001:db8::1`, port=default |
| localhost | `localhost:3128` | host=`127.0.0.1`, port=`3128` |

---

## 风险、边界与改进建议

### 安全风险

1. **非回环绑定风险**
   - `dangerously_allow_non_loopback_proxy` 允许代理监听在所有网络接口
   - 如果同时启用 Unix Socket 代理，可能导致远程访问本地服务（如 docker.sock）
   - **缓解**：当启用 Unix Socket 时强制回环绑定

2. **DNS 重绑定绕过**
   - `resolve_addr` 对非 IP 主机名回退到 `127.0.0.1`
   - 这可能导致意外的回环绑定
   - **缓解**：在 `runtime.rs` 的 `host_blocked()` 中进行 DNS 解析检查

3. **配置注入攻击**
   - `allowed_domains` 使用 glob 模式，如果用户输入 `*` 可能过于宽松
   - **缓解**：在 `policy.rs` 中拒绝全局通配符 `*`

### 边界条件

| 场景 | 行为 |
|------|------|
| 空字符串地址 | 返回错误 |
| 仅空白字符 | 返回错误 |
| 无效端口 | 使用默认端口 |
| IPv6 无方括号 | 正确识别为 IPv6 字面量 |
| 相对 Unix Socket 路径 | 被拒绝 |
| 并发配置修改 | 通过 `RwLock` 安全处理 |

### 改进建议

1. **更严格的地址验证**
   ```rust
   // 建议添加：验证地址是否可绑定
   fn validate_bindable(addr: SocketAddr) -> Result<()> {
       // 尝试临时绑定验证
   }
   ```

2. **配置热重载增强**
   - 当前仅支持完整配置替换
   - 建议支持增量更新（如仅修改 allowed_domains）

3. **IPv6 支持完善**
   - 当前默认绑定到 `127.0.0.1`（IPv4）
   - 建议支持显式 IPv6 绑定选项

4. **URL 格式标准化**
   - 当前 `socks_url` 默认值使用 `http://` scheme（语义不正确）
   - 建议改为 `socks5://` 或空 scheme

5. **配置验证增强**
   ```rust
   // 建议添加：检测冲突配置
   fn validate_config_consistency(cfg: &NetworkProxyConfig) -> Result<()> {
       // 检查 allowed_domains 和 denied_domains 是否有重叠
       // 检查 mitm 模式与 limited 模式的兼容性
   }
   ```

6. **测试覆盖扩展**
   - 添加模糊测试（fuzzing）验证地址解析的鲁棒性
   - 添加并发配置修改测试
