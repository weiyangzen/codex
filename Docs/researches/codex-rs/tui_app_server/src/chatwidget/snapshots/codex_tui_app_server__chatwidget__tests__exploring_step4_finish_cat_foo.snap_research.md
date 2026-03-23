# 研究文档：Exploring Step 4 Finish Cat Foo 快照测试

## 场景与职责

此快照文件是 `exec_history_extends_previous_when_consecutive` 测试序列的第四步，验证当 Agent 完成读取文件 `foo.txt` 后，TUI 如何渲染 "Explored"（探索完成）状态。该测试属于"探索模式"（Exploring Mode）功能，用于展示 Agent 连续执行文件读取操作时的历史记录合并与状态转换。

## 功能点目的

1. **探索状态可视化**：区分 "Exploring"（进行中）和 "Explored"（已完成）两种状态
2. **文件读取合并**：将连续的 `cat` 和 `sed` 读取操作归类到同一探索组
3. **渐进式历史构建**：展示历史记录如何随操作完成而累积
4. **命令归类**：将 `ls` 归类为 "List"，`cat` 归类为 "Read"

## 具体技术实现

### 关键流程

测试函数 `exec_history_extends_previous_when_consecutive`（行 8789）构建了一个六步的探索序列：

```rust
// 步骤 1: 开始 ls -la (List)
let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");
assert_snapshot!("exploring_step1_start_ls", active_blob(&chat));

// 步骤 2: 完成 ls -la
end_exec(&mut chat, begin_ls, "", "", 0);
assert_snapshot!("exploring_step2_finish_ls", active_blob(&chat));

// 步骤 3: 开始 cat foo.txt (Read)
let begin_cat_foo = begin_exec(&mut chat, "call-cat-foo", "cat foo.txt");
assert_snapshot!("exploring_step3_start_cat_foo", active_blob(&chat));

// 步骤 4: 完成 cat foo.txt ← 本快照
end_exec(&mut chat, begin_cat_foo, "hello from foo", "", 0);
assert_snapshot!("exploring_step4_finish_cat_foo", active_blob(&chat));

// 步骤 5: sed 范围读取（仍归类为 Read）
let begin_sed_range = begin_exec(&mut chat, "call-sed-range", "sed -n 100,200p foo.txt");
end_exec(&mut chat, begin_sed_range, "chunk", "", 0);
assert_snapshot!("exploring_step5_finish_sed_range", active_blob(&chat));

// 步骤 6: 读取 bar.txt
let begin_cat_bar = begin_exec(&mut chat, "call-cat-bar", "cat bar.txt");
end_exec(&mut chat, begin_cat_bar, "hello from bar", "", 0);
assert_snapshot!("exploring_step6_finish_cat_bar", active_blob(&chat));
```

### 本快照对应的状态（步骤 4）

在完成 `cat foo.txt` 后，活跃单元格显示：
```
• Explored
  └ List ls -la
    Read foo.txt
```

状态特征：
- `•` 表示活跃单元格标记
- `Explored` 表示探索已完成（非加粗，区别于进行中的 "Exploring"）
- `└ List ls -la` 第一个命令，类型为 List
- `Read foo.txt` 第二个命令，类型为 Read，与 List 属于同一探索组

### 数据结构

**ExecCommandBeginEvent**（`codex-rs/protocol/src/protocol.rs`）：
```rust
pub struct ExecCommandBeginEvent {
    pub call_id: String,
    pub process_id: Option<String>,
    pub turn_id: String,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub parsed_cmd: Vec<ParsedCommand>,  // 解析后的命令结构
    pub source: ExecCommandSource,       // Agent/UserShell/UnifiedExecStartup
    pub interaction_input: Option<String>,
}
```

**ParsedCommand**（用于命令归类）：
```rust
pub enum ParsedCommand {
    Read { path: PathBuf, ... },    // cat, sed 等读取操作
    List { path: PathBuf, ... },    // ls 等列表操作
    Write { path: PathBuf, ... },   // 写入操作
    // ... 其他类型
}
```

### 命令归类逻辑

在 `codex-rs/tui_app_server/src/exec_cell/render.rs` 中：

