# 研究文档：renders_with_working_header.snap

## 场景与职责

此快照测试验证状态指示器的基本工作状态显示。当 Codex 正在工作时，状态指示器显示工作状态和持续时间。

## 功能点目的

1. **工作状态指示**：清晰显示系统正在工作
2. **时间显示**：显示工作持续时间
3. **中断提示**：提示用户可以按 ESC 中断

## 具体技术实现

### 快照输出分析

```
"• Working (0s • esc to interrupt)                                               "
"                                                                                "
```

界面元素：
- `•` - 状态指示点
- `Working` - 工作状态
- `(0s` - 持续时间（秒）
- `• esc to interrupt)` - 中断快捷键提示

### 工作状态实现

```rust
pub struct StatusIndicatorWidget {
    pub working: bool,
    pub start_time: Option<Instant>,
}

impl StatusIndicatorWidget {
    fn render_header(&self) -> String {
        if self.working {
            let duration = self.start_time
                .map(|t| t.elapsed().as_secs())
                .unwrap_or(0);
            format!("• Working ({}s • esc to interrupt)", duration)
        } else {
            String::new()
        }
    }
}
```

## 关键代码路径与文件引用

1. **状态指示器**：
   - `codex-rs/tui/src/status_indicator_widget.rs`
   - `codex-rs/tui_app_server/src/status_indicator_widget.rs`

2. **时间处理**：
   - `std::time::Instant`

## 依赖与外部交互

### 状态更新
- 通过 `ChatWidget` 更新工作状态
- 定时器更新持续时间

## 风险、边界与改进建议

### 潜在风险
1. **时间精度**：秒级精度可能不够精确
2. **状态同步**：显示状态与实际状态可能不同步

### 边界情况
1. 工作时间很长（>1 小时）
2. 工作时间计算溢出
3. 系统时间调整

### 改进建议
1. 添加分钟/小时显示（如 "5m 30s"）
2. 添加进度指示（如果可预测）
3. 支持自定义状态文本
4. 添加动画效果（旋转器等）
