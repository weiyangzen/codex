# 快照研究文档: Chat Composer - Small Input State

## 基本信息
- **快照文件名**: `codex_tui__bottom_pane__chat_composer__tests__small.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **测试函数**: `small_snapshot`
- **对应结构体**: `ChatComposer`

---

## 1. 场景与职责

### 1.1 功能场景
此快照展示了**Chat Composer的小型输入状态**，当用户输入少量文本时的界面显示。具体场景包括：
- 用户输入简短查询（如"short"）
- 测试基本的文本输入和显示功能
- 验证输入后的Footer显示

### 1.2 业务职责
- **文本显示**: 正确显示用户输入的文本
- **焦点指示**: 保持输入焦点指示
- **Footer更新**: 根据输入状态更新Footer提示

---

## 2. 功能点目的

### 2.1 核心功能
| 功能 | 说明 |
|------|------|
| 文本输入 | 显示用户输入的"short" |
| 焦点指示 | `›`前缀表示输入框有焦点 |
| Footer显示 | 右侧显示"100% context left" |

### 2.2 与Empty状态的区别
| 特性 | Empty状态 | Small Input状态 |
|------|----------|----------------|
| 显示内容 | 占位符 | 实际输入文本 |
| Footer左侧 | "? for shortcuts" | 空（输入时隐藏提示） |
| 光标位置 | 占位符后 | 输入文本后 |

---

## 3. 具体技术实现

### 3.1 文本插入
```rust
fn insert_str(&mut self, s: &str) {
    self.textarea.insert_str(s);
    self.sync_popups();
}
```

### 3.2 渲染逻辑
```rust
// 有输入时不显示占位符
if self.textarea.is_empty() {
    // 显示占位符
} else {
    // 显示实际文本
    self.textarea.render(textarea_rect, buf, state);
}
```

### 3.3 Footer隐藏逻辑
```rust
// 当用户开始输入时，Footer提示可能被隐藏或改变
fn should_show_shortcut_hint(&self) -> bool {
    self.textarea.is_empty() && !self.is_task_running
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试代码
```rust
#[test]
fn small_snapshot() {
    let (tx, _rx) = unbounded_channel();
    let mut composer = ChatComposer::new(
        true,
        AppEventSender::new(tx),
        true,
        "Ask Codex to do anything".to_string(),
        true,
    );
    
    // 输入"short"
    composer.textarea.insert_str("short");
    
    let mut terminal = Terminal::new(TestBackend::new(100, 10)).unwrap();
    terminal.draw(|frame| {
        composer.render(frame.area(), frame.buffer_mut());
    }).unwrap();
    
    assert_snapshot!("small", terminal.backend());
}
```

---

## 5. 依赖与外部交互

### 5.1 TextArea组件
- 处理文本输入和显示
- 管理光标位置
- 支持多行输入

---

## 6. 风险边界与改进建议

### 6.1 边界情况
- 单字符输入
- 特殊字符输入
- 快速连续输入

### 6.2 改进建议
- 添加输入字符计数显示
- 支持输入预览（如Markdown渲染预览）
