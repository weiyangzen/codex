# socket.rs 研究文档

## 场景与职责

`socket.rs` 是 Unix 平台 shell 权限提升机制的**底层通信基础设施**，提供支持文件描述符（FD）传递的异步 socket 抽象。它是客户端与服务器之间所有通信的基础，支持两种 socket 类型：
1. **Stream Socket**（`AsyncSocket`）：用于主要的请求/响应通信
2. **Datagram Socket**（`AsyncDatagramSocket`）：用于初始握手和 FD 传递

核心职责：
1. 提供异步 socket 操作（基于 `tokio::io::unix::AsyncFd`）
2. 支持通过 Unix domain socket 传递文件描述符（SCM_RIGHTS）
3. 实现基于长度前缀的帧协议
4. 处理大消息的分片和重组
5. 提供安全的 FD 接收和所有权管理

## 功能点目的

### 1. AsyncSocket（流式 Socket）

```rust
pub(crate) struct AsyncSocket {
    inner: AsyncFd<Socket>,
}
```

基于 `SOCK_STREAM` 的异步 socket，特点：
- 面向连接的可靠传输
- 支持大消息（通过帧协议分片）
- 支持随消息传递 FD

主要方法：
- `pair()`：创建连接的 socket pair
- `from_fd()`：从现有 FD 创建
- `send()` / `send_with_fds()`：发送消息
- `receive()` / `receive_with_fds()`：接收消息

### 2. AsyncDatagramSocket（数据报 Socket）

```rust
pub(crate) struct AsyncDatagramSocket {
    inner: AsyncFd<Socket>,
}
```

基于 `SOCK_DGRAM` 的异步 socket，特点：
- 无连接，消息边界保留
- 适合短消息和初始握手
- 单次操作可传递 FD

主要方法：
- `pair()`：创建连接的 datagram socket pair
- `from_raw_fd()`：从原始 FD 创建（unsafe）
- `send_with_fds()`：发送数据和 FD
- `receive_with_fds()`：接收数据和 FD

### 3. 帧协议

Stream socket 使用基于长度前缀的帧协议：

```
[4 bytes: payload length (little-endian u32)] [N bytes: payload]
```

实现函数：
- `read_frame()`：读取完整帧（header + payload）
- `read_frame_header()`：读取帧头（长度 + FDs）
- `read_frame_payload()`：读取帧 payload
- `send_stream_frame()`：发送完整帧
- `encode_length()`：编码长度前缀

### 4. SCM_RIGHTS 支持

Unix domain socket 的 `SCM_RIGHTS` 控制消息允许在进程间传递文件描述符：

```rust
fn make_control_message(fds: &[OwnedFd]) -> std::io::Result<Vec<u8>>;
fn extract_fds(control: &[u8]) -> Vec<OwnedFd>;
```

- `make_control_message`：创建包含 FD 的控制消息（`cmsghdr` + `CMSG_DATA`）
- `extract_fds`：从控制消息中提取 FD

## 具体技术实现

### 帧协议详解

**发送流程**：
```rust
pub async fn send_with_fds<T: Serialize>(
    &self,
    msg: T,
    fds: &[OwnedFd],
) -> std::io::Result<()> {
    // 1. 序列化消息
    let payload = serde_json::to_vec(&msg)?;
    
    // 2. 构建帧：[length][payload]
    let mut frame = Vec::with_capacity(LENGTH_PREFIX_SIZE + payload.len());
    frame.extend_from_slice(&encode_length(payload.len())?);
    frame.extend_from_slice(&payload);
    
    // 3. 发送帧（首次写入包含 FDs）
    send_stream_frame(&self.inner, &frame, fds).await
}
```

**接收流程**：
```rust
async fn read_frame(async_socket: &AsyncFd<Socket>) -> std::io::Result<(Vec<u8>, Vec<OwnedFd>)> {
    // 1. 读取帧头（4 字节长度 + FDs）
    let (message_len, fds) = read_frame_header(async_socket).await?;
    
    // 2. 读取 payload
    let payload = read_frame_payload(async_socket, message_len).await?;
    
    Ok((payload, fds))
}
```

### SCM_RIGHTS 实现

**发送端**（`make_control_message`）：
```rust
fn make_control_message(fds: &[OwnedFd]) -> std::io::Result<Vec<u8>> {
    if fds.len() > MAX_FDS_PER_MESSAGE { ... }
    
    let mut control = vec![0u8; control_space_for_fds(fds.len())];
    unsafe {
        let cmsg = control.as_mut_ptr().cast::<libc::cmsghdr>();
        (*cmsg).cmsg_len = libc::CMSG_LEN(size_of::<RawFd>() as c_uint * fds.len() as c_uint) as _;
        (*cmsg).cmsg_level = libc::SOL_SOCKET;
        (*cmsg).cmsg_type = libc::SCM_RIGHTS;
        let data_ptr = libc::CMSG_DATA(cmsg).cast::<RawFd>();
        for (i, fd) in fds.iter().enumerate() {
            data_ptr.add(i).write(fd.as_raw_fd());
        }
    }
    Ok(control)
}
```

