# 研究文档：探索步骤3 - 开始读取 foo.txt

## 场景与职责

该快照测试是探索模式系列测试的第三步，验证当 Codex 开始读取文件 (`cat foo.txt`) 时，活动单元格如何显示多个探索操作。

**测试场景**：
- 已完成 `ls -la` 命令（Explored 状态）
- 开始新的探索操作：读取 foo.txt
- 验证活动单元格累积显示多个操作

## 功能点目的

1. **操作累积**：在同一个探索会话中累积显示多个相关操作
2. **上下文保持**：保持文件探索的上下文连续性
3. **进度可视化**：显示当前正在进行的操作和已完成的操作

## 具体技术实现

### 测试代码路径
- **文件**: `codex-rs/tui/src/chatwidget/tests.rs` (第 8203-8205 行)
- **测试函数**: `exec_history_extends_previous_when_consecutive`

### 核心测试逻辑

```rust
// 1. 完成 ls -la（step2 已完成）
end_exec(&mut chat, begin_ls, "", "", 0);

// 2. 开始 "cat foo.txt"（Read 操作）
let begin_cat_foo = begin_exec(&mut chat, "call-cat-foo", "cat foo.txt");

// 3. 验证活动单元格显示累积的操作
assert_snapshot!("exploring_step3_start_cat_foo", active_blob(&chat));
```

### 快照内容分析

```
• Exploring
  └ List ls -la
    Read foo.txt
```

### 显示层次结构

```
• Exploring              <- 状态行（活动指示器 + 状态）
  └ List ls -la          <- 第一个操作（已完成）
    Read foo.txt         <- 第二个操作（进行中）
```

### 操作累积逻辑

```rust
// exec_cell/render.rs
fn exploring_display_lines(&self, width: u16) -> Vec<Line<'static>> {
    // ... 状态行 ...
    
    let mut calls = self.calls.clone();
    let mut out_indented = Vec::new();
    
    while !calls.is_empty() {
        let mut call = calls.remove(0);
        
        // 合并连续的 Read 操作
        if call.parsed.iter().all(|p| matches!(p, ParsedCommand::Read { .. })) {
            while let Some(next) = calls.first() {
                if next.parsed.iter().all(|p| matches!(p, ParsedCommand::Read { .. })) {
                    call.parsed.extend(next.parsed.clone());
                    calls.remove(0);
                } else {
                    break;
                }
            }
        }
        
        // 为每个操作生成显示行
        for parsed in &call.parsed {
            match parsed {
                ParsedCommand::Read { name, .. } => {
                    lines.push(("Read", vec![name.clone().into()]));
                }
                ParsedCommand::ListFiles { cmd, path } => {
                    lines.push(("List", vec![path.clone().unwrap_or(cmd.clone()).into()]));
                }
                // ...
            }
        }
    }
    
    // 添加前缀："  └ " 为第一项，"    " 为后续项
    out.extend(prefix_lines(out_indented, "  └ ".dim(), "    ".into()));
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `exploring_display_lines` 方法，第 269-290 行（Read 合并逻辑） |
| `codex-rs/tui/src/render/line_utils.rs` | `prefix_lines` 辅助函数 |
| `codex-shell-command/src/parse_command.rs` | `ParsedCommand::Read` 定义 |

## 依赖与外部交互

### 命令类型
- `ListFiles`：目录列表，显示为 "List"
- `Read`：文件读取，显示为 "Read"

### 前缀样式
| 位置 | 前缀 | 说明 |
|------|------|------|
| 第一个操作 | `  └ ` | 树形连接符 |
| 后续操作 | `    ` | 缩进对齐 |

## 风险、边界与改进建议

### 潜在风险
1. **操作过多**：大量操作可能导致显示过长
2. **重复文件**：多次读取同一文件可能造成混淆

### 边界情况
- 同一文件多次读取（去重逻辑）
- 混合操作类型（List + Read + Search）
- 操作数量超过屏幕高度

### 改进建议
1. **操作计数**：显示 "+3 more" 提示额外操作
2. **文件图标**：使用 📄 表示文件，📁 表示目录
3. **去重优化**：相同文件多次读取时显示读取次数
4. **折叠/展开**：允许用户折叠历史操作

### 系列测试上下文
```
Step1: exploring_step1_start_ls
   ↓
Step2: exploring_step2_finish_ls
   ↓
Step3: exploring_step3_start_cat_foo (当前)
   ↓ 完成读取
Step4: exploring_step4_finish_cat_foo
   ↓
Step5: exploring_step5_finish_sed_range
   ↓
Step6: exploring_step6_finish_cat_bar
```

### 相关测试
- `codex_tui__history_cell__tests__coalesces_reads_across_multiple_calls`：测试 Read 操作合并
