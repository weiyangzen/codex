# Research: codex_tui__diff_render__tests__ansi16_insert_delete_no_background.snap

## 场景与职责

本快照文件测试 Diff 渲染器在 ANSI 16 色模式下的渲染行为。在有限的调色板环境中（如基本终端），diff 渲染需要适配仅使用前景色的模式。

## 功能点目的

验证 ANSI 16 色模式下的 diff 渲染：
- 不使用背景色（仅前景色区分）
- 添加行使用绿色前景
- 删除行使用红色前景
- 保持基本的可读性

## 具体技术实现

### 渲染输出格式

```
"1 +added in ansi16 mode                 "
"2 -deleted in ansi16 mode               "
```

### 颜色适配策略

```rust
// diff_render.rs
enum StdoutColorLevel {
    Ansi16,    // 16 色模式 - 仅前景色
    Ansi256,   // 256 色模式
    TrueColor, // 真彩色模式
}

// ANSI 16 色模式下的样式
const ANSI16_ADD_FG: Color = Color::Green;
const ANSI16_DEL_FG: Color = Color::Red;
// 注意：不使用背景色
```

### 与其他模式的对比

| 模式 | 添加行样式 | 删除行样式 |
|------|-----------|-----------|
| TrueColor | 绿色背景 #213A2B | 红色背景 #4A221D |
| ANSI256 | 索引色 22 背景 | 索引色 52 背景 |
| ANSI16 | 绿色前景 | 红色前景 |

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/diff_render.rs`
- **终端调色板**: `codex-rs/tui/src/terminal_palette.rs`
- **颜色检测**: `stdout_color_level()` 函数

## 依赖与外部交互

- **终端检测**: 自动检测终端支持的颜色级别
- **环境变量**: `COLORTERM`, `TERM` 等影响颜色级别判断
- **回退机制**: 当无法检测时安全回退到 ANSI16

## 风险、边界与改进建议

### 边界情况

1. **色盲用户**: 红绿色盲可能难以区分添加/删除
2. **终端兼容性**: 某些终端可能对 ANSI 颜色的解释不同
3. **亮色终端**: 在亮色背景下绿色/红色可能对比度不足

### 风险点

1. **可访问性**: 仅依赖颜色区分可能不符合 WCAG 标准
2. **一致性**: 不同终端的颜色显示可能有差异

### 改进建议

1. 添加额外的文本标记（如 `[+]` / `[-]`）辅助区分
2. 支持下划线、粗体等其他样式属性
3. 提供高对比度模式选项
4. 考虑使用蓝色/黄色替代红/绿以提高色盲友好性