**接收端**（`extract_fds`）：
```rust
fn extract_fds(control: &[u8]) -> Vec<OwnedFd> {
    let mut fds = Vec::new();
    let mut hdr: libc::msghdr = unsafe { std::mem::zeroed() };
    hdr.msg_control = control.as_ptr() as *mut libc::c_void;
    hdr.msg_controllen = control.len() as _;
    
    let mut cmsg = unsafe { libc::CMSG_FIRSTHDR(&hdr) as *const libc::cmsghdr };
    while !cmsg.is_null() {
        if (*cmsg).cmsg_level == libc::SOL_SOCKET && (*cmsg).cmsg_type == libc::SCM_RIGHTS {
            let data_ptr = unsafe { libc::CMSG_DATA(cmsg).cast::<RawFd>() };
            let fd_count = ...; // 计算 FD 数量
            for i in 0..fd_count {
                let fd = unsafe { data_ptr.add(i).read() };
                fds.push(unsafe { OwnedFd::from_raw_fd(fd) });
            }
        }
        cmsg = unsafe { libc::CMSG_NXTHDR(&hdr, cmsg) };
    }
    fds
}
```

### 常量定义

```rust
const MAX_FDS_PER_MESSAGE: usize = 16;      // 单条消息最大 FD 数
const LENGTH_PREFIX_SIZE: usize = size_of::<u32>();  // 长度前缀大小
const MAX_DATAGRAM_SIZE: usize = 8192;      // 最大数据报大小
```

### Socket 创建

**Stream Socket Pair**：
```rust
pub fn pair() -> std::io::Result<(AsyncSocket, AsyncSocket)> {
    // 使用 pair_raw 避免 SO_NOSIGPIPE 等副作用
    let (server, client) = Socket::pair_raw(Domain::UNIX, Type::STREAM, None)?;
    server.set_cloexec(true)?;
    client.set_cloexec(true)?;
    Ok((AsyncSocket::new(server)?, AsyncSocket::new(client)?))
}
```

**Datagram Socket Pair**：
```rust
pub fn pair() -> std::io::Result<(Self, Self)> {
    let (server, client) = Socket::pair_raw(Domain::UNIX, Type::DGRAM, None)?;
    server.set_cloexec(true)?;
    client.set_cloexec(true)?;
    Ok((Self::new(server)?, Self::new(client)?))
}
```

**注意**：使用 `pair_raw` 而非 `pair`，避免 Apple 平台上的 `SO_NOSIGPIPE` 等副作用。

## 关键代码路径与文件引用

### 本文件内关键行

| 行号 | 内容 | 说明 |
|------|------|------|
| 19-21 | 常量定义 | `MAX_FDS_PER_MESSAGE`, `LENGTH_PREFIX_SIZE`, `MAX_DATAGRAM_SIZE` |
| 24-42 | `assume_init` 辅助函数 | 处理 `MaybeUninit` 转换 |
| 44-46 | `control_space_for_fds` | 计算控制消息空间 |
| 48-75 | `extract_fds` | 从 SCM_RIGHTS 提取 FD |
| 77-85 | `read_frame` | 读取完整帧 |
| 87-141 | `read_frame_header` | 读取帧头（长度 + FDs） |
| 143-173 | `read_frame_payload` | 读取帧 payload |
| 175-194 | `send_datagram_bytes` | 发送数据报 |
| 196-204 | `encode_length` | 编码长度前缀 |
| 206-229 | `make_control_message` | 创建 SCM_RIGHTS 控制消息 |
| 231-245 | `receive_datagram_bytes` | 接收数据报 |
| 247-313 | `AsyncSocket` | 流式 socket 实现 |
| 315-360 | `send_stream_frame` / `send_stream_chunk` | 流式帧发送 |
| 362-406 | `AsyncDatagramSocket` | 数据报 socket 实现 |
| 408-519 | 测试模块 | comprehensive tests |

### 依赖文件

- `codex-rs/shell-escalation/src/unix/escalate_client.rs`：使用 `AsyncDatagramSocket`, `AsyncSocket`
- `codex-rs/shell-escalation/src/unix/escalate_server.rs`：使用 `AsyncDatagramSocket`, `AsyncSocket`

### 被依赖文件

本文件是底层基础设施，被 `escalate_client.rs` 和 `escalate_server.rs` 使用。

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `libc` | `cmsghdr`, `CMSG_*` 宏, `SOL_SOCKET`, `SCM_RIGHTS` |
| `serde::Deserialize`, `serde::Serialize` | 消息序列化 |
| `socket2::Domain`, `socket2::Socket`, `socket2::Type` | 底层 socket 操作 |
| `tokio::io::Interest`, `tokio::io::unix::AsyncFd` | 异步 IO |

### 关键数据结构

