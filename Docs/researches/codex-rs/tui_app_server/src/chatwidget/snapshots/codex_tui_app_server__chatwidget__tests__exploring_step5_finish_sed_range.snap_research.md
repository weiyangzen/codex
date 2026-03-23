# 研究文档：Exploring Step 5 Finish Sed Range 快照测试

## 场景与职责

此快照文件是 `exec_history_extends_previous_when_consecutive` 测试序列的第五步，验证当 Agent 使用 `sed` 命令读取文件特定范围（`sed -n 100,200p foo.txt`）后，TUI 如何将该操作归类并合并到现有的 "Read" 组中。该测试验证命令解析器能够正确识别 `sed` 范围读取操作，并将其与之前的 `cat foo.txt` 归类为同一类型的文件读取操作。

## 功能点目的

1. **智能命令归类**：将 `sed -n 100,200p foo.txt` 识别为对 `foo.txt` 的读取操作
2. **读取操作合并**：将连续的读取操作（无论使用 `cat` 还是 `sed`）归类到同一组
3. **文件去重**：同一文件的多次读取在显示时合并（`foo.txt` 只显示一次）
4. **探索状态保持**：保持 "Explored" 完成状态

## 具体技术实现

### 关键流程

测试序列的第 5 步（行 8809-8812）：

```rust
// 步骤 5: 开始 & 完成 "sed -n 100,200p foo.txt"（被视为 foo.txt 的 Read）
let begin_sed_range = begin_exec(&mut chat, "call-sed-range", "sed -n 100,200p foo.txt");
end_exec(&mut chat, begin_sed_range, "chunk", "", 0);
assert_snapshot!("exploring_step5_finish_sed_range", active_blob(&chat));
```

### sed 命令解析

`codex-shell-command` crate 将 `sed -n 100,200p foo.txt` 解析为：
```rust
ParsedCommand::Read {
    path: PathBuf::from("foo.txt"),
    // ... 其他字段
}
```

解析逻辑识别以下读取模式：
- `cat <file>` - 完整文件读取
- `sed -n <range>p <file>` - 范围读取
- `head -n <N> <file>` - 头部读取
- `tail -n <N> <file>` - 尾部读取
- `grep ... <file>` - 过滤读取（视情况而定）

### 本快照对应的状态（步骤 5）

在完成 `sed -n 100,200p foo.txt` 后，活跃单元格显示：
```
• Explored
  └ List ls -la
    Read foo.txt
```

与步骤 4 的快照对比：
- **步骤 4**（`exploring_step4_finish_cat_foo`）：相同输出
- **步骤 5**（本快照）：相同输出

这表明 `sed` 读取 `foo.txt` 被合并到现有的 `Read foo.txt` 条目中，没有创建新的显示行。

### 读取合并算法

在 `codex-rs/tui_app_server/src/exec_cell/render.rs` 行 269-280：

```rust
let mut calls = self.calls.clone();
let mut out_indented = Vec::new();
while !calls.is_empty() {
    let mut call = calls.remove(0);
    if call.parsed.iter().all(|parsed| matches!(parsed, ParsedCommand::Read { .. })) {
        // 当前命令是读取操作，尝试合并后续相同文件的读取
        while let Some(next) = calls.first() {
            if next.parsed.iter().all(|p| matches!(p, ParsedCommand::Read { .. })) {
                // 合并逻辑：如果读取同一文件，合并到同一行
                // 文件去重：foo.txt 只显示一次
                calls.remove(0);
            } else {
                break;
            }
        }
    }
    out_indented.push(...);
}
```

## 关键代码路径与文件引用

### 测试代码
- **文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
- **测试函数**：`exec_history_extends_previous_when_consecutive`（行 8789）
- **本快照断言**：行 8812
- **辅助函数**：
  - `begin_exec`（行 3618）：开始命令执行
  - `end_exec`（行 3622）：结束命令执行
  - `active_blob`（行 3670）：获取活跃单元格的显示内容

### 命令解析
- **文件**：`codex-rs/shell_command/src/parse_command.rs`
  - 将 shell 命令解析为 `ParsedCommand` 枚举
  - `sed` 范围读取识别逻辑

### 渲染逻辑
- **文件**：`codex-rs/tui_app_server/src/exec_cell/render.rs`
  - 行 269-280：读取操作合并
  - 文件去重逻辑

### ExecCell 模型
- **文件**：`codex-rs/tui_app_server/src/exec_cell/model.rs`
  - `ExecCell` 管理命令调用序列
  - `calls: Vec<ExecCall>` 存储所有命令

## 依赖与外部交互

### 上游依赖
1. **codex-shell-command**：命令解析，识别 `sed` 为读取操作
2. **codex-protocol**：定义执行事件
3. **ratatui**：文本渲染

### 下游消费
1. **历史记录系统**：合并后的读取组作为历史记录的一部分
2. **UI 渲染**：在活跃单元格显示简化的读取列表

### 相关快照对比
| 快照 | 操作 | 显示内容 |
|------|------|----------|
| step4 | `cat foo.txt` | `Read foo.txt` |
| step5 | `sed -n 100,200p foo.txt` | `Read foo.txt`（相同） |
| step6 | `cat bar.txt` | `Read foo.txt, bar.txt` |

## 风险、边界与改进建议

### 当前风险

1. **文件去重过于激进**：同一文件的不同范围读取（`sed -n 1,10p` vs `sed -n 100,200p`）被完全合并，用户无法知道读取了哪些范围
2. **无范围信息显示**：`sed` 的范围参数在显示中完全丢失
3. **解析依赖**：`sed` 命令的解析可能无法覆盖所有变体

### 边界情况

1. **不同范围读取同一文件**：
   ```bash
   sed -n 1,10p foo.txt
   sed -n 100,200p foo.txt
   ```
   当前行为：合并为单行 `Read foo.txt`
   潜在问题：用户不知道有两个不同的读取操作

2. **复杂 sed 命令**：
   ```bash
   sed -n 100,200p foo.txt | grep "pattern"
   ```
   管道后的命令如何归类？

3. **读取后写入同一文件**：
   ```bash
   cat foo.txt
   echo "new" > foo.txt
   ```
   读取和写入的边界处理

### 改进建议

1. **范围信息显示**：
   ```
   Read foo.txt (lines 100-200)
   ```
   或
   ```
   Read foo.txt
     ├ lines 1-10
     └ lines 100-200
   ```

2. **读取计数器**：
   ```
   Read foo.txt (2 times)
   ```

3. **详细模式切换**：
   - 默认：合并显示
   - 详细：展开显示每个操作

4. **增强 sed 解析**：
   - 支持更多 `sed` 选项（`-e` 脚本、正则表达式等）
   - 处理管道组合命令

5. **增加测试覆盖**：
   - 测试同一文件的不同范围读取
   - 测试管道命令
   - 测试 `awk` 等其他范围读取工具
   - 测试大文件（GB 级别）的读取显示

6. **可视化改进**：
   ```
   • Explored
     └ List ls -la
       Read foo.txt [2 ops]
         └ (hover/expand for details)
   ```
