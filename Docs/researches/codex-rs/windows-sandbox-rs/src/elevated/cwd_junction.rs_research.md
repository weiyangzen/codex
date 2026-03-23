# cwd_junction.rs 研究文档

## 场景与职责

`cwd_junction.rs` 是 Windows 沙箱系统中用于**工作目录重定向**的辅助模块。当 Read ACL Helper（读取访问控制列表辅助程序）处于活动状态时，该模块创建一个**目录连接点（Directory Junction）**来绕过 ACL 限制，使沙箱用户能够访问实际工作目录。

### 核心场景

1. **ACL 限制绕过**：当父进程启用了 Read ACL Helper 时，直接访问某些目录可能被 ACL 阻止
2. **CWD 透明重定向**：通过 junction 将 `%USERPROFILE%\.codex\.sandbox\cwd\<hash>` 映射到实际工作目录
3. **沙箱用户透明性**：子进程看到的 CWD 是 junction 路径，但操作实际作用于目标目录

### 与 command_runner_win.rs 的关系

该模块被 `command_runner_win.rs` 中的 `effective_cwd` 函数调用：

```rust
fn effective_cwd(req_cwd: &Path, log_dir: Option<&Path>) -> PathBuf {
    let use_junction = read_acl_mutex::read_acl_mutex_exists()?;
    if use_junction {
        cwd_junction::create_cwd_junction(req_cwd, log_dir)
            .unwrap_or_else(|| req_cwd.to_path_buf())
    } else {
        req_cwd.to_path_buf()
    }
}
```

## 功能点目的

### 1. Junction 路径生成
- **目的**：为每个唯一的工作目录生成确定性的 junction 路径
- **机制**：使用 `DefaultHasher` 对路径字符串进行哈希，生成十六进制名称
- **存储位置**：`%USERPROFILE%\.codex\.sandbox\cwd\<hash>`

### 2. Junction 生命周期管理
- **创建**：使用 Windows `mklink /J` 命令创建目录连接点
- **复用**：如果 junction 已存在且是有效的重解析点（reparse point），直接复用
- **重建**：如果现有路径不是重解析点（如常规文件/目录），删除后重新创建

### 3. 错误恢复
- **优雅降级**：任何步骤失败时返回 `None`，调用方将使用原始 CWD
- **详细日志**：通过 `log_note` 记录每个关键步骤的诊断信息

## 具体技术实现

### 关键函数

#### `junction_name_for_path(path: &Path) -> String`
```rust
fn junction_name_for_path(path: &Path) -> String {
    let mut hasher = DefaultHasher::new();
    path.to_string_lossy().hash(&mut hasher);
    format!("{:x}", hasher.finish())
}
```
- 使用 `std::collections::hash_map::DefaultHasher`（SipHash）
- 将路径的字符串表示（含 UNC 前缀等）哈希为 64 位值
- 格式化为小写十六进制字符串

#### `junction_root_for_userprofile(userprofile: &str) -> PathBuf`
```rust
fn junction_root_for_userprofile(userprofile: &str) -> PathBuf {
    PathBuf::from(userprofile)
        .join(".codex")
        .join(".sandbox")
        .join("cwd")
}
```
- 构建 junction 存储的根目录
- 路径结构：`%USERPROFILE%\.codex\.sandbox\cwd\`

#### `create_cwd_junction(requested_cwd: &Path, log_dir: Option<&Path>) -> Option<PathBuf>`

**完整流程：**

```
1. 获取 USERPROFILE 环境变量
2. 构建 junction_root 路径
3. 创建 junction_root 目录（create_dir_all）
4. 计算 junction_path = junction_root + hash(requested_cwd)
5. 检查 junction_path 是否存在：
   a. 存在且是重解析点（FILE_ATTRIBUTE_REPARSE_POINT）-> 复用
   b. 存在但不是重解析点 -> 删除目录后重建
   c. 不存在 -> 创建新 junction
6. 使用 cmd /c mklink /J 创建 junction
7. 验证创建成功（检查状态码和路径存在性）
8. 返回 junction_path 或 None
```

### 关键技术细节

#### 重解析点检测
```rust
use windows_sys::Win32::Storage::FileSystem::FILE_ATTRIBUTE_REPARSE_POINT;

match std::fs::symlink_metadata(&junction_path) {
    Ok(md) if (md.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT) != 0 => {
        // 是有效的 junction，复用
    }
    // ...
}
```

#### Windows 命令执行
```rust
// 使用 raw_arg 避免 Windows 引号转义问题
let output = std::process::Command::new("cmd")
    .raw_arg("/c")
    .raw_arg("mklink")
    .raw_arg("/J")
    .raw_arg(&link_quoted)
    .raw_arg(&target_quoted)
    .output()
