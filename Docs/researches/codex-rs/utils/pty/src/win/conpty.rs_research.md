# conpty.rs 研究文档

## 文件信息
- **路径**: `codex-rs/utils/pty/src/win/conpty.rs`
- **大小**: 5,463 bytes
- **来源**: 基于 WezTerm (MIT License) 的 vendored 代码，有本地修改

---

## 一、场景与职责

### 1.1 核心定位
`conpty.rs` 是 Windows 平台下 ConPTY (Console Pseudo Terminal) 的 **高层封装层**，实现了 `portable-pty` crate 定义的 `PtySystem` trait，为 Codex 提供跨平台的 PTY 抽象。

### 1.2 主要职责
1. **PtySystem 实现**: 提供 `ConPtySystem` 结构体实现 `portable_pty::PtySystem` trait
2. **Master/Slave PTY 对管理**: 创建和管理 PTY 主从设备对 (`ConPtyMasterPty` / `ConPtySlavePty`)
3. **原始 ConPTY 句柄暴露**: 通过 `RawConPty` 为需要底层访问的场景提供原始句柄
4. **窗口大小管理**: 支持 PTY 的 resize 操作

### 1.3 在架构中的位置
```
┌─────────────────────────────────────────────────────────────┐
│                    codex-utils-pty                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │   lib.rs    │───▶│   pty.rs    │───▶│  win/conpty.rs  │  │
│  └─────────────┘    └─────────────┘    └─────────────────┘  │
│                                               │             │
│                                               ▼             │
│                                        ┌─────────────┐      │
│                                        │ psuedocon.rs│      │
│                                        │(底层WinAPI) │      │
│                                        └─────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 ConPtySystem - PTY 系统工厂
```rust
#[derive(Default)]
pub struct ConPtySystem {}
```
- 实现 `PtySystem::openpty()` 方法，创建 PTY 主从对
- 使用 `create_conpty_handles()` 辅助函数初始化管道和伪控制台

### 2.2 RawConPty - 原始句柄访问
```rust
pub struct RawConPty {
    con: PsuedoCon,
    input_write: FileDescriptor,
    output_read: FileDescriptor,
}
```
- **目的**: 为需要直接操作 ConPTY 句柄的场景（如 Windows Sandbox）提供底层访问
- **关键方法**:
  - `new(cols, rows)` - 创建指定大小的原始 ConPTY
  - `pseudoconsole_handle()` - 获取 HPCON 句柄
  - `into_raw_handles()` - 消费自身返回原始句柄三元组 (HPCON, input_write, output_read)

### 2.3 ConPtyMasterPty - PTY 主设备
```rust
#[derive(Clone)]
pub struct ConPtyMasterPty {
    inner: Arc<Mutex<Inner>>,
}
```
- 实现 `MasterPty` trait
- 提供读取子进程输出、写入输入、调整窗口大小的能力
- 使用 `Arc<Mutex<Inner>>` 实现线程安全的共享状态

### 2.4 ConPtySlavePty - PTY 从设备
```rust
pub struct ConPtySlavePty {
    inner: Arc<Mutex<Inner>>,
}
```
- 实现 `SlavePty` trait
- 负责实际 spawned 进程，将进程附加到 PTY

---

## 三、具体技术实现

### 3.1 关键流程

#### 3.1.1 创建 PTY 对 (openpty)
```rust
fn create_conpty_handles(size: PtySize) 
    -> anyhow::Result<(PsuedoCon, FileDescriptor, FileDescriptor)>
```
流程:
1. 创建 stdin/stdout 管道对 (`Pipe::new()`)
2. 使用管道读/写端创建 `PsuedoCon`
3. 返回 `(PsuedoCon, stdin.write, stdout.read)`

```
┌─────────────┐     ┌─────────────┐
│  stdin pipe │     │ stdout pipe │
│ ┌───┐ ┌───┐ │     │ ┌───┐ ┌───┐ │
│ │read│ │write│ │     │ │read│ │write│ │
│ └───┘ └───┘ │     │ └───┘ └───┘ │
└──────┬──────┘     └──────┬──────┘
       │                   │
       ▼                   ▼
┌─────────────────────────────────┐
│         PsuedoCon::new          │
│    (CreatePseudoConsole)        │
└─────────────────────────────────┘
```

#### 3.1.2 窗口大小调整 (resize)
```rust
impl Inner {
    pub fn resize(&mut self, num_rows, num_cols, pixel_width, pixel_height) 
        -> Result<(), Error>
}
```
- 调用 `PsuedoCon::resize()` 调整底层 ConPTY
- 更新本地缓存的 `PtySize`

### 3.2 数据结构

#### 3.2.1 Inner - 共享状态
```rust
struct Inner {
    con: PsuedoCon,                    // 底层伪控制台
    readable: FileDescriptor,          // 读取子进程输出
    writable: Option<FileDescriptor>,  // 写入子进程输入 (Option 因为 take_writer 会消耗)
    size: PtySize,                     // 当前窗口大小
}
```

#### 3.2.2 PtySize (来自 portable-pty)
```rust
pub struct PtySize {
    pub rows: u16,
    pub cols: u16,
    pub pixel_width: u16,
    pub pixel_height: u16,
}
```

### 3.3 关键代码路径

| 操作 | 调用链 |
|------|--------|
| 创建 PTY | `ConPtySystem::openpty()` → `create_conpty_handles()` → `PsuedoCon::new()` |
| 调整大小 | `ConPtyMasterPty::resize()` → `Inner::resize()` → `PsuedoCon::resize()` |
| 读取输出 | `ConPtyMasterPty::try_clone_reader()` → `FileDescriptor::try_clone()` |
| 写入输入 | `ConPtyMasterPty::take_writer()` → 消耗 `Inner.writable` |
| 启动进程 | `ConPtySlavePty::spawn_command()` → `PsuedoCon::spawn_command()` |

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖
```rust
use crate::win::psuedocon::PsuedoCon;  // 底层 ConPTY 实现
use portable_pty::{                      // 外部 trait 定义
    Child, MasterPty, PtyPair, PtySize, 
    PtySystem, SlavePty, CommandBuilder 
};
use filedescriptor::{FileDescriptor, Pipe};  // 文件描述符抽象
```

### 4.2 调用关系图
```
conpty.rs
    │
    ├─── uses ───▶ psuedocon.rs (PsuedoCon, conpty_supported)
    │
    ├─── implements ───▶ portable_pty::PtySystem
    │
    ├─── implements ───▶ portable_pty::MasterPty
    │
    ├─── implements ───▶ portable_pty::SlavePty
    │
    └─── used by ───▶ pty.rs (platform_native_pty_system)
              │
              └─── used by ───▶ lib.rs (pub use)
