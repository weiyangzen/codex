# manifest.rs 研究文档

## 场景与职责

`manifest.rs` 定义了 artifact runtime 发布的元数据结构。它是 package manager 与 artifact runtime 之间的数据契约，用于描述发布的版本信息、支持的平台和对应的归档文件。

该文件的核心职责：
1. **发布元数据定义**：定义 release manifest 的数据结构
2. **序列化/反序列化**：支持 JSON 格式的编码和解码
3. **版本信息传递**：在下载和安装过程中传递版本和平台信息

## 功能点目的

### 1. ReleaseManifest 结构体

```rust
pub struct ReleaseManifest {
    pub schema_version: u32,
    pub runtime_version: String,
    pub release_tag: String,
    pub node_version: Option<String>,
    pub platforms: BTreeMap<String, PackageReleaseArchive>,
}
```

字段说明：

| 字段 | 类型 | 用途 |
|------|------|------|
| `schema_version` | `u32` | manifest 格式版本，用于未来兼容性 |
| `runtime_version` | `String` | artifact runtime 的语义化版本 |
| `release_tag` | `String` | GitHub release 标签，如 `"artifact-runtime-v0.1.0"` |
| `node_version` | `Option<String>` | 所需的 Node.js 版本（可选） |
| `platforms` | `BTreeMap<String, PackageReleaseArchive>` | 平台到归档的映射 |

### 2. PackageReleaseArchive

来自 `codex_package_manager` 的归档描述：
```rust
pub struct PackageReleaseArchive {
    pub archive: String,       // 归档文件名
    pub sha256: String,        // SHA-256 校验和
    pub format: ArchiveFormat, // Zip 或 TarGz
    pub size_bytes: Option<u64>, // 文件大小（可选）
}
```

## 具体技术实现

### 序列化配置

```rust
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct ReleaseManifest {
    pub schema_version: u32,
    pub runtime_version: String,
    pub release_tag: String,
    #[serde(default)]
    pub node_version: Option<String>,
    pub platforms: BTreeMap<String, PackageReleaseArchive>,
}
```

使用 `#[serde(default)]` 确保向后兼容：如果 manifest 中没有 `node_version` 字段，则默认为 `None`。

### 示例 Manifest

```json
{
  "schema_version": 1,
  "runtime_version": "0.1.0",
  "release_tag": "artifact-runtime-v0.1.0",
  "node_version": "18.17.0",
  "platforms": {
    "darwin-arm64": {
      "archive": "artifact-runtime-v0.1.0-darwin-arm64.tar.gz",
      "sha256": "abc123...",
      "format": "tar.gz",
      "size_bytes": 12345678
    },
    "darwin-x64": {
      "archive": "artifact-runtime-v0.1.0-darwin-x64.tar.gz",
      "sha256": "def456...",
      "format": "tar.gz",
      "size_bytes": 12345679
    },
    "linux-x64": {
      "archive": "artifact-runtime-v0.1.0-linux-x64.tar.gz",
      "sha256": "ghi789...",
      "format": "tar.gz",
      "size_bytes": 12345680
    },
    "windows-x64": {
      "archive": "artifact-runtime-v0.1.0-windows-x64.zip",
      "sha256": "jkl012...",
      "format": "zip",
      "size_bytes": 12345681
    }
  }
}
```

### 平台标识符

平台键使用 `codex_package_manager::PackagePlatform::as_str()` 的返回值：
- `"darwin-arm64"` - macOS Apple Silicon
- `"darwin-x64"` - macOS Intel
- `"linux-arm64"` - Linux ARM64
- `"linux-x64"` - Linux x86_64
- `"windows-arm64"` - Windows ARM64
- `"windows-x64"` - Windows x86_64

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/manifest.rs` (15 行)

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/package-manager/src/archive.rs` - `PackageReleaseArchive`, `ArchiveFormat`

### 调用方文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/manager.rs` - `ArtifactRuntimePackage::ReleaseManifest`
- `/home/sansha/Github/codex/codex-rs/artifacts/src/lib.rs` - 导出 `ReleaseManifest`
- `/home/sansha/Github/codex/codex-rs/artifacts/src/tests.rs` - 单元测试中使用

### 关键调用链

