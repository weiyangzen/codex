# executable_name.rs 研究文档

## 场景与职责

`executable_name.rs` 是 `codex-execpolicy` crate 的**平台兼容工具模块**，负责处理可执行文件名称的跨平台差异。主要解决以下问题：

1. **Windows 后缀处理**：Windows 可执行文件有多种后缀（`.exe`, `.cmd`, `.bat`, `.com`），需要统一处理
2. **大小写不敏感**：Windows 文件系统默认大小写不敏感，需要规范化比较
3. **路径提取**：从完整路径中提取可执行文件名作为查找键

该模块虽然代码量小，但对于确保策略在 Windows 和 Unix 系统上行为一致至关重要。

## 功能点目的

### 1. `executable_lookup_key` - 生成可执行文件名查找键

将可执行文件名转换为统一的查找键，用于策略规则匹配：

- **Windows**：
  - 转换为小写
  - 移除已知可执行后缀（`.exe`, `.cmd`, `.bat`, `.com`）
- **Unix**：保持原样

### 2. `executable_path_lookup_key` - 从路径生成查找键

从完整路径中提取文件名并生成查找键：

```rust
executable_path_lookup_key(Path::new("/usr/bin/git"))  // → Some("git")
executable_path_lookup_key(Path::new("/usr/bin/git.exe"))  // Windows → Some("git")
```

## 具体技术实现

### Windows 后缀处理

```rust
#[cfg(windows)]
const WINDOWS_EXECUTABLE_SUFFIXES: [&str; 4] = [".exe", ".cmd", ".bat", ".com"];

pub(crate) fn executable_lookup_key(raw: &str) -> String {
    #[cfg(windows)]
    {
        let raw = raw.to_ascii_lowercase();
        for suffix in WINDOWS_EXECUTABLE_SUFFIXES {
            if raw.ends_with(suffix) {
                let stripped_len = raw.len() - suffix.len();
                return raw[..stripped_len].to_string();
            }
        }
        raw
    }

    #[cfg(not(windows))]
    {
        raw.to_string()
    }
}
```

实现细节：
- 使用 `to_ascii_lowercase()` 而非 `to_lowercase()`，只处理 ASCII 字符，性能更好且行为确定
- 后缀检查顺序重要，但这里后缀互不重叠，顺序不影响结果
- 使用字符串切片而非正则表达式，性能更优

### 路径处理

```rust
pub(crate) fn executable_path_lookup_key(path: &Path) -> Option<String> {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(executable_lookup_key)
}
```

使用标准库 `Path::file_name()` 提取文件名，处理：
- 路径以分隔符结尾的情况（返回 `None`）
- 非 UTF-8 文件名（返回 `None`）

## 依赖与外部交互

### 外部依赖

| 项目 | 用途 |
|------|------|
| `std::path::Path` | 路径处理 |

无第三方依赖，仅使用标准库。

### 被依赖方

| 模块 | 用途 |
|------|------|
| `parser.rs` | 解析 `host_executable` 时验证路径 |
| `policy.rs` | 主机可执行文件规则匹配 |

## 风险、边界与改进建议

### 风险点

1. **Windows 后缀列表不完整**：只包含常见后缀，可能遗漏 `.ps1`、`.vbs` 等脚本后缀
2. **大小写处理局限**：仅处理 ASCII，非 ASCII 字符在 Windows 上可能有问题
3. **非 UTF-8 路径**：直接返回 `None`，可能导致策略匹配失败

### 边界条件

1. **空字符串**：返回空字符串
2. **纯后缀**：`.exe` → 空字符串
3. **无后缀**：保持不变
4. **多个后缀**：只移除最后一个匹配的后缀，`script.exe.bat` → `script.exe`
5. **大小写混合**：`Git.EXE` → `git`

### 改进建议

1. **扩展后缀列表**：
   ```rust
   const WINDOWS_EXECUTABLE_SUFFIXES: [&str; 7] = [
       ".exe", ".cmd", ".bat", ".com", ".ps1", ".vbs", ".js"
   ];
   ```

2. **非 UTF-8 处理**：考虑使用 `std::os::windows::ffi::OsStrExt` 处理非 UTF-8 路径

3. **配置化**：允许用户配置额外的可执行后缀

4. **测试覆盖**：添加 Windows 特定的单元测试

5. **文档说明**：在 README 中说明 Windows 和 Unix 的行为差异

### 代码在策略匹配中的应用

来自 `policy.rs` 的使用示例：

```rust
fn match_host_executable_rules(&self, cmd: &[String]) -> Vec<RuleMatch> {
    let Ok(program) = AbsolutePathBuf::try_from(first.clone()) else {
        return Vec::new();
    };
    let Some(basename) = executable_path_lookup_key(program.as_path()) else {
        return Vec::new();
    };
    let Some(rules) = self.rules_by_program.get_vec(&basename) else {
        return Vec::new();
    };
    // ...
}
```

这个流程展示了如何使用 `executable_path_lookup_key` 实现从绝对路径到 basename 规则的回退匹配。
