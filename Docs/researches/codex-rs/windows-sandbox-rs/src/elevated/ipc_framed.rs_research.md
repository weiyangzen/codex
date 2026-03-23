# ipc_framed.rs 研究文档

## 场景与职责

`ipc_framed.rs` 定义了 Windows 沙箱系统中**提升权限路径（elevated path）**的 IPC（进程间通信）协议。该协议用于父进程（Codex CLI）与提升权限的命令运行器（command_runner_win.rs）之间的双向通信。

### 核心场景

1. **进程启动协调**：父进程发送启动参数，运行器返回进程就绪通知
2. **流式 I/O**：运行器将子进程的 stdout/stderr 流式传输回父进程
3. **交互式输入**：父进程向运行器发送 stdin 数据
4. **生命周期控制**：父进程发送终止信号，运行器返回退出状态

### 协议特点

- **长度前缀帧**：每个消息以 4 字节小端长度前缀开头，后跟 JSON 编码的负载
- **Base64 编码**：二进制数据（如 stdin/stdout）使用 Base64 编码传输
- **版本控制**：支持协议版本协商（当前为版本 1）
- **类型安全**：使用 Rust 强类型和 serde 进行序列化/反序列化

### 与传统路径的区别

| 特性 | Elevated Path（IPC） | Legacy Path（直接） |
|------|---------------------|---------------------|
| 通信方式 | 命名管道 + 帧协议 | 直接句柄继承 |
| TTY 支持 | 是（通过 ConPTY） | 有限 |
| 超时控制 | 运行器端管理 | 父进程管理 |
| 进程终止 | 显式 Terminate 消息 | 直接 TerminateProcess |

## 功能点目的

### 1. 帧格式定义
- **目的**：提供可靠的消息边界检测和版本协商
- **格式**：`[4字节长度][JSON负载]`，小端序
- **最大帧大小**：8MB（防止内存耗尽攻击）

### 2. 消息类型系统
- **目的**：支持多种消息类型的区分路由
- **机制**：使用 serde 的 internally tagged enum，`type` 字段作为标签
- **序列化**：snake_case 命名规范

### 3. 数据编码
- **目的**：在 JSON 中安全传输二进制数据
- **机制**：Base64 编码（标准字符集，无填充优化）

### 4. 错误传播
- **目的**：将运行器端的错误信息传递回父进程
- **结构**：包含错误代码和可读消息

## 具体技术实现

### 关键数据结构

#### 帧包装器
```rust
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FramedMessage {
    pub version: u8,           // 协议版本，当前为 1
    #[serde(flatten)]
    pub message: Message,      // 实际消息内容
}
```

#### 消息类型枚举
```rust
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Message {
    SpawnRequest { payload: Box<SpawnRequest> },    // 父 -> 运行器：启动请求
    SpawnReady { payload: SpawnReady },             // 运行器 -> 父：进程就绪
    Output { payload: OutputPayload },              // 运行器 -> 父：输出数据
    Stdin { payload: StdinPayload },                // 父 -> 运行器：输入数据
    Exit { payload: ExitPayload },                  // 运行器 -> 父：进程退出
    Error { payload: ErrorPayload },                // 运行器 -> 父：错误信息
    Terminate { payload: EmptyPayload },            // 父 -> 运行器：终止信号
}
```

#### 启动请求（核心结构）
```rust
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SpawnRequest {
    pub command: Vec<String>,              // 命令及参数
    pub cwd: PathBuf,                      // 工作目录
    pub env: HashMap<String, String>,      // 环境变量
    pub policy_json_or_preset: String,     // 沙箱策略（JSON 或预设名称）
    pub sandbox_policy_cwd: PathBuf,       // 策略计算的基准目录
    pub codex_home: PathBuf,               // 沙箱用户的 Codex 主目录
    pub real_codex_home: PathBuf,          // 实际用户的 Codex 主目录
    pub cap_sids: Vec<String>,             // 能力 SID 列表
    pub timeout_ms: Option<u64>,           // 超时时间（毫秒）
    pub tty: bool,                         // 是否使用 TTY 模式
    #[serde(default)]
    pub stdin_open: bool,                  // 是否保持 stdin 打开
    #[serde(default)]
    pub use_private_desktop: bool,         // 是否使用私有桌面
}
```