```
PackageManager::ensure_installed
    -> fetch_release_manifest
        -> HTTP GET manifest_url
        -> serde_json::from_slice::<ReleaseManifest>
            -> 解析 schema_version, runtime_version, release_tag, node_version, platforms
    -> platform_archive
        -> manifest.platforms.get(platform.as_str())
            -> 获取 PackageReleaseArchive
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `serde::Deserialize` | JSON 反序列化 |
| `serde::Serialize` | JSON 序列化（用于测试） |
| `std::collections::BTreeMap` | 平台到归档的有序映射 |
| `codex_package_manager::PackageReleaseArchive` | 归档描述类型 |

### 模块关系

```
manifest.rs
    |
    +-- uses package-manager/archive.rs (PackageReleaseArchive)
    |
    +-- exported by lib.rs (ReleaseManifest)
    |
    +-- used by manager.rs (ArtifactRuntimePackage trait impl)
    |
    +-- used by tests.rs (测试数据构建)
```

### 版本演进考虑

`schema_version` 字段为未来的 manifest 格式变更提供扩展点：

```rust
// 可能的未来版本处理
match manifest.schema_version {
    1 => handle_v1(manifest),
    2 => handle_v2(manifest),
    _ => Err(ArtifactRuntimeError::UnsupportedManifestVersion {
        version: manifest.schema_version,
    }),
}
```

## 风险、边界与改进建议

### 当前风险

1. **schema_version 未使用**：当前代码没有检查 schema_version，未来格式变更可能导致解析错误
2. **平台键硬编码**：平台标识符字符串在多处使用，容易不一致
3. **缺少验证**：没有验证 manifest 的完整性（如检查 platforms 非空）

### 边界情况

1. **空 platforms**：manifest 中没有平台条目时，安装会失败
2. **未知平台**：当前平台不在 manifest 中时，返回 `MissingPlatform` 错误
3. **大小写敏感**：平台键是大小写敏感的，`"Darwin-Arm64"` 与 `"darwin-arm64"` 不同
4. **JSON 扩展**：manifest 可以包含额外字段而不破坏解析（serde 默认忽略未知字段）

### 改进建议

1. **添加 schema 版本检查**：
   ```rust
   const SUPPORTED_SCHEMA_VERSIONS: &[u32] = &[1];
   
   impl ReleaseManifest {
       pub fn validate(&self) -> Result<(), ArtifactRuntimeError> {
           if !SUPPORTED_SCHEMA_VERSIONS.contains(&self.schema_version) {
               return Err(ArtifactRuntimeError::UnsupportedSchemaVersion {
                   version: self.schema_version,
                   supported: SUPPORTED_SCHEMA_VERSIONS.to_vec(),
               });
           }
           if self.platforms.is_empty() {
               return Err(ArtifactRuntimeError::EmptyPlatforms);
           }
           Ok(())
       }
   }
   ```

2. **使用类型安全的平台键**：
   ```rust
   pub struct PlatformKey(String);
   
   impl From<ArtifactRuntimePlatform> for PlatformKey {
       fn from(platform: ArtifactRuntimePlatform) -> Self {
           Self(platform.as_str().to_string())
       }
   }
   
   pub struct ReleaseManifest {
       // ...
       pub platforms: BTreeMap<PlatformKey, PackageReleaseArchive>,
   }
   ```

3. **添加 manifest 签名验证**：
   ```rust
   pub struct ReleaseManifest {
       // ...
       #[serde(default)]
       pub signature: Option<String>, // 对 manifest 内容的签名
   }
   
   impl ReleaseManifest {
       pub fn verify_signature(&self, public_key: &str) -> Result<(), ArtifactRuntimeError> {
           // 验证 manifest 的加密签名
       }
   }
   ```

4. **支持增量更新**：
   ```rust
   pub struct ReleaseManifest {
       // ...
       #[serde(default)]
       pub delta_updates: Option<BTreeMap<String, DeltaUpdateInfo>>,
   }
   
   pub struct DeltaUpdateInfo {
       pub from_version: String,
       pub patch_archive: PackageReleaseArchive,
   }
   ```

5. **添加元数据**：
   ```rust
   pub struct ReleaseManifest {
       // ...
       #[serde(default)]
       pub release_date: Option<String>, // ISO 8601 格式
       #[serde(default)]
       pub release_notes_url: Option<String>,
       #[serde(default)]
       pub min_codex_version: Option<String>, // 兼容的 Codex CLI 最低版本
   }
   ```

6. **压缩 manifest**：
   对于包含大量平台的大型 manifest，考虑支持 gzip 压缩：
   ```rust
   // manifest.json.gz
   ```

7. **文档生成**：
   添加生成 manifest 文档的工具，帮助用户理解可用版本：
   ```rust
   impl ReleaseManifest {
       pub fn to_markdown(&self) -> String {
           // 生成人类可读的文档
       }
   }
   ```
