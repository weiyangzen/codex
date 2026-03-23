# archive.rs 研究文档

## 场景与职责

`archive.rs` 是 `codex-package-manager` crate 的核心模块之一，负责处理软件包归档文件的验证、解压和包根目录检测。它是包管理器与文件系统交互的关键层，确保从远程下载的归档文件能够安全、完整地解压到本地缓存目录。

### 核心职责
1. **归档元数据管理**：定义 `PackageReleaseArchive` 结构体，描述发布清单中的平台特定归档信息
2. **完整性验证**：提供 SHA-256 校验和文件大小验证功能
3. **安全解压**：支持 `.zip` 和 `.tar.gz` 两种格式的安全解压，防止路径遍历攻击
4. **包根检测**：自动检测解压后的包根目录（支持直接包含 `manifest.json` 或单层嵌套目录结构）

## 功能点目的

### 1. PackageReleaseArchive - 归档元数据结构
```rust
pub struct PackageReleaseArchive {
    pub archive: String,        // 归档文件名
    pub sha256: String,         // 期望的 SHA-256 校验值
    pub format: ArchiveFormat,  // 归档格式（Zip/TarGz）
    pub size_bytes: Option<u64>, // 可选的文件大小
}
```

**设计目的**：
- 与发布清单（release manifest）JSON 格式对应，支持反序列化
- 提供完整的归档验证所需元数据
- `size_bytes` 为可选字段，提供额外的完整性检查层

### 2. ArchiveFormat - 归档格式枚举
```rust
pub enum ArchiveFormat {
    #[serde(rename = "zip")]
    Zip,
    #[serde(rename = "tar.gz")]
    TarGz,
}
```

**设计目的**：
- 明确支持的归档格式，便于扩展
- 使用 serde rename 匹配清单中的字符串表示

### 3. detect_single_package_root - 包根目录检测

**算法逻辑**：
1. 首先检查解压根目录是否直接包含 `manifest.json`
2. 如果不存在，扫描根目录下的所有子目录
3. 如果只有一个子目录且包含 `manifest.json`，返回该子目录
4. 否则返回错误 `MissingPackageRoot`

**设计考量**：
- 支持两种常见的归档布局：扁平结构和单层嵌套结构
- 避免过度复杂的嵌套检测，保持行为可预测

### 4. verify_archive_size & verify_sha256 - 完整性验证

**安全考量**：
- SHA-256 验证使用 `sha2` crate，将计算结果与期望值（不区分大小写）比较
- 大小验证在 SHA-256 之前执行，快速失败机制
- 大小验证为可选（`Option<u64>`），保持向后兼容

### 5. extract_archive - 归档解压主入口

**分发逻辑**：
```rust
match format {
    ArchiveFormat::Zip => extract_zip_archive(archive_path, destination),
    ArchiveFormat::TarGz => extract_tar_gz_archive(archive_path, destination),
}
```

### 6. extract_zip_archive - ZIP 安全解压

**安全特性**：
- 使用 `ZipArchive::enclosed_name()` 防止路径遍历攻击
- 自动创建父目录结构
- Unix 平台保留文件权限（通过 `unix_mode()`）

**关键代码路径**：
```rust
let Some(relative_path) = entry.enclosed_name() else {
    return Err(PackageManagerError::ArchiveExtraction(format!(
        "zip entry `{}` escapes extraction root",
        entry.name()
    )));
};
```

### 7. extract_tar_gz_archive - Tar.gz 安全解压

**安全特性**：
- 拒绝符号链接、硬链接、块/字符设备、FIFO、稀疏文件
- 跳过 PAX 扩展和 GNU 长名/长链接条目
- 使用 `safe_extract_path` 确保路径安全

**拒绝的条目类型**：
```rust
if entry_type.is_symlink()
    || entry_type.is_hard_link()
    || entry_type.is_block_special()
    || entry_type.is_character_special()
    || entry_type.is_fifo()
    || entry_type.is_gnu_sparse()
{
    return Err(PackageManagerError::ArchiveExtraction(...));
}
```

### 8. safe_extract_path - 路径安全验证

**算法逻辑**：
1. 遍历路径组件，只允许 `Normal` 和 `CurDir`
2. 拒绝 `ParentDir`（`..`）、`RootDir` 和 `Prefix` 组件
3. 确保清理后的路径非空

**安全意义**：
- 防止路径遍历攻击（ZipSlip/TarSlip）
- 确保所有解压文件都位于指定的目标根目录内

## 具体技术实现

### 关键数据结构

| 结构/枚举 | 用途 | 关键字段 |
|-----------|------|----------|
| `PackageReleaseArchive` | 归档元数据 | archive, sha256, format, size_bytes |
| `ArchiveFormat` | 格式枚举 | Zip, TarGz |

### 关键函数流程

