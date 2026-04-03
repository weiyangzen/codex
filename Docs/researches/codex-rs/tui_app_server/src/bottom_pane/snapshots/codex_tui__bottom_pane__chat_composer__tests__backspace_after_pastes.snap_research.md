# Chat Composer Backspace After Pastes Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui` crate 中 `chat_composer` 模块的测试快照，记录了**粘贴内容后执行退格操作**的 UI 状态。此测试验证了粘贴大内容后的占位符显示和退格操作的正确性。

### 业务场景
- 用户粘贴大量内容（超过 1000 字符阈值）
- 系统显示占位符 `[Pasted Content N chars]` 而非实际内容
- 用户执行退格操作删除部分占位符

## 功能点目的

### 核心功能
1. **大粘贴内容处理**：超过阈值的内容显示为占位符
2. **占位符管理**：多个粘贴内容分别显示为独立占位符
3. **退格操作**：正确处理占位符的删除

### UI 设计特点
- 占位符格式：`[Pasted Content {count} chars]`
- 多个占位符连续显示
- 底部显示上下文剩余百分比

## 具体技术实现

### 大粘贴阈值
```rust
/// If the pasted content exceeds this number of characters, replace it with a
/// placeholder in the UI.
const LARGE_PASTE_CHAR_THRESHOLD: usize = 1000;
```

### 粘贴处理逻辑
```rust
pub fn handle_paste(&mut self, pasted: String) -> bool {
    let pasted = pasted.replace("\r\n", "\n").replace('\r', "\n");
    let char_count = pasted.chars().count();
    
    if char_count > LARGE_PASTE_CHAR_THRESHOLD {
        // 大粘贴：创建占位符
        let placeholder = self.next_large_paste_placeholder(char_count);
        self.textarea.insert_element(&placeholder);
        self.pending_pastes.push((placeholder, pasted));
    } else if char_count > 1
        && self.image_paste_enabled()
        && self.handle_paste_image_path(pasted.clone())
    {
        // 图片路径：附加图片
        self.textarea.insert_str(" ");
    } else {
        // 普通粘贴：直接插入
        self.insert_str(&pasted);
    }
    
    self.paste_burst.clear_after_explicit_paste();
    self.sync_popups();
    true
}
```

### 占位符生成
```rust
fn next_large_paste_placeholder(&mut self, char_count: usize) -> String {
    let counter = self.large_paste_counters.entry(char_count).or_insert(0);
    *counter += 1;
    format!("[Pasted Content {char_count} chars]")
}
```

### 退格处理
```rust
// 退格操作由 TextArea 组件处理
// 占位符作为单个元素，退格会删除整个占位符
```

## 关键代码路径与文件引用

### 主要源文件
- `codex-rs/tui/src/bottom_pane/chat_composer.rs` - 原始 TUI 实现
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` - tui_app_server 实现

### 关键方法
| 方法 | 文件 | 职责 |
|------|------|------|
| `handle_paste()` | chat_composer.rs:776 | 处理粘贴内容 |
| `next_large_paste_placeholder()` | chat_composer.rs:XXX | 生成大粘贴占位符 |
| `current_text_with_pending()` | chat_composer.rs:925 | 获取包含待处理粘贴的完整文本 |

## 依赖与外部交互

### 数据结构
```rust
struct ChatComposer {
    pending_pastes: Vec<(String, String)>,  // (placeholder, actual_content)
    large_paste_counters: HashMap<usize, usize>,
    // ...
}
```

### 提交时处理
```rust
pub(crate) fn current_text_with_pending(&self) -> String {
    let mut text = self.textarea.text().to_string();
    for (placeholder, actual) in &self.pending_pastes {
        if text.contains(placeholder) {
            text = text.replace(placeholder, actual);
        }
    }
    text
}
```

## 风险、边界与改进建议

### 潜在风险
1. **占位符冲突**：占位符格式可能与用户输入冲突
2. **内存占用**：pending_pastes 可能积累大量内容

### 边界情况
1. **空粘贴**：处理空字符串粘贴
2. **重复粘贴**：相同内容的多次粘贴

### 改进建议
1. **占位符唯一性**：使用 UUID 确保占位符唯一
2. **内容清理**：定期清理不再需要的 pending_pastes
3. **粘贴预览**：提供查看粘贴内容的快捷方式

### 相关测试
- `backspace_after_pastes` - 本快照对应的测试
- `multiple_pastes` - 多次粘贴测试
- `large` - 大粘贴测试
