# logging.rs 深度研究文档

## 场景与职责

`logging.rs` 是 Windows Sandbox 模块中的**日志管理器**，提供统一的日志记录功能，用于调试沙箱操作、排查问题和审计。该模块设计简洁，专注于沙箱特定的日志需求。

### 核心职责
1. **统一日志格式**：提供带时间戳和进程标识的标准化日志格式
2. **文件日志记录**：将日志写入 `codex_home/.sandbox/sandbox.log`
3. **调试日志支持**：通过环境变量控制详细调试输出
4. **命令预览截断**：避免日志中出现过长的命令行

## 功能点目的

### 1. 日志文件配置
```rust
const LOG_COMMAND_PREVIEW_LIMIT: usize = 200;
pub const LOG_FILE_NAME: &str = "sandbox.log";
```
- `LOG_COMMAND_PREVIEW_LIMIT`：命令行预览的最大字符数
- `LOG_FILE_NAME`：日志文件名

### 2. 进程标识 (`exe_label`)
```rust
fn exe_label() -> &'static str
```
- 使用 `OnceLock` 实现懒加载的单例
- 返回当前可执行文件的文件名（如 `codex-cli.exe`）
- 失败时返回 `"proc"`

### 3. 命令预览截断 (`preview`)
```rust
fn preview(command: &[String]) -> String
```
- 将命令数组连接为字符串
- 如果超过 `LOG_COMMAND_PREVIEW_LIMIT`，截断并保留有效 UTF-8 边界
- 使用 `codex_utils_string::take_bytes_at_char_boundary` 确保不截断多字节字符

### 4. 核心日志函数

#### `log_note` - 通用日志记录
```rust
pub fn log_note(msg: &str, base_dir: Option<&Path>)
```
- **格式**：`[YYYY-MM-DD HH:MM:SS.mmm {exe_label}] {msg}`
- **用途**：记录一般性事件和状态
- **示例输出**：
  ```
  [2024-01-15 09:30:45.123 codex-cli] START: git status
  ```

#### `log_start` - 命令开始
```rust
pub fn log_start(command: &[String], base_dir: Option<&Path>)
```
- 记录命令执行开始
- 格式：`START: {previewed_command}`

#### `log_success` - 命令成功
```rust
pub fn log_success(command: &[String], base_dir: Option<&Path>)
```
- 记录命令成功完成
- 格式：`SUCCESS: {previewed_command}`

#### `log_failure` - 命令失败
```rust
pub fn log_failure(command: &[String], detail: &str, base_dir: Option<&Path>)
```
- 记录命令执行失败
- 格式：`FAILURE: {previewed_command} ({detail})`

#### `debug_log` - 调试日志
```rust
pub fn debug_log(msg: &str, base_dir: Option<&Path>)
```
- **条件执行**：仅在 `SBX_DEBUG=1` 环境变量设置时输出
- **双重输出**：同时写入日志文件和标准错误（stderr）
- **格式**：`DEBUG: {msg}`

### 5. 内部辅助函数

#### `log_file_path`
```rust
fn log_file_path(base_dir: &Path) -> Option<PathBuf>
```
- 检查 `base_dir` 是否为有效目录
- 返回完整日志文件路径

#### `append_line`
```rust
fn append_line(line: &str, base_dir: Option<&Path>)
```
- 使用 `OpenOptions::new().create(true).append(true)` 打开文件
- 以追加模式写入单行日志
- 错误被静默忽略（最佳努力）

## 具体技术实现

### 时间戳生成
```rust
let ts = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
```
- 使用本地时区
- 格式：年-月-日 时:分:秒.毫秒
- 3位毫秒精度

### 文件操作
```rust
if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
    let _ = writeln!(f, "{}", line);
}
```
- 原子追加写入
- 错误被静默处理（使用 `let _ =`）
- 自动创建日志文件（如果不存在）

### 调试日志条件
```rust
if std::env::var("SBX_DEBUG").ok().as_deref() == Some("1") {
    append_line(&format!("DEBUG: {msg}"), base_dir);
    eprintln!("{msg}");
}
```
- 环境变量精确匹配 `"1"`
- 同时输出到文件和控制台（stderr）

