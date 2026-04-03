# Footer Shortcuts - Shift and Esc 测试研究文档

## 场景与职责

### 测试场景
该快照测试验证快捷帮助覆盖层在以下条件下的显示：
- **Shift+Enter 提示启用**: 显示 "shift + enter for newline" 而非 "ctrl + j"
- **Esc 回退提示启用**: 显示 "esc again to edit previous message" 而非 "esc esc"

### 测试数据
- **模式**: `ShortcutOverlay`（快捷帮助覆盖层）
- **Esc 回退提示**: 启用 (`esc_backtrack_hint: true`)
- **Shift+Enter 提示**: 启用 (`use_shift_enter_hint: true`)
- **协作模式**: 禁用 (`collaboration_modes_enabled: false`)
- **WSL 环境**: 否 (`is_wsl: false`)

### 期望行为
快捷覆盖层应根据 `ShortcutsState` 中的标志显示不同的快捷键绑定。

---

## 功能点目的

### 核心功能
该测试验证快捷帮助系统的**条件绑定机制**：

1. **平台适配**: 根据终端能力选择最合适的快捷键（Shift+Enter vs Ctrl+J）
2. **状态感知**: 根据用户历史行为调整提示（Esc vs Esc Esc）
3. **动态内容**: 同一快捷方式在不同条件下显示不同绑定

### 业务价值
- **平台兼容性**: 支持不同终端的能力差异
- **用户体验**: 根据用户习惯调整提示
- **学习辅助**: 帮助用户了解当前有效的快捷键

### 快捷方式条件绑定
```
换行快捷键:
- 支持增强键: "shift + enter for newline"
- 不支持:     "ctrl + j for newline"

编辑上一条消息:
- 已按过 Esc: "esc again to edit previous message"
- 未按过:     "esc esc to edit previous message"
```

---

## 具体技术实现

### 关键代码路径

#### 1. 测试入口
```rust
// footer.rs:1279-1295
snapshot_footer(
    "footer_shortcuts_shift_and_esc",
    FooterProps {
        mode: FooterMode::ShortcutOverlay,
        esc_backtrack_hint: true,      // 启用 Esc 回退提示
        use_shift_enter_hint: true,    // 启用 Shift+Enter 提示
        is_task_running: false,
        collaboration_modes_enabled: false,
        is_wsl: false,
        // ...
    },
);
```

#### 2. 快捷方式状态
```rust
// footer.rs:723-729
#[derive(Clone, Copy, Debug)]
struct ShortcutsState {
    use_shift_enter_hint: bool,      // 控制换行快捷键显示
    esc_backtrack_hint: bool,        // 控制 Esc 提示显示
    is_wsl: bool,
    collaboration_modes_enabled: bool,
}
```

#### 3. 条件绑定定义
```rust
// footer.rs:962-976 (InsertNewline 快捷方式)
ShortcutDescriptor {
    id: ShortcutId::InsertNewline,
    bindings: &[
        ShortcutBinding {
            key: key_hint::shift(KeyCode::Enter),
            condition: DisplayCondition::WhenShiftEnterHint,  // 条件：启用 Shift+Enter
        },
        ShortcutBinding {
            key: key_hint::ctrl(KeyCode::Char('j')),
            condition: DisplayCondition::WhenNotShiftEnterHint,  // 条件：未启用
        },
    ],
    prefix: "",
    label: " for newline",
}
```

#### 4. 显示条件匹配
```rust
// footer.rs:889-908
enum DisplayCondition {
    Always,
    WhenShiftEnterHint,      // use_shift_enter_hint = true
    WhenNotShiftEnterHint,   // use_shift_enter_hint = false
    WhenUnderWSL,
    WhenCollaborationModesEnabled,
}

impl DisplayCondition {
    fn matches(self, state: ShortcutsState) -> bool {
        match self {
            DisplayCondition::WhenShiftEnterHint => state.use_shift_enter_hint,
            DisplayCondition::WhenNotShiftEnterHint => !state.use_shift_enter_hint,
            // ...
        }
    }
}
```

