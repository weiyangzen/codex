# lib.rs 研究文档

## 文件信息
- **路径**: `codex-rs/core/tests/common/lib.rs`
- **大小**: 16,584 bytes (524 行)
- **所属模块**: core_test_support (测试支持库入口)

---

## 场景与职责

此文件是 `core_test_support` crate 的库入口点，为 Codex Core 模块的集成测试提供全面的测试基础设施。它通过模块组织、初始化宏、辅助函数和测试工具，构建了一个完整的测试支持框架。

### 核心职责
1. **模块组织**: 声明和导出所有测试支持子模块
2. **测试初始化**: 通过 `ctor` crate 在测试启动时执行全局初始化
3. **路径工具**: 提供跨平台的路径处理函数
4. **配置管理**: 简化测试配置的创建和加载
5. **事件等待**: 提供异步事件等待辅助函数
6. **文件系统监控**: 提供异步文件等待工具
7. **条件跳过宏**: 提供基于环境条件的测试跳过宏

---

## 功能点目的

### 1. 模块声明与导出
```rust
pub mod apps_test_server;    // Apps/MCP 测试服务器
pub mod context_snapshot;    // 上下文快照格式化
pub mod process;             // 进程管理工具
pub mod responses;           // OpenAI API Mock 响应
pub mod streaming_sse;       // 流式 SSE 测试服务器
pub mod test_codex;          // TestCodex 构建器
pub mod test_codex_exec;     // codex-exec 测试支持
pub mod tracing;             // 测试追踪支持
pub mod zsh_fork;            // Zsh fork 测试运行时
```

### 2. 全局初始化 (ctor)

#### 确定性进程 ID
```rust
#[ctor]
fn enable_deterministic_unified_exec_process_ids_for_tests() {
    codex_core::test_support::set_thread_manager_test_mode(/*enabled*/ true);
    codex_core::test_support::set_deterministic_process_ids(/*enabled*/ true);
}
```
- 启用测试模式，确保进程 ID 可预测
- 避免测试中的非确定性行为

#### Insta 工作区根配置
```rust
#[ctor]
fn configure_insta_workspace_root_for_snapshot_tests() {
    // 设置 INSTA_WORKSPACE_ROOT 环境变量
    // 使 insta 快照测试能够正确定位快照文件
}
```
- 配置 insta 快照测试框架
- 确保在 Bazel 和 Cargo 构建中都能正常工作

### 3. 断言工具

#### 正则匹配断言
```rust
#[track_caller]
pub fn assert_regex_match<'s>(pattern: &str, actual: &'s str) -> regex_lite::Captures<'s> {
    let regex = Regex::new(pattern).unwrap_or_else(|err| {
        panic!("failed to compile regex {pattern:?}: {err}");
    });
    regex.captures(actual)
        .unwrap_or_else(|| panic!("regex {pattern:?} did not match {actual:?}"))
}
```
- 使用 `#[track_caller]` 属性确保 panic 指向调用位置
- 返回捕获组以便进一步验证

### 4. 跨平台路径工具

#### test_path_buf_with_windows
```rust
pub fn test_path_buf_with_windows(unix_path: &str, windows_path: Option<&str>) -> PathBuf {
    if cfg!(windows) {
        // 转换 Unix 路径为 Windows 路径
    } else {
        PathBuf::from(unix_path)
    }
}
```
- 在 Windows 上将 Unix 风格路径转换为 Windows 风格
- 支持显式指定 Windows 路径或自动生成

#### test_absolute_path
```rust
pub fn test_absolute_path(unix_path: &str) -> AbsolutePathBuf {
    AbsolutePathBuf::from_absolute_path(test_path_buf(unix_path))
        .expect("test path should be absolute")
}
```
- 创建跨平台的绝对路径
- 使用 `codex_utils_absolute_path::AbsolutePathBuf`

#### test_tmp_path
```rust
pub fn test_tmp_path() -> AbsolutePathBuf {
    test_absolute_path_with_windows("/tmp", Some(r"C:\Users\codex\AppData\Local\Temp"))
}
```
- 提供跨平台的临时目录路径
- Linux: `/tmp`
- Windows: `C:\Users\codex\AppData\Local\Temp`

