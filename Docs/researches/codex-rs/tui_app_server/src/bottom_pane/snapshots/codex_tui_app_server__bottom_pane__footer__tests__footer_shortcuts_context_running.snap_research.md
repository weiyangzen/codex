# Research: Footer Shortcuts Context Running Snapshot

## 场景与职责

此快照展示了当任务正在运行时的底部栏状态，显示 "? for shortcuts" 和 "72% context left"。与空闲状态不同，运行状态下的上下文使用量显示为具体的百分比（72%），反映了任务执行期间的资源消耗。

## 功能点目的

- **资源监控**: 实时显示任务执行期间的上下文使用量
- **快捷入口**: 保持 "? for shortcuts" 提示，确保用户随时可以访问帮助
- **状态感知**: 通过上下文使用量变化，让用户感知任务的进行

## 具体技术实现

任务运行时的底部栏显示逻辑：

1. **上下文计算**: 
   - 从 `FooterProps.context_tokens_used` 获取已使用量
   - 从 `FooterProps.context_tokens_total` 获取总量
   - 计算百分比：`used / total * 100`
2. **显示格式**: 显示为 "{percent}% context left" 或 "{percent}% used"
3. **简化布局**: 运行状态下简化其他提示，只保留核心信息

代码逻辑：
```rust
fn context_window_line(used: u64, total: u64) -> String {
    let percent = (used as f64 / total as f64 * 100.0) as u8;
    format!("{}% context left", 100 - percent)
    // 或
    format!("{}% used", percent)
}

// 运行状态下的渲染
if is_running {
    let left = "? for shortcuts";
    let right = context_window_line(used, total);
    // 中间可能显示进度信息
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **上下文计算**: `context_window_line()` 函数
- **运行状态**: `FooterProps.is_running` 控制显示模式
- **数据更新**: 任务执行期间的上下文使用量更新机制

## 依赖与外部交互

- 依赖 `FooterProps.context_tokens_used` 和 `context_tokens_total`
- 依赖后端 API 提供的实时令牌使用数据
- 与任务执行系统集成，接收进度和上下文使用更新
- 需要处理高频率的数据更新，避免过度刷新 UI

## 风险、边界与改进建议

- **边界情况**: 当上下文接近上限时，应添加警告提示
- **改进建议**: 添加上下文使用量的可视化进度条
- **改进建议**: 当使用量超过阈值（如 80%）时，改变显示颜色为黄色或红色
- **改进建议**: 显示预计剩余可用消息数，而非仅百分比
- **改进建议**: 添加上下文使用历史图表，帮助用户理解使用模式
