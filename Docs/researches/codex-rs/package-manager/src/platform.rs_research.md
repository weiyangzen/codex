# platform.rs 研究文档

## 场景与职责

`platform.rs` 定义了 `PackagePlatform` 枚举，用于表示和管理 Codex 包管理器支持的目标平台。该模块负责平台检测和平台标识符的生成，是跨平台包分发的基础组件。

### 核心职责
1. **平台枚举定义**：定义所有支持的操作系统-架构组合
2. **当前平台检测**：在运行时检测当前进程的平台
3. **平台标识符生成**：生成用于清单和缓存路径的平台字符串

## 功能点目的

### 1. PackagePlatform - 平台枚举

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PackagePlatform {
    DarwinArm64,   // macOS on Apple Silicon
    DarwinX64,     // macOS on x86_64
    LinuxArm64,    // Linux on AArch64
    LinuxX64,      // Linux on x86_64
    WindowsArm64,  // Windows on AArch64
    WindowsX64,    // Windows on x86_64
}
```

**支持的平台矩阵**：

| 枚举变体 | 操作系统 | 架构 | 目标市场 |
|----------|----------|------|----------|
| `DarwinArm64` | macOS | ARM64 (Apple Silicon) | Mac (M1/M2/M3) |
| `DarwinX64` | macOS | x86_64 | Intel Mac |
| `LinuxArm64` | Linux | AArch64 | ARM Linux 服务器/设备 |
| `LinuxX64` | Linux | x86_64 | x86 Linux 服务器/桌面 |
| `WindowsArm64` | Windows | AArch64 | ARM Windows 设备 |
| `WindowsX64` | Windows | x86_64 | Windows 桌面/服务器 |

**设计考量**：
- 使用 `Clone + Copy`：平台值小而简单，可复制
- 使用 `Eq + PartialEq`：支持相等比较，用于缓存查找
- 显式命名：避免混淆，如 `Darwin` 而非 `MacOS`

### 2. detect_current - 当前平台检测

```rust
pub fn detect_current() -> Result<Self, PackageManagerError>
```

**检测逻辑**：
```rust
match (std::env::consts::OS, std::env::consts::ARCH) {
    ("macos", "aarch64") | ("macos", "arm64") => Ok(Self::DarwinArm64),
    ("macos", "x86_64") => Ok(Self::DarwinX64),
    ("linux", "aarch64") | ("linux", "arm64") => Ok(Self::LinuxArm64),
    ("linux", "x86_64") => Ok(Self::LinuxX64),
    ("windows", "aarch64") | ("windows", "arm64") => Ok(Self::WindowsArm64),
    ("windows", "x86_64") => Ok(Self::WindowsX64),
    (os, arch) => Err(PackageManagerError::UnsupportedPlatform {
        os: os.to_string(),
        arch: arch.to_string(),
    }),
}
```

**设计考量**：
- 使用 `std::env::consts`：编译期常量，无需运行时检测
- 别名处理：同时接受 `aarch64` 和 `arm64`（常见别名）
- 错误处理：不支持的平台返回结构化错误

### 3. as_str - 平台标识符

```rust
pub fn as_str(self) -> &'static str
```

**映射表**：

| 枚举变体 | 字符串标识 |
|----------|------------|
| `DarwinArm64` | `"darwin-arm64"` |
| `DarwinX64` | `"darwin-x64"` |
| `LinuxArm64` | `"linux-arm64"` |
| `LinuxX64` | `"linux-x64"` |
| `WindowsArm64` | `"windows-arm64"` |
| `WindowsX64` | `"windows-x64"` |

**使用场景**：
- 发布清单中的平台键名
- 缓存目录命名（`~/.codex/packages/<package>/<version>/<platform>/`）
- 日志和错误信息

**设计考量**：
- 返回 `&'static str`：零分配，编译期确定
- 使用 kebab-case：URL 和路径友好

## 具体技术实现

### 标准库依赖

```rust
use std::env::consts::{OS, ARCH};
```

`std::env::consts` 提供：
- `OS`：目标操作系统（`"macos"`, `"linux"`, `"windows"` 等）
- `ARCH`：目标架构（`"x86_64"`, `"aarch64"` 等）

这些常量在编译期确定，基于目标三元组。

### 错误处理

```rust
Err(PackageManagerError::UnsupportedPlatform {
    os: os.to_string(),
    arch: arch.to_string(),
})
```

返回结构化错误：
- 包含检测到的操作系统和架构
- 便于调试和错误报告
- 调用者可据此提供有用的用户提示

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 使用内容 |
|------|----------|
| `error` | `PackageManagerError::UnsupportedPlatform` |

### 调用方