```rust
// 流式 Socket（面向连接，支持大消息）
pub(crate) struct AsyncSocket {
    inner: AsyncFd<Socket>,
}

// 数据报 Socket（无连接，消息边界保留）
pub(crate) struct AsyncDatagramSocket {
    inner: AsyncFd<Socket>,
}
```

### 消息流程

```
发送方:
    序列化消息 (serde_json::to_vec)
        ↓
    构建帧: [length: u32][payload: bytes]
        ↓
    创建控制消息 (make_control_message, 如果有 FDs)
        ↓
    sendmsg (首次写入包含 FDs)

接收方:
    recvmsg (读取帧头，捕获 FDs)
        ↓
    解析长度
        ↓
    读取 payload
        ↓
    提取 FDs (extract_fds)
        ↓
    反序列化消息 (serde_json::from_slice)
```

## 风险、边界与改进建议

### 已知风险

1. **FD 数量限制**：`MAX_FDS_PER_MESSAGE = 16` 是硬编码限制，超过会返回错误。这个限制来自 `libc::CMSG_SPACE` 的缓冲区大小。

2. **大消息处理**：虽然帧协议支持大消息，但 `encode_length` 使用 `u32`，最大支持 4GB payload。实际受限于可用内存。

3. **数据报大小限制**：`MAX_DATAGRAM_SIZE = 8192`，超过此大小的数据报会被截断。

4. **Unsafe 代码**：使用大量 `unsafe` 代码操作 `libc` 结构，需要仔细审查：
   - `assume_init` 系列函数
   - `CMSG_DATA`, `CMSG_FIRSTHDR`, `CMSG_NXTHDR` 调用
   - `OwnedFd::from_raw_fd`

### 边界情况

1. **FD 重叠**：当接收到的 FD 编号与目标 FD 相同时（如都是 0），`dup2` 会正确处理。这在 `escalate_server.rs` 的测试中被验证。

2. **空消息**：`read_frame_payload` 正确处理 `message_len == 0` 的情况，返回空 Vec。

3. **连接关闭**：
   - 读取时遇到 EOF 返回 `UnexpectedEof` 错误
   - 写入时遇到关闭返回 `WriteZero` 错误

4. **部分写入**：`send_stream_chunk` 返回实际写入的字节数，调用者需要循环直到全部写入。

### 测试覆盖

文件包含 comprehensive 的测试套件（约 110 行测试代码）：

| 测试 | 目的 |
|------|------|
| `async_socket_round_trips_payload_and_fds` | 验证完整的消息 + FD 往返 |
| `async_socket_handles_large_payload` | 验证大消息（10KB）处理 |
| `async_datagram_sockets_round_trip_messages` | 验证数据报 socket |
| `send_datagram_bytes_rejects_excessive_fd_counts` | 验证 FD 数量限制 |
| `send_stream_chunk_rejects_excessive_fd_counts` | 验证 FD 数量限制 |
| `encode_length_errors_for_oversized_messages` | 验证消息大小限制 |
| `receive_fails_when_peer_closes_before_header` | 验证连接关闭处理 |

### 改进建议

1. **FD 数量可配置**：将 `MAX_FDS_PER_MESSAGE` 改为可配置参数：
   ```rust
   pub const fn max_fds_per_message() -> usize { 16 }
   ```

2. **零拷贝优化**：对于大 payload，考虑使用 `bytes::Bytes` 避免拷贝。

3. **更详细的错误类型**：
   ```rust
   pub enum SocketError {
       TooManyFds { requested: usize, max: usize },
       MessageTooLarge { size: usize },
       UnexpectedEof,
       // ...
   }
   ```

4. **超时支持**：为读写操作添加超时参数：
   ```rust
   pub async fn receive_with_timeout<T>(
       &self,
       timeout: Duration,
   ) -> std::io::Result<T>;
   ```

5. **指标收集**：添加可选的指标收集（消息数量、大小、FD 数量等）：
   ```rust
   pub struct SocketMetrics {
       pub messages_sent: AtomicU64,
       pub bytes_sent: AtomicU64,
       pub fds_sent: AtomicU64,
   }
   ```

6. **安全审查**：对 `unsafe` 代码块进行形式化验证或 fuzz 测试。

7. **文档示例**：添加使用示例：
   ```rust
   /// # Example
   /// ```
   /// let (server, client) = AsyncSocket::pair()?;
   /// 
   /// // 发送消息
   /// client.send("hello").await?;
   /// 
   /// // 接收消息
   /// let msg: String = server.receive().await?;
   /// ```
   ```

### 性能考虑

1. **缓冲区分配**：每次发送都分配新的 Vec，对于高频场景可以考虑使用对象池。

2. **序列化**：使用 `serde_json`，如果性能成为瓶颈可以考虑 `bincode` 或 `rkyv`。

3. **异步等待**：使用 `AsyncFd` 的 `readable()` / `writable()` 等待，避免忙等。

4. **系统调用**：每次 `send_with_fds` 至少两次系统调用（`sendmsg` 循环直到完成），对于小消息可以考虑批量发送。
