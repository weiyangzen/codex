# seatbelt_network_policy.sbpl 研究文档

## 场景与职责

本文件是 Codex **macOS Seatbelt 沙盒的网络策略模块**，定义了网络访问的基本规则。它在 `seatbelt_base_policy.sbpl` 基础上，添加网络相关的允许规则，用于支持需要网络访问的沙盒化进程。

**核心职责**：
- 允许安全的本地系统 socket 通信
- 允许必要的 Mach 服务查找（安全、网络配置）
- 允许网络路由表查询
- 允许 Darwin 用户缓存目录写入（网络相关缓存）

## 功能点目的

### 1. 系统 Socket 访问
```lisp
(allow system-socket
  (require-all
    (socket-domain AF_SYSTEM)
    (socket-protocol 2)))
```
允许 `AF_SYSTEM` 域 socket（协议 2），用于本地平台服务通信。这是 macOS 系统服务的标准通信机制。

### 2. Mach 服务查找
允许与关键系统服务通信：
- `com.apple.bsd.dirhelper` - 目录辅助服务
- `com.apple.system.opendirectoryd.membership` - 目录服务成员查询
- `com.apple.SecurityServer` - 安全服务器（TLS 证书）
- `com.apple.networkd` - 网络守护进程
- `com.apple.ocspd` - OCSP（证书状态协议）
- `com.apple.trustd.agent` - 证书信任代理
- `com.apple.SystemConfiguration.DNSConfiguration` - DNS 配置
- `com.apple.SystemConfiguration.configd` - 系统配置

### 3. 网络路由表查询
```lisp
(allow sysctl-read
  (sysctl-name-regex #"^net.routetable"))
```
允许读取网络路由表信息，用于网络诊断和配置。

### 4. 缓存目录写入
```lisp
(allow file-write*
  (subpath (param "DARWIN_USER_CACHE_DIR")))
```
允许写入 Darwin 用户缓存目录，用于网络缓存、证书缓存等。

## 具体技术实现

### 策略结构

```lisp
; 当网络访问启用时，这些规则在 seatbelt_base_policy.sbpl 之后添加

; 1. 系统 Socket（AF_SYSTEM）
(allow system-socket ...)

; 2. Mach 服务查找
(allow mach-lookup ...)

; 3. 网络 sysctl
(allow sysctl-read ...)

; 4. 缓存目录
(allow file-write* (subpath (param "DARWIN_USER_CACHE_DIR")))
```

### 动态规则注入

注释说明：代理特定的允许规则由 `codex-core` 基于环境动态注入：
```rust
// seatbelt.rs 中的动态网络策略生成
fn dynamic_network_policy(...) -> String {
    if should_use_restricted_network_policy {
        // 允许特定 localhost 端口
        for port in &proxy.ports {
            policy.push_str(&format!(
                "(allow network-outbound (remote ip \"localhost:{port}\"))\n"
            ));
        }
        // 添加基础网络策略
        format!("{policy}{MACOS_SEATBELT_NETWORK_POLICY}")
    } else if network_policy.is_enabled() {
        // 完全开放网络
        "(allow network-outbound)\n(allow network-inbound)\n..."
    } else {
        String::new()
    }
}
```

### 参数使用

`DARWIN_USER_CACHE_DIR` 通过 `-D` 参数传递：
```rust
fn macos_dir_params() -> Vec<(String, PathBuf)> {
    if let Some(p) = confstr_path(libc::_CS_DARWIN_USER_CACHE_DIR) {
        return vec![("DARWIN_USER_CACHE_DIR".to_string(), p)];
    }
    vec![]
}
```

## 关键代码路径与文件引用

### 引用关系
```
seatbelt.rs (line 29)
  └── const MACOS_SEATBELT_NETWORK_POLICY: &str
      └── include_str!("seatbelt_network_policy.sbpl")
```

### 使用流程
1. `dynamic_network_policy` 根据配置决定网络策略
2. 如果启用受限网络，将本文件内容追加到策略
3. 动态添加代理特定的规则

### 相关文件
- `seatbelt_base_policy.sbpl` - 基础策略
- `seatbelt.rs` - 动态策略生成

## 依赖与外部交互

### 系统依赖
- **macOS 网络框架**: `SystemConfiguration`, `networkd`
- **安全框架**: `SecurityServer`, `trustd`, `ocspd`
- **XPC**: Mach IPC 机制

### 与动态策略的交互
本文件提供静态网络基线，动态策略添加：
- 代理端口特定规则
- Unix socket 规则
- 本地绑定规则

```rust
let network_policy = dynamic_network_policy_for_network(
    network_sandbox_policy,
    enforce_managed_network,
    &proxy,
);
// 可能包含 MACOS_SEATBELT_NETWORK_POLICY
```

## 风险、边界与改进建议

### 潜在风险

1. **证书验证绕过**
   - 允许与 `ocspd` 和 `trustd` 通信
   - 恶意代码可能尝试干扰证书验证

2. **网络配置泄露**
   - 允许读取 DNS 配置和路由表
   - 可能泄露网络拓扑信息

3. **缓存污染**
   - 允许写入用户缓存目录
   - 可能污染网络缓存或证书缓存

### 边界限制

1. **受限的网络访问**
   - 仅允许系统服务通信
   - 不直接允许互联网访问（由动态策略控制）

2. **平台特定**
   - 仅适用于 macOS
   - 使用 macOS 特定的 Mach 服务

3. **无出站控制**
   - 本文件不限制出站网络连接
   - 完全依赖动态策略控制

### 改进建议

1. **细化 Mach 服务访问**
   ```lisp
   ; 当前：允许所有 SecurityServer 通信
   ; 建议：考虑限制到特定操作
   (allow mach-lookup
     (global-name "com.apple.SecurityServer")
     (require-all
       (message-type "certificate_eval")))
   ```

2. **缓存隔离**
   ```lisp
   ; 当前：允许整个 DARWIN_USER_CACHE_DIR
   ; 建议：创建子目录专门用于沙盒缓存
   (subpath (param "CODEX_SANDBOX_CACHE_DIR"))
   ```

3. **审计日志**
   - 记录网络策略加载
   - 记录 Mach 服务访问

4. **文档完善**
   - 为每个 Mach 服务添加注释说明用途
   - 解释为什么需要 `AF_SYSTEM` socket

5. **与 Chrome 同步**
   - 定期与 Chrome 的网络沙盒策略对比
   - 参考注释中的 Chromium 链接更新

6. **测试覆盖**
   - 测试网络策略在各种网络配置下的行为
   - 测试证书验证是否正常工作
