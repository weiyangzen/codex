# 研究文档：unified_exec_non_empty_then_empty_active

## 场景与职责

此 snapshot 测试验证统一执行（Unified Exec）从非空交互到空交互状态的变化（活动视角）。测试场景包括：
- 任务开始
- 统一执行启动（`just fix` 命令）
- 一次非空交互（`pwd` 命令）
- 一次空交互（仅按回车）
- 验证活动单元格（active cell）正确显示交互内容

该测试确保在活动状态下（任务未完成），当前交互内容能够正确显示在活动单元格中。

## 功能点目的

活动单元格是 TUI 中显示当前正在进行的统一执行交互的组件：
1. **实时反馈**：立即显示用户与后台终端的交互
2. **当前状态**：展示最近一次交互的内容
3. **活动识别**：区分历史记录和活动状态
4. **输入确认**：确认用户的输入已被接收
5. **上下文保持**：在任务进行期间保持交互上下文可见

这种设计使用户能够实时看到与后台终端的交互效果。

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
chat.on_task_started();

// 1. 开始统一执行
begin_unified_exec_startup(&mut chat, "call-wait-3", "proc-3", "just fix");

// 2. 非空交互（输入 "pwd"）
terminal_interaction(&mut chat, "call-wait-3a", "proc-3", "pwd\n");

// 3. 空交互（仅按回车）
terminal_interaction(&mut chat, "call-wait-3b", "proc-3", "");

// 4. 获取活动单元格内容（任务完成前）
let pre_cells = drain_insert_history(&mut rx);
let active_combined = pre_cells
    .iter()
    .map(|lines| lines_to_single_string(lines))
    .collect::<String>();
```

### 渲染输出格式
```
↳ Interacted with background terminal · just fix
  └ pwd
```

格式解析：
- `↳`：活动交互指示符（箭头表示当前活动）
- `Interacted with background terminal`：交互类型描述
- `· just fix`：关联的统一执行命令
- `└ pwd`：用户输入的内容（树形缩进，使用 `└` 表示最后一项）

### 活动单元格 vs 历史单元格
```
活动单元格（Active）          历史单元格（History）
├─ 显示当前进行中的交互        ├─ 显示已完成的交互
├─ 使用 ↳ 指示符              ├─ 使用 • 或 ↳ 指示符
├─ 任务完成后移入历史          ├─ 永久保存在历史记录中
└─ 可被新交互替换              └─ 不可修改
```

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/chatwidget/mod.rs`**（或等效文件）
   - 实现活动单元格管理
   - `active_cell` 字段存储当前活动单元格
   - `active_cell_revision` 跟踪单元格版本

2. **`codex-rs/tui/src/history_cell/`**（历史单元格子模块）
   - 实现活动单元格的渲染逻辑
   - 树形结构和缩进处理

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 5375-5397）
   - 测试函数 `unified_exec_non_empty_then_empty_snapshots`
   - 验证活动单元格的正确显示

### 相关数据结构
```rust
// ChatWidget 中的活动单元格相关字段
pub struct ChatWidget {
    active_cell: Option<Box<dyn HistoryCell>>,  // 当前活动单元格
    active_cell_revision: u64,                  // 单元格版本号
    // ... 其他字段
}

// 活动单元格特征（概念性）
trait ActiveCell: HistoryCell {
    fn update(&mut self, event: TerminalInteractionEvent);
    fn is_active(&self) -> bool;
    fn finalize(self) -> Box<dyn HistoryCell>;
}
```

### 活动单元格生命周期
```
TurnStarted
    ↓
begin_unified_exec_startup
    ↓
terminal_interaction (非空)
    ↓
创建/更新 ActiveCell
    ↓
terminal_interaction (空)
    ↓
保持 ActiveCell（不更新内容）
    ↓
TurnComplete
    ↓
ActiveCell → HistoryCell
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget` | 活动单元格管理和状态跟踪 |
| `history_cell` | 单元格渲染和树形结构 |
| `bottom_pane` | 统一执行状态管理 |

### 事件依赖
- `TerminalInteractionEvent`：触发活动单元格更新
- `TurnStartedEvent`：初始化活动单元格系统
- `TurnCompleteEvent`：将活动单元格转为历史记录

### 测试辅助函数
```rust
// 获取活动单元格内容的辅助函数
fn active_blob(chat: &ChatWidget) -> String {
    // 从 chat 中提取活动单元格的文本内容
    chat.active_cell
        .as_ref()
        .map(|cell| lines_to_single_string(&cell.display_lines(80)))
        .unwrap_or_default()
}
```

## 风险、边界与改进建议

### 潜在风险
1. **单元格丢失**：任务完成时活动单元格可能丢失未保存的内容
2. **并发更新**：多个并发交互可能导致活动单元格内容混乱
3. **内存泄漏**：长时间运行的任务可能导致活动单元格占用过多内存

### 边界情况
1. **无交互**：如果没有交互事件，活动单元格应保持为空
2. **仅空交互**：如果只有空交互，活动单元格应显示等待状态
3. **快速连续交互**：快速连续交互应正确合并或分别显示
4. **超大输入**：非常大的输入内容可能影响活动单元格性能

### 改进建议
1. **实时预览**：在活动单元格中实时显示后台终端的输出
2. **交互计数**：显示交互次数（如 "Interacted (3 times)"）
3. **时间显示**：在活动单元格中显示最后一次交互的时间
4. **可编辑性**：允许用户编辑最近一次交互（如果尚未执行）
5. **快捷操作**：提供快捷方式快速复制或重新执行交互内容
6. **视觉区分**：使用更明显的方式区分活动单元格和历史单元格

### 相关测试
- `unified_exec_non_empty_then_empty_active`：本测试文件（活动视角）
- `unified_exec_non_empty_then_empty_after`：同一测试的历史视角
- `unified_exec_empty_then_non_empty_after`：反向状态变化测试
