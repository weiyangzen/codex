# error.rs 研究文档

## 场景与职责

`error.rs` 定义了 `codex-package-manager` crate 的统一错误类型 `PackageManagerError`。该模块使用 `thiserror` crate 提供符合 Rust 错误处理最佳实践的错误类型，为包管理器的所有操作提供类型安全的错误传播机制。

### 核心职责
1. **错误类型定义**：定义包管理器可能遇到的所有错误变体
2. **错误转换**：提供与其他错误类型的无缝转换
3. **错误展示**：实现 `std::fmt::Display` 提供人类可读的错误信息
4. **错误溯源**：通过 `#[source]` 属性保留错误链

## 功能点目的

### 1. PackageManagerError - 错误枚举

```rust
#[derive(Debug, Error)]
pub enum PackageManagerError {
    UnsupportedPlatform { os: String, arch: String },
    InvalidBaseUrl(#[source] url::ParseError),
    Http { context: String, #[source] source: reqwest::Error },
    Io { context: String, #[source] source: std::io::Error },
    MissingPlatform(String),
    UnexpectedPackageVersion { expected: String, actual: String },
    UnexpectedArchiveSize { expected: u64, actual: u64 },
    ChecksumMismatch { expected: String, actual: String },
    ArchiveExtraction(String),
    MissingPackageRoot(PathBuf),
}
```

### 2. 错误变体详解

| 变体 | 场景 | 字段说明 |
|------|------|----------|
| `UnsupportedPlatform` | 当前平台不受支持 | `os`: 操作系统名称, `arch`: 架构名称 |
| `InvalidBaseUrl` | 基础 URL 解析失败 | 包装 `url::ParseError` |
| `Http` | HTTP 请求失败 | `context`: 操作上下文, `source`: 底层错误 |
| `Io` | 文件系统操作失败 | `context`: 操作上下文, `source`: IO 错误 |
| `MissingPlatform` | 清单缺少当前平台条目 | 平台标识字符串 |
| `UnexpectedPackageVersion` | 版本不匹配 | `expected`: 期望版本, `actual`: 实际版本 |
| `UnexpectedArchiveSize` | 归档大小不匹配 | `expected`: 期望大小, `actual`: 实际大小 |
| `ChecksumMismatch` | SHA-256 校验失败 | `expected`: 期望校验值, `actual`: 实际校验值 |
| `ArchiveExtraction` | 归档解压失败 | 错误描述字符串 |
| `MissingPackageRoot` | 无法检测包根目录 | 解压路径 |

### 3. 错误信息模板

使用 `thiserror` 的 `#[error("...")]` 属性定义：

```rust
#[error("unsupported platform: {os}-{arch}")]
UnsupportedPlatform { os: String, arch: String }

#[error("{context}")]
Http { context: String, #[source] source: reqwest::Error }

#[error("checksum mismatch: expected `{expected}`, got `{actual}`")]
ChecksumMismatch { expected: String, actual: String }
```

**设计考量**：
- 包含关键上下文信息（路径、版本、大小等）
- 使用 `#[source]` 保留错误链，支持 `Error::source()` 遍历
- 人类可读的格式化字符串

## 具体技术实现

### thiserror 使用

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum PackageManagerError { ... }
```

`thiserror` 自动实现：
- `std::fmt::Display`
- `std::error::Error`（包括 `source()` 方法）
- `From` 转换（用于 `#[source]` 标记的字段）

### 错误溯源

```rust
#[error("{context}")]
Io {
    context: String,
    #[source]
    source: std::io::Error,
},
```

调用 `Error::source()` 可获取底层的 `std::io::Error`，支持完整的错误链遍历。

## 关键代码路径与文件引用

### 内部依赖
- 无（本模块为底层模块）

### 被调用方

