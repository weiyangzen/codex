# 快照研究文档: footer_active_agent_label

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__footer__tests__footer_active_agent_label.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **测试函数**: `footer_snapshots`
- **表达式**: `terminal.backend()`
- **断言行**: 1207

---

## 场景与职责

### 功能场景
此快照捕获了**底部栏显示活跃Agent标签**的状态。当用户正在与特定的AI Agent（如"Robie [explorer]"）交互时，底部栏会显示当前活跃的Agent标识。

### 业务职责
1. **上下文提示**: 告知用户当前正在与哪个Agent交互
2. **多Agent区分**: 在多Agent场景下帮助用户识别当前对话对象
3. **状态展示**: 作为底部栏的被动上下文信息（passive footer context）

### 显示条件
- `active_agent_label` 有值（如 "Robie [explorer]"）
- `status_line_enabled` 为 false（否则status line优先）
- 当前模式允许显示被动上下文（`shows_passive_footer_line` 返回 true）

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| Agent标签显示 | 标识当前Agent | `FooterProps.active_agent_label` |
| 上下文百分比 | 显示剩余上下文 | `context_window_line()` 显示 "100% context left" |
| 左侧缩进 | 统一视觉风格 | `FOOTER_INDENT_COLS` (2空格) |

### UI布局
```
"  Robie [explorer]                                           100% context left  "
  └─ 2空格缩进  └─ Agent标签 ───────────────────────────────  └─ 右侧上下文信息
```

### 与Status Line的关系
```rust
pub(crate) fn passive_footer_status_line(props: &FooterProps) -> Option<Line<'static>> {
    if !shows_passive_footer_line(props) {
        return None;
    }

    let mut line = if props.status_line_enabled {
        props.status_line_value.clone()  // Status line 优先
    } else {
        None
    };

    if let Some(active_agent_label) = props.active_agent_label.as_ref() {
        if let Some(existing) = line.as_mut() {
            existing.spans.push(" · ".into());
            existing.spans.push(active_agent_label.clone().into());
        } else {
            line = Some(Line::from(active_agent_label.clone()));  // 仅显示Agent标签
        }
    }

    line
}
```

---

## 具体技术实现

### FooterProps定义
```rust
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) esc_backtrack_hint: bool,
    pub(crate) use_shift_enter_hint: bool,
    pub(crate) is_task_running: bool,
    pub(crate) collaboration_modes_enabled: bool,
    pub(crate) is_wsl: bool,
    pub(crate) quit_shortcut_key: KeyBinding,
    pub(crate) context_window_percent: Option<i64>,
    pub(crate) context_window_used_tokens: Option<i64>,
    pub(crate) status_line_value: Option<Line<'static>>,
    pub(crate) status_line_enabled: bool,
    pub(crate) active_agent_label: Option<String>,  // <-- 本快照测试的字段
}
```

### 测试配置
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    esc_backtrack_hint: false,
    use_shift_enter_hint: false,
    is_task_running: false,
    collaboration_modes_enabled: false,
    is_wsl: false,
    quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
    context_window_percent: None,
    context_window_used_tokens: None,
    status_line_value: None,
    status_line_enabled: false,  // <-- 禁用status line
    active_agent_label: Some("Robie [explorer]".to_string()),  // <-- 设置Agent标签
};
```

### 渲染流程
1. `shows_passive_footer_line(props)` 返回 true（ComposerEmpty模式）
2. `passive_footer_status_line(props)` 生成 "Robie [explorer]"
3. `context_window_line()` 生成右侧 "100% context left"
4. `render_context_right()` 将上下文信息右对齐

---

## 关键代码路径与文件引用

### 主要代码位置
| 文件 | 行号范围 | 功能 |
|------|----------|------|
| `footer.rs` | 66-87 | `FooterProps` 结构体定义 |
| `footer.rs` | 638-659 | `passive_footer_status_line()` |
| `footer.rs` | 848-860 | `context_window_line()` |
| `footer.rs` | 529-554 | `render_context_right()` |

### 测试代码位置
- **测试代码**: `footer.rs` 第 1634-1649 行
```rust
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    // ...
    status_line_enabled: false,
    active_agent_label: Some("Robie [explorer]".to_string()),
};

snapshot_footer("footer_active_agent_label", props);
```

### 相关快照
- `footer_status_line_with_active_agent_label`: Status line和Agent标签同时显示

---

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `crate::status::format_tokens_compact` | 格式化token数量 |
| `crate::ui_consts::FOOTER_INDENT_COLS` | 底部栏缩进常量（2） |
| `crate::render::line_utils::prefix_lines` | 行前缀处理 |

### 渲染流程
```
FooterProps
    ↓
passive_footer_status_line() 或 footer_from_props_lines()
    ↓
render_footer_line() / render_footer_from_props()
    ↓
prefix_lines() 添加缩进
    ↓
Paragraph::new().render()
```

---

## 风险边界与改进建议

### 潜在风险

#### 1. 标签长度风险
- **问题**: Agent标签可能很长，导致与右侧上下文重叠
- **当前处理**: 左侧内容优先，右侧可能被隐藏
- **建议**: 考虑标签截断或最大长度限制

#### 2. 与Status Line的互斥
- **问题**: 当 `status_line_enabled` 为 true 时，Agent标签作为后缀附加
- **潜在问题**: 组合后的内容可能过长
- **建议**: 添加组合长度检查

#### 3. 特殊字符处理
- **问题**: Agent标签可能包含特殊字符（如本例中的方括号）
- **当前处理**: 直接显示，无转义
- **建议**: 确保标签内容经过清理

### 改进建议

#### 1. 标签长度限制
```rust
const MAX_AGENT_LABEL_LEN: usize = 30;

fn truncate_agent_label(label: &str) -> String {
    if label.len() > MAX_AGENT_LABEL_LEN {
        format!("{}...", &label[..MAX_AGENT_LABEL_LEN])
    } else {
        label.to_string()
    }
}
```

#### 2. 标签格式化
```rust
// 建议: 统一标签格式
fn format_agent_label(name: &str, role: &str) -> String {
    format!("{} [{}]", name, role)
}
```

#### 3. 可点击标签
```rust
// 建议: 使Agent标签可点击，快速切换Agent
Line::from(vec![
    active_agent_label.clone().cyan().underlined().into(),
    " (click to switch)".dim().into(),
])
```

### 测试覆盖分析
- ✅ 基础Agent标签显示测试
- ✅ 与Status Line组合显示测试（`footer_status_line_with_active_agent_label`）
- ⚠️ 建议添加: 长标签截断测试
- ⚠️ 建议添加: 特殊字符处理测试
