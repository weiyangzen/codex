# Linux Sandbox Managed Proxy 测试套件研究文档

## 场景与职责

`managed_proxy.rs` 是 Codex Linux Sandbox 的托管代理模式测试文件，负责验证在受限网络环境下通过托管 HTTP/HTTPS 代理进行安全网络访问的机制。该测试套件覆盖以下核心场景：

1. **托管代理模式验证**：确保当配置代理环境变量时，沙箱正确路由网络流量
2. **网络隔离与代理桥接**：验证直接出站连接被阻断，仅代理连接被允许
3. **Fail-Closed 安全模型**：确保未配置代理时命令执行失败（而非静默允许直接访问）
4. **Unix 域套接字限制**：验证在代理模式下 AF_UNIX 套接字创建被禁止（防止绕过代理）

托管代理模式是 Codex 沙箱的关键安全特性，允许 AI 代理在受控网络环境下访问外部资源，同时防止未经授权的直接网络连接。

## 功能点目的

### 1. Fail-Closed 安全验证
- **测试** (`managed_proxy_mode_fails_closed_without_proxy_env`)：验证当启用代理模式但未配置代理环境变量时，命令执行失败
- **目的**：防止配置错误导致意外开放网络访问

### 2. 代理路由与直接出站阻断
- **测试** (`managed_proxy_mode_routes_through_bridge_and_blocks_direct_egress`)：
  - 启动本地 TCP 监听器模拟 HTTP 代理
  - 验证 HTTP 请求通过代理路由（使用绝对路径形式的 HTTP 请求）
  - 验证直接 TCP 连接（`/dev/tcp/192.0.2.1/80`）被阻断

### 3. Unix 域套接字限制
- **测试** (`managed_proxy_mode_denies_af_unix_creation_for_user_command`)：
  - 使用 Python 尝试创建 AF_UNIX 套接字
  - 验证返回 `PermissionError`（exit code 0 表示被正确拒绝）
- **目的**：防止通过 Unix 域套接字绕过代理路由

## 具体技术实现

### 关键常量定义

```rust
// 代理环境变量键名列表（大小写敏感）
const PROXY_ENV_KEYS: &[&str] = &[
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "FTP_PROXY",
    "YARN_HTTP_PROXY", "YARN_HTTPS_PROXY",
    "NPM_CONFIG_HTTP_PROXY", "NPM_CONFIG_HTTPS_PROXY", "NPM_CONFIG_PROXY",
    "BUNDLE_HTTP_PROXY", "BUNDLE_HTTPS_PROXY",
    "PIP_PROXY",
    "DOCKER_HTTP_PROXY", "DOCKER_HTTPS_PROXY",
];

// 托管代理权限错误片段（用于检测环境限制）
const MANAGED_PROXY_PERMISSION_ERR_SNIPPETS: &[&str] = &[
    "loopback: Failed RTM_NEWADDR",
    "loopback: Failed RTM_NEWLINK",
    "setting up uid map: Permission denied",
    "No permissions to create a new namespace",
    "error isolating Linux network namespace for proxy mode",
];

const NETWORK_TIMEOUT_MS: u64 = 4_000;
```

### 核心辅助函数

#### `strip_proxy_env`
清除环境变量中的所有代理设置：

```rust
fn strip_proxy_env(env: &mut HashMap<String, String>) {
    for key in PROXY_ENV_KEYS {
        env.remove(*key);
        let lower = key.to_ascii_lowercase();
        env.remove(lower.as_str());
    }
}
```

注意：同时处理大写和小写形式（某些工具使用小写 `http_proxy`）。

#### `managed_proxy_skip_reason`
检测当前环境是否支持托管代理测试：

```rust
async fn managed_proxy_skip_reason() -> Option<String> {
    // 1. 首先检查 bwrap 是否可用
    if should_skip_bwrap_tests().await {
        return Some("vendored bwrap was not built in this environment".to_string());
    }

    // 2. 测试代理模式下的基本执行能力
    let mut env = create_env_from_core_vars();
    strip_proxy_env(&mut env);
    env.insert("HTTP_PROXY".to_string(), "http://127.0.0.1:9".to_string());

    let output = run_linux_sandbox_direct(
        &["bash", "-c", "true"],
        &SandboxPolicy::DangerFullAccess,
        true,  // allow_network_for_proxy
        env,
        NETWORK_TIMEOUT_MS,
    ).await;
    
    if output.status.success() {
        return None;  // 测试可以执行
    }

    // 3. 检查是否是权限错误（如缺少网络命名空间权限）
    let stderr = String::from_utf8_lossy(&output.stderr);
    if is_managed_proxy_permission_error(stderr.as_ref()) {
        return Some(format!(
            "managed proxy requires kernel namespace privileges unavailable here: {}",
            stderr.trim()
        ));
    }

    None
}
```

#### `run_linux_sandbox_direct`
直接调用 `codex-linux-sandbox` 二进制：

