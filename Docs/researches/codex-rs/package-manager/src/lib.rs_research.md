# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-package-manager` crate 的库入口文件，负责模块组织和公共 API 导出。该文件遵循 Rust 库设计的最佳实践，将内部模块细节隐藏，仅暴露必要的公共类型和 trait。

### 核心职责
1. **模块声明**：声明 crate 的所有子模块
2. **公共 API 导出**：选择性地导出公共类型
3. **测试模块配置**：条件编译包含测试模块

## 功能点目的

### 1. 模块声明

```rust
mod archive;
mod config;
mod error;
mod manager;
mod package;
mod platform;

#[cfg(test)]
mod tests;
```

**设计考量**：
- 所有模块使用 `mod` 声明，表示它们是 crate 的私有模块
- 模块名使用 snake_case，符合 Rust 命名规范
- 测试模块使用 `#[cfg(test)]` 条件编译，仅在测试构建时包含

### 2. 公共 API 导出

```rust
pub use archive::ArchiveFormat;
pub use archive::PackageReleaseArchive;
pub use config::PackageManagerConfig;
pub use error::PackageManagerError;
pub use manager::PackageManager;
pub use package::ManagedPackage;
pub use platform::PackagePlatform;
```

**导出策略**：

| 类型 | 来源模块 | 导出理由 |
|------|----------|----------|
| `ArchiveFormat` | archive | 包类型实现需要指定归档格式 |
| `PackageReleaseArchive` | archive | 清单中的归档元数据结构 |
| `PackageManagerConfig` | config | 创建包管理器所需 |
| `PackageManagerError` | error | 错误处理需要 |
| `PackageManager` | manager | 核心 API |
| `ManagedPackage` | package | 包类型必须实现的 trait |
| `PackagePlatform` | platform | 平台检测和指定 |

**设计原则**：
- 最小暴露原则：仅导出使用 crate 必需的类型
- 内部实现细节（如 `extract_archive`、`verify_sha256`）保持私有
- 通过 `ManagedPackage` trait 允许扩展，而非暴露内部函数

## 具体技术实现

### 模块可见性

```rust
mod archive;  // 私有模块
pub use archive::ArchiveFormat;  // 公开特定类型
```

这种设计允许：
- 内部函数自由重构而不破坏公共 API
- 公共 API 保持简洁和稳定
- 未来可以更改内部模块结构而不影响用户

### 测试模块

```rust
#[cfg(test)]
mod tests;
```

- 使用 `#[cfg(test)]` 确保测试代码不包含在发布构建中
- 测试模块位于 `tests.rs` 文件，与 `lib.rs` 同级

## 关键代码路径与文件引用

### 模块结构

```
codex-package-manager/
├── src/
│   ├── lib.rs          # 本文件：模块声明和公共 API 导出
│   ├── archive.rs      # 归档处理（解压、验证）
│   ├── config.rs       # 配置结构
│   ├── error.rs        # 错误类型
│   ├── manager.rs      # 包管理器核心逻辑
│   ├── package.rs      # ManagedPackage trait
│   ├── platform.rs     # 平台检测
│   └── tests.rs        # 单元测试和集成测试
```

### 外部调用方

| Crate | 使用方式 | 说明 |
|-------|----------|------|
| `codex-artifacts` | `use codex_package_manager::{ManagedPackage, PackageManager, ...}` | 主要消费者，实现 artifact runtime 包管理 |

**使用示例**（来自 artifacts）：
```rust
use codex_package_manager::ManagedPackage;
use codex_package_manager::PackageManager;
use codex_package_manager::PackageManagerConfig;
use codex_package_manager::PackageManagerError;
use codex_package_manager::PackageReleaseArchive;
```

## 依赖与外部交互

### 无直接依赖

`lib.rs` 本身不引入任何外部依赖，依赖在子模块中按需引入。

### 通过 re-export 隐式依赖

用户通过 `codex_package_manager::` 命名空间访问的类型，其实际定义位于子模块，依赖关系如下：

| 公共类型 | 实际依赖 |
|----------|----------|
| `PackageManagerError` | `thiserror` |
| `PackageReleaseArchive` | `serde` |
| `ArchiveFormat` | `serde` |
| `PackageManager` | `reqwest`, `tokio`, `fd-lock`, `tempfile` |

## 风险、边界与改进建议

### 已知风险

1. **API 演进限制**
   - **风险**：一旦类型被 `pub use` 导出，修改其签名即为破坏性变更
   - **缓解**：当前导出的类型都是核心抽象，相对稳定

2. **模块组织僵化**
   - **风险**：当前所有模块扁平组织，未来功能增加可能导致文件过大
   - **现状**：当前模块数量适中（6 个），暂无问题

### 改进建议

1. **预lude 模块**
   - 添加 `pub mod prelude` 提供常用类型的便捷导入
   ```rust
   pub mod prelude {
       pub use crate::{PackageManager, PackageManagerConfig, ManagedPackage, PackageManagerError};
   }
   ```
   - 用户可使用 `use codex_package_manager::prelude::*;`

2. **特性标志（Feature Flags）**
   - 考虑为不同功能添加可选特性
   ```toml
   [features]
   default = ["zip", "tar"]
   zip = ["dep:zip"]
   tar = ["dep:tar", "dep:flate2"]
   ```
   - 允许用户按需裁剪依赖

3. **文档内联**
   - 在 `lib.rs` 顶部添加 crate 级别文档
   ```rust
   //! # codex-package-manager
   //! 
   //! Generic package manager for Codex runtime artifacts.
   ```

4. **重导出优化**
   - 考虑是否导出 `url::Url` 等常用关联类型
   - 避免用户需要单独依赖 `url` crate

5. **版本兼容性**
   - 添加 `#[doc(hidden)]` 的内部 API 标记
   - 明确区分公共 API 和内部实现细节

### 与 README 的关系

`README.md` 提供了 crate 的高级概述，而 `lib.rs` 定义了实际的代码边界。两者应保持一致：
- README 中提到的类型都应在 `lib.rs` 中导出
- `lib.rs` 导出的类型应在 README 中有相应说明

当前状态：README 完整描述了 `ManagedPackage` trait 和 `PackageManager` 的使用，与 `lib.rs` 导出一致。
