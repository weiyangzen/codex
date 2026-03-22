# installed.rs 研究文档

## 场景与职责

`installed.rs` 负责管理已安装的 artifact runtime 的加载、验证和 JavaScript 运行时解析。它是 artifact runtime 子系统的核心组件，连接了 package manager 的抽象与实际的 JavaScript 执行环境。

该文件的核心职责：
1. **运行时加载**：从磁盘加载已缓存的 artifact runtime
2. **路径验证**：验证运行时路径的安全性和有效性（防止目录遍历攻击）
3. **元数据解析**：解析 `package.json` 获取运行时版本和入口点
4. **JS 运行时解析**：在系统 Node.js、Electron 和 Codex 桌面应用之间选择最佳的 JavaScript 执行环境

## 功能点目的

### 1. InstalledArtifactRuntime 结构体

表示一个已验证的运行时安装，包含：
- `root_dir`: 运行时根目录
- `runtime_version`: 版本号（来自 package.json）
- `platform`: 目标平台
- `build_js_path`: artifact 构建入口点路径

### 2. load_cached_runtime 函数

从指定的缓存根目录加载特定版本的运行时：
```rust
pub fn load_cached_runtime(
    cache_root: &Path,
    runtime_version: &str,
) -> Result<InstalledArtifactRuntime, ArtifactRuntimeError>
```

### 3. resolve_js_runtime 方法

按优先级选择 JavaScript 运行时：
1. 系统 Node.js (`node` 命令)
2. 系统 Electron (`electron` 命令)
3. Codex 桌面应用内置的 Electron

### 4. 路径安全验证

`resolve_relative_runtime_path` 函数防止目录遍历攻击：
- 拒绝空路径和绝对路径
- 拒绝包含 `..`、Windows 盘符或根目录组件的路径

## 具体技术实现

### 核心数据结构

```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InstalledArtifactRuntime {
    root_dir: PathBuf,
    runtime_version: String,
    platform: ArtifactRuntimePlatform,
    build_js_path: PathBuf,
}

struct PackageMetadata {
    version: String,
    build_js_relative_path: String,
}
```

### 路径安全验证算法

```rust
fn resolve_relative_runtime_path(
    root_dir: &Path,
    relative_path: &str,
) -> Result<PathBuf, ArtifactRuntimeError> {
    let relative = Path::new(relative_path);
    
    // 拒绝空路径和绝对路径
    if relative.as_os_str().is_empty() || relative.is_absolute() {
        return Err(ArtifactRuntimeError::InvalidRuntimePath(...));
    }
    
    // 拒绝危险组件：..、Windows 盘符、根目录
    if relative.components().any(|component| {
        matches!(
            component,
            Component::ParentDir | Component::Prefix(_) | Component::RootDir
        )
    }) {
        return Err(ArtifactRuntimeError::InvalidRuntimePath(...));
    }
    
    Ok(root_dir.join(relative))
}
```

### 运行时根目录检测

```rust
fn detect_runtime_root(extraction_root: &Path) -> Result<PathBuf, ArtifactRuntimeError> {
    // 直接检查当前目录
    if is_runtime_root(extraction_root) {
        return Ok(extraction_root.to_path_buf());
    }
    
    // 检查单个子目录（处理 tar/zip 包含顶层目录的情况）
    let mut directory_candidates = Vec::new();
    for entry in std::fs::read_dir(extraction_root)? { ... }
    
    if directory_candidates.len() == 1 {
        let candidate = &directory_candidates[0];
        if is_runtime_root(candidate) {
            return Ok(candidate.clone());
        }
    }
    
    Err(...)
}
```

### package.json 解析

```rust
#[derive(serde::Deserialize)]
struct PackageJson {
    name: String,
    version: String,
    exports: PackageExports,
}

#[derive(serde::Deserialize)]
#[serde(untagged)]
enum PackageExports {
    Main(String),           // "exports": "./dist/index.js"
    Map(BTreeMap<String, String>),  // "exports": { ".": "./dist/index.js" }
}
```

验证要求：
- `name` 必须是 `"@oai/artifact-tool"`
- `exports` 必须包含 `"."` 入口点
- 入口点路径以 `"./"` 开头，需要去除前缀

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/installed.rs` (283 行)

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/error.rs` - 错误类型定义
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/js_runtime.rs` - JS 运行时检测
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/manifest.rs` - ReleaseManifest 类型
- `/home/sansha/Github/codex/codex-rs/package-manager/src/platform.rs` - `PackagePlatform` 类型

