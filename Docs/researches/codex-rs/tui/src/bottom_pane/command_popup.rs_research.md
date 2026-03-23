# command_popup.rs 深度研究

## 场景与职责

`command_popup.rs` 实现了 TUI (Terminal User Interface) 中的斜杠命令 (`/command`) 自动补全弹出框。当用户在聊天输入框中输入 `/` 开头的内容时，会显示一个可筛选的命令列表，包含内置命令和用户自定义提示词 (Custom Prompts)。

**核心职责：**
1. **命令发现**：聚合内置斜杠命令和用户自定义提示词
2. **智能筛选**：根据用户输入实时过滤匹配项，支持前缀匹配和精确匹配
3. **优先级排序**：精确匹配优先于前缀匹配，保持原有展示顺序
4. **特性门控**：根据功能开关动态显示/隐藏特定命令
5. **可视化渲染**：使用 ratatui 渲染带高亮的命令列表

## 功能点目的

### 1. CommandItem - 命令项枚举

```rust
pub(crate) enum CommandItem {
    Builtin(SlashCommand),  // 内置命令
    UserPrompt(usize),      // 用户自定义提示词（索引引用）
}
```

**设计目的：**
- 统一内置命令和用户提示词的处理
- 使用索引引用避免克隆 CustomPrompt 数据
- 支持两种类型的差异化处理

### 2. CommandPopup - 命令弹出框

**关键字段：**
- `command_filter`: 当前筛选字符串（用户输入的 `/` 后的内容）
- `builtins`: 可用的内置命令列表（根据特性标志过滤）
- `prompts`: 用户自定义提示词列表（已排序，去除了与内置命令冲突的）
- `state`: 滚动和选择状态 (`ScrollState`)

### 3. CommandPopupFlags - 特性标志

```rust
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

**目的：** 控制特定命令的可见性，实现功能渐进式发布和 A/B 测试

### 4. ALIAS_COMMANDS - 别名命令隐藏

```rust
const ALIAS_COMMANDS: &[SlashCommand] = &[SlashCommand::Quit, SlashCommand::Approvals];
```

**目的：**
- `quit` 是 `exit` 的别名
- `approvals` 是 `permissions` 的别名
- 在默认列表中隐藏别名，避免重复显示，但用户输入别名时仍可匹配

## 具体技术实现

### 筛选算法

```rust
fn filtered(&self) -> Vec<(CommandItem, Option<Vec<usize>>)>
```

**匹配策略：**
1. **空筛选**：显示所有非别名内置命令 + 所有用户提示词
2. **精确匹配**：命令名或显示名完全匹配，优先级最高
3. **前缀匹配**：命令名或显示名以筛选词开头，次之

**高亮索引计算：**
- 记录匹配字符的起始偏移量
- 用于渲染时高亮匹配部分

### 用户提示词处理

**命名冲突处理：**
```rust
let exclude: HashSet<String> = builtins.iter().map(|(n, _)| (*n).to_string()).collect();
prompts.retain(|p| !exclude.contains(&p.name));
```
- 用户提示词与内置命令同名时被排除
- 保护内置命令的优先级

**显示格式：**
```rust
format!("/{PROMPTS_CMD_PREFIX}:{}", prompt.name)  // /prompts:name
```

**双重搜索支持：**
- 输入 "name" → 匹配 `/prompts:name`
- 输入 "prompts:name" → 直接匹配

### 与 slash_commands 模块协作

```rust
slash_commands::builtins_for_input(flags.into())
    .into_iter()
    .filter(|(name, _)| !name.starts_with("debug"))
    .collect()
