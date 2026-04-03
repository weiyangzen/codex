# status_and_composer_fill_height_without_bottom_padding Snapshot 研究文档

## 场景与职责

本快照测试展示了 `BottomPane` 在**状态指示器和 Composer 填充可用高度**时的渲染行为，验证底部没有多余的 padding，确保空间利用最大化。

**典型使用场景**：
- 底部面板高度刚好匹配内容需求
- 验证布局算法不会产生多余的空白
- 紧凑界面下的空间优化

## 功能点目的

该测试验证以下核心功能：

1. **高度填充**：状态指示器和 Composer 正确填充可用高度
2. **无底部 Padding**：底部没有多余的空白行
3. **紧凑布局**：空间利用最大化
4. **高度计算准确性**：`desired_height()` 返回正确的高度值

**渲染输出特征**：
```
• Working (0s • esc to interr…          <- 状态指示器（截断）
                                        <- 空行
                                        <- 空行（flex 空间）
› Ask Codex to do anything              <- Composer 输入框
                                        <- 空行
           100% context left            <- 底部状态栏
```

## 具体技术实现

### 测试设置
```rust
#[test]
fn status_and_composer_fill_height_without_bottom_padding() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let mut pane = BottomPane::new(BottomPaneParams {
        // ... 参数初始化
    });

    // 激活 spinner（状态视图替换 composer）
    pane.set_task_running(true);

    // 使用 height == desired_height；期望渲染 spacer + status + composer 行
    // 没有尾部 padding
    let height = pane.desired_height(30);
    assert!(
        height >= 3,
        "expected at least 3 rows to render spacer, status, and composer; got {height}"
    );
    let area = Rect::new(0, 0, 30, height);
    assert_snapshot!("status_and_composer_fill_height_without_bottom_padding", 
                     render_snapshot(&pane, area));
}
```

### Flex 布局逻辑
```rust
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    let mut flex = FlexRenderable::new();
    
    // 状态指示器（flex: 0，固定高度）
    if let Some(status) = &self.status {
        flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
    }
    
    // 空行分隔（flex: 0）
    if has_inline_previews && has_status_or_footer {
        flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
    }
    
    // Composer（flex: 0，固定高度）
    let mut flex2 = FlexRenderable::new();
    flex2.push(/*flex*/ 1, RenderableItem::Owned(flex.into()));
    flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
}
```

### 高度计算验证
```rust
let height = pane.desired_height(30);
assert!(height >= 3, "expected at least 3 rows...");
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/mod.rs` - BottomPane 组件实现

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `status_and_composer_fill_height_without_bottom_padding` (test) | 1440-1468 | 本测试用例 |
| `set_task_running()` | 716-740 | 设置任务运行状态 |
| `desired_height()` | 1227-1229 | 计算所需高度 |
| `as_renderable()` | 1123-1167 | 主渲染逻辑 |

### 布局组件高度
| 组件 | flex 值 | 说明 |
|------|---------|------|
| StatusIndicatorWidget | 0 | 固定高度 |
| 空行分隔 | 0 | 固定 1 行 |
| PendingInputPreview | 1 | 占用剩余空间 |
| ChatComposer | 0 | 固定高度 |

## 依赖与外部交互

### 依赖模块
- `crate::render::renderable::FlexRenderable` - 弹性布局系统
- `crate::status_indicator_widget::StatusIndicatorWidget` - 状态指示器
- `crate::bottom_pane::chat_composer::ChatComposer` - 聊天输入框

### Flex 布局原理
- `flex: 0` - 组件使用其 `desired_height()` 返回的高度
- `flex: 1` - 组件占用所有剩余可用空间
- 多个 `flex: 1` 组件按比例分配剩余空间

## 风险、边界与改进建议

### 当前边界情况
1. **固定宽度**：测试使用 30 字符宽度
2. **最小高度**：验证高度 >= 3 行
3. **无排队消息**：测试中未设置排队消息

### 潜在风险
1. **高度变化**：内容变化可能导致高度计算不准确
2. **截断问题**：宽度 30 导致状态文本被截断
3. **布局抖动**：高度计算误差可能导致布局闪烁

### 改进建议
1. **动态高度**：根据内容动态调整 flex 分配
2. **最小高度保证**：确保关键组件不会被压缩到不可读
3. **响应式布局**：根据可用空间调整组件排列
4. **高度缓存**：缓存高度计算结果避免重复计算
5. **边界测试**：添加更多极端尺寸下的测试用例