```rust
// 判断是否为读取操作
if call.parsed.iter().all(|parsed| matches!(parsed, ParsedCommand::Read { .. })) {
    // 合并连续的读取操作到同一组
    while let Some(next) = calls.first() {
        if next.parsed.iter().all(|p| matches!(p, ParsedCommand::Read { .. })) {
            // 合并...
        }
    }
}
```

## 关键代码路径与文件引用

### 测试代码
- **文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
- **测试函数**：`exec_history_extends_previous_when_consecutive`（行 8789）
- **本快照断言**：行 8807
- **辅助函数**：
  - `begin_exec`（行 3618）：开始命令执行
  - `end_exec`（行 3622）：结束命令执行
  - `active_blob`（行 3670）：获取活跃单元格的显示内容

### 被测试的组件
- **文件**：`codex-rs/tui_app_server/src/exec_cell/render.rs`
  - `render` 方法处理探索状态的渲染
  - 行 260-266：处理 "Exploring"/"Explored" 标签
  - 行 269-280：合并连续的读取操作

### ExecCell 模型
- **文件**：`codex-rs/tui_app_server/src/exec_cell/model.rs`
  - `ExecCell` 结构体管理命令调用列表
  - `ExecCall` 表示单个命令调用
  - `is_active()` 方法判断是否有正在进行的命令

### 协议定义
- **文件**：`codex-rs/protocol/src/protocol.rs`
  - `ExecCommandBeginEvent`（行 ~2600）
  - `ExecCommandEndEvent`
  - `ExecCommandSource` 枚举（Agent 来源表示 Agent 发起的命令）

## 依赖与外部交互

### 上游依赖
1. **codex-shell-command**：命令解析，将 `cat foo.txt` 解析为 `ParsedCommand::Read`
2. **codex-protocol**：定义执行事件和命令状态
3. **ratatui**：文本渲染和样式（加粗、缩进等）
4. **insta**：快照测试

### 下游消费
1. **历史记录系统**：探索组作为历史记录单元格的一部分
2. **UI 渲染**：在活跃单元格区域显示当前探索状态

### 相关快照
- `exploring_step1_start_ls`：初始 List 状态
- `exploring_step2_finish_ls`：List 完成
- `exploring_step3_start_cat_foo`：开始读取 foo.txt
- `exploring_step4_finish_cat_foo`：本快照，完成读取
- `exploring_step5_finish_sed_range`：sed 范围读取
- `exploring_step6_finish_cat_bar`：读取 bar.txt

## 风险、边界与改进建议

### 当前风险

1. **硬编码归类规则**：命令类型判断依赖硬编码的解析逻辑，可能无法覆盖所有边缘情况
2. **无输出显示**：快照不显示命令的实际输出（"hello from foo"），仅显示命令本身
3. **状态转换依赖**："Explored" 状态依赖于所有命令完成，但如果命令失败如何处理？

### 边界情况

1. **混合操作类型**：如果 List 后紧跟 Write 而非 Read，会如何分组？
2. **命令失败**：`exit_code != 0` 时是否仍显示为 "Explored"？
3. **空输出**：本测试 stdout 为 "hello from foo"，但空输出时行为如何？
4. **并发命令**：多个同时进行的命令如何归类？

### 改进建议

1. **输出预览**：
   - 在探索组中显示每个命令的简短输出预览
   - 示例：`Read foo.txt (12 bytes)`

2. **失败状态区分**：
   - 使用不同图标或颜色区分成功和失败的命令
   - 示例：`✗ Read foo.txt (failed)` vs `✓ Read foo.txt`

3. **可展开详情**：
   - 允许用户展开查看完整输出
   - 添加行数/字节数统计

4. **智能分组增强**：
   - 考虑文件路径相关性（同一目录的文件归为一组）
   - 考虑时间窗口（短时间内操作归为一组）

5. **增加测试覆盖**：
   - 测试命令失败场景
   - 测试空输出场景
   - 测试混合操作类型（List + Write + Read）
   - 测试大量文件（100+）的读取

6. **国际化**：
   - "Explored"/"List"/"Read" 等标签需要支持本地化
