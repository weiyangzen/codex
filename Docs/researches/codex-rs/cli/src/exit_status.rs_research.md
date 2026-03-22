# exit_status.rs 研究文档

## 场景与职责

`exit_status.rs` 是 Codex CLI 中处理进程退出状态的小型工具模块。它负责将子进程的 `ExitStatus` 转换为适当的进程退出码，确保：

1. **信号传播**: Unix 系统上正确传递子进程接收的信号
2. **退出码保留**: 正常退出时保留原始退出码
3. **错误回退**: 无法确定状态时提供合理的默认值

## 功能点目的

### Unix 平台处理
- 优先使用 `status.code()` 获取标准退出码
- 对于信号终止的进程，使用 `128 + signal` 的约定（遵循 Shell 惯例）
- 极端情况下回退到退出码 1

### Windows 平台处理
- 使用 `status.code()` 获取退出码
- 无法获取时回退到退出码 1（Windows 上信号概念不同）

## 具体技术实现

### Unix 实现

```rust
#[cfg(unix)]
pub(crate) fn handle_exit_status(status: std::process::ExitStatus) -> ! {
    use std::os::unix::process::ExitStatusExt;

    if let Some(code) = status.code() {
        std::process::exit(code);
    } else if let Some(signal) = status.signal() {
        std::process::exit(128 + signal);
    } else {
        std::process::exit(1);
    }
}
```

**关键逻辑**:
1. `status.code()`: 正常退出的退出码 (0-255)
2. `status.signal()`: 终止进程的信号编号
3. `128 + signal`: Shell 标准约定，例如 SIGTERM (15) → 退出码 143

### Windows 实现

```rust
#[cfg(windows)]
pub(crate) fn handle_exit_status(status: std::process::ExitStatus) -> ! {
    if let Some(code) = status.code() {
        std::process::exit(code);
    } else {
        std::process::exit(1);
    }
}
```

Windows 上信号处理不同，通常通过退出码传递异常信息。

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/cli/src/exit_status.rs` (23 行)

### 调用方
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs`: 沙箱子进程退出处理

### 调用关系
```
debug_sandbox.rs
    └── child.wait().await
            └── handle_exit_status(status)
                    └── std::process::exit(code)
```

## 依赖与外部交互

### 标准库依赖
- `std::process::ExitStatus`: 进程退出状态
- `std::os::unix::process::ExitStatusExt`: Unix 扩展方法

### 平台特性
- `#[cfg(unix)]`: Unix 平台（Linux、macOS 等）
- `#[cfg(windows)]`: Windows 平台

## 风险、边界与改进建议

### 风险点

1. **信号值溢出**: 信号编号 > 127 时，`128 + signal` 可能溢出（实际中极罕见，标准信号最大为 31）
2. **Windows 信号模拟**: Windows 上某些"信号"可能无法正确传递
3. **嵌套调用**: 函数使用 `-> !` 永不返回类型，确保调用者不会继续执行

### 边界情况

| 场景 | Unix 行为 | Windows 行为 |
|------|----------|-------------|
| 正常退出 code=0 | exit(0) | exit(0) |
| 正常退出 code=1 | exit(1) | exit(1) |
| SIGTERM (15) | exit(143) | N/A |
| SIGKILL (9) | exit(137) | N/A |
| 无法获取状态 | exit(1) | exit(1) |

### 改进建议

1. **文档完善**: 添加更详细的文档说明信号到退出码的映射
2. **日志记录**: 在调试模式下记录退出状态处理详情
3. **测试覆盖**: 添加单元测试验证各种退出场景
4. **信号名称**: 考虑在日志中显示信号名称而非仅数字
5. **ExitCode**: 考虑使用 `std::process::ExitCode` (Rust 1.61+) 以获得更好的类型安全

### 代码示例改进

```rust
// 建议添加文档和常量
#[cfg(unix)]
pub(crate) fn handle_exit_status(status: std::process::ExitStatus) -> ! {
    use std::os::unix::process::ExitStatusExt;

    const SIGNAL_EXIT_CODE_BASE: i32 = 128;

    if let Some(code) = status.code() {
        std::process::exit(code);
    } else if let Some(signal) = status.signal() {
        // Standard shell convention: 128 + signal number
        std::process::exit(SIGNAL_EXIT_CODE_BASE + signal);
    } else {
        std::process::exit(1);
    }
}
```

### 相关参考

- Bash 退出码约定: https://tldp.org/LDP/abs/html/exitcodes.html
- POSIX 信号标准: https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/signal.h.html
