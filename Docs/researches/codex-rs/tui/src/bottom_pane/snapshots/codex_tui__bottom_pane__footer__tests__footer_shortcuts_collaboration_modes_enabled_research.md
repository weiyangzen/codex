# Footer Shortcuts - Collaboration Modes Enabled 测试研究文档

## 场景与职责

### 测试场景
该快照测试验证当**协作模式启用**时，快捷帮助覆盖层（Shortcut Overlay）显示 "shift + tab to change mode" 条目的行为。

### 测试数据
- **模式**: `ShortcutOverlay`（快捷帮助覆盖层）
- **协作模式**: 启用 (`collaboration_modes_enabled: true`)
- **Esc 回退提示**: 禁用 (`esc_backtrack_hint: false`)
- **Shift+Enter 提示**: 禁用 (`use_shift_enter_hint: false`)
- **WSL 环境**: 否 (`is_wsl: false`)

### 期望行为
当 `collaboration_modes_enabled` 为 true 时，快捷帮助覆盖层应包含模式切换的说明条目。

---

## 功能点目的

### 核心功能
该测试验证快捷帮助系统的**条件显示机制**：

1. **功能开关控制**: 根据 `collaboration_modes_enabled` 动态显示/隐藏相关快捷条目
2. **模式发现**: 帮助用户了解如何切换协作模式（Plan/Pair Programming/Execute）
3. **上下文感知帮助**: 只显示与当前配置相关的快捷方式

### 业务价值
- **功能可见性**: 用户可以快速了解所有可用功能
- **避免混淆**: 不显示未启用功能的快捷方式
- **学习曲线**: 降低新用户学习成本

### 快捷覆盖层结构
```
/ for commands                             ! for shell commands
ctrl + j for newline                       tab to queue message
@ for file paths                           ctrl + v to paste images
ctrl + g to edit in external editor        esc esc to edit previous message
ctrl + c to exit                           shift + tab to change mode  ← 本测试验证
                                             ctrl + t to view transcript
```

---

## 具体技术实现

### 关键代码路径

#### 1. 测试入口
```rust
// footer.rs:1297-1313
snapshot_footer(
    "footer_shortcuts_collaboration_modes_enabled",
    FooterProps {
        mode: FooterMode::ShortcutOverlay,  // 快捷覆盖层模式
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: false,
        collaboration_modes_enabled: true,  // 关键：协作模式启用
        is_wsl: false,
        // ...
    },
);
```

#### 2. 快捷覆盖层生成
```rust
// footer.rs:750-799
fn shortcut_overlay_lines(state: ShortcutsState) -> Vec<Line<'static>> {
    // 为每个快捷方式构建行
    for descriptor in SHORTCUTS {
        if let Some(text) = descriptor.overlay_entry(state) {
            match descriptor.id {
                ShortcutId::ChangeMode => change_mode = text,  // 模式切换条目
                // ...
            }
        }
    }
    
    // 构建列布局
    let mut ordered = vec![
        commands, shell_commands, newline, queue_message_tab,
        file_paths, paste_image, external_editor, edit_previous, quit,
    ];
    
    // 条件性添加模式切换条目
    if change_mode.width() > 0 {
        ordered.push(change_mode);
    }
    
    ordered.push(Line::from(""));
    ordered.push(show_transcript);
    
    build_columns(ordered)
}
```

#### 3. 快捷方式描述符
```rust
// footer.rs:1048-1057
ShortcutDescriptor {
    id: ShortcutId::ChangeMode,
    bindings: &[ShortcutBinding {
        key: key_hint::shift(KeyCode::Tab),
        condition: DisplayCondition::WhenCollaborationModesEnabled,  // 条件显示
    }],
    prefix: "",
    label: " to change mode",
}
```

