# execv_checker.rs 研究文档

## 场景与职责

`execv_checker.rs` 是执行策略引擎的最终安全检查层，负责：

1. **文件路径验证**：验证可读/可写文件路径是否在允许的目录范围内
2. **路径规范化**：将相对路径转换为绝对路径
3. **可执行文件验证**：检查系统路径中的可执行文件是否存在且可执行
4. **安全检查执行**：作为 `ExecvChecker` 结构体的核心实现

该模块是策略验证的最后防线，确保即使命令通过了语法和语义检查，也不会访问未授权的文件系统区域。

## 功能点目的

### 1. ExecvChecker 结构

```rust
pub struct ExecvChecker {
    execv_policy: Policy,  // 策略规则
}
```

提供两个主要方法：
- `r#match()`：语法和语义匹配（委托给 Policy）
- `check()`：文件系统安全检查

### 2. 文件路径验证

**验证流程**：
1. 遍历 `ValidExec` 中的所有参数（args）和选项（opts）
2. 根据 `ArgType` 分类处理：
   - `ReadableFile`：验证路径在可读目录列表中
   - `WriteableFile`：验证路径在可写目录列表中
   - 其他类型：跳过

**验证逻辑**：
```rust
check_file_in_folders!(file, folders, ErrorType);
// 展开为：
if !folders.iter().any(|folder| file.starts_with(folder)) {
    return Err(ErrorType { file, folders });
}
```

### 3. 路径规范化

**ensure_absolute_path()**：
```rust
fn ensure_absolute_path(path: &str, cwd: &Option<OsString>) -> Result<PathBuf>
```

处理逻辑：
- 相对路径：基于 CWD 转换为绝对路径
- 绝对路径：直接规范化
- 无 CWD 的相对路径：返回错误

使用 `path_absolutize` crate 处理路径解析。

### 4. 可执行文件检查

**is_executable_file()**：
- Unix：检查文件存在且有执行权限（mode & 0o111 != 0）
- Windows：仅检查文件存在（TODO：检查 PATHEXT）

## 具体技术实现

### 宏定义

**check_file_in_folders!**：
```rust
macro_rules! check_file_in_folders {
    ($file:expr, $folders:expr, $error:ident) => {
        if !$folders.iter().any(|folder| $file.starts_with(folder)) {
            return Err($error {
                file: $file.clone(),
                folders: $folders.to_vec(),
            });
        }
    };
}
```

用于减少重复代码，但增加了宏的复杂性。

### 核心方法

**ExecvChecker::check()**：
```rust
pub fn check(
    &self,
    valid_exec: ValidExec,
    cwd: &Option<OsString>,
    readable_folders: &[PathBuf],
    writeable_folders: &[PathBuf],
) -> Result<String>
```

算法：
1. 遍历参数和选项（使用 `chain` 组合）
2. 根据 ArgType 分支处理
3. 规范化路径
4. 检查路径是否在允许范围内
5. 查找第一个存在的可执行系统路径
6. 返回推荐的可执行文件路径

**路径处理**：
```rust
let file = PathBuf::from(path);
let result = if file.is_relative() {
    match cwd {
        Some(cwd) => file.absolutize_from(cwd),
        None => return Err(CannotCheckRelativePath { file }),
    }
} else {
    file.absolutize()
};
```

**Unix 可执行检查**：
```rust
#[cfg(unix)]
{
    use std::os::unix::fs::PermissionsExt;
    let permissions = metadata.permissions();
    metadata.is_file() && (permissions.mode() & 0o111 != 0)
}
```

### 测试实现

**setup() 辅助函数**：
```rust
fn setup(fake_cp: &Path) -> ExecvChecker {
    let source = format!(r#"
define_program(
    program="cp",
    args=[ARG_RFILE, ARG_WFILE],
    system_path=[{fake_cp:?}]
)
"#);
    let parser = PolicyParser::new("#test", &source);
    let policy = parser.parse().unwrap();
    ExecvChecker::new(policy)
}
```

**测试用例**：
- 无可读/可写目录：失败
- 仅可读目录：写操作失败
- 两者都有：成功
- 父目录不在范围内：失败

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/execpolicy-legacy/src/execv_checker.rs`

### 依赖文件
- `codex-rs/execpolicy-legacy/src/policy.rs`：Policy 类型
- `codex-rs/execpolicy-legacy/src/valid_exec.rs`：ValidExec, MatchedArg
- `codex-rs/execpolicy-legacy/src/arg_type.rs`：ArgType
- `codex-rs/execpolicy-legacy/src/exec_call.rs`：ExecCall
- `codex-rs/execpolicy-legacy/src/error.rs`：Error
- `codex-rs/execpolicy-legacy/src/policy_parser.rs`：PolicyParser

### 被依赖文件
- 作为库的一部分被外部使用
- `main.rs` 可能使用（当前未直接使用 ExecvChecker）

### 调用流程

```
外部调用者
  └── ExecvChecker::new(policy)
      ├── r#match(&exec_call) -> MatchedExec
      │   └── policy.check(exec_call)
      └── check(valid_exec, cwd, readable, writeable) -> Result<String>
          ├── 遍历 args 和 opts
          │   ├── ArgType::ReadableFile -> ensure_absolute_path -> check_file_in_folders
          │   └── ArgType::WriteableFile -> ensure_absolute_path -> check_file_in_folders
          └── 查找可执行文件 -> 返回路径
