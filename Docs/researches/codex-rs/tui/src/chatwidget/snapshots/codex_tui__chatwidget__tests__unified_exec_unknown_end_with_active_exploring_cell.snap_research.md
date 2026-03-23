# 研究报告: unified_exec_unknown_end_with_active_exploring_cell.snap

## 场景与职责

该快照文件验证 **Unified Exec** 与 **Exploring** 单元格共存时的渲染效果。当后台终端命令完成时，同时有一个正在进行的探索操作（如文件读取），需要正确处理两者的显示。

测试场景：
- 启动一个 Exploring 操作（`cat /dev/null`）
- 启动一个 Unified Exec（`echo repro-marker`）
- Unified Exec 完成
- 验证历史记录和活跃单元格正确分离显示

## 功能点目的

**多任务状态管理**：

1. **并行操作** - 支持同时进行的多种操作类型
2. **独立追踪** - 每种操作类型独立记录状态
3. **完成隔离** - 一个操作完成不影响其他进行中的操作
4. **清晰展示** - 用户能清楚区分不同操作

## 具体技术实现

### 测试实现

```rust
// tests.rs:5130-5151
#[tokio::test]
async fn unified_exec_unknown_end_with_active_exploring_cell_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();

    // 启动 Exploring 操作
    begin_exec(&mut chat, "call-exploring", "cat /dev/null");
    // 启动 Unified Exec（孤儿进程）
    let orphan =
        begin_unified_exec_startup(&mut chat, "call-orphan", "proc-1", "echo repro-marker");
    // Unified Exec 完成
    end_exec(&mut chat, orphan, "repro-marker\n", "", 0);

    let cells = drain_insert_history(&mut rx);
    let history = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    let active = active_blob(&chat);
    let snapshot = format!("History:\n{history}\nActive:\n{active}");
    assert_snapshot!("unified_exec_unknown_end_with_active_exploring_cell", snapshot);
}
```

### 渲染输出

```
History:
• Ran echo repro-marker
  └ repro-marker

Active:
• Exploring
  └ Read null
```

**解析**：
- `History:` - 已完成的历史记录
  - `• Ran echo repro-marker` - Unified Exec 完成记录
  - `  └ repro-marker` - 命令输出
- `Active:` - 当前进行中的操作
  - `• Exploring` - 探索操作进行中
  - `  └ Read null` - 具体读取操作

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5130-5151 | 多任务状态测试 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 3470-3480 | `begin_exec` 辅助函数 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 3530-3550 | `end_exec` 辅助函数 |

## 依赖与外部交互

### 操作类型区分

```rust
enum ActiveOperation {
    Exploring {       // 文件探索
        path: String,
        content: String,
    },
    UnifiedExec {     // 后台执行
        process_id: String,
        command: String,
    },
    // ...
}
```

### 完成处理

```rust
fn on_exec_end(&mut self, event: ExecCommandEndEvent) {
    match event.source {
        ExecCommandSource::Exploring => {
            // 更新 Exploring 单元格
        }
        ExecCommandSource::UnifiedExecStartup => {
            // 提交到历史，不影响其他操作
            self.submit_unified_exec_history(&event);
        }
        _ => {}
    }
}
```

## 风险、边界与改进建议

### 特定风险

1. **状态混淆** - 多个相似操作难以区分
2. **资源竞争** - 多个操作竞争 UI 更新
3. **完成顺序** - 操作完成的顺序与启动顺序不同

### 边界情况

1. **级联完成** - 一个操作完成触发其他操作
2. **循环依赖** - 操作之间相互等待
3. **大量并行** - 数十个同时进行的操作

### 改进建议

1. **操作分组** - 按类型或项目分组显示操作
2. **进度汇总** - 显示所有进行中的操作进度概览
3. **依赖图** - 可视化操作之间的依赖关系
4. **智能排序** - 根据优先级或时间自动排序操作

### 相关测试

- `unified_exec_end_after_task_complete_is_suppressed` - 任务完成后抑制
- `unified_exec_interaction_after_task_complete_is_suppressed` - 交互抑制
