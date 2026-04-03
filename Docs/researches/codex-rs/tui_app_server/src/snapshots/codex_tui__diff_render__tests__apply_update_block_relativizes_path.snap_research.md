# 路径相对化渲染测试快照研究文档

## 场景与职责

### 测试场景
本快照测试验证当使用绝对路径表示文件变更时，diff渲染器能够智能地将绝对路径转换为相对路径显示。测试使用当前工作目录（cwd）拼接出的绝对路径（`abs_old.rs` 和 `abs_new.rs`），验证渲染输出是否显示为相对路径格式。

### 业务场景
在实际使用中，Codex TUI 可能接收到以下形式的文件路径：
1. **绝对路径**：来自LLM的响应或系统API返回
2. **相对路径**：用户直接输入或项目内引用
3. **跨仓库路径**：位于不同Git仓库的文件
4. **Home目录文件**：位于用户主目录的配置文件

### 组件职责
- **路径显示优化** (`display_path_for`): 将各种形式的路径转换为最简洁的显示形式
- **Git仓库感知**: 利用Git仓库根目录判断文件是否属于同一项目
- **Home目录简化**: 将 `/home/username/...` 简化为 `~/...`
- **重命名路径处理**: 同时处理源路径和目标路径（对于文件移动/重命名场景）

## 功能点目的

### 核心功能
1. **路径简化**: 减少视觉噪音，让用户专注于文件名而非完整路径
2. **一致性**: 确保同一变更集中的所有路径使用统一的显示风格
3. **上下文感知**: 根据当前工作目录和Git仓库信息做出最优显示决策

### 测试验证点
```rust
let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"));
let abs_old = cwd.join("abs_old.rs");
let abs_new = cwd.join("abs_new.rs");

// 使用绝对路径创建变更
changes.insert(
    abs_old,
    FileChange::Update {
        unified_diff: patch,
        move_path: Some(abs_new),  // 重命名场景
    },
);
```

### 预期输出
```
"• Edited abs_old.rs → abs_new.rs (+1 -1)"
```

关键观察：
- 绝对路径被转换为相对路径显示
- 重命名操作使用箭头符号 `→` 连接源文件和目标文件
- 统计信息 `(+1 -1)` 表示1行新增，1行删除

## 具体技术实现

### 路径显示算法
```rust
pub(crate) fn display_path_for(path: &Path, cwd: &Path) -> String {
    // 1. 已经是相对路径，直接返回
    if path.is_relative() {
        return path.display().to_string();
    }

    // 2. 尝试相对于当前工作目录
    if let Ok(stripped) = path.strip_prefix(cwd) {
        return stripped.display().to_string();
    }

    // 3. 检查是否在同一Git仓库
    let path_in_same_repo = match (get_git_repo_root(cwd), get_git_repo_root(path)) {
        (Some(cwd_repo), Some(path_repo)) => cwd_repo == path_repo,
        _ => false,
    };

    let chosen = if path_in_same_repo {
        // 3a. 同一仓库：计算相对路径
        pathdiff::diff_paths(path, cwd).unwrap_or_else(|| path.to_path_buf())
    } else {
        // 3b. 不同仓库或不是仓库：尝试简化为 ~/path
        relativize_to_home(path)
            .map(|p| PathBuf::from_iter([Path::new("~"), p.as_path()]))
            .unwrap_or_else(|| path.to_path_buf())
    };
    
    chosen.display().to_string()
}
```

### 决策流程图
```
输入: path, cwd
│
├─ path 是相对路径? ──→ 是 ──→ 直接返回 path
│
└─ 否
   │
   ├─ path 以 cwd 开头? ──→ 是 ──→ 返回 path[cwd.len()..]
   │
   └─ 否
      │
      ├─ cwd 和 path 在同一Git仓库? ──→ 是 ──→ 使用 pathdiff 计算相对路径
      │
      └─ 否 ──→ 尝试替换为 ~/path ──→ 失败则返回原始绝对路径
```

### 重命名路径渲染
```rust
fn render_path(row: &Row) -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    // 源路径
    spans.push(display_path_for(&row.path, cwd).into());
    
    // 如果有目标路径（重命名），添加箭头
    if let Some(move_path) = &row.move_path {
        spans.push(format!(" → {}", display_path_for(move_path, cwd)).into());
    }
    spans
}
```

### Home目录简化
```rust
// 来自 exec_command 模块
pub(crate) fn relativize_to_home(path: &Path) -> Option<PathBuf> {
    let home = std::env::var_os("HOME")?;
    let home_path = Path::new(&home);
    path.strip_prefix(home_path).ok().map(|p| p.to_path_buf())
}
```

## 关键代码路径与文件引用

### 核心实现文件
| 文件路径 | 功能描述 |
|---------|---------|
| `codex-rs/tui/src/diff_render.rs` | 包含 `display_path_for` 和路径渲染逻辑 |
| `codex-rs/tui/src/exec_command.rs` | 包含 `relativize_to_home` 辅助函数 |
| `codex-core/src/git_info.rs` | Git仓库信息查询（`get_git_repo_root`） |

### 关键函数调用链
```
ui_snapshot_apply_update_block_relativizes_path (test)
  └── create_diff_summary
        └── render_changes_block
              ├── render_path(&row)  // 处理每个文件的路径显示
              │   ├── display_path_for(&row.path, cwd)      // 源路径
              │   │   ├── path.is_relative()
              │   │   ├── path.strip_prefix(cwd)
              │   │   ├── get_git_repo_root(cwd)
              │   │   ├── get_git_repo_root(path)
              │   │   ├── pathdiff::diff_paths()
              │   │   └── relativize_to_home(path)
              │   └── display_path_for(move_path, cwd)      // 目标路径（如有）
              └── format!(" → {}", ...)  // 重命名箭头
```

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `pathdiff` | 计算两个绝对路径之间的相对路径 |
| `std::env::var_os("HOME")` | 获取用户主目录路径 |
| `codex_core::git_info::get_git_repo_root` | 查询路径所属的Git仓库根目录 |

