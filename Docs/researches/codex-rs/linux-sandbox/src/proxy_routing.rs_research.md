# proxy_routing.rs 研究文档

## 场景与职责

`proxy_routing.rs` 实现了 Linux 沙箱的**托管代理路由**功能，解决在**网络隔离环境**中让沙箱内进程访问外部 HTTP/HTTPS 代理的问题。核心场景：

1. **安全网络访问**：用户配置了本地回环代理（如 `http://127.0.0.1:8080`），但沙箱使用 `--unshare-net` 隔离了网络命名空间
2. **代理路由桥接**：在主机网络命名空间和沙箱网络命名空间之间建立透明的 TCP 到 Unix Domain Socket (UDS) 桥接
3. **多代理支持**：支持 HTTP_PROXY、HTTPS_PROXY 等多种代理环境变量同时配置

## 功能点目的

### 1. 主机端路由准备 (`prepare_host_proxy_route_spec`)

在沙箱启动前（主机网络命名空间中）执行：
- 扫描环境变量中的代理配置
- 解析回环地址端点
- 创建 UDS 监听 socket
- 启动主机桥接进程（TCP ↔ UDS）
- 生成路由规范（JSON 序列化）传递给沙箱

### 2. 沙箱内路由激活 (`activate_proxy_routes_in_netns`)

在沙箱网络命名空间内执行：
- 解析主机传递的路由规范
- 启动本地桥接进程（UDS ↔ TCP）
- 重写环境变量指向本地端口
- 建立透明的双向数据流

### 3. 代理端点解析 (`parse_loopback_proxy_endpoint`)

智能解析代理 URL：
- 支持带 scheme（`http://127.0.0.1:8080`）和不带 scheme（`127.0.0.1:8080`）的格式
- 仅接受回环地址（localhost, 127.0.0.1, ::1）
- 根据 scheme 推断默认端口

### 4. 代理环境变量重写 (`rewrite_proxy_env_value`)

将原始代理 URL 重写为沙箱内可访问的地址：
- 保持 scheme 不变
- 替换 host 为 `127.0.0.1`
- 替换 port 为本地桥接端口

### 5. 生命周期管理

- **socket 目录创建**：使用 `0o700` 权限创建临时目录
- **僵尸进程清理**：通过 PID 检测清理已死亡的进程遗留目录
- **清理工作进程**：fork 守护进程监控桥接进程，自动清理资源

## 具体技术实现

### 核心数据结构

```rust
/// 路由规范（主机→沙箱传递）
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct ProxyRouteSpec {
    routes: Vec<ProxyRouteEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
struct ProxyRouteEntry {
    env_key: String,      // 如 "HTTP_PROXY"
    uds_path: PathBuf,    // 如 "/tmp/codex-linux-sandbox-proxy-1234-0/proxy-route-0.sock"
}

/// 计划中的路由（主机端内部使用）
#[derive(Debug, Clone, PartialEq, Eq)]
struct PlannedProxyRoute {
    env_key: String,
    endpoint: SocketAddr,  // 如 127.0.0.1:8080
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ProxyRoutePlan {
    routes: Vec<PlannedProxyRoute>,
    has_proxy_config: bool,  // 用于错误诊断
}
```

### 支持的代理环境变量

```rust
const PROXY_ENV_KEYS: &[&str] = &[
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "FTP_PROXY",
    "YARN_HTTP_PROXY", "YARN_HTTPS_PROXY",
    "NPM_CONFIG_HTTP_PROXY", "NPM_CONFIG_HTTPS_PROXY", "NPM_CONFIG_PROXY",
    "BUNDLE_HTTP_PROXY", "BUNDLE_HTTPS_PROXY",
    "PIP_PROXY",
    "DOCKER_HTTP_PROXY", "DOCKER_HTTPS_PROXY",
];
```

### 主机桥接架构

```
主机网络命名空间                    沙箱网络命名空间
┌─────────────────┐                ┌─────────────────┐
│  代理服务器      │                │  应用程序        │
│  127.0.0.1:8080 │◄──────TCP──────┤                 │
└────────┬────────┘                │  HTTP_PROXY=    │
         │                         │  127.0.0.1:PORT │
         │    ┌─────────────────┐  └────────┬────────┘
         └───►│  host_bridge    │           │
              │  (TCP ↔ UDS)    │◄───UDS────┘
              │  bind: UDS路径   │
              └─────────────────┘
```

