# Research: codex_tui_app_server__diff_render__tests__apply_update_block_relativizes_path.snap

## 场景与职责

此快照测试文件验证 Codex TUI 应用服务器在处理文件重命名（move/rename）操作时路径的相对化显示功能。当文件被重命名时，差异展示需要同时显示旧路径和新路径，并且将这些路径相对于当前工作目录（CWD）进行简化，以提供更清晰、更简洁的用户界面。

**应用场景：**
- 文件重命名操作的差异展示
- 跨目录移动文件的变更可视化
- 确保绝对路径在 UI 中显示为相对路径

**测试特点：**
- 使用绝对路径创建文件变更（`abs_old.rs` → `abs_new.rs`）
- 验证路径相对于当前工作目录的转换
- 测试路径显示格式：`old_path → new_path (+add -del)`

## 功能点目的

### 1. 路径相对化显示
```
"• Edited abs_old.rs → abs_new.rs (+1 -1)"
```

**功能说明：**
- 将绝对路径转换为相对于 CWD 的路径
- 使用箭头符号（→）表示重命名关系
- 保持变更统计信息（+1 -1）

### 2. 文件重命名差异渲染
```
"    1 -X                "
"    1 +X changed        "
"    2  Y                "
```

**渲染逻辑：**
- 第 1 行：旧内容 `X` 被标记为删除（-）
- 第 1 行：新内容 `X changed` 被标记为新增（+）
- 第 2 行：未变更内容 `Y` 显示为上下文（空格）

### 3. 路径显示优先级
`display_path_for` 函数实现了以下路径简化策略：

1. **相对路径优先**：如果路径已是相对路径，直接返回
2. **CWD 前缀剥离**：如果路径以 CWD 开头，移除 CWD 前缀
3. **Git 仓库相对**：如果在同一 Git 仓库内，计算相对路径
4. **Home 目录简化**：将用户主目录替换为 `~`

## 具体技术实现

### 路径相对化算法
```rust
pub(crate) fn display_path_for(path: &Path, cwd: &Path) -> String {
    // 1. 已经是相对路径
    if path.is_relative() {
        return path.display().to_string();
    }

    // 2. 相对于 CWD
    if let Ok(stripped) = path.strip_prefix(cwd) {
        return stripped.display().to_string();
    }

    // 3. 同一 Git 仓库内
    let path_in_same_repo = match (get_git_repo_root(cwd), get_git_repo_root(path)) {
        (Some(cwd_repo), Some(path_repo)) => cwd_repo == path_repo,
        _ => false,
    };
    let chosen = if path_in_same_repo {
        pathdiff::diff_paths(path, cwd).unwrap_or_else(|| path.to_path_buf())
    } else {
        // 4. 简化为 ~/path
        relativize_to_home(path)
            .map(|p| PathBuf::from_iter([Path::new("~"), p.as_path()]))
            .unwrap_or_else(|| path.to_path_buf())
    };
    chosen.display().to_string()
}
```

### 测试实现
```rust
#[test]
fn ui_snapshot_apply_update_block_relativizes_path() {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"));
    let abs_old = cwd.join("abs_old.rs");
    let abs_new = cwd.join("abs_new.rs");

    let original = "X\nY\n";
    let modified = "X changed\nY\n";
    let patch = diffy::create_patch(original, modified).to_string();

    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    changes.insert(
        abs_old,
        FileChange::Update {
            unified_diff: patch,
            move_path: Some(abs_new),  // 关键：指定 move_path
        },
    );

    let lines = create_diff_summary(&changes, &cwd, 80);
    snapshot_lines("apply_update_block_relativizes_path", lines, 80, 10);
}
```

### 重命名路径渲染
在 `render_changes_block` 函数（第 402-464 行）：

```rust
let render_path = |row: &Row| -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    spans.push(display_path_for(&row.path, cwd).into());
    if let Some(move_path) = &row.move_path {
        spans.push(format!(" → {}", display_path_for(move_path, cwd)).into());
    }
    spans
};
```

### 文件变更数据结构
```rust
pub enum FileChange {
    Add { content: String },
    Delete { content: String },
    Update {
        unified_diff: String,
        move_path: Option<PathBuf>,  // 重命名目标路径
    },
}
```

## 关键代码路径与文件引用

