# sandbox_utils.rs 深度研究文档

## 场景与职责

`sandbox_utils.rs` 是 Windows Sandbox 模块中的**共享工具库**，集中了设置流程中使用的通用辅助函数。该模块的设计目标是减少代码重复，为遗留路径和提权路径提供统一的小工具函数。

### 核心职责
1. **Git 仓库检测**：查找 Git 工作区根目录
2. **Git 安全配置**：自动注入 `safe.directory` 配置
3. **目录创建**：确保 Codex home 目录存在

## 功能点目的

### 1. `find_git_root` - 查找 Git 仓库根
```rust
fn find_git_root(start: &Path) -> Option<PathBuf>
```
- **用途**：从指定路径向上遍历，查找 Git 仓库根目录
- **支持**：
  - 普通 `.git` 目录
  - Git worktree（`.git` 文件指向外部 gitdir）
- **算法**：
  1. 规范化起始路径
  2. 检查当前目录的 `.git`：
     - 如果是目录，返回当前目录
     - 如果是文件，解析 `gitdir:` 指向
  3. 向上遍历到父目录，重复步骤 2
  4. 到达根目录仍未找到则返回 `None`

**Git worktree 支持**：
```
.git 文件内容：
gitdir: /path/to/main/repo/.git/worktrees/example

解析后返回：/path/to/main/repo
```

### 2. `ensure_codex_home_exists` - 确保目录存在
```rust
pub fn ensure_codex_home_exists(p: &Path) -> Result<()>
```
- **用途**：确保 Codex home 目录存在，如不存在则创建
- **实现**：调用 `std::fs::create_dir_all`
- **使用场景**：
  - 设置流程开始前
  - 确保日志和配置文件有写入位置

### 3. `inject_git_safe_directory` - 注入 Git 安全配置
```rust
pub fn inject_git_safe_directory(env_map: &mut HashMap<String, String>, cwd: &Path)
```
- **用途**：解决 Git 的目录所有权检查问题
- **背景**：
  - Git 2.35+ 引入了目录所有权安全检查
  - 如果仓库由不同用户拥有，Git 会拒绝执行命令
  - 沙箱用户与主用户不同，导致 Git 命令失败
- **解决方案**：
  - 通过环境变量设置 `safe.directory`
  - 使用 `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n` 机制

**环境变量设置示例**：
```rust
// 假设在 /home/user/project 目录
// 找到 git_root = /home/user/project

env_map.insert("GIT_CONFIG_KEY_0", "safe.directory");
env_map.insert("GIT_CONFIG_VALUE_0", "/home/user/project");
env_map.insert("GIT_CONFIG_COUNT", "1");
```

## 具体技术实现

### Git 根目录查找算法
```rust
fn find_git_root(start: &Path) -> Option<PathBuf> {
    let mut cur = dunce::canonicalize(start).ok()?;
    loop {
        let marker = cur.join(".git");
        if marker.is_dir() {
            return Some(cur);
        }
        if marker.is_file() {
            if let Ok(txt) = std::fs::read_to_string(&marker) {
                if let Some(rest) = txt.trim().strip_prefix("gitdir:") {
                    let gitdir = rest.trim();
                    let resolved = if Path::new(gitdir).is_absolute() {
                        PathBuf::from(gitdir)
                    } else {
                        cur.join(gitdir)
                    };
                    return resolved.parent().map(|p| p.to_path_buf()).or(Some(cur));
                }
            }
            return Some(cur);
        }
        let parent = cur.parent()?;
        if parent == cur {
            return None;
        }
        cur = parent.to_path_buf();
    }
}
```

### Git 配置注入
```rust
pub fn inject_git_safe_directory(env_map: &mut HashMap<String, String>, cwd: &Path) {
    if let Some(git_root) = find_git_root(cwd) {
        let mut cfg_count: usize = env_map
            .get("GIT_CONFIG_COUNT")
            .and_then(|v| v.parse::<usize>().ok())
            .unwrap_or(0);
        let git_path = git_root.to_string_lossy().replace("\\\\", "/");
        env_map.insert(
            format!("GIT_CONFIG_KEY_{cfg_count}"),
            "safe.directory".to_string(),
        );
        env_map.insert(format!("GIT_CONFIG_VALUE_{cfg_count}"), git_path);
        cfg_count += 1;
        env_map.insert("GIT_CONFIG_COUNT".to_string(), cfg_count.to_string());
    }
}
```

## 关键代码路径与文件引用

