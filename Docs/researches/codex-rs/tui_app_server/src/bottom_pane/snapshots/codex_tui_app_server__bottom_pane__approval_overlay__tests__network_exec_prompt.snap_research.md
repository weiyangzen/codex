# TUI App Server Approval Overlay Network Exec Prompt Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `approval_overlay.rs` 模块的测试快照，与 `codex_tui` 前缀的对应文件类似，但针对 `tui_app_server` crate 进行验证。用于验证**网络访问审批覆盖层**在 app-server 架构下的渲染输出。

### 与 TUI Crate 的关系
- `tui_app_server` 是 Codex 的 TUI 应用服务器实现
- 与 `tui` crate 共享相同的审批覆盖层逻辑
- 通过快照测试确保两者渲染一致性

### 快照差异
对比 `codex_tui` 和 `codex_tui_app_server` 版本：
- 两者渲染输出基本一致
- `tui_app_server` 版本使用 `format!("{buf:?}")` 输出 Buffer 的 Debug 表示
- 包含更详细的样式信息

## 功能点目的

### 核心功能
与 `codex_tui` 版本相同：
1. **主机标识**：清晰显示要访问的网络主机
2. **理由说明**：解释为什么需要网络访问
3. **分级授权**：提供多种授权选项
4. **拒绝选项**：允许拒绝并继续

### App-Server 特定目标
- **协议兼容性**：确保通过 app-server 协议正确处理审批
- **决策同步**：确保用户决策正确传递到服务器
- **状态管理**：正确处理审批状态

## 具体技术实现

### 渲染输出分析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 100, height: 12 },
    content: [
        "                                                                                                    ",
        "  Do you want to approve network access to "example.com"?                                           ",
        "                                                                                                    ",
        "  Reason: network request blocked                                                                   ",
        "                                                                                                    ",
        "                                                                                                    ",
        "› 1. Yes, just this once (y)                                                                        ",
        "  2. Yes, and allow this host for this conversation (a)                                             ",
        "  3. Yes, and allow this host in the future (p)                                                     ",
        "  4. No, and tell Codex what to do differently (esc)                                                ",
        "                                                                                                    ",
        "  Press enter to confirm or esc to cancel                                                           ",
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 2, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: BOLD,
        x: 57, y: 1, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 10, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: ITALIC,
        x: 33, y: 3, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 0, y: 6, fg: Cyan, bg: Reset, underline: Reset, modifier: BOLD,
        x: 28, y: 6, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 53, y: 7, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 54, y: 7, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 45, y: 8, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 46, y: 8, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 48, y: 9, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
        x: 51, y: 9, fg: Reset, bg: Reset, underline: Reset, modifier: NONE,
        x: 2, y: 11, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,
    ]
}
```

### 样式分析
- `y: 1` (标题行): `BOLD` - 标题加粗
- `y: 3` (理由行): `ITALIC` - 理由斜体
- `y: 6` (选中选项): `Cyan` + `BOLD` - 选中项青色加粗
- `y: 7, 8, 9` (快捷键): `DIM` - 快捷键灰色
- `y: 11` (底部提示): `DIM` - 提示灰色

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- **测试函数**: `network_exec_prompt` (在 tests 模块中)

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::NetworkApprovalContext`
- `codex_protocol::protocol::NetworkPolicyAmendment`
- `ratatui::buffer::Buffer`

### 外部交互
- **App Server**：通过协议处理审批请求
- **网络策略管理器**：存储和应用网络访问规则

## 风险、边界与改进建议

### 潜在风险
1. **协议延迟**：审批决策的网络延迟
2. **状态不一致**：客户端和服务器审批状态不一致
3. **并发审批**：多个并发审批请求的处理

### 边界情况
1. **连接断开**：审批过程中断开连接
2. **超时**：服务器响应超时
3. **重复请求**：相同的审批请求多次发送

### 改进建议
1. **本地缓存**：缓存最近的审批决策
2. **乐观更新**：先更新本地状态，再同步服务器
3. **冲突解决**：处理客户端和服务器状态冲突
4. **审批队列**：管理多个待处理审批

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- 协议定义: `codex-rs/app-server-protocol/src/protocol/`