```

**关键设计决策：**
- 使用 `raw_arg` 而非 `arg`：避免 `std::process::Command` 的引号转义与 `cmd.exe` 解析冲突
- 路径用双引号包裹：处理含空格的路径
- 依赖 `mklink` 内置命令：Windows 没有直接的 Rust API 创建 junction，需调用系统命令

### 数据结构

```rust
// 隐式数据结构
struct JunctionInfo {
    root: PathBuf,      // %USERPROFILE%\.codex\.sandbox\cwd
    name: String,       // 16进制哈希值
    full_path: PathBuf, // root + name
    target: PathBuf,    // 实际工作目录
}
```

## 关键代码路径与文件引用

### 当前文件结构

| 函数 | 行号 | 职责 |
|------|------|------|
| `junction_name_for_path` | 13-17 | 生成路径哈希名称 |
| `junction_root_for_userprofile` | 19-24 | 构建 junction 根目录 |
| `create_cwd_junction` | 26-142 | 主入口，管理 junction 生命周期 |

### 调用关系

```
command_runner_win.rs::effective_cwd()
    └── create_cwd_junction(requested_cwd, log_dir)
        ├── std::env::var("USERPROFILE")
        ├── std::fs::create_dir_all(junction_root)
        ├── std::fs::symlink_metadata(junction_path)
        │   └── 检查 FILE_ATTRIBUTE_REPARSE_POINT
        ├── std::fs::remove_dir(junction_path)  // 如果需要重建
        └── std::process::Command::new("cmd")   // mklink
```

### 依赖模块

```
cwd_junction.rs
├── codex_windows_sandbox::log_note  # 日志记录
├── std::collections::hash_map::DefaultHasher  # 哈希
├── std::os::windows::fs::MetadataExt  # Windows 文件属性
└── windows_sys::Win32::Storage::FileSystem::FILE_ATTRIBUTE_REPARSE_POINT
```

## 依赖与外部交互

### 输入依赖

| 来源 | 类型 | 说明 |
|------|------|------|
| 环境变量 | `USERPROFILE` | 用户主目录，用于构建 junction 根路径 |
| 参数 | `requested_cwd` | 实际请求的工作目录 |
| 参数 | `log_dir` | 可选的日志目录，用于诊断输出 |

### 输出交互

| 目标 | 类型 | 说明 |
|------|------|------|
| 文件系统 | Junction | 在 `%USERPROFILE%\.codex\.sandbox\cwd\` 下创建 |
| 日志 | 文本 | 通过 `log_note` 记录操作结果 |
| 返回值 | `Option<PathBuf>` | 成功返回 junction 路径，失败返回 None |

### 外部系统交互

| 系统 | 交互方式 | 目的 |
|------|----------|------|
| Windows 文件系统 | `CreateDirectory` / `RemoveDirectory` | 目录管理 |
| Windows 重解析点 | `mklink /J` 命令 | 创建 junction |
| Windows 文件属性 | `GetFileAttributes`（通过 std） | 检测重解析点 |

## 风险、边界与改进建议

### 已知风险

1. **哈希冲突**
   - 使用 64 位哈希，虽然概率极低，但理论上不同路径可能生成相同 junction 名称
   - **影响**：可能导致两个不同目录共享同一个 junction，造成安全或功能问题

2. **Junction 残留**
   - 如果 runner 进程异常终止，已创建的 junction 不会被清理
   - 长期运行可能导致 `%USERPROFILE%\.codex\.sandbox\cwd\` 目录膨胀

3. **并发竞争**
   - 多个 runner 实例同时尝试创建相同 junction 时可能产生竞争条件
   - `mklink` 命令可能因 "文件已存在" 失败

4. **权限问题**
   - 创建 junction 需要 `SeCreateSymbolicLinkPrivilege` 权限
   - 在沙箱用户上下文中可能受限（但通常目录连接点权限要求较低）

5. **路径长度限制**
   - Windows 传统路径长度限制为 260 字符（MAX_PATH）
   - 长路径可能被截断或导致失败

### 边界条件

| 边界 | 处理 |
|------|------|
| USERPROFILE 未设置 | 返回 `None`，使用原始 CWD |
| junction_root 创建失败 | 记录日志，返回 `None` |
| 现有路径不是重解析点且删除失败 | 记录日志，返回 `None` |
| mklink 命令失败 | 记录 stdout/stderr，返回 `None` |
| 路径包含引号 | Windows 路径不能包含引号，无需额外处理 |

### 改进建议

1. **哈希冲突检测**
   ```rust
   // 建议：存储目标路径到 junction 目录的元数据文件中
   let marker = junction_path.join(".codex-junction-target");
   if marker.exists() {
       let stored_target = std::fs::read_to_string(&marker)?;
       if stored_target != requested_cwd.to_string_lossy() {
           // 哈希冲突！使用不同的哈希算法或添加 salt
       }
   }
   ```

2. **定期清理机制**
   ```rust
   // 建议：添加函数清理过期的 junction
   pub fn cleanup_stale_junctions(junction_root: &Path, max_age: Duration) -> Result<()> {
       // 删除超过 max_age 未访问的 junction
   }
   ```

3. **并发安全**
   ```rust
   // 建议：使用文件锁或命名互斥量协调并发创建
   let lock = fs2::FileExt::lock_exclusive(junction_root.join(".lock"))?;
   // 执行创建操作
   ```

4. **长路径支持**
   ```rust
   // 建议：使用 \\?\ 前缀启用扩展长度路径
   let extended_path = format!(r"\\?\{}", junction_path.display());
   ```

5. **原生 API 替代**
   - 考虑使用 `CreateSymbolicLinkW` Windows API 直接创建 junction，避免 `cmd /c mklink` 的开销和依赖
   - 需要处理 `SeCreateSymbolicLinkPrivilege` 权限检查

6. **测试覆盖**
   - 当前文件没有单元测试，建议添加：
     - 哈希生成一致性测试
     - Junction 创建/复用/重建测试
     - 错误路径测试（权限不足、路径不存在等）

7. **性能优化**
   - 缓存 `junction_root` 路径，避免重复计算
   - 使用 `std::fs::symlink_metadata` 前先检查 `exists()` 可能更高效