## 关键代码路径与文件引用

### 内部依赖
| 函数 | 来源 | 用途 |
|------|------|------|
| `take_bytes_at_char_boundary` | `codex_utils_string` | 安全截断 UTF-8 字符串 |

### 被调用方
| 调用方 | 函数 | 场景 |
|--------|------|------|
| `lib.rs` (windows_impl) | `log_start`, `log_success`, `log_failure` | 命令执行生命周期 |
| `setup_orchestrator.rs` | `log_note` | 设置流程记录 |
| `elevated_impl.rs` | `log_note`, `log_start`, `log_success`, `log_failure` | 提权执行记录 |
| `identity.rs` | `debug_log` | 调试信息 |
| `hide_users.rs` | `log_note` | 用户隐藏操作 |
| `helper_materialization.rs` | `log_note` | 辅助程序复制 |

### 导出接口
```rust
#[cfg(target_os = "windows")]
pub use logging::log_note;
#[cfg(target_os = "windows")]
pub use logging::LOG_FILE_NAME;
```

## 依赖与外部交互

### 外部 Crate
- `chrono`：日期时间处理
- `std::fs::OpenOptions`：文件操作
- `std::io::Write`：写入 trait
- `std::sync::OnceLock`：线程安全单例
- `codex_utils_string`：字符串工具

### 环境变量
- `SBX_DEBUG`：启用调试日志（值为 `"1"` 时启用）

### 文件系统交互
- 日志文件路径：`{base_dir}/sandbox.log`
- 追加模式写入
- 自动创建目录和文件

## 风险、边界与改进建议

### 已知风险

1. **日志文件增长**
   - 问题：日志文件可能无限增长
   - 缓解：当前无内置轮转机制
   - 建议：考虑添加日志轮转或大小限制

2. **并发写入**
   - 问题：多进程同时写入同一日志文件
   - 缓解：操作系统级别的文件锁通常可保证追加写入的原子性
   - 风险：极端情况下可能出现交错写入

3. **磁盘空间**
   - 问题：磁盘满时写入失败
   - 缓解：错误被静默处理
   - 注意：重要日志可能丢失

### 边界条件

1. **`base_dir` 为 `None`**：不记录任何日志
2. **`base_dir` 不是目录**：不记录任何日志
3. **文件打开失败**：错误被静默忽略
4. **写入失败**：错误被静默忽略
5. **空命令数组**：`preview` 返回空字符串
6. **多字节字符边界**：`take_bytes_at_char_boundary` 确保安全截断

### 改进建议

1. **日志级别**
   - 当前：仅区分普通日志和调试日志
   - 建议：添加 INFO/WARN/ERROR 级别

2. **日志轮转**
   - 当前：单文件无限追加
   - 建议：按大小或时间轮转，保留历史日志

3. **结构化日志**
   - 当前：纯文本格式
   - 建议：支持 JSON 格式，便于机器解析

4. **异步写入**
   - 当前：同步文件写入
   - 建议：考虑异步写入避免阻塞

5. **配置选项**
   - 当前：仅通过环境变量控制调试日志
   - 建议：支持配置文件设置日志级别、路径等

6. **日志过滤**
   - 建议：支持按模块或功能过滤日志

### 测试覆盖

模块包含以下单元测试：
- `preview_does_not_panic_on_utf8_boundary`：验证 UTF-8 安全截断

### 性能考虑

1. **时间戳生成**
   - 每次日志调用都获取当前时间
   - 使用 `chrono::Local::now()` 有一定开销

2. **文件操作**
   - 每次日志调用都打开文件
   - 可考虑保持文件句柄打开以提高性能

3. **字符串分配**
   - 日志消息涉及多次字符串分配
   - 在高频场景下可能影响性能

### 使用示例

```rust
// 记录命令开始
log_start(&["git", "status"], Some(&sandbox_dir));

// 记录调试信息（仅在 SBX_DEBUG=1 时输出）
debug_log("Loading capability SIDs", Some(&sandbox_dir));

// 记录失败
log_failure(&["git", "push"], "exit code 1", Some(&sandbox_dir));
```
