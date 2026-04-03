# Diff Render - 路径相对化渲染测试

## 场景与职责

该快照测试验证 TUI 中**绝对路径的相对化显示**功能。当 Codex 处理使用绝对路径的文件变更时，需要将路径转换为相对于当前工作目录的形式，提供更简洁、可读性更好的输出。

此功能特别适用于：
- 显示重命名操作（`old_path → new_path`）
- 处理跨目录的文件移动
- 在 UI 中隐藏敏感或冗长的绝对路径信息

## 功能点目的

1. **路径简化**：将绝对路径转换为相对路径，提升可读性
2. **重命名展示**：使用箭头符号（`→`）清晰展示文件重命名
3. **工作目录感知**：基于当前工作目录进行路径转换
4. **Git 仓库感知**：在同一 Git 仓库内使用相对路径，跨仓库时使用 `~` 家目录缩写
5. **一致性保证**：确保相同文件在不同场景下显示一致

## 具体技术实现

### 核心函数

```rust
/// 将路径格式化为相对于当前工作目录的显示形式
pub(crate) fn display_path_for(path: &Path, cwd: &Path) -> String {
    // 1. 已经是相对路径，直接返回
    if path.is_relative() {
        return path.display().to_string();
    }

    // 2. 尝试相对于 cwd 的路径
    if let Ok(stripped) = path.strip_prefix(cwd) {
        return stripped.display().to_string();
    }

    // 3. 检查是否在同一个 Git 仓库
    let path_in_same_repo = match (get_git_repo_root(cwd), get_git_repo_root(path)) {
        (Some(cwd_repo), Some(path_repo)) => cwd_repo == path_repo,
        _ => false,
    };

    let chosen = if path_in_same_repo {
        // 同一仓库：计算相对路径
        pathdiff::diff_paths(path, cwd).unwrap_or_else(|| path.to_path_buf())
    } else {
        // 不同仓库：尝试使用家目录缩写
        relativize_to_home(path)
            .map(|p| PathBuf::from_iter([Path::new("~"), p.as_path()]))
            .unwrap_or_else(|| path.to_path_buf())
    };
    chosen.display().to_string()
}
```

### 重命名路径渲染

```rust
// diff_render.rs:405-412
let render_path = |row: &Row| -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    spans.push(display_path_for(&row.path, cwd).into());
    if let Some(move_path) = &row.move_path {
        spans.push(format!(" → {}", display_path_for(move_path, cwd)).into());
    }
    spans
};
```

### 路径处理策略

| 场景 | 处理方式 | 示例输出 |
|------|----------|----------|
| 相对路径 | 原样返回 | `src/main.rs` |
| 在 cwd 下 | strip_prefix | `src/main.rs` |
| 同 Git 仓库 | pathdiff | `../other/src/main.rs` |
| 跨仓库 | 家目录缩写 | `~/projects/other/src/main.rs` |
| 无法简化 | 原绝对路径 | `/usr/local/...` |

### 关键代码路径

```rust
// diff_render.rs:738-762
pub(crate) fn display_path_for(path: &Path, cwd: &Path) -> String {
    if path.is_relative() {
        return path.display().to_string();
    }

    if let Ok(stripped) = path.strip_prefix(cwd) {
        return stripped.display().to_string();
    }

    let path_in_same_repo = match (get_git_repo_root(cwd), get_git_repo_root(path)) {
        (Some(cwd_repo), Some(path_repo)) => cwd_repo == path_repo,
        _ => false,
    };
    let chosen = if path_in_same_repo {
        pathdiff::diff_paths(path, cwd).unwrap_or_else(|| path.to_path_buf())
    } else {
        relativize_to_home(path)
            .map(|p| PathBuf::from_iter([Path::new("~"), p.as_path()]))
            .unwrap_or_else(|| path.to_path_buf())
    };
    chosen.display().to_string()
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| 路径显示 | `diff_render.rs:738-762` | `display_path_for` 函数 |
| 路径渲染 | `diff_render.rs:405-412` | `render_path` 闭包 |
| 家目录处理 | `codex-rs/tui/src/exec_command.rs` | `relativize_to_home` 函数 |
| Git 根目录 | `codex_core::git_info::get_git_repo_root` | Git 仓库检测 |
| 测试用例 | `diff_render.rs:1675-1697` | `ui_snapshot_apply_update_block_relativizes_path` |

### 相关函数

- `display_path_for()` - 主路径格式化函数
- `relativize_to_home()` - 转换为家目录相对路径
- `get_git_repo_root()` - 获取 Git 仓库根目录
- `pathdiff::diff_paths()` - 计算两路径间的相对路径

## 依赖与外部交互

### 外部依赖

1. **pathdiff**：Rust 路径差异计算库
2. **std::path**：标准库路径操作

### 内部依赖

- `codex_core::git_info::get_git_repo_root` - Git 仓库根目录检测
- `crate::exec_command::relativize_to_home` - 家目录相对化

### 数据流

```
abs_old.rs (绝对路径: /home/user/project/abs_old.rs)
abs_new.rs (绝对路径: /home/user/project/abs_new.rs)
cwd = /home/user/project
    ↓ display_path_for()
"abs_old.rs" 和 "abs_new.rs" (相对路径)
    ↓ render_path()
"abs_old.rs → abs_new.rs"
    ↓ 渲染到终端
"• Edited abs_old.rs → abs_new.rs (+1 -1)"
```

## 风险、边界与改进建议

### 潜在风险

1. **路径歧义**：相对化后的路径可能在不同上下文中指代不同文件
2. **符号链接**：未处理符号链接导致的路径解析问题
3. **Windows 路径**：Windows 盘符路径（`C:\`）的处理
4. **性能**：频繁的 Git 仓库检测可能影响性能

### 边界情况

1. **cwd 变化**：工作目录变化后，同一路径可能显示不同
2. **路径不存在**：文件已被删除或移动后的路径显示
3. **特殊字符**：包含空格、Unicode 字符的路径处理
4. **超长路径**：超出终端宽度的路径截断
5. **空路径**：理论上不应出现，但需要防护

### 测试场景分析

当前测试用例：
```rust
let cwd = std::env::current_dir().unwrap();
let abs_old = cwd.join("abs_old.rs");
let abs_new = cwd.join("abs_new.rs");
// ...
```

验证点：
- 绝对路径被正确转换为相对路径
- 重命名箭头符号正确显示
- 统计信息正确附加

### 改进建议

1. **路径缓存**：
   - 缓存 Git 仓库根目录查询结果
   - 缓存路径相对化结果

2. **配置选项**：
   - 始终显示绝对路径的选项
   - 自定义路径显示长度限制
   - 路径别名/映射配置

3. **交互增强**：
   - 悬停显示完整绝对路径
   - 点击复制完整路径
   - 路径跳转功能

4. **边界处理**：
   - 处理符号链接的正确解析
   - Windows 路径的特殊处理
   - 网络路径（UNC）的支持

5. **安全考虑**：
   - 避免在日志中暴露敏感路径
   - 提供路径脱敏选项

6. **可访问性**：
   - 屏幕阅读器友好的路径朗读
   - 高对比度模式下的路径显示

### 相关测试

```rust
// diff_render.rs:1469-1487
#[test]
fn display_path_prefers_cwd_without_git_repo() {
    let cwd = PathBuf::from("/workspace/codex");
    let path = cwd.join("tui").join("example.png");
    let rendered = display_path_for(&path, &cwd);
    assert_eq!(rendered, "tui/example.png");
}
```

此测试验证了在没有 Git 仓库的情况下，路径正确相对于 cwd 显示。
