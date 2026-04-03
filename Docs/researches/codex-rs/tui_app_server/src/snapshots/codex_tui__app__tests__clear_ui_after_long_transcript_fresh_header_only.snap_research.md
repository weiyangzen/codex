# Research: codex_tui__app__tests__clear_ui_after_long_transcript_fresh_header_only.snap

## 场景与职责

本快照文件测试 TUI 在长时间对话后的 UI 清理行为。当对话历史变得很长时，应用需要清理 UI 以保持良好的性能和用户体验。此快照验证了清理后头部信息的正确显示。

## 功能点目的

测试验证在清理长对话记录后，头部区域（Header）能够正确显示：
- 应用名称和版本
- 当前使用的模型信息
- 当前工作目录

## 具体技术实现

### UI 布局结构

```
╭─────────────────────────────────────────────╮
│ >_ OpenAI Codex (v<VERSION>)                │  <- 标题行
│                                             │  <- 空行
│ model:     gpt-test high   /model to change │  <- 模型信息
│ directory: /tmp/project                     │  <- 工作目录
╰─────────────────────────────────────────────╯
```

### 关键组件

1. **标题栏**: 显示 `>_ OpenAI Codex` 和版本号
2. **模型信息行**: 显示当前模型（`gpt-test high`）和切换提示（`/model to change`）
3. **目录信息行**: 显示当前工作目录（`/tmp/project`）

### 代码路径

```rust
// app.rs 中的头部渲染逻辑
fn render_header(&self, area: Rect, buf: &mut Buffer) {
    // 渲染标题、模型信息、工作目录
}
```

## 关键代码路径与文件引用

- **源文件**: `codex-rs/tui/src/app.rs`
- **测试场景**: `clear_ui_after_long_transcript_fresh_header_only` 测试函数
- **相关模块**: 
  - `version::CODEX_CLI_VERSION` - 版本信息
  - `config::Config` - 模型和目录配置

## 依赖与外部交互

- **配置系统**: 从 `Config` 获取当前模型和工作目录
- **版本管理**: `CODEX_CLI_VERSION` 常量提供版本信息
- **终端渲染**: 使用 `ratatui` 进行边框和文本渲染

## 风险、边界与改进建议

### 边界情况

1. **长路径截断**: 工作目录路径过长时可能需要截断处理
2. **模型名称长度**: 不同模型名称长度差异可能影响对齐
3. **版本占位符**: 快照中使用 `<VERSION>` 占位符，实际显示为具体版本号

### 风险点

1. **UI 一致性**: 清理后的 UI 需要与初始状态保持一致
2. **状态同步**: 清理操作不能影响当前会话状态

### 改进建议

1. 添加目录路径的缩写显示（如 `~/project` 代替完整路径）
2. 考虑添加更多状态指示器（如连接状态、沙盒状态等）
3. 支持自定义头部信息展示