### 关键流程

#### 主机端准备流程

```rust
pub(crate) fn prepare_host_proxy_route_spec() -> io::Result<String> {
    // 1. 从环境变量收集代理配置
    let plan = plan_proxy_routes(&env);
    if plan.routes.is_empty() {
        return Err(...); // 无有效代理配置
    }
    
    // 2. 清理旧目录，创建新 socket 目录
    let socket_dir = create_proxy_socket_dir()?;
    
    // 3. 去重端点，分配 UDS 路径
    for route in &plan.routes {
        socket_by_endpoint.insert(route.endpoint, socket_path);
    }
    
    // 4. 为每个唯一端点启动主机桥接
    for (endpoint, socket_path) in &socket_by_endpoint {
        host_bridge_pids.push(spawn_host_bridge(*endpoint, socket_path)?);
    }
    
    // 5. 启动清理守护进程
    spawn_proxy_socket_dir_cleanup_worker(socket_dir, host_bridge_pids)?;
    
    // 6. 序列化路由规范
    serde_json::to_string(&ProxyRouteSpec { routes })
}
```

#### 主机桥接进程

```rust
fn run_host_bridge(endpoint: SocketAddr, uds_path: &Path, ready_fd: libc::c_int) -> io::Result<()> {
    set_parent_death_signal()?;  // PR_SET_PDEATHSIG
    
    // 绑定 UDS
    let listener = UnixListener::bind(uds_path)?;
    
    // 通知父进程就绪
    write_ready_signal(ready_fd)?;
    
    // 接受连接，为每个连接 spawn 线程
    loop {
        let (unix_stream, _) = listener.accept()?;
        std::thread::spawn(move || {
            let tcp_stream = TcpStream::connect(endpoint)?;
            proxy_bidirectional(tcp_stream, unix_stream);
        });
    }
}
```

#### 沙箱内本地桥接

```rust
fn run_local_bridge(uds_path: &Path, ready_fd: libc::c_int) -> io::Result<()> {
    set_parent_death_signal()?;
    
    // 绑定到回环地址的随机端口
    let listener = bind_local_loopback_listener()?;
    let port = listener.local_addr()?.port();
    
    // 通知父进程端口号
    write_port(ready_fd, port)?;
    
    // 接受连接，转发到 UDS
    loop {
        let (tcp_stream, _) = listener.accept()?;
        let unix_stream = UnixStream::connect(uds_path)?;
        proxy_bidirectional(tcp_stream, unix_stream);
    }
}
```

#### 双向代理

```rust
fn proxy_bidirectional(mut tcp_stream: TcpStream, mut unix_stream: UnixStream) -> io::Result<()> {
    // 克隆流以实现双向并发
    let mut tcp_reader = tcp_stream.try_clone()?;
    let mut unix_writer = unix_stream.try_clone()?;
    
    // TCP → UDS 在一个线程
    let tcp_to_unix = std::thread::spawn(|| {
        std::io::copy(&mut tcp_reader, &mut unix_writer)
    });
    
    // UDS → TCP 在主线程
    let unix_to_tcp = std::io::copy(&mut unix_stream, &mut tcp_stream)?;
    
    tcp_to_unix.join()?.?;
    unix_to_tcp?;
    Ok(())
}
```

### 环路接口处理

当绑定到回环地址失败时（容器环境常见），尝试启动 `lo` 接口：

```rust
fn ensure_loopback_interface_up() -> io::Result<()> {
    // 创建 socket
    let fd = unsafe { libc::socket(libc::AF_INET, libc::SOCK_DGRAM | libc::SOCK_CLOEXEC, 0) };
    
    // 获取当前 flags
    let mut ifreq = ...;
    unsafe { libc::ioctl(fd, libc::SIOCGIFFLAGS, &mut ifreq) };
    
    // 设置 IFF_UP
    ifreq.ifr_ifru.ifru_flags |= libc::IFF_UP as libc::c_short;
    unsafe { libc::ioctl(fd, libc::SIOCSIFFLAGS, &ifreq) };
    
    // 设置回环地址 127.0.0.1
    let loopback_addr = libc::sockaddr_in { ... };
    unsafe { libc::ioctl(fd, libc::SIOCSIFADDR, &addr_req) };
}
```

