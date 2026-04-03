# 研究文档：renders_with_queued_messages@macos.snap

## 场景与职责

此快照测试验证状态指示器在 macOS 平台上的特定显示效果。不同平台可能有不同的快捷键表示方式。

## 功能点目的

1. **平台适配**：根据平台显示相应的快捷键符号
2. **macOS 特性**：使用 macOS 风格的快捷键表示（⌥ 代替 alt）
3. **一致性**：保持功能一致，仅调整显示

## 具体技术实现

### 快照输出对比

Linux/Windows (`renders_with_queued_messages.snap`):
```
"   alt + ↑ edit                                                                 "
```

macOS (本快照):
```
"   ⌥ + ↑ edit                                                                   "
```

差异：
- `alt` → `⌥` (Option 键符号)

### 平台特定代码

```rust
fn format_edit_hint() -> String {
    #[cfg(target_os = "macos")]
    {
        "⌥ + ↑ edit".to_string()
    }
    
    #[cfg(not(target_os = "macos"))]
    {
        "alt + ↑ edit".to_string()
    }
}
```

## 关键代码路径与文件引用

1. **平台检测**：
   - `codex-rs/tui/src/status_indicator_widget.rs` 第 289 行附近

2. **快捷键提示**：
   - `crate::key_hint` - 跨平台快捷键格式化

## 依赖与外部交互

### 条件编译
- `#[cfg(target_os = "macos")]` - macOS 特定代码
- `#[cfg(not(target_os = "macos"))]` - 其他平台代码

## 风险、边界与改进建议

### 潜在风险
1. **符号兼容性**：`⌥` 符号在某些终端可能显示不正确
2. **用户困惑**：不熟悉 Mac 的用户可能不理解 `⌥` 符号

### 边界情况
1. 终端不支持 Unicode 符号
2. 远程连接到 Mac（SSH）
3. 字体缺失

### 改进建议
1. 检测终端 Unicode 支持，必要时回退到文字表示
2. 添加首次使用提示，解释符号含义
3. 支持配置快捷键显示风格
