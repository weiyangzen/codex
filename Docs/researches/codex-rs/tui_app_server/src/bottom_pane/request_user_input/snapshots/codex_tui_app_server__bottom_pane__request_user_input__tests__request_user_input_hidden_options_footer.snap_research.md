# Research: request_user_input_hidden_options_footer.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证当选项列表部分被隐藏时的底部栏显示行为。

## 功能点目的

### 测试目标
验证当选项区域无法显示所有选项时，底部栏正确显示 `option X/Y` 格式的位置指示器。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                   
What would you like to do next?                                               
                                                                                
  2. Run tests      Pick a crate and run its tests.                           
  3. Review a diff  Summarize or review current changes.                      
› 4. Refactor       Tighten structure and remove dead code.                  
                                                                                
option 4/5 | tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **部分选项隐藏**: 只显示选项 2、3、4，选项 1 和 5 被隐藏
2. **位置指示器**: `option 4/5` 显示当前选中第4个选项，共5个
3. **选中状态**: `› 4. Refactor` 显示当前选中第4个选项

## 具体技术实现

### 选项隐藏检测逻辑

`render_ui()` 方法中的检测:
```rust
let options_hidden = self.has_options()
    && sections.options_area.height > 0
    && self.options_required_height(content_area.width) > sections.options_area.height;
let option_tip = if options_hidden {
    let selected = self.selected_option_index().unwrap_or(0).saturating_add(1);
    let total = self.options_len();
    Some(super::FooterTip::new(format!("option {selected}/{total}")))
} else {
    None
};
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/render.rs` | 检测选项是否被隐藏并生成位置提示 |
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | 选项高度计算 |

## 风险、边界与改进建议

### 潜在风险
1. **位置指示器精度**: 当选项文本长度差异大时，高度计算可能有偏差
2. **滚动状态同步**: 确保 `ScrollState` 的选中索引与实际渲染一致

### 改进建议
1. **进度条**: 用进度条替代文字指示器，更直观
2. **滚动动画**: 添加平滑滚动动画提升用户体验
