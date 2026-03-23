# dummy.rs 研究文档

## 场景与职责

`dummy.rs` 是 `codex-utils-sleep-inhibitor` crate 的**兜底（fallback）实现**，用于支持那些不具备原生睡眠抑制能力的平台。当目标操作系统不是 Linux、macOS 或 Windows 时，编译系统会自动选择此模块作为 `SleepInhibitor` 的平台实现。

该模块的设计哲学是**零成本抽象**：在不支持睡眠抑制的平台上，调用方代码无需任何修改即可编译运行，相关操作成为无操作（no-op），既不会崩溃也不会产生副作用。

## 功能点目的

### 1. 跨平台兼容性保证
- **目的**：确保 crate 在任何 Rust 支持的目标平台上都能编译通过
- **实现**：提供一个最小化的 `SleepInhibitor` 结构体，满足公共接口契约

### 2. 无操作（No-op）语义
- **目的**：在功能不可用的平台上，睡眠抑制调用静默成功
- **实现**：`acquire()` 和 `release()` 方法为空实现

## 具体技术实现

### 数据结构

```rust
#[derive(Debug, Default)]
pub(crate) struct SleepInhibitor;
```

- **零字段结构体**：不占用任何运行时内存
- **自动派生**：`Debug` 用于日志输出，`Default` 支持 `Self::default()` 构造

### 方法实现

| 方法 | 签名 | 实现 | 复杂度 |
|------|------|------|--------|
| `new` | `pub(crate) fn new() -> Self` | `Self`（利用 `Default`） | O(1) |
| `acquire` | `pub(crate) fn acquire(&mut self)` | 空实现 | O(1) |
| `release` | `pub(crate) fn release(&mut self)` | 空实现 | O(1) |

### 条件编译配置

在 `lib.rs` 中通过 `cfg` 属性进行平台选择：

```rust
#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
mod dummy;

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
use dummy as imp;
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/sleep-inhibitor/src/dummy.rs`（12 行）

### 调用路径
```
lib.rs (公共接口)
  └── 条件编译选择 dummy as imp
       └── dummy.rs (本文件)
```

### 被调用方
- 无（本模块是叶子节点）

## 依赖与外部交互

### 编译时依赖
| 依赖 | 用途 |
|------|------|
| `std` | `Default` trait |
| `core::fmt::Debug` | 调试输出 |

### 运行时依赖
- **无**：本模块不调用任何外部系统 API

## 风险、边界与改进建议

### 当前风险
1. **静默失败风险**：调用方无法区分"功能不支持"和"功能已启用"，可能导致用户在长时间任务期间意外进入睡眠

### 边界情况
1. **平台检测边界**：`cfg` 条件使用否定形式，未来新增平台默认落入此实现，可能不符合预期
2. **无状态边界**：多次调用 `acquire()` 或 `release()` 不会产生任何效果或错误

### 改进建议

#### 1. 增加平台能力查询接口
```rust
// 建议添加
impl SleepInhibitor {
    pub(crate) fn is_supported() -> bool {
        false
    }
}
```

#### 2. 日志警告（可选）
在 `acquire()` 中添加 `tracing::debug!` 日志，帮助调试：
```rust
pub(crate) fn acquire(&mut self) {
    tracing::debug!("Sleep inhibition not supported on this platform");
}
```

#### 3. 显式平台白名单
考虑使用正向匹配而非否定匹配，避免新平台意外落入 dummy 实现：
```rust
// 当前（风险：新平台默认落入 dummy）
#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]

// 建议（更安全的替代方案）
#[cfg(any(target_os = "freebsd", target_os = "openbsd", target_os = "netbsd"))]
```

### 测试建议
- 单元测试：验证 `new()` 不 panic
- 集成测试：验证多次 `acquire/release` 循环不 panic
- 已在 `lib.rs` 的 `tests` 模块中覆盖