#### 5. 特殊处理：EditPrevious
```rust
// footer.rs:1021-1029
ShortcutDescriptor {
    id: ShortcutId::EditPrevious,
    bindings: &[ShortcutBinding {
        key: key_hint::plain(KeyCode::Esc),
        condition: DisplayCondition::Always,
    }],
    prefix: "",
    label: "",
}

// footer.rs:925-941 (overlay_entry 中的特殊处理)
fn overlay_entry(&self, state: ShortcutsState) -> Option<Line<'static>> {
    // ...
    match self.id {
        ShortcutId::EditPrevious => {
            if state.esc_backtrack_hint {
                line.push_span(" again to edit previous message");
            } else {
                line.extend(vec![
                    " ".into(),
                    key_hint::plain(KeyCode::Esc).into(),
                    " to edit previous message".into(),
                ]);
            }
        }
        _ => line.push_span(self.label),
    };
    // ...
}
```

### 渲染流程

```
测试调用
    ↓
shortcut_overlay_lines(ShortcutsState {
    use_shift_enter_hint: true,
    esc_backtrack_hint: true,
    ...
})
    ├─ InsertNewline: 
    │   └─ WhenShiftEnterHint.matches() = true
    │   └─ 选择 "shift + enter"
    │
    ├─ EditPrevious:
    │   └─ esc_backtrack_hint = true
    │   └─ 生成 "esc again to edit previous message"
    │
    └─ build_columns(...) 构建双列布局
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:723-729` | `ShortcutsState` - 快捷方式状态结构 |
| `codex-rs/tui/src/bottom_pane/footer.rs:889-908` | `DisplayCondition` - 显示条件枚举 |
| `codex-rs/tui/src/bottom_pane/footer.rs:917-941` | `ShortcutDescriptor::overlay_entry` - 条目构建 |
| `codex-rs/tui/src/bottom_pane/footer.rs:962-976` | `InsertNewline` 快捷方式定义 |
| `codex-rs/tui/src/bottom_pane/footer.rs:1021-1029` | `EditPrevious` 快捷方式定义 |

### 数据结构
```rust
// footer.rs:876-888
struct ShortcutBinding {
    key: KeyBinding,
    condition: DisplayCondition,
}

impl ShortcutBinding {
    fn matches(&self, state: ShortcutsState) -> bool {
        self.condition.matches(state)
    }
}
```

### 快捷方式查找
```rust
// footer.rs:917-922
impl ShortcutDescriptor {
    fn binding_for(&self, state: ShortcutsState) -> Option<&'static ShortcutBinding> {
        self.bindings.iter().find(|binding| binding.matches(state))
    }
}
```

---

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|-----|------|
| `crate::key_hint` | 键盘快捷键渲染（`shift`, `ctrl`, `plain`） |
| `crossterm::event::KeyCode` | 键码定义 |
| `ratatui::text::Line` | 文本行构建 |

### 与 ChatComposer 的集成
```rust
// chat_composer.rs:361-362
esc_backtrack_hint: bool,
use_shift_enter_hint: bool,

// chat_composer.rs:481-482 (new_with_config 中初始化)
let use_shift_enter_hint = enhanced_keys_supported;
```

### 状态来源
```rust
// esc_backtrack_hint 来源：
// - 用户按过 Esc 后设置为 true
// - 表示再按一次 Esc 即可编辑上一条消息

// use_shift_enter_hint 来源：
// - 基于终端是否支持增强键（enhanced_keys_supported）
// - 现代终端通常支持 Shift+Enter
```

---

## 风险边界与改进建议

### 当前风险边界

#### 1. 互斥条件的完整性
- **风险**: `WhenShiftEnterHint` 和 `WhenNotShiftEnterHint` 是互斥的，但必须确保至少一个匹配
- **边界**: 如果逻辑错误导致两者都不匹配，快捷方式将不显示
- **建议**: 添加断言确保每个快捷方式至少有一个绑定匹配

