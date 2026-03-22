# js_runtime.rs 研究文档

## 场景与职责

`js_runtime.rs` 负责检测和选择用于执行 artifact 构建的 JavaScript 运行时环境。它实现了跨平台的 JavaScript 引擎发现机制，支持 Node.js 和 Electron 两种运行时，并能够自动检测 Codex 桌面应用内置的 Electron。

该文件的核心职责：
1. **运行时检测**：在系统 PATH 中查找 `node` 和 `electron` 命令
2. **Codex 应用检测**：在标准安装位置查找 Codex 桌面应用
3. **运行时选择**：按优先级选择最佳的 JavaScript 运行时
4. **平台能力检查**：判断当前平台是否支持 artifact runtime 管理

## 功能点目的

### 1. JsRuntime 和 JsRuntimeKind

```rust
pub enum JsRuntimeKind {
    Node,
    Electron,
}

pub struct JsRuntime {
    executable_path: PathBuf,
    kind: JsRuntimeKind,
}
```

`JsRuntime` 封装了 JavaScript 可执行文件的路径和类型，提供：
- `executable_path()`: 获取可执行文件路径
- `requires_electron_run_as_node()`: 判断是否需要设置 `ELECTRON_RUN_AS_NODE=1` 环境变量

### 2. is_js_runtime_available 函数

检查 artifact 执行是否可行，考虑两种情况：
1. 已缓存的运行时 + 可解析的 JS 运行时
2. 系统上直接可用的 JS 运行时

### 3. can_manage_artifact_runtime 函数

平台能力检查，判断当前操作系统和架构是否受支持。这是特性开关，用于决定是否向用户暴露 artifact runtime 管理功能。

### 4. 运行时选择优先级

```rust
resolve_js_runtime_from_candidates(
    node_runtime,      // 优先级 1: 系统 Node.js
    electron_runtime,  // 优先级 2: 系统 Electron
    codex_app_candidates,  // 优先级 3: Codex 桌面应用
)
```

### 5. 跨平台 Codex 应用检测

支持 macOS、Windows 和 Linux 的标准安装位置：

| 平台 | 搜索路径 |
|------|----------|
| macOS | `/Applications/Codex*.app`, `$HOME/Applications/Codex*.app` |
| Windows | `%LOCALAPPDATA%\Programs\Codex*`, `%ProgramFiles%\Codex*`, `%ProgramFiles(x86)%\Codex*` |
| Linux | `/opt/Codex*`, `/usr/lib/Codex*` |

## 具体技术实现

### 运行时检测实现

```rust
pub(crate) fn system_node_runtime() -> Option<JsRuntime> {
    which("node")
        .ok()
        .and_then(|path| node_runtime_from_path(&path))
}

pub(crate) fn system_electron_runtime() -> Option<JsRuntime> {
    which("electron")
        .ok()
        .and_then(|path| electron_runtime_from_path(&path))
}
```

使用 `which` crate 在 PATH 中查找命令，然后验证路径是否为文件。

### Codex 应用检测（macOS）

```rust
"macos" => {
    let mut roots = vec![PathBuf::from("/Applications")];
    if let Some(home) = std::env::var_os("HOME") {
        roots.push(PathBuf::from(home).join("Applications"));
    }

    roots
        .into_iter()
        .flat_map(|root| {
            CODEX_APP_PRODUCT_NAMES
                .into_iter()
                .map(move |product_name| {
                    root.join(format!("{product_name}.app"))
                        .join("Contents")
                        .join("MacOS")
                        .join(product_name)
                })
        })
        .collect()
}
```

### Codex 应用产品名称

```rust
const CODEX_APP_PRODUCT_NAMES: [&str; 6] = [
    "Codex",
    "Codex (Dev)",
    "Codex (Agent)",
    "Codex (Nightly)",
    "Codex (Alpha)",
    "Codex (Beta)",
];
```

支持多种构建变体，包括开发版、代理版、每日构建和预发布版本。

### Electron 特殊处理

```rust
pub fn requires_electron_run_as_node(&self) -> bool {
    self.kind == JsRuntimeKind::Electron
}
```

当使用 Electron 作为 Node.js 替代品时，需要设置 `ELECTRON_RUN_AS_NODE=1` 环境变量，使 Electron 以 Node.js 模式运行而不是启动 GUI 应用。

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/js_runtime.rs` (171 行)

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/installed.rs` - 使用 `load_cached_runtime`
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/manager.rs` - 导出 `can_manage_artifact_runtime`
- `/home/sansha/Github/codex/codex-rs/package-manager/src/platform.rs` - `ArtifactRuntimePlatform`

### 调用方文件
- `/home/sansha/Github/codex/codex-rs/artifacts/src/runtime/installed.rs` - `InstalledArtifactRuntime::resolve_js_runtime`
- `/home/sansha/Github/codex/codex-rs/artifacts/src/client.rs` - 检查 `requires_electron_run_as_node`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/artifacts.rs` - 使用 `ArtifactRuntimeManager`