## 关键代码路径与文件引用

### 内部依赖

| 函数/类型 | 定义位置 | 用途 |
|-----------|---------|------|
| `create_ready_pipe` | `proxy_routing.rs:630-637` | 创建父子进程同步管道 |
| `close_fd` | `proxy_routing.rs:639-645` | 安全关闭文件描述符 |
| `set_parent_death_signal` | `proxy_routing.rs:606-615` | 设置 PR_SET_PDEATHSIG |

### 外部调用

| 调用方 | 被调用函数 | 位置 |
|--------|-----------|------|
| `linux_run_main.rs` | `prepare_host_proxy_route_spec` | `linux_run_main.rs:181` |
| `linux_run_main.rs` | `activate_proxy_routes_in_netns` | `linux_run_main.rs:143` |

### 系统调用

| 系统调用 | 用途 |
|---------|------|
| `libc::fork()` | 创建桥接子进程和清理守护进程 |
| `libc::pipe2()` | 创建就绪通知管道 |
| `libc::prctl(PR_SET_PDEATHSIG)` | 父进程死亡时终止子进程 |
| `libc::kill(pid, 0)` | 检测进程是否存在 |
| `libc::socket()` | 创建网络 socket |
| `libc::ioctl(SIOCGIFFLAGS/SIOCSIFFLAGS/SIOCSIFADDR)` | 配置网络接口 |

## 依赖与外部交互

### 外部 crate

| Crate | 用途 |
|-------|------|
| `serde`/`serde_json` | 路由规范序列化 |
| `url::Url` | 代理 URL 解析 |
| `libc` | 系统调用封装 |

### 文件系统交互

- **临时目录**：`$CODEX_HOME/tmp` 或系统临时目录
- **权限**：`0o700` 确保其他用户无法访问 socket
- **命名模式**：`codex-linux-sandbox-proxy-{pid}-{attempt}`

### 进程管理

- **子进程监控**：通过 `kill(pid, 0)` 轮询检测
- **清理策略**：100ms 轮询间隔，桥接进程全部退出后清理目录
- **僵尸处理**：启动时扫描并清理无主目录

## 风险、边界与改进建议

### 当前风险

1. **资源泄漏风险**：
   - 如果父进程异常终止，依赖 `PR_SET_PDEATHSIG` 通知子进程
   - 信号可能丢失（如父进程被 SIGKILL）
   - 缓解：启动时的僵尸目录清理

2. **并发限制**：
   - 每个连接 spawn 一个新线程，无上限
   - 恶意应用可能通过大量连接耗尽资源

3. **安全性**：
   - UDS 路径在临时目录中，权限 `0o700`
   - 但同一用户的其他进程仍可访问

### 边界情况

1. **代理 URL 格式**：
   - 支持 `http://`, `https://`, `socks5://` 等 scheme
   - 支持带/不带 scheme 的简写形式
   - 仅接受回环地址（安全边界）

2. **端口冲突**：
   - 本地桥接使用随机端口（bind 到 0）
   - 如果回环接口未启动，尝试自动启动

3. **目录创建竞争**：
   - 128 次尝试创建唯一目录
   - 使用 PID + 递增计数器避免冲突

### 改进建议

1. **连接限制**：
   ```rust
   // 添加连接数限制
   static CONNECTION_COUNT: AtomicUsize = AtomicUsize::new(0);
   const MAX_CONNECTIONS: usize = 100;
   ```

2. **超时处理**：
   - 为 TCP 连接添加超时
   - 为 UDS 连接添加超时
   - 防止半开连接占用资源

3. **日志记录**：
   - 当前完全静默，建议添加可选的调试日志
   - 记录代理路由建立/断开事件

4. **优雅关闭**：
   - 使用 `Arc<AtomicBool>` 信号机制
   - 支持优雅关闭而非直接 `_exit`

5. **IPv6 支持增强**：
   - 当前仅支持 `::1` 字面量
   - 考虑支持其他 IPv6 回环形式

6. **测试覆盖**：
   - 添加多代理并发测试
   - 添加父进程异常终止测试
   - 添加大流量压力测试

7. **错误信息改进**：
   - 区分"无代理配置"和"代理配置无效"
   - 提供更具体的诊断信息