```
extract_archive
├── extract_zip_archive
│   ├── File::open
│   ├── ZipArchive::new
│   ├── 遍历 entries
│   │   ├── enclosed_name() 安全检查
│   │   ├── create_dir_all 创建目录
│   │   ├── File::create 创建文件
│   │   ├── std::io::copy 复制内容
│   │   └── apply_zip_permissions 设置权限
│   └── Ok(())
└── extract_tar_gz_archive
    ├── File::open
    ├── GzDecoder::new
    ├── Archive::new
    ├── 遍历 entries
    │   ├── safe_extract_path 安全检查
    │   ├── 类型检查（拒绝特殊文件）
    │   ├── create_dir_all 创建目录
    │   └── entry.unpack 解压
    └── Ok(())
```

## 关键代码路径与文件引用

### 内部依赖
- `crate::PackageManagerError` - 错误类型定义（error.rs）

### 外部依赖
| Crate | 用途 | 版本来源 |
|-------|------|----------|
| `flate2` | Gzip 解码 | workspace |
| `sha2` | SHA-256 计算 | workspace |
| `tar` | Tar 归档处理 | workspace |
| `zip` | Zip 归档处理 | workspace |

### 调用关系

**被调用方**（来自 manager.rs）：
- `extract_archive` - 在 `ensure_installed` 中用于解压下载的归档
- `verify_archive_size` - 在 `ensure_installed` 中验证下载完整性
- `verify_sha256` - 在 `ensure_installed` 中验证校验和
- `detect_single_package_root` - 在 `ManagedPackage::detect_extracted_root` 默认实现中使用

**调用方**（来自 tests.rs）：
- `extract_archive` - 测试用例 `tar_gz_extraction_supports_default_package_root_detection`
- `detect_single_package_root` - 测试用例验证包根检测

## 依赖与外部交互

### 平台特定代码

**Unix 权限处理**（`#[cfg(unix)]`）：
```rust
fn apply_zip_permissions(
    entry: &zip::read::ZipFile<'_>,
    output_path: &Path,
) -> Result<(), PackageManagerError>
```
- 使用 `std::os::unix::fs::PermissionsExt` 设置 Unix 文件权限
- 非 Unix 平台为空实现（直接返回 Ok(())）

### 文件系统交互

| 操作 | 用途 | 错误处理 |
|------|------|----------|
| `std::fs::read_dir` | 扫描解压目录 | 包装为 `PackageManagerError::Io` |
| `std::fs::create_dir_all` | 创建目录结构 | 包装为 `PackageManagerError::Io` |
| `File::open/create` | 文件操作 | 包装为 `PackageManagerError::Io` |
| `std::io::copy` | 复制归档内容 | 包装为 `PackageManagerError::Io` |

## 风险、边界与改进建议

### 已知风险

1. **路径遍历攻击**
   - **缓解措施**：`safe_extract_path` 和 `enclosed_name()` 双重检查
   - **残留风险**：复杂的相对路径组合可能绕过检测（已处理 `..` 和根目录）

2. **符号链接攻击（Tar）**
   - **缓解措施**：明确拒绝所有符号链接条目
   - **影响**：某些合法使用符号链接的包可能无法安装

3. **权限保留不完整**
   - **ZIP**：仅支持 Unix 权限，Windows 权限信息丢失
   - **Tar.gz**：依赖 `tar` crate 的默认权限处理

4. **内存使用**
   - 归档内容通过 `std::io::copy` 流式复制，不会一次性加载大文件到内存

### 边界条件

| 场景 | 行为 |
|------|------|
| 空归档 | `safe_extract_path` 返回错误（空路径） |
| 嵌套多层目录 | 仅支持单层嵌套，深层嵌套会失败 |
| 多个顶层目录 | `detect_single_package_root` 失败 |
| 损坏的归档 | 底层 crate 返回错误，包装为 `ArchiveExtraction` |
| 权限不足 | 返回 `Io` 错误，包含具体路径信息 |

### 改进建议

1. **支持更多归档格式**
   - 考虑添加 `.tar.xz`、`.tar.bz2` 等格式的支持
   - 实现方式：扩展 `ArchiveFormat` 枚举，添加对应解压逻辑

2. **进度回调**
   - 当前解压过程无进度反馈
   - 建议：添加可选的进度回调函数参数

3. **并行解压**
   - 大归档文件可考虑并行解压多个条目
   - 注意：需要保持目录创建的顺序性

4. **更灵活的包根检测**
   - 当前仅支持单层嵌套
   - 可考虑递归搜索 `manifest.json`，但需限制深度防止 DoS

5. **Windows 权限支持**
   - 当前 Windows 平台不保留任何权限信息
   - 可考虑使用 `zip` crate 的 Windows 权限扩展

6. **校验和算法扩展**
   - 当前仅支持 SHA-256
   - 可考虑支持 BLAKE3 等更现代的算法

### 测试覆盖

测试文件 `tests.rs` 中相关测试：
- `tar_gz_extraction_supports_default_package_root_detection` - Tar.gz 基础解压
- `tar_gz_extraction_rejects_symlinks` - 符号链接拒绝
- `zip_extraction_rejects_parent_paths` - 路径遍历防护
- `ensure_installed_*` 系列测试 - 端到端集成测试
