# codex-rs/artifacts/README.md 研究文档

## 场景与职责

`codex-artifacts` crate 是 Codex 项目中负责 **Artifact 运行时管理和执行** 的核心组件。Artifact 是 Codex 生成的一种结构化输出（如 React 组件、SVG 图表、Markdown 文档等），需要一个专门的 JavaScript 运行时来构建和渲染。

该 crate 的两大核心职责：
1. **运行时管理**: 定位、验证和可选地下载固定的 Artifact 运行时
2. **命令执行**: 针对已解析的运行时生成构建或渲染命令

## 功能点目的

### 1. ArtifactRuntimeManager

运行时管理器，负责：
- 从 GitHub Releases 下载 Artifact 运行时
- 验证运行时完整性（SHA256 校验）
- 缓存到本地目录 (`~/.codex/packages/artifacts/`)
- 支持多平台（macOS/Windows/Linux × x64/ARM64）

### 2. ArtifactsClient

执行客户端，负责：
- 执行 artifact 构建请求
- 包装用户 JavaScript 代码
- 管理子进程（超时、环境变量、stdout/stderr 捕获）

### 3. JavaScript 运行时解析

按优先级查找可用的 JS 执行环境：
1. 系统 Node.js
2. 系统 Electron
3. Codex Desktop App 内置 Electron

## 具体技术实现

### 模块架构

```
codex-artifacts
├── src/lib.rs                    # 公共 API 导出
├── src/client.rs                 # ArtifactsClient 实现
│   ├── ArtifactsClient           # 主客户端结构
│   ├── ArtifactBuildRequest      # 构建请求参数
│   ├── ArtifactCommandOutput     # 命令输出结果
│   └── build_wrapped_script()    # JS 代码包装
└── src/runtime/
    ├── mod.rs                    # 模块聚合
    ├── manager.rs                # ArtifactRuntimeManager
    │   ├── ArtifactRuntimeReleaseLocator  # Release 定位
    │   ├── ArtifactRuntimeManagerConfig   # 配置
    │   └── ArtifactRuntimeManager         # 管理器
    ├── installed.rs              # 已安装运行时
    │   ├── InstalledArtifactRuntime       # 运行时实例
    │   └── load_cached_runtime()          # 加载缓存
    ├── js_runtime.rs             # JS 运行时解析
    │   ├── JsRuntime             # JS 运行时信息
    │   ├── JsRuntimeKind         # Node/Electron 枚举
    │   └── is_js_runtime_available()      # 可用性检查
    ├── manifest.rs               # Release 清单
    │   └── ReleaseManifest       # manifest.json 结构
    └── error.rs                  # 错误类型
    │   └── ArtifactRuntimeError  # 统一错误枚举
```

### 关键流程

#### 运行时安装流程

```rust
// ArtifactRuntimeManager::ensure_installed()
1. 检查本地缓存 (resolve_cached)
2. 获取文件锁 (fd_lock)
3. 再次检查缓存（双重检查锁定模式）
4. 下载 manifest.json
5. 下载平台特定的归档文件 (.zip/.tar.gz)
6. 验证 SHA256 和文件大小
7. 解压到 staging 目录
8. 验证 package.json 和入口文件
9. 原子性移动到安装目录
10. 最终验证
```

#### 构建执行流程

```rust
// ArtifactsClient::execute_build()
1. 解析运行时 (resolve_runtime)
2. 创建临时 staging 目录 (tempfile::TempDir)
3. 生成包装后的 JS 脚本
4. 写入脚本文件
5. 配置命令（可执行文件、环境变量、工作目录）
6. 启动子进程
7. 异步读取 stdout/stderr
8. 等待进程完成或超时
9. 返回输出结果
```

#### JS 代码包装

```javascript
// build_wrapped_script() 生成的代码结构
const artifactTool = await import("file:///path/to/build.mjs");
globalThis.artifactTool = artifactTool;
for (const [name, value] of Object.entries(artifactTool)) {
  if (name === "default" || Object.prototype.hasOwnProperty.call(globalThis, name)) {
    continue;
  }
  globalThis[name] = value;
}
// 用户代码插入此处
```

这种包装方式使得用户代码可以直接使用 `artifactTool` 导出的 API，如 `ok` 等。

### 数据结构

#### ReleaseManifest

```rust
pub struct ReleaseManifest {
    pub schema_version: u32,           // 清单格式版本
    pub runtime_version: String,       // 运行时版本
    pub release_tag: String,           // GitHub release tag
    pub node_version: Option<String>,  // 所需 Node 版本
    pub platforms: BTreeMap<String, PackageReleaseArchive>,  // 平台->归档映射
}
```

#### PackageReleaseArchive

```rust
pub struct PackageReleaseArchive {
    pub archive: String,        // 文件名
    pub sha256: String,         // 校验和
    pub format: ArchiveFormat,  // Zip 或 TarGz
    pub size_bytes: Option<u64>, // 文件大小
}
```

#### InstalledArtifactRuntime

```rust
pub struct InstalledArtifactRuntime {
    root_dir: PathBuf,              // 安装根目录
    runtime_version: String,        // 版本号
    platform: ArtifactRuntimePlatform,  // 平台
    build_js_path: PathBuf,         // 构建入口文件
}
```

### 公共 API

