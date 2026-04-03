# 研究文档：static_overlay_wraps_long_lines.snap

## 场景与职责

此快照测试验证静态覆盖层中长行的换行处理。当内容行很长时，应该正确换行以适应终端宽度。

## 功能点目的

1. **长行换行**：自动换行以适应屏幕宽度
2. **可读性保持**：换行后保持内容可读
3. **进度指示**：显示当前滚动位置

## 具体技术实现

### 快照输出分析

```
"/ S T A T I C / / / / / "
"a very long line that   "
"should wrap when        "
"rendered within a narrow"
"─────────────────── 0% ─"
" ↑/↓ to scroll   pgup/pg"
" q to quit              "
"                        "
```

关键观察：
- 长行被分割成多行
- 每行都有适当的填充
- 进度显示为 `0%`（在顶部）

### 换行实现

```rust
fn wrap_content_lines(content: &[String], width: usize) -> Vec<String> {
    let mut result = vec![];
    
    for line in content {
        if line.width() <= width {
            result.push(line.clone());
        } else {
            // 使用 textwrap 进行换行
            let wrapped = textwrap::wrap(line, width);
            result.extend(wrapped.into_iter().map(|s| s.to_string()));
        }
    }
    
    result
}
```

## 关键代码路径与文件引用

1. **覆盖层实现**：
   - `codex-rs/tui/src/pager_overlay.rs`
   - 第 798 行附近（根据 assertion_line）

2. **换行工具**：
   - `crate::wrapping` 模块

## 依赖与外部交互

### 换行依赖
- `textwrap` - 文本换行库

## 风险、边界与改进建议

### 潜在风险
1. **单词截断**：换行可能在单词中间截断
2. **格式丢失**：换行可能破坏原始格式

### 边界情况
1. 极长的无空格字符串
2. 包含 ANSI 转义序列的行
3. 包含多字节字符的行

### 改进建议
1. 支持水平滚动替代换行
2. 添加换行/截断切换选项
3. 对代码内容使用语法感知换行
