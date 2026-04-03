# command_popup.rs 研究文档

## 场景与职责

`command_popup.rs` 是 Codex TUI 应用中负责斜杠命令（slash command）自动补全弹窗的核心模块。当用户在输入框中键入 `/` 开头的命令时，该模块提供一个可筛选、可选择的命令列表，支持：

1. **内置命令展示**：根据功能开关动态过滤可用的内置斜杠命令
2. **自定义 Prompt 展示**：集成用户定义的自定义 Prompt（通过 `/prompts:name` 调用）
3. **智能筛选**：支持前缀匹配和模糊匹配，高亮匹配字符
4. **优先级排序**：精确匹配优先于前缀匹配

该模块实现了 `WidgetRef` trait，可直接嵌入 ratatui 的渲染流程。

## 功能点目的

### 1. 命令项抽象（CommandItem）
- **目的**：统一内置命令和自定义 Prompt 的表示
- **变体**：
  - `Builtin(SlashCommand)`: 内置斜杠命令
  - `UserPrompt(usize)`: 自定义 Prompt 的索引

### 2. 功能开关控制（CommandPopupFlags）
- **目的**：根据配置动态控制命令可见性
- **字段**：
  - `collaboration_modes_enabled`: 协作模式（/collab, /plan）
  - `connectors_enabled`: 连接器（/apps）
  - `fast_command_enabled`: 快速命令（/fast）
  - `personality_command_enabled`: 个性设置（/personality）
  - `realtime_conversation_enabled`: 实时对话（/realtime）
  - `audio_device_selection_enabled`: 音频设备选择（/settings）
  - `windows_degraded_sandbox_active`: Windows 降级沙盒（/elevate-sandbox）

### 3. 智能筛选算法
- **目的**：根据用户输入快速过滤命令列表
- **策略**：
  - 空筛选时：按顺序显示所有内置命令（排除别名）+ 排序后的自定义 Prompts
  - 非空筛选时：先精确匹配，再前缀匹配
  - 支持同时搜索 Prompt 名称和完整命令格式（`/prompts:name`）

### 4. 别名隐藏机制
- **目的**：避免重复展示功能相同的命令
- **实现**：`ALIAS_COMMANDS` 常量定义别名（如 `quit` 是 `exit` 的别名），默认隐藏

### 5. 名称冲突处理
- **目的**：确保内置命令优先级高于自定义 Prompt
- **实现**：创建弹窗时，自动过滤掉与内置命令同名的自定义 Prompt

## 具体技术实现

### 关键数据结构

```rust
/// 可选择项：内置命令或用户 Prompt
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum CommandItem {
    Builtin(SlashCommand),
    UserPrompt(usize),  // 在 prompts 列表中的索引
}

pub(crate) struct CommandPopup {
    command_filter: String,           // 当前筛选文本
    builtins: Vec<(&'static str, SlashCommand)>,  // 可见内置命令
    prompts: Vec<CustomPrompt>,       // 自定义 Prompt 列表
    state: ScrollState,               // 滚动/选择状态
}

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct CommandPopupFlags {
    pub(crate) collaboration_modes_enabled: bool,
    pub(crate) connectors_enabled: bool,
    pub(crate) fast_command_enabled: bool,
    pub(crate) personality_command_enabled: bool,
    pub(crate) realtime_conversation_enabled: bool,
    pub(crate) audio_device_selection_enabled: bool,
    pub(crate) windows_degraded_sandbox_active: bool,
}
```

### 筛选算法实现

```rust
fn filtered(&self) -> Vec<(CommandItem, Option<Vec<usize>>)> {
    // 空筛选：返回所有项（排除别名）
    if filter.is_empty() { ... }
    
    // 非空筛选：分离精确匹配和前缀匹配
    let mut exact: Vec<...> = Vec::new();
    let mut prefix: Vec<...> = Vec::new();
    
    // 为每个命令计算匹配
    for (_, cmd) in self.builtins.iter() {
        push_match(CommandItem::Builtin(*cmd), cmd.command(), None, 0);
    }
    
    // Prompt 支持两种搜索方式：
    // - 输入 "name" 匹配 "/prompts:name"
    // - 输入 "prompts:name" 直接匹配
    for (idx, p) in self.prompts.iter().enumerate() {
        let display = format!("{PROMPTS_CMD_PREFIX}:{}", p.name);
        push_match(CommandItem::UserPrompt(idx), &display, Some(&p.name), prompt_prefix_len);
    }
    
    // 精确匹配优先
    out.extend(exact);
    out.extend(prefix);
    out
}
```

### 文本变化处理

```rust
pub(crate) fn on_composer_text_change(&mut self, text: String) {
    // 提取第一行第一个 '/' 后的内容
    let first_line = text.lines().next().unwrap_or("");
    if let Some(stripped) = first_line.strip_prefix('/') {
        // 提取第一个 token（非空白字符序列）
        let token = stripped.trim_start();
        let cmd_token = token.split_whitespace().next().unwrap_or("");
        self.command_filter = cmd_token.to_string();
    } else {
        self.command_filter.clear();
    }
    
    // 重置或限制选中索引
    let matches_len = self.filtered_items().len();
    self.state.clamp_selection(matches_len);
    self.state.ensure_visible(matches_len, MAX_POPUP_ROWS.min(matches_len));
}
```

