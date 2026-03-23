# Cargo.toml 研究文档

## 场景与职责

该文件是 `codex-utils-sleep-inhibitor` crate 的 Cargo 包配置，定义了跨平台睡眠抑制的依赖关系和构建设置。它是 Cargo 构建系统和 Bazel 依赖解析的权威来源。

## 功能点目的

- **包元数据声明**: 定义 crate 名称、版本、版本号和许可证
- **跨平台依赖管理**: 使用条件依赖为不同操作系统（macOS、Linux、Windows）配置特定的系统库
- **Workspace 继承**: 复用工作区级别的统一配置（版本、版本号、许可证、lints）
- **平台抽象**: 为 Codex TUI 提供统一的睡眠抑制 API，底层实现随平台变化

## 具体技术实现

### 包元数据

```toml
[package]
name = "codex-utils-sleep-inhibitor"
version.workspace = true      # 继承 workspace 版本
edition.workspace = true      # 继承 workspace Rust 版本号
license.workspace = true      # 继承 workspace 许可证
```

### 依赖结构

| 依赖 | 目标平台 | 用途 |
|------|----------|------|
| `tracing` | 所有平台 | 结构化日志记录 |
| `core-foundation` | macOS | Core Foundation 框架绑定，用于 IOKit 字符串处理 |
| `libc` | Linux | Linux 系统调用（getpid, prctl, SIGTERM） |
| `windows-sys` | Windows | Windows Power API 绑定 |

### Windows 特性配置

```toml
[target.'cfg(target_os = "windows")'.dependencies]
windows-sys = { version = "0.61.2", features = [
    "Win32_Foundation",           # CloseHandle, INVALID_HANDLE_VALUE
    "Win32_System_Power",         # PowerCreateRequest, PowerSetRequest
    "Win32_System_SystemServices", # POWER_REQUEST_CONTEXT_VERSION
    "Win32_System_Threading",     # REASON_CONTEXT, POWER_REQUEST_CONTEXT_SIMPLE_STRING
] }
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/utils/sleep-inhibitor/Cargo.toml` - 本文件

### 源文件映射
| 源文件 | 平台条件 | 实现方式 |
|--------|----------|----------|
| `src/lib.rs` | 所有平台 | 统一 API 和状态管理 |
| `src/macos.rs` | `target_os = "macos"` | IOKit IOPMAssertion API |
| `src/iokit_bindings.rs` | `target_os = "macos"` | bindgen 生成的 FFI 绑定 |
| `src/linux_inhibitor.rs` | `target_os = "linux"` | systemd-inhibit / gnome-session-inhibit 子进程 |
| `src/windows_inhibitor.rs` | `target_os = "windows"` | PowerCreateRequest / PowerSetRequest |
| `src/dummy.rs` | 其他平台 | 空实现 |

### Workspace 配置来源
- `/home/sansha/Github/codex/codex-rs/Cargo.toml` - workspace 根配置，提供 `version`、`edition`、`license`、`lints` 继承值

## 依赖与外部交互

### 通用依赖
- **tracing**: Workspace 统一版本的日志框架，用于记录睡眠抑制操作的警告和错误

### macOS 依赖
- **core-foundation 0.9**: 
  - 用途：创建 `CFString` 对象传递给 IOKit API
  - 关键类型：`CFString`, `TCFType`, `CFStringRef`
  - 链接框架：`IOKit.framework`（在 `macos.rs` 中通过 `#[link]` 属性指定）

### Linux 依赖
- **libc**: Workspace 统一版本
  - 用途：系统调用 `getpid()`, `prctl(PR_SET_PDEATHSIG, SIGTERM)`
  - 目的：确保子进程在父进程退出时自动终止（避免孤儿进程）

### Windows 依赖
- **windows-sys 0.61.2**: 
  - 用途：调用 Windows 电源管理 API
  - 关键 API：
    - `PowerCreateRequest` - 创建电源请求对象
    - `PowerSetRequest` - 设置系统必需电源请求
    - `PowerClearRequest` - 清除电源请求
    - `CloseHandle` - 关闭请求句柄
    - `REASON_CONTEXT` - 请求原因上下文结构

## 风险、边界与改进建议

### 风险点

1. **平台依赖版本漂移**: 
   - `core-foundation` 和 `windows-sys` 是固定版本而非 workspace 管理
   - 建议：评估是否可纳入 workspace 统一版本管理

2. **Linux 运行时依赖**:
   - Linux 实现依赖外部命令 `systemd-inhibit` 或 `gnome-session-inhibit`
   - 这些不在 Cargo.toml 中声明，属于隐式运行时依赖
   - 风险：目标系统可能缺少这些工具

3. **Windows API 版本**:
   - `windows-sys` 0.61.2 是相对较新的版本
   - 需确保与项目其他 Windows 相关 crate 的版本兼容

### 边界情况

1. **平台检测**: 使用 `cfg(target_os = ...)` 进行条件编译，编译时确定平台
2. **非目标平台**: 非 Linux/macOS/Windows 平台使用 `dummy` 实现，API 正常但无实际功能
3. **特性冲突**: 多个平台条件可能同时满足（如交叉编译），但实际编译时只有一个生效

### 改进建议

1. **依赖版本统一**:
   ```toml
   # 建议将平台特定依赖也纳入 workspace
   [target.'cfg(target_os = "macos")'.dependencies]
   core-foundation = { workspace = true }
   
   [target.'cfg(target_os = "windows")'.dependencies]
   windows-sys = { workspace = true }
   ```

2. **文档化运行时依赖**:
   - 在 crate 文档或 README 中明确说明 Linux 需要 `systemd-inhibit` 或 `gnome-session-inhibit`
   - 考虑在编译时检测或运行时友好提示

3. **功能特性门控**:
   - 可考虑添加可选特性（如 `sleep-inhibit`）允许用户禁用此功能以减少依赖
   - 当前设计是始终包含，通过运行时 `enabled` 标志控制

4. **依赖最小化**:
   - Linux 的 `libc` 依赖仅用于 `prctl` 和 `getpid`
   - 可考虑使用 `nix` crate 提供更安全的封装，或保持原样以减少依赖