#### 输出负载
```rust
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct OutputPayload {
    pub data_b64: String,                  // Base64 编码的数据
    pub stream: OutputStream,              // 流标识（Stdout/Stderr）
}

#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum OutputStream {
    Stdout,
    Stderr,
}
```

#### 退出负载
```rust
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ExitPayload {
    pub exit_code: i32,                    // 进程退出码
    pub timed_out: bool,                   // 是否因超时终止
}
```

### 帧编解码

#### 编码（write_frame）
```rust
pub fn write_frame<W: Write>(mut writer: W, msg: &FramedMessage) -> Result<()> {
    let payload = serde_json::to_vec(msg)?;           // JSON 序列化
    if payload.len() > MAX_FRAME_LEN {                // 大小检查（8MB）
        anyhow::bail!("frame too large: {}", payload.len());
    }
    let len = payload.len() as u32;
    writer.write_all(&len.to_le_bytes())?;            // 4字节小端长度
    writer.write_all(&payload)?;                      // JSON 负载
    writer.flush()?;
    Ok(())
}
```

#### 解码（read_frame）
```rust
pub fn read_frame<R: Read>(mut reader: R) -> Result<Option<FramedMessage>> {
    let mut len_buf = [0u8; 4];
    match reader.read_exact(&mut len_buf) {
        Ok(()) => {}
        Err(err) if err.kind() == std::io::ErrorKind::UnexpectedEof => {
            return Ok(None);                          // 正常 EOF
        }
        Err(err) => return Err(err.into()),
    }
    let len = u32::from_le_bytes(len_buf) as usize;
    if len > MAX_FRAME_LEN {                          // 大小检查
        anyhow::bail!("frame too large: {}", len);
    }
    let mut payload = vec![0u8; len];
    reader.read_exact(&mut payload)?;                 // 读取完整负载
    let msg: FramedMessage = serde_json::from_slice(&payload)?;  // JSON 反序列化
    Ok(Some(msg))
}
```

### Base64 编解码

```rust
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;

/// 编码二进制数据为 Base64 字符串
pub fn encode_bytes(data: &[u8]) -> String {
    STANDARD.encode(data)
}

/// 解码 Base64 字符串为二进制数据
pub fn decode_bytes(data: &str) -> Result<Vec<u8>> {
    Ok(STANDARD.decode(data.as_bytes())?)
}
```

## 关键代码路径与文件引用

### 当前文件结构

| 结构/函数 | 行号 | 职责 |
|-----------|------|------|
| `MAX_FRAME_LEN` | 24 | 最大帧大小限制（8MB） |
| `FramedMessage` | 27-32 | 帧包装器结构 |
| `Message` | 38-48 | 消息类型枚举 |
| `SpawnRequest` | 51-67 | 启动请求参数 |
| `SpawnReady` | 70-73 | 进程就绪通知 |
| `OutputPayload` | 76-80 | 输出数据负载 |
| `OutputStream` | 83-88 | 输出流标识 |
| `StdinPayload` | 91-94 | 输入数据负载 |
| `ExitPayload` | 97-101 | 退出状态负载 |
| `ErrorPayload` | 104-108 | 错误信息负载 |
| `EmptyPayload` | 111-112 | 空负载（控制消息） |
| `encode_bytes` | 115-117 | Base64 编码 |
| `decode_bytes` | 120-122 | Base64 解码 |
| `write_frame` | 125-135 | 写入帧 |
| `read_frame` | 138-153 | 读取帧 |

### 调用关系

```
command_runner_win.rs
    ├── read_frame()              # 读取 SpawnRequest
    ├── write_frame()             # 发送 SpawnReady, Output, Exit, Error
    ├── encode_bytes()            # 编码输出数据
    └── decode_bytes()            # 解码输入数据

elevated_impl.rs (父进程侧)
    ├── write_frame()             # 发送 SpawnRequest
    ├── read_frame()              # 读取 SpawnReady, Output, Exit, Error
    ├── encode_bytes()            # 编码输入数据
    └── decode_bytes()            # 解码输出数据
```

### 协议流程

```
Parent (elevated_impl.rs)          Runner (command_runner_win.rs)
        |                                      |
        |---- write_frame(SpawnRequest) ----->|
        |                                      |
        |<--- read_frame(SpawnReady) ---------|
        |                                      |
        |---- write_frame(Stdin) ------------>| (可选，重复)
        |                                      |
        |<--- read_frame(Output) -------------| (重复，stdout/stderr)
        |                                      |
        |---- write_frame(Terminate) -------->| (可选)
        |                                      |
        |<--- read_frame(Exit) ---------------|
        |                                      |
```

