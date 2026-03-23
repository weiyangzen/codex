# process.rs 研究文档

## 文件信息
- **路径**: `codex-rs/core/tests/common/process.rs`
- **大小**: 1,380 bytes (48 行)
- **所属模块**: core_test_support

---

## 场景与职责

此文件提供了进程管理相关的测试工具函数，主要用于在测试中监控和控制外部进程的生命周期。它是 `core_test_support` crate 的一部分，为需要验证进程行为的集成测试提供基础设施。

### 核心职责
1. **PID 文件等待**: 异步等待 PID 文件创建并读取其内容
2. **进程存活检测**: 使用 `kill -0` 检查进程是否存在
3. **进程退出等待**: 异步等待进程终止

### 使用场景
- 测试 Codex 子进程（如沙箱进程、shell 进程）的启动和退出
- 验证进程生命周期管理
- 测试进程间通信（通过 PID 文件）

---

## 功能点目的

### 1. wait_for_pid_file
```rust
pub async fn wait_for_pid_file(path: &Path) -> anyhow::Result<String>
```

**功能**: 异步等待 PID 文件创建并读取其内容。

**实现细节**:
- 使用 `tokio::time::timeout` 设置 2 秒超时
- 每 25 毫秒轮询检查文件是否存在
- 读取文件内容并去除空白字符
- 返回 PID 字符串

**使用场景**:
```rust
let pid = wait_for_pid_file(Path::new("/tmp/codex.pid")).await?;
// 使用 pid 进行后续操作
```

### 2. process_is_alive
```rust
pub fn process_is_alive(pid: &str) -> anyhow::Result<bool>
```

**功能**: 检查指定 PID 的进程是否存在。

**实现细节**:
- 使用 Unix `kill -0 <pid>` 命令
- `kill -0` 不发送信号，仅检查进程是否存在且有权信号
- 返回 `true` 如果进程存在，`false` 如果不存在
- 如果命令执行失败，返回错误

**平台限制**:
- 当前实现仅支持 Unix 系统（使用 `kill` 命令）
- Windows 不支持此函数

### 3. wait_for_process_exit
```rust
pub async fn wait_for_process_exit(pid: &str) -> anyhow::Result<()>
```

**功能**: 异步等待进程终止。

**实现细节**:
- 内部调用 `process_is_alive` 检查进程状态
- 每 25 毫秒检查一次
- 使用 `tokio::time::timeout` 设置 2 秒超时
- 进程退出时返回 Ok，超时返回错误

**内部实现**:
```rust
async fn wait_for_process_exit_inner(pid: String) -> anyhow::Result<()> {
    loop {
        if !process_is_alive(&pid)? {
            return Ok(());
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
}
```

---

## 具体技术实现

### 异步轮询模式
所有函数都使用轮询模式实现异步等待：

```rust
tokio::time::timeout(Duration::from_secs(2), async {
    loop {
        if condition_met() {
            return result;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
})
```

**优点**:
- 简单可靠
- 不依赖外部文件系统事件

**缺点**:
- 轮询有 CPU 开销（虽然 25ms 间隔很小）
- 不是真正的异步事件驱动

### 错误处理
使用 `anyhow` crate 进行错误处理：
- `Context` trait 添加错误上下文
- `?` 操作符传播错误

### Unix 特定实现
`process_is_alive` 使用 `kill` 命令：
```rust
let status = std::process::Command::new("kill")
    .args(["-0", pid])
    .status()?;
```

这是 Unix 系统检查进程存在的标准方法：
- 退出码 0: 进程存在
- 退出码非 0: 进程不存在或无权限

---

## 关键代码路径与文件引用

### 模块关系
```
process.rs
    ├── 被 lib.rs 导出: pub mod process
    └── 被测试代码使用
```

### 使用示例
在 `codex-rs/core/tests/suite/unified_exec.rs` 或类似测试中：
```rust
use core_test_support::process::{wait_for_pid_file, wait_for_process_exit, process_is_alive};

#[tokio::test]
async fn test_process_lifecycle() {
    // 启动子进程...
    
    // 等待 PID 文件创建
    let pid = wait_for_pid_file(pid_file_path).await.unwrap();
    
    // 验证进程存在
    assert!(process_is_alive(&pid).unwrap());
    
    // 请求进程退出...
    
    // 等待进程退出
    wait_for_process_exit(&pid).await.unwrap();
    
    // 验证进程已不存在
    assert!(!process_is_alive(&pid).unwrap());
}
```