### 5. DotSlash 工具

#### fetch_dotslash_file
```rust
pub fn fetch_dotslash_file(
    dotslash_file: &std::path::Path,
    dotslash_cache: Option<&std::path::Path>,
) -> anyhow::Result<PathBuf>
```
- 使用 DotSlash 工具获取可执行文件
- 支持自定义缓存目录
- 验证返回路径是否为有效文件

### 6. 测试配置管理

#### load_default_config_for_test
```rust
pub async fn load_default_config_for_test(codex_home: &TempDir) -> Config {
    ConfigBuilder::default()
        .codex_home(codex_home.path().to_path_buf())
        .harness_overrides(default_test_overrides())
        .build()
        .await
        .expect("defaults for test should always succeed")
}
```
- 创建隔离的测试配置
- 使用临时目录作为 `codex_home`，避免污染用户真实配置
- 自动配置 Linux 沙箱路径（在 Linux 平台上）

#### default_test_overrides
```rust
#[cfg(target_os = "linux")]
fn default_test_overrides() -> ConfigOverrides {
    ConfigOverrides {
        codex_linux_sandbox_exe: Some(
            codex_utils_cargo_bin::cargo_bin("codex-linux-sandbox")
                .expect("should find binary for codex-linux-sandbox"),
        ),
        ..ConfigOverrides::default()
    }
}
```
- 平台特定的配置覆盖
- Linux 上自动查找 `codex-linux-sandbox` 二进制文件

### 7. SSE Fixture 加载

#### load_sse_fixture
```rust
pub fn load_sse_fixture(path: impl AsRef<std::path::Path>) -> String {
    // 从 JSON fixture 构建 SSE 流
    // fixture 格式: [{"type": "event_name", ...fields}]
    // 输出格式: "event: event_name\ndata: {...}\n\n"
}
```
- 从 JSON fixture 文件构建 SSE (Server-Sent Events) 流
- 简化测试中的 SSE 响应构造

#### load_sse_fixture_with_id_from_str
```rust
pub fn load_sse_fixture_with_id_from_str(raw: &str, id: &str) -> String {
    // 替换 __ID__ 占位符为实际 ID
}
```
- 支持模板替换，用于动态 ID 注入

### 8. 异步事件等待

#### wait_for_event
```rust
pub async fn wait_for_event<F>(
    codex: &CodexThread,
    predicate: F,
) -> codex_protocol::protocol::EventMsg
where
    F: FnMut(&codex_protocol::protocol::EventMsg) -> bool,
```
- 等待匹配谓词的事件
- 默认超时 1 秒（实际实现为 10 秒最小值）

#### wait_for_event_match
```rust
pub async fn wait_for_event_match<T, F>(codex: &CodexThread, matcher: F) -> T
where
    F: Fn(&codex_protocol::protocol::EventMsg) -> Option<T>,
```
- 等待事件并提取值
- 返回匹配的值而非整个事件

#### wait_for_event_with_timeout
```rust
pub async fn wait_for_event_with_timeout<F>(
    codex: &CodexThread,
    mut predicate: F,
    wait_time: tokio::time::Duration,
) -> codex_protocol::protocol::EventMsg
```
- 带自定义超时的事件等待
- 内部使用 `tokio::time::timeout`
- 最小超时 10 秒以容纳异步启动工作

### 9. 环境变量访问

```rust
pub fn sandbox_env_var() -> &'static str {
    codex_core::spawn::CODEX_SANDBOX_ENV_VAR
}

pub fn sandbox_network_env_var() -> &'static str {
    codex_core::spawn::CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR
}
```
- 提供沙箱相关环境变量的访问
- 用于条件跳过宏

### 10. Shell 命令格式化

```rust
pub fn format_with_current_shell(command: &str) -> Vec<String> {
    codex_core::shell::default_user_shell()
        .derive_exec_args(command, /*use_login_shell*/ true)
}

pub fn format_with_current_shell_display(command: &str) -> String {
    let args = format_with_current_shell(command);
    shlex::try_join(args.iter().map(String::as_str))
        .expect("serialize current shell command")
}
```
- 将命令格式化为当前 shell 的执行参数
- 支持登录 shell 和非登录 shell 模式
- 使用 `shlex` 正确序列化参数