```

### 4.3 外部调用方
1. **pty.rs**: `platform_native_pty_system()` 返回 `Box::new(crate::win::ConPtySystem::default())`
2. **windows-sandbox-rs/src/conpty/mod.rs**: 使用 `RawConPty` 创建沙箱进程的 PTY
3. **lib.rs**: 导出 `RawConPty` 供外部使用

---

## 五、依赖与外部交互

### 5.1 外部 Crates
| Crate | 用途 |
|-------|------|
| `portable-pty` | PTY 抽象 trait 定义 (`PtySystem`, `MasterPty`, `SlavePty`, `Child`) |
| `filedescriptor` | 跨平台文件描述符抽象 (`FileDescriptor`, `Pipe`, `OwnedHandle`) |
| `anyhow` | 错误处理 |
| `winapi` | Windows API 类型 (`COORD`) |

### 5.2 Windows API 依赖 (通过 winapi crate)
```rust
use winapi::um::wincon::COORD;  // 控制台坐标结构
```

### 5.3 平台特定代码
- **条件编译**: `#[cfg(windows)]` (在 lib.rs 中控制模块包含)
- **非 Windows 平台**: 使用 `portable_pty::native_pty_system()` (Unix PTY)

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 线程安全与锁竞争
```rust
pub struct ConPtyMasterPty {
    inner: Arc<Mutex<Inner>>,  // 所有操作都需获取锁
}
```
- **风险**: `Arc<Mutex<>>` 模式可能导致锁竞争，高并发场景下性能受限
- **边界**: `try_clone_reader()` 和 `take_writer()` 都需要获取锁

#### 6.1.2 Writer 只能获取一次
```rust
fn take_writer(&self) -> anyhow::Result<Box<dyn std::io::Write + Send>> {
    Ok(Box::new(
        self.inner
            .lock()
            .unwrap()
            .writable
            .take()  // 消耗 Option，只能调用一次
            .ok_or_else(|| anyhow::anyhow!("writer already taken"))?,
    ))
}
```
- **边界**: 设计限制，符合 `portable-pty` 的 `MasterPty` trait 要求

#### 6.1.3 unwrap() 使用
```rust
let mut inner = self.inner.lock().unwrap();  // 第159行
```
- **风险**: 锁中毒时 panic
- **缓解**: 这是 vendored 代码风格，生产环境需要评估

### 6.2 平台兼容性

#### 6.2.1 ConPTY 可用性检查
```rust
// psuedocon.rs
pub fn conpty_supported() -> bool {
    windows_build_number().is_some_and(|build| build >= MIN_CONPTY_BUILD)
}
const MIN_CONPTY_BUILD: u32 = 17_763;  // Windows 10 October 2018 Update
```
- **边界**: 需要 Windows 10 版本 1809 或更高版本
- **回退**: 旧版本 Windows 不支持 ConPTY，需要其他方案

### 6.3 改进建议

#### 6.3.1 错误处理改进
- 将 `.unwrap()` 替换为更优雅的错误传播
- 考虑使用 `parking_lot::Mutex` 替代 `std::sync::Mutex` 避免中毒问题

#### 6.3.2 性能优化
- 评估是否需要更细粒度的锁策略
- 考虑使用无锁数据结构处理高频读写操作

#### 6.3.3 文档完善
- 添加更多关于 `RawConPty` 使用场景的例子
- 说明 `into_raw_handles()` 的安全约定（调用者负责关闭句柄）

#### 6.3.4 测试覆盖
- 当前测试主要在 `tests.rs` 中，建议增加：
  - 并发 resize 测试
  - 大流量数据传输测试
  - 边界条件测试（如 0x0 窗口大小）

### 6.4 与上游 WezTerm 的关系
- 代码源自 WezTerm，但 Codex 有本地修改（如 bug #13945 修复）
- 需要定期同步上游修复
- 当前 divergence 已在 `mod.rs` 中记录

---

## 七、相关文件索引

| 文件 | 关系 | 说明 |
|------|------|------|
| `win/mod.rs` | 父模块 | 定义 `WinChild`, `WinChildKiller`, 导出 `ConPtySystem` |
| `win/psuedocon.rs` | 依赖 | 底层 ConPTY WinAPI 封装 (`PsuedoCon`) |
| `win/procthreadattr.rs` | 依赖 | 进程线程属性列表管理 |
| `pty.rs` | 调用方 | 跨平台 PTY 封装，使用 `ConPtySystem` |
| `lib.rs` | 调用方 | 导出 `RawConPty` |
| `tests.rs` | 测试 | 集成测试 |
| `Cargo.toml` | 配置 | 依赖 `portable-pty`, `filedescriptor` |
| `windows-sandbox-rs/src/conpty/mod.rs` | 外部调用方 | 使用 `RawConPty` 创建沙箱 PTY |