## 依赖与外部交互

### 输入依赖

| 来源 | 类型 | 说明 |
|------|------|------|
| `serde` | 序列化 | 结构体的 Serialize/Deserialize derive |
| `base64` | 编码 | 二进制数据的 Base64 编解码 |
| `anyhow` | 错误处理 | 错误类型和上下文 |

### 输出交互

| 目标 | 类型 | 说明 |
|------|------|------|
| 命名管道 | 字节流 | 通过 `write_frame`/`read_frame` |
| 调用方 | Rust 类型 | 直接返回反序列化的结构体 |

### 外部系统交互

该模块是纯协议层，不直接与操作系统交互，依赖 `std::io::Read/Write` 抽象。

## 风险、边界与改进建议

### 已知风险

1. **帧大小限制**
   - 当前限制为 8MB，如果子进程输出超过此大小的块，需要分帧
   - 实际实现中 `read_handle_loop` 使用 8KB 缓冲区，不会触发此限制

2. **JSON 编码开销**
   - 二进制数据需要 Base64 编码，增加约 33% 的传输开销
   - 对于大量数据传输可能成为瓶颈

3. **版本兼容性**
   - 当前硬编码版本为 1，未来版本升级需要向后兼容处理

4. **EOF 处理歧义**
   - `read_frame` 返回 `Ok(None)` 表示连接关闭，但调用方可能误以为是超时

5. **序列化失败**
   - 如果 `SpawnRequest` 包含无法序列化的路径（如非法 Unicode），serde 可能 panic

### 边界条件

| 边界 | 处理 |
|------|------|
| 帧大小 > 8MB | 返回错误，连接断开 |
| 意外 EOF | 返回 `Ok(None)` |
| 无效的 JSON | 返回 serde 错误 |
| 未知消息类型 | serde 反序列化失败 |
| Base64 解码失败 | 返回错误，通常跳过该消息 |

### 改进建议

1. **流控制机制**
   ```rust
   // 建议：添加窗口大小或背压机制防止内存溢出
   pub struct FlowControl {
       pub window_size: u32,
       pub pending_bytes: u32,
   }
   ```

2. **压缩支持**
   ```rust
   // 建议：对大帧添加可选的压缩
   pub struct CompressedPayload {
       pub algorithm: CompressionAlgorithm,  // "gzip", "zstd", etc.
       pub data: String,  // base64 encoded compressed data
   }
   ```

3. **心跳机制**
   ```rust
   // 建议：添加 Ping/Pong 消息检测连接健康
   pub enum Message {
       // ... existing variants
       Ping { payload: EmptyPayload },
       Pong { payload: EmptyPayload },
   }
   ```

4. **版本协商**
   ```rust
   // 建议：支持版本范围协商
   pub struct SpawnRequest {
       pub supported_versions: Vec<u8>,  // [1, 2]
       // ...
   }
   
   pub struct SpawnReady {
       pub negotiated_version: u8,
       // ...
   }
   ```

5. **二进制协议选项**
   - 考虑使用 Protocol Buffers 或 MessagePack 替代 JSON，减少解析开销和传输大小

6. **零拷贝优化**
   ```rust
   // 建议：对大数据使用内存映射或共享内存
   pub struct ShmOutput {
       pub shm_name: String,
       pub offset: u64,
       pub length: u64,
   }
   ```

7. **测试覆盖增强**
   - 当前只有一个基本测试，建议添加：
     - 大帧分片测试
     - 并发读写测试
     - 错误恢复测试
     - 版本不匹配测试

8. **文档完善**
   ```rust
   // 建议：为每个字段添加详细文档
   pub struct SpawnRequest {
       /// 要执行的命令及参数，argv[0] 应为可执行文件路径
       pub command: Vec<String>,
       /// 工作目录，必须是绝对路径
       pub cwd: PathBuf,
       // ...
   }
   ```

9. **类型安全改进**
   ```rust
   // 建议：使用 newtype 模式增强类型安全
   pub struct ExitCode(pub i32);
   pub struct TimeoutMs(pub u64);
   ```

10. **协议规范文档**
    - 建议编写独立的协议规范文档（如 PROTOCOL.md），详细描述：
      - 帧格式字节级定义
      - 状态机转换图
      - 错误处理策略
      - 兼容性保证