### 11. 测试二进制文件定位

```rust
pub fn stdio_server_bin() -> Result<String, CargoBinError> {
    codex_utils_cargo_bin::cargo_bin("test_stdio_server")
        .map(|p| p.to_string_lossy().to_string())
}
```
- 使用 `codex_utils_cargo_bin` 定位测试二进制文件
- 支持 Bazel 和 Cargo 两种构建系统

### 12. 文件系统等待工具 (fs_wait)

#### wait_for_path_exists
```rust
pub async fn wait_for_path_exists(
    path: impl Into<PathBuf>,
    timeout: Duration,
) -> Result<PathBuf>
```
- 异步等待路径存在
- 使用 `notify` crate 监听文件系统事件
- 超时返回错误

#### wait_for_matching_file
```rust
pub async fn wait_for_matching_file(
    root: impl Into<PathBuf>,
    timeout: Duration,
    predicate: impl FnMut(&Path) -> bool + Send + 'static,
) -> Result<PathBuf>
```
- 等待匹配谓词的文件出现
- 使用 `walkdir` 遍历目录

### 13. 条件跳过宏

#### skip_if_sandbox!
```rust
#[macro_export]
macro_rules! skip_if_sandbox {
    () => {{
        if ::std::env::var($crate::sandbox_env_var())
            == ::core::result::Result::Ok("seatbelt".to_string())
        {
            eprintln!("{} is set to 'seatbelt', skipping test.", $crate::sandbox_env_var());
            return;
        }
    }};
    // 支持返回值变体
}
```
- 在 Seatbelt 沙箱中跳过测试
- 用于无法在被沙箱化的环境中运行的测试

#### skip_if_no_network!
```rust
#[macro_export]
macro_rules! skip_if_no_network {
    () => {{
        if ::std::env::var($crate::sandbox_network_env_var()).is_ok() {
            println!("Skipping test because it cannot execute when network is disabled...");
            return;
        }
    }};
}
```
- 在网络被禁用时跳过测试
- 检查 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量

#### codex_linux_sandbox_exe_or_skip!
```rust
#[macro_export]
macro_rules! codex_linux_sandbox_exe_or_skip {
    () => {{
        #[cfg(target_os = "linux")]
        {
            match codex_utils_cargo_bin::cargo_bin("codex-linux-sandbox") {
                Ok(path) => Some(path),
                Err(err) => {
                    eprintln!("codex-linux-sandbox binary not available, skipping test: {err}");
                    return;
                }
            }
        }
        #[cfg(not(target_os = "linux"))]
        {
            None
        }
    }};
}
```
- 尝试获取 Linux 沙箱二进制文件路径
- 如果不可用则跳过测试
- 非 Linux 平台返回 `None`

#### skip_if_windows!
```rust
#[macro_export]
macro_rules! skip_if_windows {
    ($return_value:expr $(,)?) => {{
        if cfg!(target_os = "windows") {
            println!("Skipping test because it cannot execute on Windows.");
            return $return_value;
        }
    }};
}
```
- 在 Windows 平台上跳过测试
- 支持指定返回值

---

## 具体技术实现

### 初始化顺序
```
1. enable_deterministic_unified_exec_process_ids_for_tests()
   └── 设置线程管理器测试模式
   └── 设置确定性进程 ID

2. configure_insta_workspace_root_for_snapshot_tests()
   └── 检测 repo_root
   └── 设置 INSTA_WORKSPACE_ROOT 环境变量
```

### 文件系统监控实现
```rust
fn wait_for_path_exists_blocking(path: PathBuf, timeout: Duration) -> Result<PathBuf> {
    if path.exists() { return Ok(path); }
    
    let watch_root = nearest_existing_ancestor(&path);
    let (tx, rx) = mpsc::channel();
    let mut watcher = notify::recommended_watcher(move |res| {
        let _ = tx.send(res);
    })?;
    watcher.watch(&watch_root, RecursiveMode::Recursive)?;
    
    // 循环等待文件出现或超时
}
```
- 使用 `notify` crate 进行跨平台文件系统监控
- 使用 `mpsc` 通道接收事件
- 使用 `walkdir` 进行目录遍历

