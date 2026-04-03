# 快照研究文档: footer_esc_hint_idle

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__footer__tests__footer_esc_hint_idle.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **测试函数**: `footer_snapshots`
- **表达式**: `terminal.backend()`

---

## 场景与职责

### 功能场景
此快照捕获了**空闲状态下首次按Esc后的提示**。当用户在空闲状态按下Esc键时，底部栏显示"再次按Esc编辑上一条消息"的提示，引导用户使用Esc键快速编辑历史消息。

### 业务职责
1. **快捷键发现**: 帮助用户发现Esc键的编辑功能
2. **操作引导**: 引导用户按两次Esc进入编辑模式
3. **防误触**: 需要按两次Esc才触发编辑，防止意外编辑

### 触发条件
- `mode: FooterMode::EscHint` - Esc提示模式
- `esc_backtrack_hint: false` - 未启用回退提示（需要按两次Esc）
- `is_task_running: false` - 空闲状态（运行中不显示Esc提示）

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| Esc提示 | 提示按两次Esc编辑 | `esc_hint_line()` |
| 双Esc显示 | 显示两次Esc按键 | `"esc esc"` |
| 功能说明 | 说明Esc键用途 | "to edit previous message" |

### UI内容
```
"  esc esc to edit previous message                                              "
  └─ 2空格缩进  └─ 双Esc提示 ────────────────────────────────────────────────────
```

### Esc编辑流程
```
用户按Esc（空闲状态）
    ↓
显示 "esc esc to edit previous message"
    ↓
用户再次按Esc → 进入上一条消息编辑模式
用户按其他键 → 取消提示
```

---

## 具体技术实现

### Esc提示生成
```rust
fn esc_hint_line(esc_backtrack_hint: bool) -> Line<'static> {
    let esc = key_hint::plain(KeyCode::Esc);
    if esc_backtrack_hint {
        Line::from(vec![esc.into(), " again to edit previous message".into()]).dim()
    } else {
        Line::from(vec![
            esc.into(),
            " ".into(),
            esc.into(),  // <-- 显示两次Esc
            " to edit previous message".into(),
        ]).dim()
    }
}
```

### FooterMode定义
```rust
pub(crate) enum FooterMode {
    // ...
    EscHint,  // <-- 本快照测试的模式
    // ...
}
```

### 测试配置
```rust
snapshot_footer(
    "footer_esc_hint_idle",
    FooterProps {
        mode: FooterMode::EscHint,  // <-- Esc提示模式
        esc_backtrack_hint: false,  // <-- 需要按两次Esc
        use_shift_enter_hint: false,
        is_task_running: false,  // <-- 空闲状态
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: None,
        context_window_used_tokens: None,
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

### 模式进入逻辑
```rust
pub(crate) fn esc_hint_mode(current: FooterMode, is_task_running: bool) -> FooterMode {
    if is_task_running {
        current  // 运行中不改变模式
    } else {
        FooterMode::EscHint  // 空闲时进入Esc提示模式
    }
}
```

---

## 关键代码路径与文件引用

### 主要代码位置
| 文件 | 行号范围 | 功能 |
|------|----------|------|
| `footer.rs` | 137-138 | `FooterMode::EscHint` 定义 |
| `footer.rs` | 735-748 | `esc_hint_line()` 函数 |
| `footer.rs` | 169-175 | `esc_hint_mode()` 函数 |
| `footer.rs` | 616 | EscHint 模式处理 |

### 测试代码位置
- **测试代码**: `footer.rs` 第 1351-1367 行

---

## 依赖与外部交互

### 事件流
```
用户按Esc（空闲状态）
    ↓
ChatComposer 处理
    ↓
设置 mode = FooterMode::EscHint
    ↓
启动定时器
    ↓
渲染 "esc esc to edit previous message"
    ↓
用户再次按Esc → 进入编辑模式
或用户按其他键 → 重置模式
```

### 与回退提示的区别
| esc_backtrack_hint | 显示内容 |
|-------------------|----------|
| false | "esc esc to edit previous message" |
| true | "esc again to edit previous message" |

---

## 风险边界与改进建议

### 潜在风险

#### 1. 双Esc不易发现
- **问题**: 用户可能不理解为什么要按两次Esc
- **建议**: 添加更明确的说明或动画

#### 2. 与Vim模式的混淆
- **问题**: 习惯Vim的用户可能期望Esc进入正常模式
- **建议**: 考虑添加Vim兼容模式配置

### 改进建议

#### 1. 添加快捷键图标
```rust
Line::from(vec![
    "⏎ ".dim().into(),  // 返回图标
    esc.into(),
    " ".into(),
    esc.into(),
    " to edit previous".into(),
])
```

#### 2. 添加上一条消息预览
```rust
// 建议: 显示将要编辑的消息预览
fn esc_hint_line(esc_backtrack_hint: bool, previous_msg: &str) -> Line<'static> {
    let preview = if previous_msg.len() > 20 {
        format!("{}...", &previous_msg[..20])
    } else {
        previous_msg.to_string()
    };
    Line::from(vec![
        esc.into(),
        " ".into(),
        esc.into(),
        format!(" to edit: '{}'", preview).into(),
    ]).dim()
}
```

### 测试覆盖分析
- ✅ 空闲状态Esc提示测试
- ✅ 回退提示测试（`footer_esc_hint_primed`）
- ⚠️ 建议添加: 编辑模式进入测试
