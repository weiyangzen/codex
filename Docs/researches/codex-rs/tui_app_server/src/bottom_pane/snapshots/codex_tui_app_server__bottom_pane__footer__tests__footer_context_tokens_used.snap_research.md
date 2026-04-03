# Research: Footer Context Tokens Used Snapshot

## 场景与职责

此快照展示了底部栏在显示上下文令牌使用量时的状态。当会话已经使用了一定量的上下文令牌时，底部栏右侧会显示具体的使用量（如 "123K used"），帮助用户了解当前会话的资源消耗情况。

## 功能点目的

- **资源使用透明**: 向用户展示当前会话已消耗的上下文令牌数量
- **容量管理**: 帮助用户判断是否需要开始新会话以避免超出上下文限制
- **快捷入口**: 左侧显示 "? for shortcuts"，提供快捷键帮助入口

## 具体技术实现

上下文令牌使用量的显示通过 `context_window_line()` 函数实现：

1. **数据获取**: 从 `FooterProps.context_tokens_used` 获取已使用的令牌数
2. **格式化显示**: 
   - 小于 1000: 直接显示数字（如 "500 used"）
   - 大于等于 1000: 使用 K 单位（如 "123K used"）
3. **位置固定**: 始终显示在底部栏最右侧
4. **颜色编码**: 可能根据使用量百分比使用不同颜色（如绿色、黄色、红色）

代码逻辑：
```rust
fn context_window_line(tokens_used: u64) -> String {
    if tokens_used >= 1000 {
        format!("{}K used", tokens_used / 1000)
    } else {
        format!("{} used", tokens_used)
    }
}
```

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **格式化函数**: `context_window_line()` 处理令牌数量的格式化显示
- **渲染位置**: 在 `render()` 方法中固定布局在右侧
- **数据源**: `FooterProps.context_tokens_used: u64`

## 依赖与外部交互

- 依赖 `FooterProps.context_tokens_used` 接收已使用令牌数
- 依赖 `FooterProps.context_tokens_total` 计算剩余百分比（如需要）
- 与左侧提示信息（如 "? for shortcuts"）独立显示
- 数据来源通常是后端 API 返回的会话状态信息

## 风险、边界与改进建议

- **边界情况**: 当令牌使用量接近上限时，应考虑添加警告颜色或闪烁效果
- **改进建议**: 添加悬停提示显示精确数字（而非近似值如 "123K"）
- **改进建议**: 考虑显示百分比（如 "45% used"）而非绝对值，更直观
- **改进建议**: 当接近限制时，可以显示建议操作（如 "Start new session?"）
- **改进建议**: 支持点击上下文显示区域打开详细的资源使用面板