---

## 关键代码路径与文件引用

### 模块依赖图
```
lib.rs
    ├── apps_test_server.rs      → wiremock, serde_json
    ├── context_snapshot.rs      → regex_lite, serde_json
    ├── process.rs               → tokio
    ├── responses.rs             → wiremock, tokio-tungstenite
    ├── streaming_sse.rs         → tokio
    ├── test_codex.rs            → codex_core, tempfile
    ├── test_codex_exec.rs       → assert_cmd
    ├── tracing.rs               → opentelemetry
    └── zsh_fork.rs              → codex_core::config
```

### 外部 crate 使用
| Crate | 用途 |
|-------|------|
| `ctor` | 全局初始化 |
| `tempfile` | 临时目录 |
| `tokio` | 异步运行时 |
| `notify` | 文件系统监控 |
| `walkdir` | 目录遍历 |
| `regex_lite` | 正则表达式 |
| `shlex` | Shell 命令解析 |

---

## 依赖与外部交互

### 与 codex_core 的交互
```rust
use codex_core::test_support::set_thread_manager_test_mode;
use codex_core::shell::default_user_shell;
use codex_core::spawn::{CODEX_SANDBOX_ENV_VAR, CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR};
```
- 使用 `codex_core::test_support` 模块的测试专用 API
- 访问内部环境变量常量

### 与 codex_protocol 的交互
```rust
use codex_protocol::protocol::EventMsg;
```
- 使用协议定义的事件类型

---

## 风险、边界与改进建议

### 潜在风险

1. **unsafe 代码使用**
   ```rust
   unsafe {
       std::env::set_var("INSTA_WORKSPACE_ROOT", workspace_root);
   }
   ```
   - 在 `#[ctor]` 中使用 `unsafe` 设置环境变量
   - 风险较低，因为这是在测试启动时单线程执行

2. **硬编码路径**
   ```rust
   test_absolute_path_with_windows("/tmp", Some(r"C:\Users\codex\AppData\Local\Temp"))
   ```
   - Windows 路径假设用户名为 "codex"
   - 在实际环境中可能不存在

3. **宏的复杂性**
   - 条件跳过宏使用复杂的条件编译
   - 维护成本较高

### 边界条件

1. **超时处理**
   - `wait_for_event_with_timeout` 有最小 10 秒限制
   - 短超时请求会被延长

2. **平台差异**
   - Linux 沙箱仅在 Linux 上可用
   - Windows 路径处理可能不完整

3. **资源清理**
   - `fs_wait` 函数创建的文件监控器需要正确清理
   - 在测试 panic 时可能泄漏资源

### 改进建议

1. **配置化临时路径**
   ```rust
   pub fn test_tmp_path() -> AbsolutePathBuf {
       let windows_tmp = std::env::var("TEMP")
           .unwrap_or_else(|_| r"C:\Users\codex\AppData\Local\Temp".to_string());
       test_absolute_path_with_windows("/tmp", Some(&windows_tmp))
   }
   ```

2. **异步清理**
   ```rust
   pub struct FileWatcherGuard {
       watcher: notify::RecommendedWatcher,
   }
   
   impl Drop for FileWatcherGuard {
       fn drop(&mut self) {
           // 确保资源清理
       }
   }
   ```

3. **宏简化**
   使用过程宏简化条件跳过：
   ```rust
   #[skip_if_sandbox]
   #[tokio::test]
   async fn my_test() { }
   ```

4. **更好的错误信息**
   ```rust
   pub fn assert_regex_match<'s>(pattern: &str, actual: &'s str) -> regex_lite::Captures<'s> {
       // 添加更多上下文信息到 panic 消息
   }
   ```

---

## 相关文件
- `codex-rs/core/tests/common/*.rs` - 各子模块实现
- `codex-rs/core/src/test_support.rs` - codex_core 的测试支持 API
- `codex-rs/utils/cargo-bin/src/lib.rs` - cargo_bin 实现
- `codex-rs/core/tests/all.rs` - 集成测试入口