---

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `tokio` | 异步运行时 (timeout, sleep) |
| `anyhow` | 错误处理 |
| `std::fs` | 文件读取 |
| `std::process::Command` | 执行 kill 命令 |

### 平台依赖
| 平台 | 支持状态 |
|-----|---------|
| Linux | 完全支持 |
| macOS | 完全支持 |
| Windows | `process_is_alive` 不可用 |

---

## 风险、边界与改进建议

### 潜在风险

1. **平台兼容性**
   ```rust
   .args(["-0", pid])
   ```
   - `kill -0` 是 Unix 特有的
   - Windows 上此函数会失败
   - 建议：添加 Windows 支持或明确文档说明

2. **PID 重用**
   - 在进程退出后、等待函数返回前，PID 可能被系统重用
   - 可能导致误判进程状态
   - 建议：结合其他机制（如进程组 ID）验证

3. **权限问题**
   - `kill -0` 需要足够的权限检查进程
   - 在某些安全环境中可能失败

4. **轮询开销**
   - 25ms 轮询间隔在大量并发测试中可能有性能影响
   - 建议：考虑使用 `notify` crate 的文件系统事件（对于 PID 文件）

### 边界条件

1. **空 PID 文件**
   ```rust
   if !trimmed.is_empty() {
       return trimmed.to_string();
   }
   ```
   - 正确处理空文件情况
   - 继续等待直到有内容

2. **无效 PID**
   - `process_is_alive` 接受任何字符串
   - 如果 PID 格式无效，`kill` 命令会返回错误

3. **僵尸进程**
   - `kill -0` 对僵尸进程返回成功
   - 可能无法正确检测已终止但未被回收的进程

4. **超时处理**
   - 2 秒超时可能对于慢速系统不够
   - 建议：使超时可配置

### 改进建议

1. **Windows 支持**
   ```rust
   #[cfg(windows)]
   pub fn process_is_alive(pid: &str) -> anyhow::Result<bool> {
       use std::process::Command;
       // 使用 tasklist 或 PowerShell 检查进程
       let output = Command::new("tasklist")
           .args(["/FI", &format!("PID eq {}", pid)])
           .output()?;
       // 解析输出...
   }
   ```

2. **可配置超时**
   ```rust
   pub async fn wait_for_pid_file_with_timeout(
       path: &Path,
       timeout: Duration,
   ) -> anyhow::Result<String>
   ```

3. **事件驱动替代轮询**
   ```rust
   pub async fn wait_for_pid_file_event_driven(path: &Path) -> anyhow::Result<String> {
       use notify::{Watcher, RecursiveMode};
       // 使用 notify 监听文件创建事件
   }
   ```

4. **类型安全 PID**
   ```rust
   pub struct Pid(String);
   
   impl Pid {
       pub fn parse(s: &str) -> anyhow::Result<Self> {
           // 验证 PID 格式
           s.parse::<u32>()?;
           Ok(Self(s.to_string()))
       }
   }
   ```

5. **进程组支持**
   ```rust
   pub fn process_group_is_alive(pgid: &str) -> anyhow::Result<bool> {
       // 检查进程组是否存在
   }
   ```

6. **更好的错误信息**
   ```rust
   pub async fn wait_for_pid_file(path: &Path) -> anyhow::Result<String> {
       tokio::time::timeout(Duration::from_secs(2), async {
           // ...
       })
       .await
       .with_context(|| format!("timed out waiting for pid file: {}", path.display()))?
   }
   ```

---

## 相关文件
- `codex-rs/core/tests/common/lib.rs` - 模块导出
- `codex-rs/core/src/spawn.rs` - 进程创建相关代码
- `codex-rs/core/src/unified_exec/` - 统一执行模块（可能使用这些工具）
- `codex-rs/core/tests/suite/unified_exec.rs` - 统一执行测试

---

## 总结

`process.rs` 是一个小而精的测试工具模块，提供了进程生命周期管理的基本功能。虽然代码量不大，但在测试需要验证进程行为的场景中非常重要。当前实现简单可靠，但存在平台兼容性和性能方面的改进空间。