### 内部依赖
| 依赖 | 类型 | 用途 |
|------|------|------|
| `dunce` | crate | 路径规范化 |
| `std::path::{Path, PathBuf}` | 标准库 | 路径操作 |
| `std::collections::HashMap` | 标准库 | 环境变量映射 |

### 被调用方
| 调用方 | 函数 | 场景 |
|--------|------|------|
| `elevated_impl.rs` | `find_git_root` / `inject_git_safe_directory` | 提权执行环境准备 |
| `setup_orchestrator.rs` (可能) | `ensure_codex_home_exists` | 设置流程 |

### 导出状态
该模块的函数通常作为内部工具使用，不直接对外导出。

## 依赖与外部交互

### 外部 Crate
- `dunce`：改进的 `canonicalize` 实现，避免 UNC 路径前缀

### 标准库
- `std::fs`：文件系统操作
- `std::path`：路径操作
- `std::collections::HashMap`：环境变量存储

### Git 环境变量协议
Git 支持通过环境变量传递配置：
- `GIT_CONFIG_COUNT`：配置项数量
- `GIT_CONFIG_KEY_n`：第 n 个配置项的键
- `GIT_CONFIG_VALUE_n`：第 n 个配置项的值

**示例**：
```bash
GIT_CONFIG_COUNT=2 \
GIT_CONFIG_KEY_0=safe.directory \
GIT_CONFIG_VALUE_0=/path/to/repo1 \
GIT_CONFIG_KEY_1=user.name \
GIT_CONFIG_VALUE_1="Sandbox User" \
git status
```

## 风险、边界与改进建议

### 已知风险

1. **Git 版本兼容性**
   - 问题：`safe.directory` 配置在 Git 2.35+ 引入
   - 影响：旧版本 Git 会忽略这些环境变量
   - 缓解：这是安全功能，旧版本无此限制

2. **路径规范化问题**
   - 问题：`dunce::canonicalize` 要求路径存在
   - 影响：如果 cwd 被删除，函数返回 `None`
   - 缓解：调用方应确保路径存在

3. **多仓库场景**
   - 问题：如果命令在子模块或嵌套仓库中执行
   - 行为：返回最近的 Git 根目录
   - 注意：这可能不是用户期望的行为

### 边界条件

1. **非 Git 目录**：`find_git_root` 返回 `None`，`inject_git_safe_directory` 不执行任何操作
2. **损坏的 .git 文件**：如果 `.git` 文件格式不正确，返回当前目录
3. **相对 gitdir**：正确处理相对于 `.git` 文件的路径
4. **空环境变量**：`GIT_CONFIG_COUNT` 不存在时从 0 开始
5. **路径分隔符**：将 `\\` 替换为 `/` 以适应 Git 的跨平台路径格式

### 改进建议

1. **缓存 Git 根目录**
   - 当前：每次调用都重新遍历
   - 建议：添加 LRU 缓存，提高重复调用性能

2. **支持更多 Git 配置**
   - 当前：仅支持 `safe.directory`
   - 建议：提供通用函数注入任意 Git 配置

3. **子模块支持**
   - 当前：返回最近的 Git 根
   - 建议：添加选项控制是否进入子模块

4. **错误报告**
   - 当前：静默失败（返回 `None`）
   - 建议：添加调试日志记录查找过程

5. **路径验证**
   - 当前：假设路径有效
   - 建议：验证 `gitdir` 指向的目录确实存在

### 使用模式

```rust
// 在设置流程中
let mut env_map = HashMap::new();
inject_git_safe_directory(&mut env_map, &cwd);
// env_map 现在包含 safe.directory 配置

// 创建进程时传递 env_map
spawn_process_with_env(command, cwd, &env_map)?;
```

### 性能特征

1. **文件系统访问**
   - `find_git_root` 需要多次 `metadata` 调用
   - 深度嵌套的目录结构会增加遍历时间

2. **字符串操作**
   - 路径替换和连接涉及内存分配
   - 对长路径有一定开销

3. **建议**
   - 在已知非 Git 目录的场景跳过调用
   - 缓存结果避免重复遍历

### 安全考虑

1. **目录遍历**
   - `find_git_root` 向上遍历文件系统
   - 不会访问不相关的目录

2. **环境变量注入**
   - 仅注入 `safe.directory` 配置
   - 不影响其他 Git 配置

3. **路径处理**
   - 使用 `dunce` 避免 UNC 路径问题
   - 正确处理相对和绝对路径
