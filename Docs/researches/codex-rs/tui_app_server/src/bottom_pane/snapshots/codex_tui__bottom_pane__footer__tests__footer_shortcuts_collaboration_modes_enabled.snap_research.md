# Footer Shortcuts Collaboration Modes Enabled Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `footer.rs` 模块的测试快照，用于验证**启用协作模式时的底部栏快捷键显示**。当 `collaboration_modes_enabled` 为 true 时，快捷键覆盖层包含模式切换相关的快捷键。

### 业务场景
- 用户启用了实验性的协作模式功能
- 用户按 `?` 查看快捷键
- 需要显示模式切换快捷键（如 `shift + tab to change mode`）

### 协作模式
- **Plan Mode** - 规划模式
- **Pair Programming Mode** - 结对编程模式（当前隐藏）
- **Execute Mode** - 执行模式（当前隐藏）

## 功能点目的

### 核心功能
1. **模式切换提示**：告知用户如何切换协作模式
2. **功能发现**：让用户了解协作模式功能的存在
3. **上下文适应**：根据功能启用状态调整显示

### 用户体验目标
- **功能可见性**：用户知道协作模式功能可用
- **操作指导**：明确告知切换模式的快捷键
- **渐进披露**：不干扰未启用该功能的用户

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct FooterProps {
    collaboration_modes_enabled: bool,  // 是否启用协作模式
    // ...
}

#[derive(Clone, Copy, Debug)]
struct ShortcutsState {
    collaboration_modes_enabled: bool,
    // ...
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum DisplayCondition {
    Always,
    WhenShiftEnterHint,
    WhenNotShiftEnterHint,
    WhenUnderWSL,
    WhenCollaborationModesEnabled,  // 仅在协作模式启用时显示
}
```

### 条件快捷键定义
```rust
const SHORTCUTS: &[ShortcutDescriptor] = &[
    // ... 其他快捷键
    ShortcutDescriptor {
        id: ShortcutId::ChangeMode,
        bindings: &[ShortcutBinding {
            key: key_hint::shift(KeyCode::Tab),
            condition: DisplayCondition::WhenCollaborationModesEnabled,
        }],
        prefix: "",
        label: " to change mode",
    },
    // ...
];
```

### 条件匹配
```rust
impl DisplayCondition {
    fn matches(self, state: ShortcutsState) -> bool {
        match self {
            // ...
            DisplayCondition::WhenCollaborationModesEnabled => {
                state.collaboration_modes_enabled
            }
        }
    }
}

impl ShortcutDescriptor {
    fn binding_for(&self, state: ShortcutsState) -> Option<&'static ShortcutBinding> {
        self.bindings.iter().find(|binding| binding.matches(state))
    }
    
    fn overlay_entry(&self, state: ShortcutsState) -> Option<Line<'static>> {
        let binding = self.binding_for(state)?;
        // 生成快捷键行...
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **测试函数**: `footer_shortcuts_collaboration_modes_enabled` (行 535 附近)
- **快捷键过滤**: `binding_for` 和 `overlay_entry` 方法

### 渲染输出分析
```
"  / for commands                             ! for shell commands               "
"  ctrl + j for newline                       tab to queue message               "
"  @ for file paths                           ctrl + v to paste images           "
"  ctrl + g to edit in external editor        ctrl + esc to edit previous message   "
"  ctrl + c to exit                           shift + tab to change mode         "
"                                             ctrl + t to view transcript        "
```

- 第 5 行：新增 "shift + tab to change mode"
- 仅在 `collaboration_modes_enabled` 为 true 时显示

## 依赖与外部交互

### 内部依赖
- `DisplayCondition::WhenCollaborationModesEnabled` - 条件枚举
- `ShortcutsState` - 快捷键状态
- `ShortcutDescriptor` - 快捷键描述符

### 外部交互
- **功能标志系统**：获取 `collaboration_modes_enabled` 配置
- **配置持久化**：保存用户的功能启用偏好

## 风险、边界与改进建议

### 潜在风险
1. **功能不稳定**：协作模式可能是实验性功能，提示其存在可能提高期望
2. **界面拥挤**：额外的快捷键可能使覆盖层更拥挤
3. **条件复杂**：多种条件组合可能导致意外行为

### 边界情况
1. **功能切换**：用户在显示覆盖层时切换功能启用状态
2. **快捷键冲突**：模式切换快捷键与其他功能冲突
3. **模式状态**：当前模式影响快捷键显示

### 改进建议
1. **实验性标记**：在提示中添加实验性标记
2. **模式指示器**：在底部栏常驻显示当前模式
3. **模式预览**：切换前预览模式效果
4. **快捷键自定义**：允许用户自定义模式切换快捷键
5. **功能教程**：添加协作模式的交互式教程

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- 功能配置: `codex-rs/core/src/features.rs`
