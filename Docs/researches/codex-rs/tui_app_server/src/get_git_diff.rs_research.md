# get_git_diff.rs 研究文档

## 场景与职责

`get_git_diff.rs` 是 Codex TUI 应用服务器中用于计算当前工作目录 Git 变更的工具模块。它实现了与 TypeScript 版本 `codex-cli` 相同的行为，为 AI 助手提供代码变更上下文。

该模块的核心职责包括：
1. **Git 仓库检测**：判断当前目录是否在 Git 仓库中
2. **跟踪文件变更**：获取已跟踪文件的 `git diff` 输出
3. **未跟踪文件处理**：将未跟踪文件模拟为 `/dev/null` 的 diff
4. **跨平台支持**：兼容 Windows (NUL) 和 Unix (/dev/null) 系统

## 功能点目的

### 1. get_git_diff - 主入口函数

```rust
pub(crate) async fn get_git_diff() -> io::Result<(bool, String)>
```

- **返回值**：
  - `bool`：是否在 Git 仓库中
  - `String`：合并的 diff 输出（跟踪文件 + 未跟踪文件）

- **行为**：
  - 不在 Git 仓库中 → 返回 `(false, "")`
  - 在 Git 仓库中 → 返回 `(true, diff_output)`

### 2. 跟踪文件 Diff

使用 `git diff --color` 获取：
- 已修改但未暂存的变更
- 彩色输出（保留终端颜色代码）

### 3. 未跟踪文件 Diff

使用 `git ls-files --others --exclude-standard` 列出未跟踪文件，然后：
- 对每个文件执行 `git diff --color --no-index -- /dev/null <file>`
- 并行处理（使用 `tokio::task::JoinSet`）
- 将结果追加到主 diff

### 4. 跨平台空设备处理

```rust
let null_device: &Path = if cfg!(windows) {
    Path::new("NUL")
} else {
    Path::new("/dev/null")
};
```

## 具体技术实现

### 关键流程

#### 1. 完整调用流程

```
get_git_diff()
    ↓
inside_git_repo() ──→ 不在仓库？返回 (false, "")
    ↓
并行执行：
    ├── run_git_capture_diff(["diff", "--color"]) ──→ tracked_diff
    └── run_git_capture_stdout(["ls-files", "--others", "--exclude-standard"]) ──→ untracked_list
    ↓
对 untracked_list 中的每个文件：
    └── JoinSet::spawn(async {
        run_git_capture_diff(["diff", "--color", "--no-index", "--", "/dev/null", file])
    })
    ↓
收集所有未跟踪文件 diff 结果
    ↓
返回 (true, format!("{tracked_diff}{untracked_diff}"))
```

#### 2. Git 命令执行细节

**标准输出捕获**（`run_git_capture_stdout`）：
```rust
async fn run_git_capture_stdout(args: &[&str]) -> io::Result<String> {
    let output = Command::new("git")
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())  // 忽略错误输出
        .output()
        .await?;
    
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        Err(io::Error::other("git failed"))
    }
}
```

**Diff 捕获**（`run_git_capture_diff`）：
```rust
async fn run_git_capture_diff(args: &[&str]) -> io::Result<String> {
    let output = Command::new("git")
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .await?;
    
    // 关键：Git diff 在有差异时返回 exit code 1
    if output.status.success() || output.status.code() == Some(1) {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        Err(io::Error::other("git failed"))
    }
}
```

#### 3. 并行处理未跟踪文件

```rust
let mut join_set: tokio::task::JoinSet<io::Result<String>> = tokio::task::JoinSet::new();

for file in untracked_output.split('\n').map(str::trim).filter(|s| !s.is_empty()) {
    let null_path = null_path.clone();
    let file = file.to_string();
    join_set.spawn(async move {
        let args = ["diff", "--color", "--no-index", "--", &null_path, &file];
        run_git_capture_diff(&args).await
    });
}

while let Some(res) = join_set.join_next().await {
    match res {
        Ok(Ok(diff)) => untracked_diff.push_str(&diff),
        Ok(Err(err)) if err.kind() == io::ErrorKind::NotFound => {}
        Ok(Err(err)) => return Err(err),
        Err(_) => {}
    }
}
```