#### 4. 显示条件匹配
```rust
// footer.rs:889-908
enum DisplayCondition {
    Always,
    WhenShiftEnterHint,
    WhenNotShiftEnterHint,
    WhenUnderWSL,
    WhenCollaborationModesEnabled,  // 本测试验证的条件
}

impl DisplayCondition {
    fn matches(self, state: ShortcutsState) -> bool {
        match self {
            DisplayCondition::WhenCollaborationModesEnabled => {
                state.collaboration_modes_enabled  // 检查协作模式标志
            }
            // ...
        }
    }
}
```

#### 5. 条目构建
```rust
// footer.rs:917-941
impl ShortcutDescriptor {
    fn overlay_entry(&self, state: ShortcutsState) -> Option<Line<'static>> {
        // 查找匹配当前状态的绑定
        let binding = self.binding_for(state)?;
        
        let mut line = Line::from(vec![
            self.prefix.into(),
            binding.key.into()
        ]);
        
        // 特殊处理 EditPrevious 条目
        match self.id {
            ShortcutId::EditPrevious => { /* ... */ }
            _ => line.push_span(self.label),
        };
        
        Some(line)
    }
}
```

### 渲染流程

```
测试调用
    ↓
footer_from_props_lines (mode = ShortcutOverlay)
    ↓
shortcut_overlay_lines(state)
    ├─ 遍历 SHORTCUTS 数组
    ├─ ChangeMode 条目: condition.matches(state) = true
    │   └─ 生成 "shift + tab to change mode"
    ├─ 其他条目按条件生成
    └─ build_columns(ordered) 构建双列布局
    ↓
渲染 6 行双列布局
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:750-799` | `shortcut_overlay_lines` - 快捷覆盖层生成 |
| `codex-rs/tui/src/bottom_pane/footer.rs:800-846` | `build_columns` - 双列布局构建 |
| `codex-rs/tui/src/bottom_pane/footer.rs:862-875` | `ShortcutId` - 快捷方式标识符枚举 |
| `codex-rs/tui/src/bottom_pane/footer.rs:889-908` | `DisplayCondition` - 显示条件枚举 |
| `codex-rs/tui/src/bottom_pane/footer.rs:909-941` | `ShortcutDescriptor` - 快捷方式描述符 |
| `codex-rs/tui/src/bottom_pane/footer.rs:943-1057` | `SHORTCUTS` - 快捷方式定义数组 |

### 数据结构
```rust
// footer.rs:723-729
struct ShortcutsState {
    use_shift_enter_hint: bool,
    esc_backtrack_hint: bool,
    is_wsl: bool,
    collaboration_modes_enabled: bool,  // 控制 ChangeMode 显示
}

// footer.rs:876-888
struct ShortcutBinding {
    key: KeyBinding,
    condition: DisplayCondition,
}
```

### 布局常量
```rust
// footer.rs:801-808
const COLUMNS: usize = 2;
const COLUMN_PADDING: [usize; COLUMNS] = [4, 4];
const COLUMN_GAP: usize = 4;
```

---

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|-----|------|
| `crate::key_hint` | 键盘快捷键渲染（如 `shift`, `ctrl`, `plain`） |
| `ratatui::text::Line` / `Span` | 文本行构建 |
| `crossterm::event::KeyCode` | 键码定义 |

### 与 ChatComposer 的集成
```rust
// chat_composer.rs:402
collaboration_modes_enabled: bool,

// chat_composer.rs:592-594
pub fn set_collaboration_modes_enabled(&mut self, enabled: bool) {
    self.collaboration_modes_enabled = enabled;
}
```

### 快捷方式定义
```rust
// footer.rs:943-1057 的 SHORTCUTS 数组包含 11 个快捷方式：
// 1. Commands (/)
// 2. ShellCommands (!)
// 3. InsertNewline (shift+enter / ctrl+j)
// 4. QueueMessageTab (tab)
// 5. FilePaths (@)
// 6. PasteImage (ctrl+v / ctrl+alt+v for WSL)
// 7. ExternalEditor (ctrl+g)
// 8. EditPrevious (esc / esc esc)
// 9. Quit (ctrl+c)
// 10. ShowTranscript (ctrl+t)
// 11. ChangeMode (shift+tab) ← 本测试关注
```

---

## 风险边界与改进建议