### 关键调用链

```
ArtifactsClient::execute_build
    -> runtime.resolve_js_runtime()
        -> resolve_js_runtime_from_candidates
            -> system_node_runtime()
                -> which("node") -> node_runtime_from_path
            -> system_electron_runtime()
                -> which("electron") -> electron_runtime_from_path
            -> codex_app_runtime_candidates()
                -> 平台特定的路径构建
                -> electron_runtime_from_path
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `which::which` | 在 PATH 中查找可执行文件 |
| `std::env::consts` | 检测当前操作系统 (`OS`, `ARCH`) |
| `std::env::var_os` | 读取环境变量（HOME, LOCALAPPDATA 等） |

### 环境变量使用

| 变量 | 平台 | 用途 |
|------|------|------|
| `HOME` | macOS/Linux | 用户主目录 |
| `LOCALAPPDATA` | Windows | 本地应用数据目录 |
| `ProgramFiles` | Windows | 程序文件目录 |
| `ProgramFiles(x86)` | Windows | 32位程序文件目录 |

### 模块关系

```
js_runtime.rs
    |
    +-- uses installed.rs (load_cached_runtime, default_cached_runtime_root)
    |
    +-- uses manager.rs (ArtifactRuntimePlatform via re-export)
    |
    +-- used by installed.rs (InstalledArtifactRuntime::resolve_js_runtime)
    |
    +-- used by client.rs (ArtifactsClient 设置 ELECTRON_RUN_AS_NODE)
    |
    +-- exported by mod.rs (JsRuntime, JsRuntimeKind, is_js_runtime_available, can_manage_artifact_runtime)
```

## 风险、边界与改进建议

### 当前风险

1. **PATH 污染**：依赖 PATH 环境变量，可能被恶意修改
2. **版本兼容性**：不检查 Node.js/Electron 版本，可能使用不兼容的版本
3. **安全执行**：不验证可执行文件的签名或校验和
4. **性能问题**：每次调用都重新扫描文件系统，没有缓存

### 边界情况

1. **权限问题**：找到可执行文件但没有执行权限
2. **损坏的安装**：可执行文件存在但无法正常运行
3. **多个版本**：PATH 中有多个 Node.js/Electron 版本，选择顺序不确定
4. **网络文件系统**：可执行文件位于网络驱动器上，性能差或不可靠
5. **容器环境**：某些容器可能缺少标准的 PATH 设置

### 改进建议

1. **添加版本检查**：
   ```rust
   impl JsRuntime {
       pub fn check_version(&self) -> Result<Version, ArtifactRuntimeError> {
           let output = std::process::Command::new(&self.executable_path)
               .arg("--version")
               .output()?;
           // 解析版本号并验证最低要求
       }
   }
   ```

2. **缓存检测结果**：
   ```rust
   use std::sync::OnceLock;
   
   static JS_RUNTIME_CACHE: OnceLock<Option<JsRuntime>> = OnceLock::new();
   
   pub fn resolve_machine_js_runtime_cached() -> Option<JsRuntime> {
       JS_RUNTIME_CACHE.get_or_init(resolve_machine_js_runtime).clone()
   }
   ```

3. **添加签名验证（macOS/Windows）**：
   ```rust
   #[cfg(target_os = "macos")]
   fn verify_code_signature(path: &Path) -> Result<(), ArtifactRuntimeError> {
       // 使用 codesign 工具验证
   }
   ```

4. **改进错误诊断**：
   ```rust
   pub enum JsRuntimeError {
       NotFound,
       PermissionDenied,
       InvalidExecutable,
       VersionMismatch { expected: String, actual: String },
   }
   ```

5. **支持配置覆盖**：
   ```rust
   pub fn resolve_js_runtime_with_config(
       config: &JsRuntimeConfig,
   ) -> Option<JsRuntime> {
       // 允许通过环境变量或配置文件指定优先使用的运行时
       if let Some(explicit_path) = config.explicit_node_path {
           return node_runtime_from_path(&explicit_path);
       }
       // ... 回退到默认逻辑
   }
   ```

6. **添加健康检查**：
   ```rust
   impl JsRuntime {
       pub fn health_check(&self) -> Result<(), ArtifactRuntimeError> {
           // 执行一个简单的 JavaScript 表达式验证运行时正常工作
           let output = std::process::Command::new(&self.executable_path)
               .arg("-e")
               .arg("console.log('ok')")
               .output()?;
           // 验证输出
       }
   }
   ```

7. **支持更多运行时**：
   考虑支持 Deno 或 Bun 作为替代 JavaScript 运行时，提高灵活性

8. **异步检测**：
   将文件系统检测改为异步，避免在 async 上下文中阻塞
   ```rust
   pub async fn system_node_runtime_async() -> Option<JsRuntime> {
       // 使用 tokio::fs 进行异步文件检查
   }
   ```
