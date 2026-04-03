# UserHistoryCell 单张远程图片渲染测试

## 场景与职责

该快照测试验证 `UserHistoryCell` 在处理包含单张远程图片的用户输入时的渲染行为。这是多模态对话中最常见的场景——用户上传一张图片并附带描述性文本。

测试确保：
1. 单张远程图片正确显示为 `[Image #1]` 标签
2. 用户文本消息与图片标签正确混排
3. 视觉格式符合设计规范

## 功能点目的

### 核心功能
- **单图片标签化**：将单个远程图片URL转换为 `[Image #1]` 标签
- **图文关联**：将图片标签与用户描述文本一起展示，表明文本是对图片的描述/提问

### 测试场景
测试用例模拟用户发送一张图片并请求描述：
```rust
UserHistoryCell {
    message: "describe these".to_string(),
    text_elements: Vec::new(),
    local_image_paths: Vec::new(),
    remote_image_urls: vec!["https://example.com/example.png".to_string()],
}
```

## 具体技术实现

### 渲染流程

1. **图片列表处理**（第299-312行）：
   ```rust
   let wrapped_remote_images = if self.remote_image_urls.is_empty() {
       None
   } else {
       Some(adaptive_wrap_lines(
           self.remote_image_urls
               .iter()
               .enumerate()
               .map(|(idx, _url)| {
                   remote_image_display_line(element_style, idx.saturating_add(1))
               }),
           // ...
       ))
   };
   ```

2. **标签生成**：
   - 使用 `enumerate()` 获取索引
   - `idx.saturating_add(1)` 转换为1-based编号
   - `local_image_label_text(index)` 生成 `[Image #1]` 文本

3. **样式应用**：
   ```rust
   let element_style = style.fg(Color::Cyan);
   ```
   图片标签使用青色（Cyan）前景色，与用户消息的默认样式区分

### 快照输出解析
```
  [Image #1]

› describe these
```

- 图片标签缩进：2个空格
- 标签与消息间：空行分隔
- 消息前缀：`› `（粗体+暗淡）

## 关键代码路径与文件引用

### 核心代码
| 位置 | 描述 |
|-----|------|
| `history_cell.rs:199-206` | `UserHistoryCell` 结构体定义 |
| `history_cell.rs:274-276` | `remote_image_display_line` 辅助函数 |
| `history_cell.rs:288-372` | `HistoryCell` trait 实现 |
| `history_cell.rs:348-370` | 行组装逻辑 |

### 测试代码
- 位置：`history_cell.rs:3860-3873`
- 函数：`user_history_cell_renders_remote_image_urls`
- 断言：
  ```rust
  assert!(rendered.contains("[Image #1]"));
  assert!(rendered.contains("describe these"));
  ```

## 依赖与外部交互

### 样式系统
```rust
fn user_message_style() -> Style {
    Style::default() // 默认样式
}

let element_style = style.fg(Color::Cyan); // 图片标签使用青色
```

### 换行处理
- 使用 `adaptive_wrap_lines` 处理可能的超长内容
- 即使单张图片通常不会换行，仍统一使用换行逻辑

## 风险、边界与改进建议

### 当前限制
1. **Data URL处理**：测试用例使用HTTPS URL，但代码也支持Data URL（`data:image/png;base64,...`）
   - 相关测试：`user_history_cell_summarizes_inline_data_urls`

2. **本地图片与远程图片**：
   - `local_image_paths`：本地文件路径（当前测试未覆盖）
   - `remote_image_urls`：远程URL（当前测试覆盖）

### 改进建议

1. **添加图片类型指示**
   ```rust
   // 当前: [Image #1]
   // 建议: [📷 Image #1] 或 [🖼️ Image #1]
   ```

2. **支持图片尺寸信息**
   - 如果URL包含尺寸信息，可在标签中显示
   - 例如：`[Image #1 (1920x1080)]`

3. **URL来源提示**
   - 对于不同来源的图片使用不同颜色或图标
   - HTTP vs HTTPS vs Data URL

### 相关测试
| 测试名称 | 描述 |
|---------|------|
| `user_history_cell_numbers_multiple_remote_images` | 多张图片 |
| `user_history_cell_summarizes_inline_data_urls` | Data URL |
| `user_history_cell_height_matches_rendered_lines_with_remote_images` | 高度计算 |
