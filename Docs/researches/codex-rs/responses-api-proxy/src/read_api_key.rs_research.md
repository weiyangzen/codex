# codex-rs/responses-api-proxy/src/read_api_key.rs 研究文档

## 场景与职责

`read_api_key.rs` 是 `codex-responses-api-proxy` 中最关键的**安全模块**，负责从标准输入安全地读取 OpenAI API key，并确保其在内存中的安全存储。

### 核心安全目标

1. **最小化内存副本**：确保 API key 在内存中只有必要的副本
2. **防止交换到磁盘**：使用 `mlock(2)` 将内存页锁定在 RAM 中
3. **安全擦除**：使用 `zeroize` 确保临时缓冲区被安全清零
4. **输入验证**：验证 key 只包含允许的字符（`[A-Za-z0-9\-_]`）

## 功能点目的

### 1. 跨平台 API Key 读取

| 平台 | 实现方式 | 特点 |
|------|----------|------|
| Unix | 直接使用 `read(2)` 系统调用 | 避免 std::io::stdin() 的内部 BufReader 残留 |
| Windows | `std::io::stdin().read()` | 简化实现，TODO 标记需要改进 |

### 2. 内存安全策略

```
栈缓冲区（1024 bytes，已 zeroize）
    ↓ 复制
String（堆分配，精确大小）
    ↓ leak()
&'static str（进程生命周期）
    ↓ mlock(2)
锁定内存页（防止交换）
```

### 3. 输入验证

- 格式：`Bearer <key>`
- Key 字符集：`/^[A-Za-z0-9\-_]+$/`
- 最大长度：1024 - "Bearer ".len() = 1015 bytes

## 具体技术实现

### 关键数据结构

```rust
const BUFFER_SIZE: usize = 1024;
const AUTH_HEADER_PREFIX: &[u8] = b"Bearer ";

// 返回的静态字符串生命周期与进程相同
pub(crate) fn read_auth_header_from_stdin() -> Result<&'static str>
```

### 核心流程

```
read_auth_header_from_stdin()
├── 平台选择（Unix/Windows）
└── read_auth_header_with(read_fn)
    ├── 分配 1024 字节栈缓冲区，预填充 "Bearer "
    ├── 循环读取 stdin 到缓冲区
    │   ├── 处理短读取（short reads）
    │   ├── 查找换行符（\n 或 \r\n）
    │   └── 检查缓冲区溢出
    ├── 验证 key 非空
    ├── validate_auth_header_bytes() - 字符集验证
    ├── 转换为 String
    ├── buf.zeroize() - 清除栈缓冲区
    ├── String::leak() - 转为 &'static str
    └── mlock_str() - 锁定内存页（Unix only）
```

### Unix 低层读取实现

```rust
#[cfg(unix)]
fn read_from_unix_stdin(buffer: &mut [u8]) -> std::io::Result<usize> {
    loop {
        let result = unsafe {
            read(
                libc::STDIN_FILENO,
                buffer.as_mut_ptr().cast::<c_void>(),
                buffer.len(),
            )
        };

        if result == 0 { return Ok(0); }  // EOF
        if result < 0 {
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::Interrupted {
                continue;  // 处理信号中断
            }
            return Err(err);
        }
        return Ok(result as usize);
    }
}
```

**关键设计决策**：不使用 `std::io::stdin()` 因为其内部有 `BufReader`，可能在内存中保留不可控的数据副本。

### mlock 实现细节

```rust
#[cfg(unix)]
fn mlock_str(value: &str) {
    // 计算包含该字符串的完整内存页范围
    let page_size = unsafe { sysconf(_SC_PAGESIZE) };
    let addr = value.as_ptr() as usize;
    let len = value.len();
    
    // 对齐到页边界
    let start = addr & !(page_size - 1);
    let end = (addr + len + page_size - 1) & !(page_size - 1);
    let size = end - start;
    
    // 锁定内存页
    let _ = unsafe { mlock(start as *const c_void, size) };
}
```

**注意**：`mlock` 错误被静默忽略，这是有意的设计选择——安全加固失败不应阻止服务启动。

### 输入验证