```

- 使用 `slash_commands` 模块获取过滤后的内置命令
- 额外过滤掉 `debug` 开头的调试命令

### 高度计算

```rust
pub(crate) fn calculate_required_height(&self, width: u16) -> u16
```

- 考虑描述文本的自动换行
- 使用 `measure_rows_height` 精确计算所需行数
- 防止长描述导致弹出框溢出

## 关键代码路径与文件引用

### 本文件内关键实现

| 函数/结构 | 行号 | 说明 |
|-----------|------|------|
| `CommandItem` | 23-28 | 命令项枚举 |
| `CommandPopupFlags` | 38-46 | 特性标志结构 |
| `CommandPopup` | 30-35 | 主结构定义 |
| `new` | 63-80 | 构造函数，初始化命令列表 |
| `set_prompts` | 82-91 | 动态更新提示词列表 |
| `on_composer_text_change` | 101-126 | 处理输入变化，更新筛选 |
| `filtered` | 140-205 | 核心筛选逻辑 |
| `rows_from_matches` | 211-247 | 转换为显示行 |
| `calculate_required_height` | 130-135 | 计算所需高度 |
| `WidgetRef::render_ref` | 273-287 | 渲染实现 |

### 依赖文件

| 文件 | 用途 |
|------|------|
| `slash_commands.rs` | 内置命令过滤逻辑 |
| `slash_command.rs` | `SlashCommand` 枚举定义 |
| `scroll_state.rs` | `ScrollState` 滚动状态 |
| `selection_popup_common.rs` | 通用选择弹出框渲染 |
| `popup_consts.rs` | `MAX_POPUP_ROWS` 常量 |
| `codex_protocol::custom_prompts::CustomPrompt` | 用户提示词类型 |
| `codex_protocol::custom_prompts::PROMPTS_CMD_PREFIX` | 提示词前缀常量 |

### 调用方

- `chat_composer.rs`: 创建和管理 CommandPopup 实例
- `ChatComposer::handle_key_event`: 触发命令弹出框显示/隐藏
- `ChatComposer::on_composer_text_change`: 同步输入到弹出框筛选

## 依赖与外部交互

### 与 ChatComposer 的协作流程

1. 用户输入 `/` → ChatComposer 创建 `CommandPopup`
2. 用户继续输入 → `on_composer_text_change` 更新筛选
3. 用户按 Up/Down → `move_up`/`move_down` 更新选择
4. 用户按 Enter → `selected_item` 返回选中的命令
5. ChatComposer 执行命令或填充提示词

### 特性门控映射

| 特性标志 | 控制的命令 |
|----------|-----------|
| `collaboration_modes_enabled` | `/collab`, `/plan` |
| `connectors_enabled` | `/apps` |
| `fast_command_enabled` | `/fast` |
| `personality_command_enabled` | `/personality` |
| `realtime_conversation_enabled` | `/realtime` |
| `audio_device_selection_enabled` | `/settings` |
| `windows_degraded_sandbox_active` | `/setup-default-sandbox` |

## 风险、边界与改进建议

### 潜在风险

1. **性能问题**：
   - 每次输入变化都重新计算筛选（`O(n)` 遍历）
   - 提示词数量大时可能影响响应速度
   - 建议：添加防抖或增量更新

2. **命名冲突**：
   - 用户提示词与内置命令同名时被静默排除
   - 用户可能困惑为什么提示词不显示
   - 建议：添加日志或 UI 提示

3. **状态同步**：
   - `set_prompts` 可能在中途更新列表，导致选择索引失效
   - 当前实现会重置选择，可能打断用户操作

### 边界情况

1. **空筛选**：显示完整列表，隐藏别名命令
2. **无匹配项**：显示 "no matches" 占位符
3. **调试命令**：默认隐藏，但输入 `/debug` 前缀时显示
4. **多行输入**：只使用第一行进行命令识别

### 测试覆盖

**现有测试：**
- 筛选功能测试（前缀匹配、精确匹配）
- 命令排序测试
- 提示词发现测试
- 命名冲突处理测试
- 描述元数据测试
- 特性门控测试（collab、personality、settings 等）
- 调试命令隐藏测试

**测试缺失：**
- 大量提示词的性能测试
- 并发更新场景
- 边界条件下的渲染测试

### 改进建议

1. **模糊匹配**：
   ```rust
   // 当前：仅前缀匹配
   // 建议：添加模糊匹配支持
   use codex_utils_fuzzy_match::fuzzy_match;
   ```

2. **最近使用排序**：
   - 记录命令使用频率，优先显示常用命令
   - 提升用户体验

3. **分类显示**：
   - 将命令按类别分组（如：会话管理、配置、工具）
   - 添加分类标签

4. **描述搜索**：
   - 当前只搜索命令名
   - 建议：同时搜索描述文本

5. **键盘快捷键**：
   - 添加数字快捷键（1-9）快速选择
   - Tab 键自动补全

6. **异步提示词加载**：
   - 提示词可能来自文件系统或网络
   - 支持异步加载和缓存

### 代码质量

- **优点**：
  - 筛选逻辑清晰，优先级明确
  - 与 `selection_popup_common` 复用渲染逻辑
  - 完善的单元测试
  - 特性门控设计灵活

- **可改进**：
  - `filtered` 函数较长，可以拆分为多个小函数
  - 匹配逻辑中的字符计数可以优化（当前使用 `chars().count()`）
  - 缺少文档注释说明筛选优先级规则
