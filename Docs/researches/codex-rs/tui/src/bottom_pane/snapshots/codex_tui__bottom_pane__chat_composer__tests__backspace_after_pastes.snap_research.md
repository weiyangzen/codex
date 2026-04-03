# ChatComposer Backspace After Pastes 快照研究文档

## 场景与职责

该快照测试验证ChatComposer在处理大型粘贴内容后，执行退格操作时的UI渲染状态。测试场景包括：
- 模拟用户粘贴超过1000字符的大型内容（触发占位符机制）
- 粘贴多个大型内容片段
- 执行退格操作后的渲染状态

此测试确保粘贴占位符（`[Pasted Content N chars]`）在编辑操作后能正确显示，且页脚区域（footer）的上下文信息（如"100% context left"）保持正确渲染。

## 功能点目的

1. **大型粘贴占位符机制**：当粘贴内容超过`LARGE_PASTE_CHAR_THRESHOLD`（1000字符）时，不直接插入文本，而是插入占位符元素，实际内容存储在`pending_pastes`中
2. **退格键处理**：验证退格操作能正确处理占位符元素，保持UI一致性
3. **页脚上下文显示**：即使在编辑状态下，页脚右侧的上下文信息（如上下文窗口剩余百分比）仍需正确显示

## 具体技术实现

### 关键数据结构

```rust
// 大型粘贴占位符阈值
const LARGE_PASTE_CHAR_THRESHOLD: usize = 1000;

// ChatComposer中的相关字段
struct ChatComposer {
    pending_pastes: Vec<(String, String)>,  // (placeholder, actual_content)
    large_paste_counters: HashMap<usize, usize>, // 计数器用于生成唯一占位符
    // ...
}
```

### 关键流程

1. **粘贴处理流程**（`handle_paste`方法）：
   - 检查字符数是否超过阈值
   - 生成占位符：`[Pasted Content {char_count} chars]`
   - 将占位符插入textarea作为元素
   - 将实际内容存入`pending_pastes`

2. **占位符生成**（`next_large_paste_placeholder`方法）：
   - 基础格式：`[Pasted Content {char_count} chars]`
   - 如果有重复，添加后缀：`#{counter}`

3. **页脚渲染**：
   - 通过`footer_props()`获取页脚属性
   - 使用`context_window_line`生成右侧上下文显示

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 相关功能 |
|---------|---------|
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 主实现文件，包含粘贴处理和页脚渲染逻辑 |
| `codex-rs/tui/src/bottom_pane/footer.rs` | 页脚渲染辅助函数 |

### 关键代码位置

1. **粘贴处理逻辑**（chat_composer.rs:776-798）：
   ```rust
   pub fn handle_paste(&mut self, pasted: String) -> bool {
       // ... 处理逻辑
       if char_count > LARGE_PASTE_CHAR_THRESHOLD {
           let placeholder = self.next_large_paste_placeholder(char_count);
           self.textarea.insert_element(&placeholder);
           self.pending_pastes.push((placeholder, pasted));
       }
       // ...
   }
   ```

2. **页脚属性构建**（chat_composer.rs:3179-3206）：
   ```rust
   fn footer_props(&self) -> FooterProps {
       // ... 构建FooterProps
   }
   ```

3. **上下文行生成**（footer.rs:848-860）：
   ```rust
   pub(crate) fn context_window_line(percent: Option<i64>, used_tokens: Option<i64>) -> Line<'static>
   ```

## 依赖与外部交互

### 依赖模块

- `codex_protocol::user_input`：TextElement类型定义
- `ratatui`：终端UI渲染
- `crossterm`：键盘事件处理

### 测试辅助函数

```rust
fn snapshot_composer_state_with_width<F>(
    name: &str,
    width: u16,
    enhanced_keys_supported: bool,
    setup: F,
)
```

## 风险、边界与改进建议

### 潜在风险

1. **占位符同步问题**：如果`pending_pastes`与textarea中的占位符不同步，可能导致提交时内容丢失
2. **内存累积**：大量大型粘贴操作可能累积大量pending内容，需要确保及时清理
3. **宽度计算**：占位符显示宽度与实际内容宽度差异可能导致布局问题

### 边界情况

- 粘贴内容恰好为1000字符时的处理
- 多个相同大小的粘贴内容的占位符命名冲突
- 退格操作删除占位符时的清理逻辑

### 改进建议

1. **添加占位符数量限制**：防止内存无限增长
2. **优化占位符显示**：考虑显示更友好的摘要信息
3. **增强测试覆盖**：添加边界值测试（如恰好1000字符的粘贴）
4. **文档化占位符机制**：在用户文档中说明大型粘贴的行为

### 相关测试

- `multiple_pastes`：测试多个粘贴内容的处理
- `image_placeholder_single/multiple`：测试图片占位符
- `large`：测试大型内容的整体渲染
