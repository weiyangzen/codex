# Research: request_user_input_long_option_text.snap (tui_app_server)

## 场景与职责

本快照文件是 `codex-tui-app-server` crate 中 `request_user_input` 模块的 insta 快照测试结果，验证超长选项文本的自动换行和渲染行为。

## 功能点目的

### 测试目标
验证当选项文本长度超过可用宽度时，文本能够正确换行显示，且描述文本与标签对齐。

### 快照内容分析
```
Question 1/1 (1 unanswered)                                                                                           
Choose one option.                                                                                                    
                                                                                                                      
› 1. Job: running/completed/failed/expired; Run/Experiment: succeeded/failed/    Keep async job statuses for          
     unknown (Recommended when triaging long-running background work and status  progress tracking and include        
     transitions)                                                                enough context for debugging          
                                                                                  retries, stale workers, and          
                                                                                  unexpected expiration paths.         
    2. Add a short status model                                                    Simpler labels with less detail for  
                                                                                   quick rollouts.                      
                                                                                                                      
tab to add notes | enter to submit answer | esc to interrupt
```

关键观察点：
1. **标签换行**: 第一个选项的标签被分成3行显示
2. **描述对齐**: 描述文本与标签的第二行对齐（有缩进）
3. **视觉层次**: 使用缩进区分标签和描述，保持可读性

## 具体技术实现

### 选项行构建

`option_rows()` 方法:
```rust
pub(super) fn option_rows(&self) -> Vec<GenericDisplayRow> {
    // ...
    let mut rows = options
        .iter()
        .enumerate()
        .map(|(idx, opt)| {
            let selected = selected_idx.is_some_and(|sel| sel == idx);
            let prefix = if selected { '›' } else { ' ' };
            let label = opt.label.as_str();
            let number = idx + 1;
            let prefix_label = format!("{prefix} {number}. ");
            let wrap_indent = UnicodeWidthStr::width(prefix_label.as_str());
            GenericDisplayRow {
                name: format!("{prefix_label}{label}"),
                description: Some(opt.description.clone()),
                wrap_indent: Some(wrap_indent),  // 关键：设置换行缩进
                ..Default::default()
            }
        })
        .collect::<Vec<_>>();
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/request_user_input/mod.rs` | `option_rows()` 构建选项行 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | `GenericDisplayRow` 定义和渲染 |

## 风险、边界与改进建议

### 潜在风险
1. **极端长度**: 如果选项标签或描述极长，可能占用过多屏幕空间
2. **CJK 字符**: 中日韩字符宽度计算可能不准确

### 改进建议
1. **最大行数限制**: 限制每个选项的最大显示行数
2. **截断指示**: 超长文本显示省略号(...)并提供展开机制
