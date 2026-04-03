# 快照研究文档: Chat Composer - Large Paste State

## 基本信息
- **快照文件名**: `codex_tui__bottom_pane__chat_composer__tests__large.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **测试函数**: `large_snapshot`
- **对应结构体**: `ChatComposer`

---

## 1. 场景与职责

### 1.1 功能场景
此快照展示了**Chat Composer的大文本粘贴状态**，当用户粘贴超过1000字符的内容时显示的界面。具体场景包括：
- 用户粘贴大段代码
- 用户粘贴长文本内容
- 粘贴内容超过`LARGE_PASTE_CHAR_THRESHOLD`（1000字符）

### 1.2 业务职责
- **性能保护**: 避免在UI中渲染过大的文本
- **内容提示**: 通过占位符告知用户有粘贴内容
- **延迟展开**: 实际内容在提交时才展开

---

## 2. 功能点目的

### 2.1 核心功能
| 功能 | 说明 |
|------|------|
| 大文本检测 | 检测粘贴内容超过1000字符 |
| 占位符显示 | 显示"[Pasted Content 1005 chars]" |
| 内容存储 | 将实际内容存储在`pending_pastes`中 |
| 延迟展开 | 提交时才将占位符替换为实际内容 |

### 2.2 占位符格式
```
[Pasted Content <字符数> chars]
```

---

## 3. 具体技术实现

### 3.1 大粘贴阈值
```rust
/// If the pasted content exceeds this number of characters, replace it with a
/// placeholder in the UI.
const LARGE_PASTE_CHAR_THRESHOLD: usize = 1000;
```

### 3.2 粘贴处理逻辑
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
        // 图片路径粘贴
        self.textarea.insert_str(" ");
    } else {
        // 普通粘贴
        self.insert_str(&pasted);
    }
    // ...
}
```

### 3.3 占位符生成
```rust
fn next_large_paste_placeholder(&mut self, char_count: usize) -> String {
    let counter = self.large_paste_counters.entry(char_count).or_insert(0);
    *counter += 1;
    format!("[Pasted Content {} chars]", char_count)
}
```

### 3.4 提交时展开
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

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件
| 文件路径 | 作用 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 粘贴处理逻辑 |
| `codex-rs/tui/src/bottom_pane/textarea.rs` | 文本元素插入 |

### 4.2 数据结构
```rust
pub(crate) struct ChatComposer {
    pending_pastes: Vec<(String, String)>,  // (placeholder, actual_content)
    large_paste_counters: HashMap<usize, usize>,  // 计数器用于生成唯一占位符
}
```

---

## 5. 依赖与外部交互

### 5.1 文本元素系统
- 占位符作为特殊的文本元素插入
- 支持多个大粘贴内容
- 占位符可像普通文本一样编辑（删除、移动）

---

## 6. 风险边界与改进建议

### 6.1 潜在问题

| 问题 | 描述 | 建议 |
|------|------|------|
| 占位符冲突 | 多个相同大小的粘贴可能混淆 | 添加唯一标识符 |
| 内容丢失 | 占位符被删除后实际内容仍存储 | 添加同步清理逻辑 |
| 内存占用 | 大内容存储在内存中 | 考虑临时文件存储 |

### 6.2 改进建议

1. **占位符唯一化**
   ```rust
   fn next_large_paste_placeholder(&mut self, char_count: usize) -> String {
       let id = self.next_paste_id();
       format!("[Pasted Content #{}: {} chars]", id, char_count)
   }
   ```

2. **内容预览**
   ```rust
   // 添加悬停/快捷键预览功能
   fn preview_pasted_content(&self, placeholder: &str) -> &str {
       self.pending_pastes.iter()
           .find(|(p, _)| p == placeholder)
           .map(|(_, content)| &content[..100.min(content.len())])
   }
   ```
