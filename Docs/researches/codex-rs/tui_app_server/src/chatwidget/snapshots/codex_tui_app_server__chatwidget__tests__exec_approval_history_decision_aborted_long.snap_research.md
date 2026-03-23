# 研究文档：Exec Approval History Decision Aborted Long 快照测试

## 场景与职责

此快照文件验证当用户拒绝（取消）一个极长的命令执行请求时，TUI 如何在历史记录中渲染这个"已中止"的决定。测试确保超长命令（200+ 字符）在显示时能够被正确截断，避免历史记录被冗长命令淹没，同时保留足够信息让用户理解被拒绝的操作。

## 功能点目的

1. **命令截断显示**：当命令超过 80 字符时，自动截断并添加 "..." 后缀
2. **用户决策记录**：记录用户明确拒绝执行命令的决定
3. **历史记录简洁性**：保持历史记录的可读性，避免单行过长
4. **拒绝状态可视化**：使用 ✗ 标记清晰表示操作被取消

## 具体技术实现

### 关键流程

测试代码位于 `codex-rs/tui_app_server/src/chatwidget/tests.rs` 行 3457-3490，是更大测试函数的一部分：

1. **构造超长命令**：
   ```rust
   let long = format!("echo {}", "a".repeat(200));  // 生成 205 字符的命令
   ```

2. **创建执行批准请求事件**：
   ```rust
   let ev_long = ExecApprovalRequestEvent {
       call_id: "call-long".into(),
       approval_id: Some("call-long".into()),
       turn_id: "turn-long".into(),
       command: vec!["bash".into(), "-lc".into(), long],
       cwd: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
       reason: None,
       network_approval_context: None,
       proposed_execpolicy_amendment: None,
       proposed_network_policy_amendments: None,
       additional_permissions: None,
       skill_metadata: None,
       available_decisions: None,
       parsed_cmd: vec![],
   };
   ```

3. **发送批准请求**：
   ```rust
   chat.handle_codex_event(Event {
       id: "sub-long".into(),
       msg: EventMsg::ExecApprovalRequest(ev_long),
   });
   ```

4. **验证请求不立即写入历史**：
   ```rust
   let proposed_long = drain_insert_history(&mut rx);
   assert!(proposed_long.is_empty(), 
       "expected long approval request to avoid emitting history cells before decision");
   ```

5. **模拟用户拒绝（按 'n' 键）**：
   ```rust
   chat.handle_key_event(KeyEvent::new(KeyCode::Char('n'), KeyModifiers::NONE));
   ```

6. **捕获历史记录并验证**：
   ```rust
   let aborted_long = drain_insert_history(&mut rx)
       .pop()
       .expect("expected aborted decision cell (long)");
   assert_snapshot!("exec_approval_history_decision_aborted_long", 
       lines_to_single_string(&aborted_long));
   ```

### 数据结构

**ExecApprovalRequestEvent**（定义于 `codex-rs/protocol/src/approvals.rs` 行 147）：
```rust
pub struct ExecApprovalRequestEvent {
    pub call_id: String,
    pub approval_id: Option<String>,  // 子命令批准的回调标识
    pub turn_id: String,
    pub command: Vec<String>,         // 完整命令数组
    pub cwd: PathBuf,
    pub reason: Option<String>,       // 批准原因（如重试时无沙盒）
    pub network_approval_context: Option<NetworkApprovalContext>,
    pub proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
    pub proposed_network_policy_amendments: Option<Vec<NetworkPolicyAmendment>>,
    pub additional_permissions: Option<PermissionProfile>,
    pub skill_metadata: Option<ExecApprovalRequestSkillMetadata>,
    pub available_decisions: Option<Vec<ReviewDecision>>, // 可用的决策选项
}
```

### 命令截断逻辑

从历史记录渲染代码推断，命令截断遵循以下规则：
- 单行命令超过 80 字符时截断
- 截断后添加 "..." 后缀
- 保留命令开头部分（通常是命令名和前几参数）

快照输出显示：
```
✗ You canceled the request to run echo
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...
```
- "echo" 和大约 72 个 'a' 被保留
- 剩余部分被 "..." 替代

## 关键代码路径与文件引用

### 测试代码
- **文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
- **测试函数**：包含在更大的批准流程测试函数中（行 ~3400-3500）
- **具体代码段**：行 3457-3490
- **辅助函数**：
  - `lines_to_single_string`（行 2075）：将 ratatui Line 数组转换为字符串
  - `drain_insert_history`：清空并返回历史记录通道中的内容

### 被测试的组件
- **文件**：`codex-rs/tui_app_server/src/chatwidget.rs`
  - `handle_codex_event` 处理 `EventMsg::ExecApprovalRequest`
  - `handle_key_event` 处理用户按键（'n' 表示拒绝）
  - 历史记录更新逻辑

### 协议定义
- **文件**：`codex-rs/protocol/src/approvals.rs`
  - `ExecApprovalRequestEvent`（行 147）
  - `ReviewDecision` 枚举（决定选项）

### 历史记录渲染
- **文件**：`codex-rs/tui_app_server/src/history_cell/` 目录
  - 负责将执行事件转换为可渲染的历史记录单元格

## 依赖与外部交互

### 上游依赖
1. **codex-protocol**：定义 `ExecApprovalRequestEvent` 和相关类型
2. **ratatui**：提供文本渲染和行处理功能
3. **insta**：快照测试框架
4. **crossterm**（间接）：键盘事件定义

### 下游消费
1. **历史记录系统**：被拒绝的命令以截断形式写入历史记录
2. **用户界面**：在历史记录面板中显示中止的操作

### 相关测试
- `exec_approval_history_decision_aborted_multiline`：测试多行命令的截断
- `exec_approval_history_decision_aborted_long`：本快照，测试超长单行命令

## 风险、边界与改进建议

### 当前风险

1. **硬编码截断长度**：80 字符限制是硬编码的，可能不适合所有终端宽度
2. **信息丢失**：截断可能导致关键参数被隐藏（如重要文件路径或选项）
3. **无展开机制**：用户无法在历史记录中查看完整命令

### 边界情况

1. **恰好 80 字符**：未测试边界值（79, 80, 81 字符）
2. **多字节字符**：测试使用 ASCII 'a'，未测试 Unicode 字符的截断
3. **空命令**：未测试 command 数组为空或只有空字符串的情况
4. **非常长的单个参数**：200 个字符的单个参数 vs 多个短参数的组合

### 改进建议

1. **动态截断**：
   ```rust
   // 根据终端宽度动态计算截断长度
   let max_len = terminal_width.saturating_sub(prefix_len + suffix_len);
   ```

2. **智能截断**：
   - 优先保留命令名和关键选项
   - 在中间截断而非简单截断尾部
   - 示例：`echo ...aaaaaaaaaaaaaaaa...` 而非 `echo aaaaa...`

3. **交互式展开**：
   - 在历史记录中支持按 Enter 或点击展开完整命令
   - 添加工具提示显示完整命令

4. **增加边界测试**：
   - 测试 79, 80, 81 字符的边界情况
   - 测试包含 Unicode 字符的命令
   - 测试包含换行符的命令

5. **配置选项**：
   - 允许用户在配置中设置截断长度
   - 提供 "不截断" 选项（自动换行）

6. **改进显示格式**：
   - 考虑使用折叠/展开控件
   - 添加命令长度指示器（如 "... (+123 chars)"）