```rust
async fn run_linux_sandbox_direct(
    command: &[&str],
    sandbox_policy: &SandboxPolicy,
    allow_network_for_proxy: bool,
    env: HashMap<String, String>,
    timeout_ms: u64,
) -> Output {
    // 1. 序列化策略为 JSON
    let policy_json = serde_json::to_string(sandbox_policy).unwrap();

    // 2. 构建命令行参数
    let mut args = vec![
        "--sandbox-policy-cwd".to_string(),
        cwd.to_string_lossy().to_string(),
        "--sandbox-policy".to_string(),
        policy_json,
    ];
    if allow_network_for_proxy {
        args.push("--allow-network-for-proxy".to_string());
    }
    args.push("--".to_string());
    args.extend(command.iter().map(|entry| (*entry).to_string()));

    // 3. 执行命令
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_codex-linux-sandbox"));
    cmd.args(args)
        .env_clear()
        .envs(env)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    
    tokio::time::timeout(Duration::from_millis(timeout_ms), cmd.output()).await
}
```

### 代理路由测试实现

```rust
#[tokio::test]
async fn managed_proxy_mode_routes_through_bridge_and_blocks_direct_egress() {
    // 1. 创建本地 TCP 监听器作为模拟代理
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).expect("bind proxy listener");
    let proxy_port = listener.local_addr().expect("proxy listener local addr").port();
    
    // 2. 在后台线程运行模拟代理服务器
    let (request_tx, request_rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept proxy connection");
        stream.set_read_timeout(Some(Duration::from_secs(3))).expect("set read timeout");
        
        let mut buf = [0_u8; 4096];
        let read = stream.read(&mut buf).expect("read proxy request");
        let request = String::from_utf8_lossy(&buf[..read]).to_string();
        request_tx.send(request).expect("send proxy request");
        
        // 返回模拟 HTTP 响应
        stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK")
            .expect("write proxy response");
    });

    // 3. 配置代理环境变量
    let mut env = create_env_from_core_vars();
    strip_proxy_env(&mut env);
    env.insert("HTTP_PROXY".to_string(), format!("http://127.0.0.1:{proxy_port}"));

    // 4. 通过代理发送 HTTP 请求（使用 bash /dev/tcp 功能）
    let routed_output = run_linux_sandbox_direct(
        &[
            "bash",
            "-c",
            "proxy=\"${HTTP_PROXY#*://}\"; host=\"${proxy%%:*}\"; port=\"${proxy##*:}\"; 
             exec 3<>/dev/tcp/${host}/${port}; 
             printf 'GET http://example.com/ HTTP/1.1\\r\\nHost: example.com\\r\\n\\r\\n' >&3; 
             IFS= read -r line <&3; printf '%s\\n' \"$line\"",
        ],
        &SandboxPolicy::DangerFullAccess,
        true,
        env.clone(),
        NETWORK_TIMEOUT_MS,
    ).await;

    // 5. 验证代理收到了正确的 HTTP 请求（绝对路径形式）
    let request = request_rx.recv_timeout(Duration::from_secs(3)).expect("expected proxy request");
    assert!(request.contains("GET http://example.com/ HTTP/1.1"));

    // 6. 验证直接出站连接被阻断
    let direct_egress_output = run_linux_sandbox_direct(
        &["bash", "-c", "echo hi > /dev/tcp/192.0.2.1/80"],
        &SandboxPolicy::DangerFullAccess,
        true,
        env,
        NETWORK_TIMEOUT_MS,
    ).await;
    assert_eq!(direct_egress_output.status.success(), false);
}
```

### AF_UNIX 限制测试实现

```rust
#[tokio::test]
async fn managed_proxy_mode_denies_af_unix_creation_for_user_command() {
    // 使用 Python 测试 AF_UNIX 套接字创建
    let output = run_linux_sandbox_direct(
        &[
            "python3",
            "-c",
            "import socket,sys\n\
             try:\
                 socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n\
             except PermissionError:\
                 sys.exit(0)\n\
             except OSError:\
                 sys.exit(2)\n\
             sys.exit(1)\n",
        ],
        &SandboxPolicy::DangerFullAccess,
        true,
        env,
        NETWORK_TIMEOUT_MS,
    ).await;

    // exit code 0 表示 PermissionError 被正确抛出
    assert_eq!(output.status.code(), Some(0));
}
```

## 关键代码路径与文件引用

### 托管代理调用链

```
managed_proxy.rs test function
    ↓
run_linux_sandbox_direct
    ↓
codex-linux-sandbox --allow-network-for-proxy
    ↓
run_main (codex-rs/linux-sandbox/src/linux_run_main.rs:99)
    ↓
resolve_sandbox_policies
    ↓
[启用代理路径]
    ↓
prepare_host_proxy_route_spec (codex-rs/linux-sandbox/src/proxy_routing.rs)
    ↓
build_inner_seccomp_command (with proxy_route_spec)
    ↓
run_bwrap_with_proc_fallback (BwrapNetworkMode::ProxyOnly)
    ↓
exec_bwrap
    ↓
[内层执行]
    ↓
activate_proxy_routes_in_netns (codex-rs/linux-sandbox/src/proxy_routing.rs)
    ↓
apply_sandbox_policy_to_current_thread
    ↓
install_network_seccomp_filter_on_current_thread (NetworkSeccompMode::ProxyRouted)
```

