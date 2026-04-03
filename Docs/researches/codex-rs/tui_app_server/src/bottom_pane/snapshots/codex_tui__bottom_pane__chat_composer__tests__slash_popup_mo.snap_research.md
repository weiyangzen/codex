# Chat Composer Slash Popup MO Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `chat_composer.rs` 模块的测试快照，用于验证**斜杠命令弹出层的过滤功能**。当用户输入 `/mo` 时，显示匹配的命令（如 `/model`）。

### 业务场景
- 用户想要执行某个斜杠命令
- 用户输入 `/` 后输入命令前缀
- 系统显示匹配的命令列表

### 斜杠命令弹出层特性
- 根据输入过滤命令
- 显示命令名称和描述
- 支持键盘导航和选择

## 功能点目的

### 核心功能
1. **命令过滤**：根据输入过滤匹配的命令
2. **描述显示**：显示命令的简要说明
3. **快速选择**：支持 Enter 快速选择
4. **自动完成**：支持 Tab 自动完成

### 用户体验目标
- **快速查找**：用户可以快速找到需要的命令
- **学习辅助**：通过描述了解命令用途
- **减少输入**：通过选择减少打字

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct CommandPopup {
    items: Vec<CommandItem>,
    filtered_indices: Vec<usize>,
    query: String,
}

pub(crate) struct CommandItem {
    pub name: String,
    pub description: String,
    pub handler: CommandHandler,
}
```

### 过滤逻辑
```rust
fn update_filter(&mut self, query: &str) {
    self.query = query.to_lowercase();
    self.filtered_indices = self
        .items
        .iter()
        .enumerate()
        .filter(|(_, item)| {
            item.name.to_lowercase().contains(&self.query)
        })
        .map(|(idx, _)| idx)
        .collect();
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/command_popup.rs`
- **测试函数**: `slash_popup_mo` (在 chat_composer tests 中)

### 渲染输出分析
```
"                                                            "
"› /mo                                                       "
"                                                            "
"                                                            "
"  /model  choose what model and reasoning effort to use     "
```

- 第 2 行：输入框显示 `/mo`
- 第 5 行：匹配 `/model` 命令，显示描述

## 依赖与外部交互

### 内部依赖
- `CommandPopup` - 命令弹出层
- `CommandItem` - 命令项定义

### 外部交互
- **命令注册表**：获取可用命令列表

## 风险、边界与改进建议

### 潜在风险
1. **命令冲突**：多个命令匹配相同前缀
2. **性能问题**：大量命令时的过滤性能
3. **描述过长**：描述过长导致显示问题

### 边界情况
1. **无匹配**：输入无匹配命令时的显示
2. **空输入**：仅输入 `/` 时的默认显示
3. **无效命令**：输入不存在的命令

### 改进建议
1. **模糊匹配**：支持模糊匹配而不仅是前缀匹配
2. **最近使用**：优先显示最近使用的命令
3. **命令分组**：按类别分组显示命令
4. **别名支持**：支持命令别名

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/command_popup.rs`
