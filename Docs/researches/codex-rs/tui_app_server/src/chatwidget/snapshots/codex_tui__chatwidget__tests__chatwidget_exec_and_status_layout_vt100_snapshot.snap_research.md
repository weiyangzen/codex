# 研究文档: codex_tui__chatwidget__tests__chatwidget_exec_and_status_layout_vt100_snapshot.snap

## 场景与职责

本快照文件验证 **命令执行和状态布局** 的完整 VT100 终端渲染输出。

测试命令执行期间 TUI 的整体布局，包括历史记录、状态栏和输入区域。

## 功能点目的

1. **整体布局验证**: 验证命令执行时的完整 UI 布局
2. **VT100 兼容性**: 确保 VT100 转义序列正确
3. **多元素协调**: 验证历史、状态、输入的协调显示

## 具体技术实现

### 快照内容结构
```
[22 行空白]

• I'm going to search the repo for where "Change Approved" is rendered...

• Explored
  └ Search Change Approved
    Read diff_render.rs

• Investigating rendering code (0s • esc to interrupt)


› Summarize recent commits

  tab to queue message                                       100% context left
```

### 布局分析

| 区域 | 行 | 内容 |
|------|-----|------|
| 历史区域 | 1-22 | 空白（滚动区域） |
| 消息 | 23-24 | 用户消息 |
| 探索状态 | 26-28 | 探索操作记录 |
| 工作状态 | 30 | 状态指示 |
| 输入框 | 33 | 输入提示 |
| 底部栏 | 35 | 快捷键和上下文 |

### 关键元素

```
• Investigating rendering code (0s • esc to interrupt)
  │                        │  │ │
  │                        │  │ └── 中断提示
  │                        │  └── 计时
  │                        └── 运行时间
  └── 操作描述
```

## 关键代码路径与文件引用

### 测试定义
```rust
expression: term.backend().vt100().screen().contents()
```

### 布局组件
- `ChatWidget::render()` - 主渲染方法
- `StatusLineItem` - 状态行组件
- `bottom_pane` - 底部面板

### VT100 后端
```rust
VT100Backend::new(width, height)
```

## 依赖与外部交互

### 协议事件
- `ExecCommandBeginEvent` - 开始执行
- `ExecCommandEndEvent` - 执行完成
- `AgentStatus` - 代理状态更新

### 渲染依赖
- `ratatui::backend::Backend`
- VT100 转义序列处理

## 风险、边界与改进建议

### 布局风险
1. **窗口缩放**: 不同尺寸下的布局稳定性
2. **内容溢出**: 长消息的处理
3. **状态冲突**: 多个状态同时显示时的优先级

### 改进建议
1. **响应式布局**: 根据窗口尺寸动态调整
2. **状态合并**: 避免多个状态指示器冲突
3. **滚动优化**: 优化历史区域的滚动性能

### 相关测试
- `chatwidget_tall.snap` - 高窗口布局
- `chatwidget_markdown_code_blocks_vt100_snapshot.snap` - Markdown 布局