### 相关文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/linux-sandbox/tests/suite/managed_proxy.rs` | 本测试文件 |
| `codex-rs/linux-sandbox/src/linux_run_main.rs` | 沙箱主入口，处理 `--allow-network-for-proxy` |
| `codex-rs/linux-sandbox/src/proxy_routing.rs` | 代理路由桥接实现 |
| `codex-rs/linux-sandbox/src/landlock.rs` | seccomp 策略应用（含 ProxyRouted 模式） |
| `codex-rs/linux-sandbox/src/bwrap.rs` | Bubblewrap 网络模式（ProxyOnly） |

### ProxyRouted Seccomp 策略

在 `codex-rs/linux-sandbox/src/landlock.rs` 中定义：

```rust
NetworkSeccompMode::ProxyRouted => {
    // 允许 IP 套接字（用于连接代理）
    let deny_non_ip_socket = SeccompRule::new(vec![
        SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_INET as u64)?,
        SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_INET6 as u64)?,
    ])?;
    
    // 禁止 AF_UNIX 套接字（防止绕过代理）
    let deny_unix_socketpair = SeccompRule::new(vec![
        SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Eq, libc::AF_UNIX as u64)?,
    ])?;
    
    rules.insert(libc::SYS_socket, vec![deny_non_ip_socket]);
    rules.insert(libc::SYS_socketpair, vec![deny_unix_socketpair]);
}
```

## 依赖与外部交互

### 外部依赖

1. **Python 3**：用于 AF_UNIX 测试（测试会检查 `python3` 是否可用）
2. **Bubblewrap**：必须支持网络命名空间隔离（`--unshare-net`）
3. **网络命名空间**：需要内核支持 `CLONE_NEWNET`
4. **RTNETLINK**：代理路由设置需要 `RTM_NEWADDR` 和 `RTM_NEWLINK` 权限

### 环境要求

```rust
// 权限错误检测
fn is_managed_proxy_permission_error(stderr: &str) -> bool {
    MANAGED_PROXY_PERMISSION_ERR_SNIPPETS
        .iter()
        .any(|snippet| stderr.contains(snippet))
}
```

常见限制环境：
- Docker 默认容器（缺少 `CAP_NET_ADMIN`）
- 某些 CI 环境（如 GitHub Actions 的某些 runner）
- 用户命名空间被禁用的系统

### 代理环境变量

测试覆盖的代理变量：
- 标准变量：`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`
- 工具特定：`YARN_*`, `NPM_CONFIG_*`, `BUNDLE_*`, `PIP_*`, `DOCKER_*`
- 大小写形式：同时处理 `HTTP_PROXY` 和 `http_proxy`

## 风险、边界与改进建议

### 已知风险

1. **环境依赖性强**：托管代理测试需要特定的内核和网络权限，在受限 CI 环境中经常跳过
2. **Python 依赖**：AF_UNIX 测试依赖 Python 3，如果未安装则跳过
3. **竞态条件**：代理服务器在后台线程运行，如果系统负载高可能导致超时

### 边界情况

1. **代理端口冲突**：使用 `TcpListener::bind((Ipv4Addr::LOCALHOST, 0))` 动态分配端口避免冲突
2. **IPv6 支持**：当前测试仅使用 IPv4（`127.0.0.1`），未覆盖 IPv6 代理场景
3. **认证代理**：测试未覆盖需要认证的 HTTP 代理

### 改进建议

1. **增强环境检测**：
   ```rust
   // 建议添加更详细的权限检测
   async fn check_network_namespace_support() -> Result<(), String> {
       // 检测 /proc/sys/user/max_net_namespaces
       // 检测当前用户的 namespace 配额
   }
   ```

2. **减少外部依赖**：
   - AF_UNIX 测试可以使用纯 Rust 二进制而非 Python
   - 或者使用 `socket` 系统调用的原始接口

3. **增加测试覆盖**：
   - HTTPS 代理测试（CONNECT 方法）
   - SOCKS5 代理支持
   - 代理认证（Basic/Digest）
   - IPv6 代理路由

4. **性能优化**：
   - 模拟代理服务器可以使用异步实现替代线程
   - 减少 `managed_proxy_skip_reason` 的重复调用

5. **错误诊断**：
   - 当前测试失败时只显示 exit code，建议捕获更多诊断信息
   - 添加 `strace` 输出选项用于调试 seccomp 违规

### 安全注意事项

1. **测试隔离**：模拟代理服务器仅绑定 `127.0.0.1`，不接受外部连接
2. **资源清理**：使用 `Drop` 确保 TCP 监听器在测试结束时关闭
3. **超时保护**：所有网络操作都有超时，防止测试挂起
4. **Fail-Closed 验证**：`managed_proxy_mode_fails_closed_without_proxy_env` 是安全关键测试，确保配置错误不会开放网络