### 主要源文件
- **`codex-rs/tui_app_server/src/diff_render.rs`**
  - 第 1675-1697 行：`ui_snapshot_apply_update_block_relativizes_path` 测试函数
  - 第 738-762 行：`display_path_for` 路径相对化函数
  - 第 402-464 行：`render_changes_block` 批量渲染函数
  - 第 354-363 行：`Row` 结构体定义

### 关键调用链
```
ui_snapshot_apply_update_block_relativizes_path
  └── create_diff_summary(&changes, &cwd, 80)
        └── render_changes_block(rows, wrap_cols, cwd)
              ├── render_path(row)  // 渲染路径
              │     └── display_path_for(&row.path, cwd)
              │     └── display_path_for(move_path, cwd)  // 如果有 move_path
              └── render_change(&r.change, ...)
```

### 辅助模块
- **`codex_core::git_info::get_git_repo_root`**：获取 Git 仓库根目录
- **`crate::exec_command::relativize_to_home`**：将路径简化为相对于 home 目录
- **`pathdiff::diff_paths`**：计算两个路径之间的相对路径

## 依赖与外部交互

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `pathdiff` | 计算路径之间的相对差异 |
| `diffy` | 生成统一差异格式 |

### 内部模块依赖
```rust
use crate::exec_command::relativize_to_home;
use codex_core::git_info::get_git_repo_root;
```

### 路径处理策略对比

| 场景 | 输入 | 输出 | 函数 |
|------|------|------|------|
| 相对路径 | `src/main.rs` | `src/main.rs` | 直接返回 |
| CWD 子路径 | `/home/user/proj/src/main.rs` (CWD=/home/user/proj) | `src/main.rs` | `strip_prefix` |
| 同仓库 | `/home/user/proj/lib/helper.rs` (CWD=/home/user/proj/src) | `../lib/helper.rs` | `pathdiff::diff_paths` |
| 不同仓库 | `/other/project/file.rs` | `~/other/project/file.rs` | `relativize_to_home` |

## 风险、边界与改进建议

### 潜在风险

1. **路径分隔符不一致**
   - Windows 使用 `\`，Unix 使用 `/`
   - 当前实现依赖 Rust 的 `Path` 处理，但显示时可能混合分隔符

2. **符号链接处理**
   - 未解析符号链接，可能显示 `link/file.rs` 而非实际路径
   - 建议添加 `std::fs::canonicalize` 选项

3. **Git 仓库检测失败**
   - `get_git_repo_root` 可能返回 `None`
   - 回退到 home 目录简化可能产生不直观的路径

### 边界情况

1. **空 move_path**
   ```rust
   FileChange::Update {
       unified_diff: patch,
       move_path: None,  // 普通更新，非重命名
   }
   ```

2. **相同路径重命名**
   - 理论上不应发生，但需要防御性处理

3. **跨文件系统路径**
   - `strip_prefix` 可能失败
   - `pathdiff` 可能产生复杂相对路径

### 改进建议

1. **添加 Windows 路径测试**
   ```rust
   #[cfg(windows)]
   #[test]
   fn ui_snapshot_relativizes_path_windows() {
       let cwd = PathBuf::from(r"C:\Users\name\project");
       let abs_old = cwd.join("old.rs");
       // ...
   }
   ```

2. **支持路径别名配置**
   ```rust
   pub struct PathDisplayConfig {
       aliases: HashMap<PathBuf, String>,  // 如 {/very/long/path -> @lib}
   }
   ```

3. **添加路径工具提示**
   - 悬停时显示完整绝对路径
   - 对于简化后的路径提供原始路径信息

4. **改进 Git 子模块处理**
   ```rust
   // 检测子模块边界
   if is_git_submodule(path) {
       display_path = format!("{submodule_name}/{relative_path}");
   }
   ```

5. **路径长度限制**
   ```rust
   // 当路径过长时，中间部分使用 ... 省略
   if display_path.len() > MAX_PATH_LEN {
       display_path = truncate_path_middle(display_path);
   }
   ```

6. **添加更多路径场景测试**
   ```rust
   // 建议添加：
   // - 嵌套 Git 仓库
   // - 符号链接路径
   // - 网络路径 (\\server\share)
   // - 包含特殊字符的路径
   ```

### 相关测试文件
- `codex_tui_app_server__diff_render__tests__apply_update_with_rename_block.snap` - 带重命名的更新测试
- `codex_tui_app_server__diff_render__tests__apply_update_block.snap` - 基础更新测试