### 数据结构

| 函数/类型 | 签名 | 说明 |
|-----------|------|------|
| `get_git_diff` | `async fn() -> io::Result<(bool, String)>` | 主入口 |
| `run_git_capture_stdout` | `async fn(&[&str]) -> io::Result<String>` | 执行 Git 命令并捕获 stdout |
| `run_git_capture_diff` | `async fn(&[&str]) -> io::Result<String>` | 执行 diff 命令（接受 exit code 1） |
| `inside_git_repo` | `async fn() -> io::Result<bool>` | 检测是否在 Git 仓库中 |

### Git 命令详解

| 命令 | 用途 |
|------|------|
| `git rev-parse --is-inside-work-tree` | 检测是否在 Git 工作区 |
| `git diff --color` | 获取跟踪文件的彩色 diff |
| `git ls-files --others --exclude-standard` | 列出未跟踪文件（排除 .gitignore 中的文件） |
| `git diff --color --no-index -- /dev/null <file>` | 将文件与空设备比较，生成新增文件 diff |

## 关键代码路径与文件引用

### 本文件关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 17-62 | `get_git_diff` | 主函数，编排整个 diff 流程 |
| 32-36 | 空设备选择 | Windows/Unix 跨平台处理 |
| 39-59 | 未跟踪文件并行处理 | JoinSet 并发执行 |
| 66-82 | `run_git_capture_stdout` | 标准 Git 命令执行 |
| 86-102 | `run_git_capture_diff` | Diff 命令执行（处理 exit code 1） |
| 105-119 | `inside_git_repo` | Git 仓库检测 |

### 调用方（上游）

1. **`chatwidget.rs`** - 主要调用者
   ```rust
   // 处理 /diff 命令时调用
   let (in_repo, diff) = get_git_diff().await?;
   ```

2. **`lib.rs`** - 模块导出
   ```rust
   mod get_git_diff;
   ```

### 被调用方（下游）

- **系统命令**：`git` 可执行文件
- **Tokio 运行时**：`tokio::process::Command`, `tokio::task::JoinSet`

## 依赖与外部交互

### 外部 crate 依赖

```rust
use std::io;
use std::path::Path;
use std::process::Stdio;
use tokio::process::Command;  // 异步进程执行
use tokio::task::JoinSet;     // 并发任务管理
```

### 系统依赖

- **Git 可执行文件**：需要在 PATH 中可用
- **Shell 环境**：支持标准输入输出重定向

### 数据流

```
用户输入 /diff 命令
    ↓
chatwidget.rs
    ↓
get_git_diff()
    ↓
Git 工作区
    ├── git diff --color → 跟踪文件变更
    ├── git ls-files --others → 未跟踪文件列表
    └── git diff --no-index /dev/null <file> → 每个未跟踪文件的 diff
    ↓
合并结果
    ↓
返回给 AI 作为上下文
```

## 风险、边界与改进建议

### 潜在风险

1. **Git 未安装**
   - `inside_git_repo` 中处理了 `NotFound` 错误
   - 但其他函数可能 panic 或返回错误
   - 建议：统一处理 Git 未安装的情况

2. **大型仓库性能**
   - 未跟踪文件过多时，`JoinSet` 可能创建大量任务
   - 建议：限制并发度，使用 `Semaphore`

3. **二进制文件处理**
   - `git diff` 对二进制文件输出特殊格式
   - 当前实现直接追加，可能导致 AI 困惑
   - 建议：过滤或标记二进制文件

4. **符号链接**
   - `git diff --no-index` 对符号链接的处理可能不符合预期
   - 建议：测试并处理符号链接场景

5. **路径注入风险**
   ```rust
   let args = ["diff", "--color", "--no-index", "--", &null_path, &file];
   ```
   - 如果文件名包含特殊字符（如 `--` 开头），可能被解释为选项
   - 建议：使用 `--` 分隔选项和路径（已实现）

### 边界情况

1. **空仓库**
   - 新创建的 Git 仓库（无提交）
   - `git diff` 可能返回空或错误
   - 当前：依赖 Git 的标准行为

2. **无变更**
   - 工作区干净时
   - `tracked_diff` 为空字符串
   - `untracked_output` 为空
   - 返回 `(true, "")`