### 调用方文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/manager.rs` - `ArtifactRuntimePackage::load_installed`
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/js_runtime.rs` - `load_cached_runtime` 调用
- `/home/sansha/Github/codex/codex-rs/artifacts/src/client.rs` - `ArtifactsClient` 使用运行时
- `/home/sansha/Github/codex/codex-rs/artifacts/src/tests.rs` - 单元测试

### 关键函数调用链

```
ArtifactsClient::execute_build
    -> resolve_runtime
        -> ArtifactRuntimeManager::ensure_installed
            -> PackageManager::ensure_installed
                -> ArtifactRuntimePackage::load_installed
                    -> InstalledArtifactRuntime::load
                        -> load_package_metadata
                        -> resolve_relative_runtime_path
                        -> verify_required_runtime_path
        -> InstalledArtifactRuntime::resolve_js_runtime
            -> resolve_js_runtime_from_candidates
                -> system_node_runtime
                -> system_electron_runtime
                -> codex_app_runtime_candidates
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `std::path` | 路径操作和验证 |
| `std::collections::BTreeMap` | package.json exports 解析 |
| `serde_json` | package.json 反序列化 |
| `which` | 系统命令查找（在 js_runtime.rs 中） |

### 常量定义

```rust
const ARTIFACT_TOOL_PACKAGE_NAME: &str = "@oai/artifact-tool";
```

这是 artifact tool npm 包的名称，用于验证安装的包是否正确。

### 模块关系

```
installed.rs
    |
    +-- uses error.rs (ArtifactRuntimeError)
    |
    +-- uses js_runtime.rs (JsRuntime, resolve_js_runtime_from_candidates)
    |
    +-- uses manifest.rs (ReleaseManifest)
    |
    +-- used by manager.rs (ArtifactRuntimePackage trait impl)
    |
    +-- used by client.rs (ArtifactsClient)
```

## 风险、边界与改进建议

### 当前风险

1. **路径遍历漏洞**：虽然已经进行了验证，但复杂的符号链接场景可能绕过检查
2. **TOCTOU 竞争条件**：`verify_required_runtime_path` 检查文件存在性后，文件可能被修改或删除
3. **单个子目录假设**：`detect_runtime_root` 假设归档只有一个顶层目录，如果多个目录都包含有效运行时可能选择错误

### 边界情况

1. **符号链接**：`build_js_path.is_file()` 对符号链接返回 true，但后续执行可能失败
2. **权限问题**：文件存在但不可读时，错误消息可能不够清晰
3. **并发安装**：多个进程同时尝试安装同一版本时，文件系统操作可能冲突
4. **跨平台路径**：Windows 路径分隔符处理依赖于 `Path` 的抽象

### 改进建议

1. **增强路径验证**：
   ```rust
   // 添加符号链接解析和规范化
   fn resolve_relative_runtime_path(
       root_dir: &Path,
       relative_path: &str,
   ) -> Result<PathBuf, ArtifactRuntimeError> {
       let resolved = resolve_and_validate(...)?;
       // 确保解析后的路径仍在 root_dir 下
       if !resolved.starts_with(root_dir.canonicalize()?) {
           return Err(ArtifactRuntimeError::InvalidRuntimePath(...));
       }
       Ok(resolved)
   }
   ```

2. **添加文件锁定**：
   在加载运行时时使用读取锁，与安装过程的写入锁配合，避免读取部分写入的文件

3. **改进运行时根目录检测**：
   ```rust
   // 当有多个候选时，按版本排序选择最新
   if directory_candidates.len() > 1 {
       directory_candidates.sort_by_key(|p| extract_version(p));
       // 选择版本最新的
   }
   ```

4. **缓存元数据**：
   将解析后的 `PackageMetadata` 缓存到内存中，避免重复读取和解析 package.json

5. **添加健康检查**：
   ```rust
   impl InstalledArtifactRuntime {
       pub fn health_check(&self) -> Result<(), ArtifactRuntimeError> {
           // 验证所有必需文件存在且可读
           // 验证文件权限
           // 可选：验证文件校验和
       }
   }
   ```

6. **改进错误消息**：
   当 `package.json` 解析失败时，提供更有用的诊断信息，如建议检查文件编码或 JSON 语法

7. **支持更多 exports 格式**：
   当前只支持简单的字符串和 Map，可以考虑支持 Node.js 的 conditional exports
   ```json
   {
     "exports": {
       ".": {
         "import": "./dist/index.mjs",
         "require": "./dist/index.cjs"
       }
     }
   }
   ```