| API | 类型 | 用途 |
|-----|------|------|
| `ArtifactRuntimeManager` | struct | 运行时下载和缓存管理 |
| `load_cached_runtime()` | fn | 从指定缓存根加载已安装运行时 |
| `is_js_runtime_available()` | fn | 检查是否可用（缓存或系统 JS） |
| `ArtifactsClient` | struct | 执行 artifact 构建 |
| `ArtifactBuildRequest` | struct | 构建请求参数 |
| `ArtifactCommandOutput` | struct | 构建输出结果 |

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/client.rs` | 229 | ArtifactsClient 实现，构建执行 |
| `src/runtime/manager.rs` | 255 | ArtifactRuntimeManager 实现 |
| `src/runtime/installed.rs` | 283 | 已安装运行时加载和验证 |
| `src/runtime/js_runtime.rs` | 171 | JS 运行时检测和选择 |
| `src/runtime/manifest.rs` | 15 | ReleaseManifest 定义 |
| `src/runtime/error.rs` | 28 | 错误类型定义 |
| `src/tests.rs` | 453 | 集成测试 |

### 依赖 crate

| crate | 用途 |
|-------|------|
| `codex-package-manager` | 包管理抽象，提供通用下载/缓存逻辑 |

### 外部资源

| 资源 | URL 模式 |
|------|---------|
| Release 基础 URL | `https://github.com/openai/codex/releases/download/` |
| Manifest 文件 | `{base_url}/{tag}/{tag}-manifest.json` |
| 归档文件 | `{base_url}/{tag}/{archive_name}` |

## 依赖与外部交互

### 与 codex-package-manager 的交互

```rust
// ArtifactRuntimePackage 实现 ManagedPackage trait
impl ManagedPackage for ArtifactRuntimePackage {
    type Error = ArtifactRuntimeError;
    type Installed = InstalledArtifactRuntime;
    type ReleaseManifest = ReleaseManifest;
    
    fn install_dir(&self, cache_root: &Path, platform: ArtifactRuntimePlatform) -> PathBuf {
        cache_root.join(self.version()).join(platform.as_str())
    }
    
    fn load_installed(&self, root_dir: PathBuf, platform: ArtifactRuntimePlatform) 
        -> Result<Self::Installed, Self::Error> {
        InstalledArtifactRuntime::load(root_dir, platform)
    }
    // ... 其他方法
}
```

### 与系统的交互

1. **文件系统**: 
   - 读取/写入 `~/.codex/packages/artifacts/`
   - 创建临时目录
   - 文件锁（`fd_lock`）

2. **网络**:
   - HTTP GET 请求下载 manifest 和归档
   - 通过 `reqwest` 客户端

3. **进程**:
   - 执行 `node` 或 `electron` 命令
   - 设置环境变量（如 `ELECTRON_RUN_AS_NODE=1`）

4. **系统命令查找**:
   - `which::which("node")`
   - `which::which("electron")`

## 风险、边界与改进建议

### 风险点

1. **网络依赖风险**:
   - 首次使用必须下载运行时（数十 MB）
   - GitHub Releases 不可用时会失败
   - 建议：提供离线模式或镜像配置

2. **安全风险**:
   - 下载的代码会被执行
   - 依赖 SHA256 校验，但 manifest 本身也是下载的
   - 建议：考虑 manifest 签名验证

3. **并发风险**:
   - 多进程同时安装时使用文件锁
   - 锁超时或崩溃可能导致残留 `.lock` 文件
   - 已实现：staging 目录隔离和原子性移动

4. **平台兼容性**:
   - 仅支持 6 种平台组合
   - 新平台需要更新 `PackagePlatform`

### 边界条件

1. **超时处理**:
   - 默认构建超时：30 秒
   - 可配置：`ArtifactBuildRequest.timeout`

2. **路径限制**:
   - 运行时路径不能包含 `..` 或绝对路径
   - 防止目录遍历攻击

3. **缓存失效**:
   - 版本不匹配时自动重新下载
   - 手动删除缓存目录可强制刷新

4. **Electron 特殊处理**:
   - 需要设置 `ELECTRON_RUN_AS_NODE=1` 环境变量
   - 在 `JsRuntime::requires_electron_run_as_node()` 中处理

### 改进建议

1. **配置增强**:
   ```rust
   // 建议添加代理配置
   pub struct ArtifactRuntimeManagerConfig {
       // ... 现有字段
       pub proxy: Option<Url>,
       pub mirror_urls: Vec<Url>,
   }
   ```

2. **缓存策略**:
   - 添加 LRU 缓存限制
   - 自动清理旧版本

3. **可观测性**:
   - 添加 tracing 日志
   - 导出下载/构建指标

4. **错误改进**:
   - 区分网络错误、校验错误、权限错误
   - 提供用户友好的错误提示

5. **测试覆盖**:
   - 当前测试主要覆盖正常路径
   - 建议添加更多错误场景测试（网络超时、损坏的归档等）

6. **文档完善**:
   - 添加架构图
   - 提供故障排除指南
   - 说明如何手动安装运行时

### 相关命令

```bash
# 运行测试
cargo test -p codex-artifacts

# 格式化代码
just fmt -p codex-artifacts

# 检查代码
just fix -p codex-artifacts

# 更新 Bazel 锁文件
just bazel-lock-update
```