```rust
fn validate_auth_header_bytes(key_bytes: &[u8]) -> Result<()> {
    if key_bytes
        .iter()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Ok(());
    }
    Err(anyhow!("API key may only contain ASCII letters, numbers, '-' or '_'"))
}
```

## 关键代码路径与文件引用

| 路径 | 说明 |
|------|------|
| `src/read_api_key.rs:16-30` | 平台特定的入口函数 |
| `src/read_api_key.rs:41-70` | Unix 低层 `read(2)` 实现 |
| `src/read_api_key.rs:72-162` | 核心读取逻辑 `read_auth_header_with` |
| `src/read_api_key.rs:164-201` | `mlock_str()` 内存锁定实现 |
| `src/read_api_key.rs:206-219` | `validate_auth_header_bytes()` 输入验证 |
| `src/read_api_key.rs:221-342` | 单元测试 |

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `zeroize` | 安全内存清零（防止编译器优化掉清零操作） |
| `libc` | Unix 系统调用（`read`, `mlock`, `sysconf`） |
| `anyhow` | 错误处理 |

### 系统调用（Unix）

| 调用 | 用途 |
|------|------|
| `read(2)` | 从 stdin 读取数据 |
| `mlock(2)` | 锁定内存页，防止交换到磁盘 |
| `sysconf(_SC_PAGESIZE)` | 获取内存页大小 |

### 标准库使用

- `std::str::from_utf8`：验证 UTF-8 编码
- `String::leak`：将 String 转为 `'static` 生命周期引用

## 风险、边界与改进建议

### 已知风险

1. **Windows 实现不完整**：当前 Windows 实现使用 `std::io::stdin()`，存在与 Unix 相同的安全隐患（BufReader 残留）。注释明确标记为 TODO。

2. **mlock 失败被忽略**：如果 `mlock` 失败（如超出 RLIMIT_MEMLOCK），错误被静默忽略，API key 可能被交换到磁盘。

3. **无长度限制警告**：虽然 1024 字节对当前 OpenAI key 足够，但未来格式变化可能导致截断。

4. **进程终止后内存不清零**：`leak()` 后的内存直到进程结束才被 OS 回收，期间如果发生 core dump 可能泄露 key。

### 边界条件

| 场景 | 行为 |
|------|------|
| 空输入 | 错误："API key must be provided via stdin" |
| 仅换行符 | 同上（空 key） |
| 超长 key (>1015 bytes) | 错误："API key is too large" |
| 非法字符 | 错误："may only contain ASCII letters, numbers, '-' or '_'" |
| 非 UTF-8 序列 | 被字符集验证拦截（非法字符错误） |
| 信号中断（EINTR） | 自动重试读取 |
| mlock 失败 | 静默忽略，继续执行 |

### 测试覆盖

模块包含 9 个单元测试：

| 测试 | 覆盖场景 |
|------|----------|
| `reads_key_with_no_newlines` | EOF 终止的 key |
| `reads_key_with_short_reads` | 多段读取（模拟慢速输入） |
| `reads_key_and_trims_newlines` | CRLF 换行符处理 |
| `errors_when_no_input_provided` | 空输入错误 |
| `errors_when_buffer_filled` | 缓冲区溢出错误 |
| `propagates_io_error` | IO 错误传播 |
| `errors_on_invalid_utf8` | 非法 UTF-8 序列 |
| `errors_on_invalid_characters` | 非法字符（如 `!`） |

### 改进建议

1. **Windows 低层实现**：实现 Windows 等效的 `ReadFile` 调用，避免 std::io::stdin() 的 BufReader。

2. **mlock 失败警告**：虽然不应阻止启动，但应记录警告日志。

3. **考虑使用 `sodium_malloc`**：libsodium 的 `sodium_malloc` 提供更强的内存保护（ guard pages、canary 等）。

4. **配置化缓冲区大小**：通过环境变量或编译时配置允许调整缓冲区大小。

5. **内存保护扩展**：
   - 考虑使用 `madvise(MADV_DONTDUMP)` 防止包含在 core dump 中
   - 考虑使用 `mprotect` 设置为只读（在不需要修改时）

6. **审计日志**：记录 API key 读取事件（不记录 key 本身），便于安全审计。

7. **超时机制**：添加 stdin 读取超时，防止进程无限等待。
