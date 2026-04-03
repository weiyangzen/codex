# Chat Composer Footer Mode Shortcut Overlay Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `chat_composer.rs` 模块的测试快照，用于验证**快捷键覆盖层**的渲染输出。当用户按 `?` 键时，显示完整的快捷键帮助界面。

### 业务场景
- 用户忘记某个快捷键
- 用户想了解所有可用的快捷键
- 新用户学习 Codex TUI 的操作方式

### 覆盖层特性
- 多行显示，覆盖正常底部栏
- 两列布局，充分利用水平空间
- 根据配置动态调整（如 WSL 环境显示不同的粘贴快捷键）

## 功能点目的

### 核心功能
1. **快捷键参考**：显示所有可用的快捷键
2. **上下文感知**：根据当前状态显示相关快捷键
3. **动态调整**：根据配置（如 WSL）调整显示内容

### 用户体验目标
- **快速查阅**：用户无需离开界面即可查看快捷键
- **分类清晰**：快捷键按功能分组
- **易于关闭**：按 `?` 或 `Esc` 即可关闭

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum FooterMode {
    ShortcutOverlay,  // 快捷键覆盖层模式
    // ... 其他模式
}

pub(crate) struct FooterProps {
    use_shift_enter_hint: bool,  // 是否使用 Shift+Enter 换行提示
    esc_backtrack_hint: bool,    // 是否显示 Esc 回退提示
    is_wsl: bool,                // 是否在 WSL 环境
    collaboration_modes_enabled: bool,  // 是否启用协作模式
    // ...
}

#[derive(Clone, Copy, Debug)]
struct ShortcutsState {
    use_shift_enter_hint: bool,
    esc_backtrack_hint: bool,
    is_wsl: bool,
    collaboration_modes_enabled: bool,
}
```

### 快捷键定义
```rust
const SHORTCUTS: &[ShortcutDescriptor] = &[
    ShortcutDescriptor {
        id: ShortcutId::Commands,
        bindings: &[ShortcutBinding {
            key: key_hint::plain(KeyCode::Char('/')),
            condition: DisplayCondition::Always,
        }],
        prefix: "",
        label: " for commands",
    },
    ShortcutDescriptor {
        id: ShortcutId::ShellCommands,
        bindings: &[ShortcutBinding {
            key: key_hint::plain(KeyCode::Char('!')),
            condition: DisplayCondition::Always,
        }],
        prefix: "",
        label: " for shell commands",
    },
    // ... 更多快捷键
];
```

### 覆盖层生成
```rust
fn shortcut_overlay_lines(state: ShortcutsState) -> Vec<Line<'static>> {
    let mut commands = Line::from("");
    let mut shell_commands = Line::from("");
    // ... 其他行

    for descriptor in SHORTCUTS {
        if let Some(text) = descriptor.overlay_entry(state) {
            match descriptor.id {
                ShortcutId::Commands => commands = text,
                ShortcutId::ShellCommands => shell_commands = text,
                // ...
            }
        }
    }

    let mut ordered = vec![
        commands,
        shell_commands,
        // ...
    ];
    
    build_columns(ordered)  // 两列布局
}

fn build_columns(entries: Vec<Line<'static>>) -> Vec<Line<'static>> {
    const COLUMNS: usize = 2;
    const COLUMN_PADDING: [usize; COLUMNS] = [4, 4];
    const COLUMN_GAP: usize = 4;
    
    // 计算列宽并填充
    // 交错排列为两列
    // ...
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **测试函数**: `footer_mode_shortcut_overlay` (在 chat_composer tests 中)
- **快捷键定义**: `footer.rs` 中的 `SHORTCUTS` 常量

### 渲染输出分析
```
"  / for commands                             ! for shell commands                                   "
"  shift + enter for newline                  tab to queue message                                   "
"  @ for file paths                           ctrl + v to paste images                               "
"  ctrl + g to edit in external editor        esc again to edit previous message                     "
"  ctrl + c to exit                                                                                  "
"  ctrl + t to view transcript                                                                       "
```

- 两列布局，每列包含快捷键和描述
- 所有文本灰色显示（`.dim()`）
- 快捷键使用 `key_hint` 格式化

## 依赖与外部交互

### 内部依赖
- `key_hint` 模块 - 快捷键格式化
- `FooterMode::ShortcutOverlay` - 覆盖层模式
- `build_columns` - 列布局算法

### 外部交互
- **配置系统**：获取 WSL 状态、协作模式启用状态
- **键盘事件**：处理 `?` 键切换覆盖层

## 风险、边界与改进建议

### 潜在风险
1. **信息过载**：快捷键过多可能导致界面拥挤
2. **配置不一致**：不同环境的快捷键差异可能让用户困惑
3. **可发现性**：用户可能不知道 `?` 可以显示帮助

### 边界情况
1. **终端宽度不足**：非常窄的终端可能导致列布局失败
2. **快捷键冲突**：不同功能可能使用相同的快捷键
3. **动态快捷键**：某些快捷键只在特定状态下可用

### 改进建议
1. **分类标题**：为不同类别的快捷键添加标题
2. **搜索功能**：允许在覆盖层中搜索特定快捷键
3. **可定制性**：允许用户自定义快捷键显示
4. **交互式教程**：添加交互式快捷键学习模式
5. **快捷键提示**：在相关 UI 元素旁显示提示

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- 快捷键提示: `codex-rs/tui_app_server/src/key_hint.rs`
