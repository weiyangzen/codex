# Chat Composer Multiple Pastes Snapshot 研究文档

## 场景与职责

该快照文件测试了聊天编辑器在**多次粘贴大内容**后的显示状态。展示了多个大粘贴占位符同时存在的情况。

### 业务场景
- 用户多次粘贴大内容（超过 1000 字符）
- 每次粘贴创建独立的占位符
- 占位符按顺序排列在输入框中

## 功能点目的

### 核心功能
1. **多占位符管理**：支持多个大粘贴占位符
2. **独立计数**：每个占位符显示自己的字符数
3. **顺序保留**：保持粘贴的先后顺序

### UI 设计特点
- 多个占位符连续显示：`[Pasted Content 1003 chars][Pasted Content 1007 chars] another short paste`
- 占位符后可跟随普通文本
- 底部显示上下文剩余百分比

## 具体技术实现

### 大粘贴处理
```rust
const LARGE_PASTE_CHAR_THRESHOLD: usize = 1000;

pub fn handle_paste(&mut self, pasted: String) -> bool {
    let pasted = pasted.replace("\r\n", "\n").replace('\r', "\n");
    let char_count = pasted.chars().count();
    
    if char_count > LARGE_PASTE_CHAR_THRESHOLD {
        let placeholder = self.next_large_paste_placeholder(char_count);
        self.textarea.insert_element(&placeholder);
        self.pending_pastes.push((placeholder, pasted));
    } else {
        self.insert_str(&pasted);
    }
    // ...
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

### 数据结构
```rust
pub(crate) struct ChatComposer {
    pending_pastes: Vec<(String, String)>,  // (placeholder, content)
    large_paste_counters: HashMap<usize, usize>,  // char_count -> occurrence_count
    // ...
}
```

## 关键代码路径

### 主要源文件
- `codex-rs/tui/src/bottom_pane/chat_composer.rs`

### 相关测试
- `multiple_pastes` - 本快照
- `backspace_after_pastes` - 粘贴后退格
- `large` - 单个大粘贴