#### 2. EditPrevious 的特殊处理
- **风险**: EditPrevious 的特殊逻辑在 `overlay_entry` 中硬编码，与其他快捷方式不一致
- **边界**: 增加了代码复杂性和维护难度
- **建议**: 考虑统一处理或提取为策略模式

#### 3. 状态同步
- **风险**: `esc_backtrack_hint` 需要与实际的 Esc 处理逻辑保持同步
- **边界**: 如果状态更新延迟，提示可能与实际行为不符
- **建议**: 添加集成测试验证状态一致性

### 改进建议

#### 1. 绑定验证
```rust
impl ShortcutDescriptor {
    fn validate(&self) -> Result<(), String> {
        // 确保至少有一个 "Always" 绑定，或条件覆盖完整
        let has_always = self.bindings.iter()
            .any(|b| matches!(b.condition, DisplayCondition::Always));
        let conditions_cover_all = /* 检查条件是否互斥且完整 */;
        
        if !has_always && !conditions_cover_all {
            return Err(format!("Shortcut {:?} may have no matching binding", self.id));
        }
        Ok(())
    }
}
```

#### 2. 统一特殊处理
```rust
// 建议：为 EditPrevious 添加专用条件
enum DisplayCondition {
    // ...
    WhenEscBacktrackHint,
    WhenNotEscBacktrackHint,
}
```

#### 3. 测试矩阵扩展
```rust
// 建议：测试所有 4 种组合
#[test]
fn footer_shortcuts_all_hint_combinations() {
    for esc_hint in [true, false] {
        for shift_hint in [true, false] {
            // 验证每种组合下的快捷方式显示
        }
    }
}
```

### 相关测试
该测试与以下测试共同构成快捷方式条件测试矩阵：
- `footer_shortcuts_default`: 默认条件（shift=false, esc=false）
- `footer_shortcuts_shift_and_esc`: **本测试** - shift=true, esc=true
- `footer_shortcuts_collaboration_modes_enabled`: 协作模式条件

---

## 快照内容分析

```
"  / for commands                             ! for shell commands               "
"  shift + enter for newline                  tab to queue message               "
"  @ for file paths                           ctrl + v to paste images           "
"  ctrl + g to edit in external editor        esc again to edit previous message "
"  ctrl + c to exit                                                              "
"  ctrl + t to view transcript                                                   "
```

### 内容解析

#### 与默认配置的差异
| 行 | 本测试 (shift=true, esc=true) | 默认 (shift=false, esc=false) |
|---|------------------------------|------------------------------|
| 2 | `shift + enter for newline` | `ctrl + j for newline` |
| 4 | `esc again to edit previous message` | `esc esc to edit previous message` |

#### 关键验证点
1. ✅ **Shift+Enter 换行**: 第2行左列显示 "shift + enter"
2. ✅ **Esc 回退提示**: 第4行右列显示 "esc again"（单 Esc）
3. ✅ **无协作模式条目**: 第5行只有 "ctrl + c to exit"（无右列）
4. ✅ **双列布局**: 6行，大部分行有双列

### 样式说明
```rust
// 换行条目（第2行左列）
Line::from(vec![
    "shift".into(),
    " + ".into(),
    "enter".into(),
    " for newline".into(),
])

// 编辑上一条消息条目（第4行右列）
Line::from(vec![
    "esc".into(),
    " again to edit previous message".into(),
])
```

### 与默认快照对比
```
默认 (footer_shortcuts_default):
"  ctrl + j for newline                       ..."
"  ...                                        esc esc to edit previous message"

本测试 (footer_shortcuts_shift_and_esc):
"  shift + enter for newline                  ..."
"  ...                                        esc again to edit previous message"
         ^^^^^ ^^^^^^                                  ^^^^^
```