```

## 依赖与外部交互

### 外部 crate
- `path_absolutize`：路径规范化
  - `Absolutize` trait
  - `absolutize()` 和 `absolutize_from()` 方法

### 标准库
- `std::path::{Path, PathBuf}`
- `std::ffi::OsString`
- `std::borrow::Cow`
- `std::os::unix::fs::PermissionsExt`（Unix 特定）

### 内部依赖
- `Policy`, `ValidExec`, `MatchedExec`
- `ArgType`, `ExecCall`
- `Error`, `Result`

## 风险、边界与改进建议

### 风险点

1. **路径遍历攻击**
   - 使用 `starts_with` 检查路径前缀
   - 但路径规范化后可能绕过检查
   ```rust
   // 潜在问题：
   // readable_folders = ["/home/user"]
   // path = "/home/user/../etc/passwd"
   // 规范化后："/etc/passwd"
   // 但规范化在检查之前，所以安全
   ```

2. **符号链接**
   - `absolutize` 可能解析符号链接
   - 如果符号链接指向允许目录外的文件，可能绕过检查
   - 建议：使用 `canonicalize` 并检查最终路径

3. **竞争条件**
   - 检查路径和执行命令之间有时间窗口
   - 路径可能被替换为指向其他位置的符号链接
   - TOCTOU（Time-of-check to time-of-use）漏洞

4. **Windows 支持不完整**
   ```rust
   #[cfg(windows)]
   {
       // TODO(mbolin): Check against PATHEXT environment variable.
       return metadata.is_file();
   }
   ```
   - 不检查执行权限
   - 不验证文件扩展名

5. **宏的复杂性**
   - `check_file_in_folders!` 宏增加了代码复杂性
   - 错误类型作为标识符传递，容易出错

### 边界情况

1. **空目录列表**
   ```rust
   // 如果 readable_folders 为空，任何 ReadableFile 都会失败
   check_file_in_folders!(file, &[], ReadablePathNotInReadableFolders)
   // -> Err(ReadablePathNotInReadableFolders { file, folders: [] })
   ```

2. **相对路径无 CWD**
   ```rust
   ensure_absolute_path("foo.txt", &None)
   // -> Err(CannotCheckRelativePath { file: "foo.txt" })
   ```

3. **路径规范化失败**
   ```rust
   // 权限不足、路径不存在等
   // -> Err(CannotCanonicalizePath { file, error })
   ```

4. **无可用系统路径**
   ```rust
   // 如果 system_path 中所有路径都不可执行
   // 返回原始程序名
   ```

### 改进建议

1. **符号链接安全**
   ```rust
   fn ensure_safe_path(path: &Path, allowed: &[PathBuf]) -> Result<PathBuf> {
       let canonical = path.canonicalize()?;
       // 检查 canonical 路径是否在允许范围内
       // 同时检查路径上的每个组件
   }
   ```

2. **移除宏**
   ```rust
   fn check_path_in_folders(
       file: &PathBuf,
       folders: &[PathBuf],
       make_error: impl Fn(PathBuf, Vec<PathBuf>) -> Error,
   ) -> Result<()> {
       if !folders.iter().any(|f| file.starts_with(f)) {
           return Err(make_error(file.clone(), folders.to_vec()));
       }
       Ok(())
   }
   ```

3. **异步安全检查**
   ```rust
   pub async fn check_async(
       &self,
       valid_exec: ValidExec,
       // ...
   ) -> Result<String>
   ```
   - 支持异步文件系统操作
   - 减少阻塞

4. **缓存可执行文件检查**
   ```rust
   pub struct ExecvChecker {
       execv_policy: Policy,
       executable_cache: Arc<Mutex<HashMap<String, bool>>>,
   }
   ```

5. **更详细的错误信息**
   ```rust
   ReadablePathNotInReadableFolders {
       file: PathBuf,
       folders: Vec<PathBuf>,
       attempted_normalized: PathBuf,  // 添加规范化后的路径
   }
   ```

6. **路径验证增强**
   ```rust
   // 检查路径是否包含 null 字节
   // 检查路径长度限制
   // 检查路径组件合法性
   ```

7. **测试改进**
   - 添加符号链接测试
   - 添加竞争条件测试
   - 添加 Windows 测试（如果可能）
   - 添加性能测试