### 当前风险边界

#### 1. 硬编码的布局参数
- **风险**: 列间距、填充等参数是硬编码的
- **边界**: 如果快捷方式文本长度变化，布局可能错位
- **建议**: 添加布局自适应或文本截断机制

#### 2. 条件逻辑的复杂性
- **风险**: 每个快捷方式有自己的显示条件，逻辑分散
- **边界**: 新增条件类型时需要修改多处代码
- **建议**: 考虑使用策略模式或配置驱动的方式

#### 3. 国际化支持
- **风险**: 快捷方式标签是硬编码的英文
- **边界**: 不支持多语言
- **建议**: 添加国际化支持框架

### 改进建议

#### 1. 动态列宽计算
```rust
// 建议：根据内容动态调整列宽
fn build_columns_dynamic(entries: Vec<Line>) -> Vec<Line> {
    let max_width = entries.iter().map(|e| e.width()).max().unwrap_or(0);
    let column_width = (available_width - COLUMN_GAP) / COLUMNS;
    // 如果内容超过列宽，考虑截断或换行
}
```

#### 2. 配置驱动的快捷方式
```rust
// 建议：从配置加载快捷方式
struct ShortcutConfig {
    id: String,
    keys: Vec<KeyBinding>,
    label: String,
    condition: String, // "always", "when_collaboration_enabled", etc.
}
```

#### 3. 测试覆盖增强
```rust
// 建议：测试所有条件组合
#[test]
fn footer_shortcuts_all_condition_combinations() {
    for collab in [true, false] {
        for wsl in [true, false] {
            for shift_enter in [true, false] {
                // 验证每种组合下的快捷方式显示
            }
        }
    }
}
```

### 相关测试
该测试与以下测试共同构成快捷方式测试矩阵：
- `footer_shortcuts_default`: 默认配置（协作模式禁用）
- `footer_shortcuts_shift_and_esc`: Shift+Enter 和 Esc 回退提示
- `footer_shortcuts_collaboration_modes_enabled`: **本测试** - 协作模式启用

---

## 快照内容分析

```
"  / for commands                             ! for shell commands               "
"  ctrl + j for newline                       tab to queue message               "
"  @ for file paths                           ctrl + v to paste images           "
"  ctrl + g to edit in external editor        esc esc to edit previous message   "
"  ctrl + c to exit                           shift + tab to change mode         "
"                                             ctrl + t to view transcript        "
```

### 内容解析

#### 双列布局结构
| 行 | 左列 | 右列 |
|---|------|------|
| 1 | `/ for commands` | `! for shell commands` |
| 2 | `ctrl + j for newline` | `tab to queue message` |
| 3 | `@ for file paths` | `ctrl + v to paste images` |
| 4 | `ctrl + g to edit in external editor` | `esc esc to edit previous message` |
| 5 | `ctrl + c to exit` | `shift + tab to change mode` ← 本测试验证 |
| 6 | (空) | `ctrl + t to view transcript` |

#### 关键验证点
1. ✅ **包含模式切换条目**: "shift + tab to change mode" 存在
2. ✅ **双列布局**: 6行，每行2列
3. ✅ **列对齐**: 左列宽度一致，右列对齐
4. ✅ **暗淡样式**: 所有文本使用 `.dim()` 样式

### 与默认配置对比
```rust
// footer_shortcuts_default (collaboration_modes_enabled = false)
// 第5行: "ctrl + c to exit" (无右列内容)
// 第6行: "ctrl + t to view transcript"

// footer_shortcuts_collaboration_modes_enabled (collaboration_modes_enabled = true)
// 第5行: "ctrl + c to exit                           shift + tab to change mode"
// 第6行: "                                             ctrl + t to view transcript"
// 差异: 第5行右列新增 "shift + tab to change mode"
```

### 样式说明
- 所有文本使用 `.dim()` 样式（暗淡灰色）
- 快捷键（如 `ctrl + j`）使用 `key_hint` 模块渲染
- 列间距为 4 个空格 (`COLUMN_GAP`)