| 文件 | 使用场景 |
|------|----------|
| `platform.rs` | `UnsupportedPlatform` - 平台检测失败 |
| `manager.rs` | `Http`, `Io`, `UnexpectedPackageVersion` 等 - 各种操作错误 |
| `archive.rs` | `Io`, `ChecksumMismatch`, `UnexpectedArchiveSize`, `ArchiveExtraction`, `MissingPackageRoot` - 归档操作错误 |
| `package.rs` | 作为 `ManagedPackage::Error` 的基类型 |

### 转换使用

**From 实现**（由 `thiserror` 自动生成）：
```rust
impl From<url::ParseError> for PackageManagerError { ... }
// 注意：Http 和 Io 需要显式构造，因为包含额外 context 字段
```

## 依赖与外部交互

### 外部依赖
| Crate | 用途 | 版本来源 |
|-------|------|----------|
| `thiserror` | 派生宏 | workspace |

### 标准库依赖
- `std::path::PathBuf` - `MissingPackageRoot` 字段

## 风险、边界与改进建议

### 已知风险

1. **错误信息泄露敏感信息**
   - **风险**：路径信息可能包含用户名等敏感数据
   - **缓解**：当前实现直接包含路径，调用者需注意日志处理

2. **错误变体膨胀**
   - **风险**：随着功能增加，枚举变体可能过多
   - **现状**：当前 10 个变体，仍在合理范围

3. **字符串错误（ArchiveExtraction）**
   - **风险**：使用 `String` 而非结构化数据，不利于程序化匹配
   - **现状**：归档错误场景复杂，字符串提供灵活性

### 边界条件

| 场景 | 行为 |
|------|------|
| 空 context 字符串 | 仍显示空字符串，建议始终提供有意义的上下文 |
| 非常大的路径 | `PathBuf` 正常处理，显示时可能截断 |
| 非 UTF-8 路径 | `PathBuf` 保留原始字节，显示时可能乱码 |

### 改进建议

1. **结构化归档错误**
   ```rust
   pub enum ArchiveErrorKind {
       PathTraversal,
       UnsupportedEntry { path: String, kind: String },
       CorruptedArchive { reason: String },
   }
   ```

2. **错误分类**
   - 添加 `is_retryable()` 方法区分可重试错误
   - 网络错误（`Http`）通常可重试，校验错误（`ChecksumMismatch`）不可重试

3. **错误代码**
   - 为每个变体添加错误代码，便于程序化识别
   - 例如：`E001` 平台不支持，`E002` URL 无效等

4. **国际化支持**
   - 当前错误信息硬编码为英文
   - 可考虑使用 `fluent` 或类似方案支持多语言

5. **敏感信息脱敏**
   - 在 `Display` 实现中脱敏路径（如替换用户名为 `~`）
   - 或提供 `Display::redacted()` 方法

6. **错误上下文增强**
   - 使用 `anyhow::Context` 或 `eyre::WrapErr` 模式
   - 支持在错误传播过程中添加上下文

### 测试覆盖

测试文件 `tests.rs` 中相关测试：
- 各种错误场景的断言，如：
  - `ensure_installed_rejects_manifest_version_mismatch` - `UnexpectedPackageVersion`
  - `ensure_installed_rejects_unexpected_archive_size` - `UnexpectedArchiveSize`
  - `ensure_installed_restores_previous_install_when_final_validation_fails` - `ArchiveExtraction`
  - `zip_extraction_rejects_parent_paths` - `ArchiveExtraction`
  - `tar_gz_extraction_rejects_symlinks` - `ArchiveExtraction`

### 使用示例

**构造错误**：
```rust
PackageManagerError::Io {
    context: format!("failed to create {}", path.display()),
    source: io_error,
}
```

**匹配错误**：
```rust
match error {
    PackageManagerError::ChecksumMismatch { expected, actual } => {
        // 处理校验失败
    }
    PackageManagerError::Io { context, .. } if context.contains("timeout") => {
        // 处理超时
    }
    _ => Err(error)?,
}
```

**错误转换**：
```rust
impl From<PackageManagerError> for MyError {
    fn from(e: PackageManagerError) -> Self {
        MyError::PackageManager(e)
    }
}
```