3. **子目录执行**
   - 在 Git 仓库子目录中执行
   - `inside_git_repo` 正确检测
   - 路径解析相对于工作区根

4. **Git 工作区外的子目录**
   - 返回 `(false, "")`，不报错

5. **未跟踪文件过多**
   - 可能触发系统文件描述符限制
   - 建议：添加批量处理逻辑

### 改进建议

1. **并发控制**
   ```rust
   use tokio::sync::Semaphore;
   
   let semaphore = Arc::new(Semaphore::new(10)); // 最多 10 个并发
   
   for file in files {
       let permit = semaphore.clone().acquire_owned().await?;
       join_set.spawn(async move {
           let _permit = permit; // 持有许可直到任务完成
           // ... diff 逻辑
       });
   }
   ```

2. **二进制文件过滤**
   ```rust
   // 在获取未跟踪文件列表后
   let is_binary = check_if_binary(&file).await?;
   if is_binary {
       untracked_diff.push_str(&format!("Binary file: {}\n", file));
       continue;
   }
   ```

3. **Diff 大小限制**
   ```rust
   const MAX_DIFF_SIZE: usize = 1024 * 1024; // 1MB
   
   if untracked_diff.len() + diff.len() > MAX_DIFF_SIZE {
       return Err(io::Error::other("Diff too large"));
   }
   ```

4. **缓存机制**
   ```rust
   use std::sync::Mutex;
   use std::time::Instant;
   
   static CACHE: Mutex<Option<(Instant, String)>> = Mutex::new(None);
   const CACHE_TTL: Duration = Duration::from_secs(5);
   
   // 检查缓存是否有效
   if let Some((timestamp, diff)) = CACHE.lock().unwrap().as_ref() {
       if timestamp.elapsed() < CACHE_TTL {
           return Ok((true, diff.clone()));
       }
   }
   ```

5. **错误信息改进**
   ```rust
   // 当前
   Err(io::Error::other(format!("git {:?} failed with status {}", args, output.status)))
   
   // 建议：包含 stderr 信息
   let stderr = String::from_utf8_lossy(&output.stderr);
   Err(io::Error::other(format!(
       "git {:?} failed: {} (stderr: {})",
       args, output.status, stderr
   )))
   ```

6. **配置支持**
   ```rust
   pub struct DiffOptions {
       pub include_untracked: bool,
       pub max_file_size: Option<usize>,
       pub exclude_patterns: Vec<String>,
   }
   
   pub(crate) async fn get_git_diff_with_options(
       options: DiffOptions
   ) -> io::Result<(bool, String)>
   ```

### 测试建议

1. **单元测试**
   ```rust
   #[tokio::test]
   async fn test_inside_git_repo() {
       // 在临时 Git 仓库中测试
   }
   
   #[tokio::test]
   async fn test_outside_git_repo() {
       // 在非 Git 目录中测试
   }
   ```

2. **集成测试**
   - 测试大型仓库性能
   - 测试特殊文件名（空格、换行、Unicode）
   - 测试二进制文件处理

3. **Mock 测试**
   ```rust
   // 使用 mock 替代真实 Git 命令
   #[cfg(test)]
   mod mock {
       pub async fn mock_git_diff() -> io::Result<String> {
           Ok("mock diff output".to_string())
       }
   }
   ```

### 相关文件

| 文件路径 | 关系 | 说明 |
|----------|------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | 调用方 | 使用 diff 作为 AI 上下文 |
| `codex-rs/tui_app_server/src/lib.rs` | 模块声明 | 声明 get_git_diff 模块 |
| `codex-cli/src/utils/git.ts` | 参考实现 | TypeScript 版本的参考 |
| `codex-rs/core/src/git_info.rs` | 相关功能 | 其他 Git 相关工具 |

### 性能考虑

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| 1000+ 未跟踪文件 | 创建 1000+ 并发任务 | 限制并发度为 CPU 核心数 |
| 大文件 diff | 完整读取 | 添加文件大小检查 |
| 频繁调用 | 每次都执行 Git 命令 | 添加短时间缓存 |
| 网络文件系统 | 可能较慢 | 添加超时机制 |
