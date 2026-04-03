# 研究文档：探索步骤4 - 完成读取 foo.txt

## 场景与职责

该快照测试是探索模式系列测试的第四步，验证当 `cat foo.txt` 命令执行完成后，活动单元格的最终显示状态。

**测试场景**：
- 已完成 `ls -la` 命令
- 已完成 `cat foo.txt` 命令
- 验证活动单元格显示 "Explored" 状态和完整的操作历史

## 功能点目的

1. **完成状态展示**：所有探索操作完成后的最终状态
2. **操作历史完整记录**：保留完整的探索操作序列
3. **会话总结**：为用户提供一个探索会话的完整概览

## 具体技术实现

### 测试代码路径
- **文件**: `codex-rs/tui/src/chatwidget/tests.rs` (第 8207-8209 行)
- **测试函数**: `exec_history_extends_previous_when_consecutive`

### 核心测试逻辑

```rust
// 1. 完成 ls -la（已完成）
end_exec(&mut chat, begin_ls, "", "", 0);

// 2. 开始并完成 "cat foo.txt"
let begin_cat_foo = begin_exec(&mut chat, "call-cat-foo", "cat foo.txt");
end_exec(&mut chat, begin_cat_foo, "hello from foo", "", 0);

// 3. 验证最终状态
assert_snapshot!("exploring_step4_finish_cat_foo", active_blob(&chat));
```

### 快照内容分析

```
• Explored
  └ List ls -la
    Read foo.txt
```

### 状态演变总结

| 步骤 | 状态 | 操作显示 | 说明 |
|------|------|----------|------|
| Step1 | Exploring | `List ls -la` | 开始第一个操作 |
| Step2 | Explored | `List ls -la` | 完成第一个操作 |
| Step3 | Exploring | `List ls -la`<br>`Read foo.txt` | 开始第二个操作 |
| Step4 | Explored | `List ls -la`<br>`Read foo.txt` | 完成第二个操作 |

### 探索会话生命周期

```
┌─────────────────────────────────────────┐
│  Exploring                              │
│    └ List ls -la                        │  Step1-2: 目录探索
├─────────────────────────────────────────┤
│  Exploring                              │
│    └ List ls -la                        │  Step3-4: 文件探索
│      Read foo.txt                       │
├─────────────────────────────────────────┤
│  [可能继续更多操作...]                    │
├─────────────────────────────────────────┤
│  Explored                               │
│    └ List ls -la                        │  最终状态
│      Read foo.txt                       │  (当新会话开始)
└─────────────────────────────────────────┘
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `exploring_display_lines` 完整实现 |
| `codex-rs/tui/src/exec_cell/model.rs` | `ExecCell` 状态管理 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试用例，第 8192-8219 行 |

## 依赖与外部交互

### 事件序列
```
ExecCommandBegin (ls)
  ↓
ExecCommandEnd (ls)
  ↓
ExecCommandBegin (cat foo.txt)
  ↓
ExecCommandEnd (cat foo.txt)  <- 当前步骤
  ↓
[可能继续...]
```

### 输出处理
- `stdout: "hello from foo"`：命令输出
- `exit_code: 0`：成功退出
- 输出内容在探索模式下默认不显示（与 command_display_lines 不同）

## 风险、边界与改进建议

### 潜在风险
1. **输出丢失**：探索模式下命令输出对用户不可见
2. **长时间探索**：大量操作累积可能影响性能

### 边界情况
- 命令执行失败（非零退出码）
- 文件不存在错误
- 权限不足

### 改进建议
1. **错误指示**：在操作旁显示错误图标
2. **输出行数**：显示每个命令的输出行数
3. **快速预览**：悬停显示命令输出的前几句
4. **导出功能**：允许导出探索会话的完整日志

### 完整系列测试
```
Step1: exploring_step1_start_ls
   ↓ 开始 ls
Step2: exploring_step2_finish_ls
   ↓ 完成 ls，开始 cat foo.txt
Step3: exploring_step3_start_cat_foo
   ↓ 完成 cat foo.txt
Step4: exploring_step4_finish_cat_foo (当前)
   ↓ 开始并完成 sed 范围读取
Step5: exploring_step5_finish_sed_range
   ↓ 开始并完成 cat bar.txt
Step6: exploring_step6_finish_cat_bar
```

### 探索模式 vs 普通执行

| 特性 | 探索模式 | 普通执行 |
|------|----------|----------|
| 命令类型 | ls, cat, grep 等 | 任意命令 |
| 显示方式 | 累积显示 | 单独显示 |
| 输出显示 | 隐藏 | 显示 |
| 状态 | Exploring/Explored | Running/Ran |
| 用例 | 文件系统探索 | 代码执行、构建等 |
