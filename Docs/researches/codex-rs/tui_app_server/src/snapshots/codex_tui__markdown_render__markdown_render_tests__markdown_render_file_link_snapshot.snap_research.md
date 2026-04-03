# 研究文档：markdown_render_file_link_snapshot.snap

## 场景与职责

此快照测试验证 Markdown 渲染器对文件链接的特殊处理。Codex TUI 对本地文件链接有特殊处理，显示实际文件路径而不是链接文本。

## 功能点目的

1. **文件链接识别**：识别指向本地文件的链接
2. **路径显示**：显示实际文件路径，便于用户定位
3. **路径简化**：将绝对路径简化为相对路径

## 具体技术实现

### 文件链接处理逻辑

```rust
// codex-rs/tui/src/markdown_render.rs
fn should_render_link_destination(dest_url: &str) -> bool {
    !is_local_path_like_link(dest_url)
}

fn is_local_path_like_link(url: &str) -> bool {
    // 检查是否是本地路径格式的链接
    url.starts_with("file://") || 
    url.starts_with("./") || 
    url.starts_with("../") ||
    url.starts_with('/')
}
```

### 快照输出

```
See codex-rs/tui/src/markdown_render.rs:74.
```

这表明文件链接被渲染为实际路径，而不是 Markdown 标签文本。

### 路径简化

```rust
fn simplify_path(path: &Path, cwd: Option<&Path>) -> String {
    if let Some(cwd) = cwd {
        if let Ok(relative) = path.strip_prefix(cwd) {
            return relative.display().to_string();
        }
    }
    
    // 尝试简化 home 目录
    if let Some(home) = home_dir() {
        if let Ok(relative) = path.strip_prefix(home) {
            return format!("~/{}", relative.display());
        }
    }
    
    path.display().to_string()
}
```

## 关键代码路径与文件引用

1. **文件链接处理**：
   - `codex-rs/tui/src/markdown_render.rs` 第 128-130 行
   - `LinkState::local_target_display`

2. **路径工具**：
   - `codex_utils_string::normalize_markdown_hash_location_suffix`

## 依赖与外部交互

### 路径处理
- `std::path::Path` - 路径操作
- `dirs::home_dir` - 获取 home 目录
- `url::Url` - URL 解析

### 正则表达式
- `regex_lite::Regex` - 位置后缀匹配

## 风险、边界与改进建议

### 潜在风险
1. **路径泄露**：可能暴露敏感路径信息
2. **路径不存在**：链接指向的文件可能不存在

### 边界情况
1. 文件路径包含特殊字符
2. 符号链接
3. 网络路径（UNC 路径）

### 改进建议
1. 添加文件存在性检查，不存在的文件显示不同样式
2. 支持点击文件链接在编辑器中打开
3. 添加文件类型图标
4. 支持行号高亮