### 行渲染转换

```rust
fn rows_from_matches(&self, matches: Vec<(CommandItem, Option<Vec<usize>>)>) 
    -> Vec<GenericDisplayRow> {
    matches.into_iter().map(|(item, indices)| {
        let (name, description) = match item {
            CommandItem::Builtin(cmd) => {
                (format!("/{}", cmd.command()), cmd.description().to_string())
            }
            CommandItem::UserPrompt(i) => {
                let prompt = &self.prompts[i];
                let description = prompt.description.clone()
                    .unwrap_or_else(|| "send saved prompt".to_string());
                (format!("/{PROMPTS_CMD_PREFIX}:{}", prompt.name), description)
            }
        };
        GenericDisplayRow {
            name,
            match_indices: indices.map(|v| v.into_iter().map(|i| i + 1).collect()),
            description: Some(description),
            // ... 其他字段
        }
    }).collect()
}
```

## 关键代码路径与文件引用

### 当前文件关键路径
- `CommandPopup::new()` (行 63-80): 创建弹窗，初始化内置命令和 Prompt 列表
- `on_composer_text_change()` (行 102-127): 处理输入框文本变化，更新筛选
- `filtered()` (行 141-206): 核心筛选算法
- `filtered_items()` (行 208-210): 获取过滤后的命令项
- `rows_from_matches()` (行 212-248): 转换为可渲染行
- `move_up/move_down()` (行 251-263): 导航选择
- `selected_item()` (行 266-271): 获取当前选中项
- `WidgetRef::render_ref()` (行 274-288): 渲染实现

### 调用方
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs`:
  - 创建 `CommandPopup` 实例
  - 调用 `on_composer_text_change` 同步输入状态
  - 调用 `move_up/move_down` 处理键盘导航
  - 调用 `selected_item` 获取选中命令执行

### 被调用方
- `codex-rs/tui_app_server/src/bottom_pane/slash_commands.rs`:
  - `builtins_for_input()`: 根据功能标志获取可见内置命令
  - `BuiltinCommandFlags`: 功能标志定义
- `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs`:
  - `render_rows()`: 通用行渲染
  - `GenericDisplayRow`: 行数据格式
- `codex_protocol::custom_prompts::CustomPrompt`:
  - 自定义 Prompt 数据结构

### 相关常量
- `ALIAS_COMMANDS` (行 20): 别名命令列表（Quit, Approvals）
- `MAX_POPUP_ROWS` (来自 popup_consts): 最大弹窗行数（8）

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `slash_commands` | 内置命令枚举和过滤 |
| `selection_popup_common` | 通用弹窗渲染工具 |
| `scroll_state` | 滚动和选择状态管理 |
| `popup_consts` | 弹窗常量定义 |
| `codex_protocol::custom_prompts` | 自定义 Prompt 类型 |

### 与 ChatComposer 的交互
1. **创建时机**：当用户在输入框键入 `/` 时创建
2. **文本同步**：每次输入框变化调用 `on_composer_text_change`
3. **命令执行**：用户选择后，根据 `CommandItem` 类型：
   - `Builtin`: 转换为 `SlashCommand` 执行
   - `UserPrompt`: 展开 Prompt 内容到输入框

## 风险、边界与改进建议

### 风险点

1. **Prompt 名称冲突**
   - 风险：用户创建的 Prompt 可能与未来新增的内置命令同名
   - 现状：自动过滤冲突的 Prompt，但用户可能困惑为何 Prompt 不显示
   - 建议：添加日志或 UI 提示告知用户过滤原因

2. **性能问题**
   - 风险：大量自定义 Prompt（数百个）时，每次输入都遍历全部
   - 现状：当前使用简单线性搜索
   - 建议：Prompt 数量大时考虑前缀树或索引优化

3. **功能标志同步**
   - 风险：`CommandPopupFlags` 与 `BuiltinCommandFlags` 字段需保持同步
   - 现状：通过 `From` 实现转换，但新增标志需修改两处
   - 建议：考虑共享同一类型定义

### 边界情况

1. **空 Prompt 列表**：正常处理，仅显示内置命令
2. **无匹配筛选**：显示 "no matches"（由 `render_rows` 处理）
3. **全角字符输入**：筛选使用小写转换，支持 Unicode
4. **调试命令隐藏**：所有 `debug*` 命令被显式过滤（行 68-69）

### 改进建议

1. **模糊匹配增强**
   - 当前仅支持前缀匹配，建议添加字符级模糊匹配（如输入 "md" 匹配 "model"）

2. **最近使用排序**
   - 添加 MRU（Most Recently Used）排序，将最近使用的命令排在前面

3. **命令分类/分组**
   - 当前所有命令平铺显示，建议按类别分组（如 Model、Settings、Tools 等）

4. **Prompt 预览**
   - 选中 Prompt 时在侧边显示内容预览，帮助用户确认选择

5. **键盘快捷键**
   - 添加数字快捷键（1-9）快速选择前 9 个命令

6. **测试覆盖**
   - 当前测试覆盖基本功能，建议添加：
     - 大量 Prompt 的性能测试
     - 功能标志边界测试
     - 多语言输入测试