### 测试相关代码
```rust
#[test]
fn ui_snapshot_apply_update_block_relativizes_path() {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"));
    let abs_old = cwd.join("abs_old.rs");
    let abs_new = cwd.join("abs_new.rs");
    // ... 创建变更并使用绝对路径
    let lines = create_diff_summary(&changes, &cwd, 80);
    snapshot_lines("apply_update_block_relativizes_path", lines, 80, 10);
}
```

## 依赖与外部交互

### 系统环境依赖
| 环境变量/信息 | 用途 |
|-------------|------|
| `std::env::current_dir()` | 获取当前工作目录，作为路径相对化的基准 |
| `HOME` | 用户主目录路径，用于 `~/path` 简化 |
| Git仓库信息 | 判断文件是否属于同一项目 |

### 与 codex-core 的交互
```rust
use codex_core::git_info::get_git_repo_root;
```
- 输入：`&Path`（待查询路径）
- 输出：`Option<PathBuf>`（Git仓库根目录，None表示不在仓库中）
- 实现：通过执行 `git rev-parse --show-toplevel` 获取

### 与 codex-protocol 的交互
```rust
use codex_protocol::protocol::FileChange;
```
`FileChange::Update` 结构包含：
- `unified_diff: String` - diff内容
- `move_path: Option<PathBuf>` - 可选的目标路径（重命名场景）

### 平台差异处理
| 平台 | 路径分隔符 | 测试处理 |
|-----|-----------|---------|
| Windows | `\` | 测试使用 `cfg!(windows)` 条件编译 |
| Unix/Linux/Mac | `/` | 默认行为 |

相关测试代码：
```rust
#[test]
fn display_path_prefers_cwd_without_git_repo() {
    let cwd = if cfg!(windows) {
        PathBuf::from(r"C:\workspace\codex")
    } else {
        PathBuf::from("/workspace/codex")
    };
    // ...
}
```

## 风险、边界与改进建议

### 已知风险

1. **Git命令执行开销**
   - 风险：`get_git_repo_root` 执行外部Git命令
   - 影响：大量文件处理时可能产生性能瓶颈
   - 缓解：结果被缓存（应在 git_info 模块中实现）

2. **路径遍历攻击**
   - 风险：恶意构造的 `../../../etc/passwd` 路径
   - 现状：仅用于显示，不影响实际文件操作
   - 建议：添加路径规范化验证

3. **符号链接处理**
   - 风险：符号链接可能导致路径解析不一致
   - 现状：未明确处理符号链接场景

4. **非UTF-8路径**
   - 风险：某些系统允许非UTF-8文件名
   - 现状：Rust的 `Path::display()` 会替换无效字符

### 边界条件

| 场景 | 预期行为 | 测试状态 |
|-----|---------|---------|
| 路径等于cwd | 显示为 `.` 或空？ | 未明确测试 |
| 路径是cwd的父目录 | 使用 `pathdiff` 计算 `../` 形式 | 未测试 |
| 路径在不同磁盘（Windows） | 无法相对化，显示绝对路径 | 未测试 |
| HOME环境变量未设置 | 跳过home简化，显示绝对路径 | 未测试 |
| 路径包含 `.` 或 `..` | 应规范化后处理 | 未测试 |

### 改进建议

1. **添加路径规范化**
   ```rust
   let canonical_path = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
   ```
   消除 `.` 和 `..` 的影响

2. **缓存Git查询结果**
   ```rust
   // 使用 once_cell 或类似机制
   static GIT_ROOT_CACHE: Lazy<Mutex<HashMap<PathBuf, Option<PathBuf>>>> = ...;
   ```

3. **支持更多路径别名**
   - 考虑支持 `%USERPROFILE%`（Windows）
   - 支持工作区特定的别名（如 `$WORKSPACE_ROOT`）

4. **配置选项**
   ```toml
   # config.toml
   [display]
   path_format = "relative"  # 或 "absolute", "smart"
   ```

5. **增强测试覆盖**
   ```rust
   #[test]
   fn display_path_parent_directory() {
       let cwd = PathBuf::from("/a/b/c");
       let path = PathBuf::from("/a/b");
       assert_eq!(display_path_for(&path, &cwd), "..");
   }
   
   #[test]
   fn display_path_sibling_directory() {
       let cwd = PathBuf::from("/a/b/c");
       let path = PathBuf::from("/a/b/d");
       assert_eq!(display_path_for(&path, &cwd), "../d");
   }
   ```

6. **Windows特殊处理**
   ```rust
   #[cfg(windows)]
   fn display_path_for(path: &Path, cwd: &Path) -> String {
       // 处理不同驱动器盘符的情况
       if path.components().next() != cwd.components().next() {
           return path.display().to_string();  // 不同盘符，无法相对化
       }
       // ... 原有逻辑
   }
   ```

7. **国际化文件名**
   - 确保Unicode文件名正确显示
   - 考虑从右到左（RTL）语言的路径显示

### 相关代码审查建议
当前实现中 `relativize_to_home` 返回 `Option<PathBuf>`，在失败时回退到绝对路径。建议添加日志记录，帮助调试路径显示问题：

```rust
fn display_path_for(path: &Path, cwd: &Path) -> String {
    // ... 现有逻辑 ...
    let result = if path_in_same_repo { /* ... */ } else { /* ... */ };
    
    #[cfg(debug_assertions)]
    eprintln!("display_path: {:?} (cwd={:?}) -> {}", path, cwd, result.display());
    
    result.display().to_string()
}
```
