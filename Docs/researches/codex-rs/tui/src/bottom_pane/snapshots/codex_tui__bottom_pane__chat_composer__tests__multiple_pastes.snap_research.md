# 快照研究文档: Chat Composer - Multiple Pastes

## 基本信息
- **快照文件名**: `codex_tui__bottom_pane__chat_composer__tests__multiple_pastes.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- **测试函数**: `multiple_pastes_snapshot`
- **对应结构体**: `ChatComposer`

---

## 1. 场景与职责

### 1.1 功能场景
此快照展示了**多次粘贴后的界面状态**，包含大粘贴占位符和普通文本的混合。具体场景包括：
- 用户多次粘贴内容
- 混合大粘贴（占位符）和小粘贴（直接文本）
- 在粘贴内容后添加普通文本

### 1.2 业务职责
- **混合显示**: 正确处理占位符和普通文本的混合
- **顺序保持**: 保持粘贴和输入的顺序
- **内容追踪**: 维护多个pending_pastes条目

---

## 2. 功能点目的

### 2.1 核心功能
| 功能 | 说明 |
|------|------|
| 多占位符 | 两个大粘贴占位符 |
| 混合文本 | 占位符后跟随普通文本 |
| 顺序保持 | 按粘贴/输入顺序显示 |

### 2.2 显示内容
```
› [Pasted Content 1003 chars][Pasted Content 1007 chars] another short paste
```

---

## 3. 具体技术实现

### 3.1 pending_pastes管理
```rust
pub(crate) struct ChatComposer {
    pending_pastes: Vec<(String, String)>,  // 多个粘贴内容
}
```

### 3.2 混合渲染
- 占位符作为特殊元素渲染
- 普通文本正常显示
- 两者在textarea中顺序排列

---

## 4. 关键代码路径

### 4.1 测试逻辑
```rust
#[test]
fn multiple_pastes_snapshot() {
    composer.handle_paste("a".repeat(1003));  // 大粘贴1
    composer.handle_paste("b".repeat(1007));  // 大粘贴2
    composer.textarea.insert_str(" another short paste");  // 普通文本
}
```

---

## 5. 风险边界

### 5.1 边界情况
- 多个相同大小的粘贴区分
- 占位符和普通文本的光标移动
- 部分删除混合内容