| 文件 | 使用场景 |
|------|----------|
| `manager.rs` | `resolve_cached`, `ensure_installed` 中检测当前平台 |
| `tests.rs` | 测试用例中获取当前平台 |
| `artifacts/src/runtime/manager.rs` | 作为 `ManagedPackage::platform_archive` 参数 |

### 使用示例

**平台检测**（来自 manager.rs）：
```rust
let platform = PackagePlatform::detect_current().map_err(P::Error::from)?;
```

**缓存路径构建**（来自 manager.rs）：
```rust
let install_dir = self.config.package.install_dir(&self.config.cache_root(), platform);
```

**清单查找**（来自 tests.rs）：
```rust
manifest.platforms.get(platform.as_str()).cloned()
```

## 依赖与外部交互

### 无外部 crate 依赖

本模块仅依赖标准库，保持轻量级。

### 标准库依赖

| 项 | 用途 |
|----|----|
| `std::env::consts::OS` | 操作系统检测 |
| `std::env::consts::ARCH` | 架构检测 |

## 风险、边界与改进建议

### 已知风险

1. **平台检测局限性**
   - **风险**：`std::env::consts` 基于编译目标，而非运行时环境
   - **场景**：在 x86_64 Mac 上通过 Rosetta 运行 ARM 二进制文件
   - **行为**：检测为 ARM（因为二进制是 ARM），而非 x86_64
   - **缓解**：这是预期行为，确保使用正确的包架构

2. **不支持的平台**
   - **风险**：某些平台（如 FreeBSD、Android）不被支持
   - **行为**：返回 `UnsupportedPlatform` 错误
   - **缓解**：清晰的错误信息，用户可报告需求

3. **架构别名不一致**
   - **风险**：某些平台可能使用不同的架构名称
   - **现状**：处理了 `aarch64`/`arm64` 的常见别名
   - **潜在**：`amd64` vs `x86_64` 等

### 边界条件

| 场景 | 行为 |
|------|------|
| 标准支持平台 | 返回对应的 `PackagePlatform` |
| 未知操作系统 | 返回 `UnsupportedPlatform` 错误 |
| 未知架构 | 返回 `UnsupportedPlatform` 错误 |
| 已知 OS + 未知 Arch | 返回 `UnsupportedPlatform` 错误 |

### 改进建议

1. **更多平台支持**
   - 添加 `FreeBSD`、`Android`、`iOS` 等平台
   - 根据用户需求评估优先级

2. **运行时平台检测**
   - 当前使用编译期常量
   - 可考虑使用 `sysinfo` 等 crate 进行运行时检测
   - 适用于模拟器/兼容层场景

3. **平台能力查询**
   - 添加方法查询平台能力
   ```rust
   impl PackagePlatform {
       pub fn supports_executable_permissions(&self) -> bool;
       pub fn path_separator(&self) -> char;
       pub fn executable_extension(&self) -> Option<&'static str>;
   }
   ```

4. **目标三元组解析**
   - 添加从 Rust 目标三元组解析的方法
   ```rust
   pub fn from_target(target: &str) -> Option<Self>;
   // PackagePlatform::from_target("x86_64-pc-windows-msvc")
   ```

5. **平台分组**
   - 添加分类方法
   ```rust
   pub fn family(&self) -> PlatformFamily;  // Unix, Windows
   pub fn is_desktop(&self) -> bool;
   pub fn is_server(&self) -> bool;
   ```

6. **字符串解析**
   - 添加从字符串解析平台的方法
   ```rust
   pub fn parse(s: &str) -> Result<Self, ParseError>;
   // PackagePlatform::parse("linux-x64")
   ```

7. **模拟器检测**
   - 检测是否在模拟器/兼容层运行
   - 例如：Rosetta、QEMU、WSL

### 测试覆盖

测试文件 `tests.rs` 中相关测试：
- 所有测试用例都使用 `PackagePlatform::detect_current()`
- 验证平台检测与当前测试环境一致

**测试模式**：
```rust
let platform = PackagePlatform::detect_current().unwrap_or_else(|error| panic!("{error}"));
```

### 与发布清单的集成

发布清单 JSON 示例：
```json
{
    "package_version": "1.0.0",
    "platforms": {
        "darwin-arm64": {
            "archive": "package-v1.0.0-darwin-arm64.tar.gz",
            "sha256": "abc123...",
            "format": "tar.gz"
        },
        "linux-x64": {
            "archive": "package-v1.0.0-linux-x64.tar.gz",
            "sha256": "def456...",
            "format": "tar.gz"
        }
    }
}
```

`PackagePlatform::as_str()` 生成的字符串直接用作 JSON 键名。
