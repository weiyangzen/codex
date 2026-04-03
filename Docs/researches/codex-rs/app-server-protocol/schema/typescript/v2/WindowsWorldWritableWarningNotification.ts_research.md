# WindowsWorldWritableWarningNotification Research

## 场景与职责

`WindowsWorldWritableWarningNotification` 是 Windows 平台特有的安全警告通知类型，用于向客户端报告系统中存在全局可写目录（world-writable directories）的情况。这些目录由于权限设置过于宽松，无法被 Windows 沙箱机制有效保护，可能成为安全隐患。

**使用场景：**
- 当 Codex 在 Windows 系统上启动时，会自动扫描系统中的目录权限
- 检测到存在全局可写目录时，向客户端发送此通知
- 用户切换到有更高安全风险的目录时触发警告
- 在启用 Agent 模式或更改沙箱策略前进行安全审计

**核心职责：**
1. 通知客户端发现的安全风险目录
2. 提供样本路径供用户查看具体问题
3. 指示是否还有更多未显示的目录
4. 报告扫描过程是否失败（如 ACL 查询错误）

## 功能点目的

该通知类型的设计目的是在 Windows 平台上提供透明的安全审计机制：

1. **安全透明度**：让用户了解系统中存在的潜在安全风险
2. **沙箱限制说明**：解释为什么某些目录无法被沙箱保护
3. **用户决策支持**：提供足够信息让用户决定是否继续使用特定沙箱模式
4. **扫描结果摘要**：通过样本路径和额外计数高效传达大量信息

**字段设计意图：**
- `samplePaths`: 最多显示 3 个样本路径，避免通知过于冗长
- `extraCount`: 当存在更多目录时，告知用户还有多少未显示
- `failedScan`: 指示扫描是否失败，失败时保护措施可能未完全生效

## 具体技术实现

### 数据结构

```typescript
export type WindowsWorldWritableWarningNotification = {
  samplePaths: Array<string>,  // 样本路径列表（最多3个）
  extraCount: number,          // 额外目录数量
  failedScan: boolean,         // 扫描是否失败
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsWorldWritableWarningNotification {
    pub sample_paths: Vec<String>,
    pub extra_count: usize,
    pub failed_scan: bool,
}
```

### 协议集成

在 `ServerNotification` 枚举中注册：
```rust
WindowsWorldWritableWarning => "windows/worldWritableWarning" (v2::WindowsWorldWritableWarningNotification)
```

### Windows 扫描实现

扫描逻辑位于 `windows-sandbox-rs/src/audit.rs`：

1. **候选目录收集** (`gather_candidates`):
   - 当前工作目录 (CWD)
   - TEMP/TMP 环境变量目录
   - USERPROFILE 和 PUBLIC 目录
   - PATH 环境变量中的目录
   - 系统根目录 (C:/, C:/Windows)

2. **权限检查** (`path_has_world_write_allow`):
   - 使用 Windows ACL API 检查 "Everyone" (World) SID 的写权限
   - 检查 `FILE_WRITE_DATA | FILE_APPEND_DATA | FILE_WRITE_EA | FILE_WRITE_ATTRIBUTES` 权限

3. **扫描限制**:
   - 每个目录最多扫描 1000 个项目
   - 总扫描时间限制 2 秒
   - 最多检查 50000 个项目
   - 跳过符号链接和特定系统目录

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4971-4975)
  - Rust 结构体定义
- `codex-rs/app-server-protocol/src/protocol/common.rs` (line 933)
  - ServerNotification 枚举注册

### TypeScript 生成
- `codex-rs/app-server-protocol/schema/typescript/v2/WindowsWorldWritableWarningNotification.ts`
  - 生成的 TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/index.ts` (line 332)
  - Barrel export
- `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts` (line 52)
  - 导入并在 union 类型中使用

### JSON Schema
- `codex-rs/app-server-protocol/schema/json/v2/WindowsWorldWritableWarningNotification.json`
- `codex-rs/app-server-protocol/schema/json/ServerNotification.json`

### Windows 扫描实现
- `codex-rs/windows-sandbox-rs/src/audit.rs`
  - `audit_everyone_writable()`: 主扫描函数
  - `gather_candidates()`: 候选目录收集
  - `path_has_world_write_allow()`: ACL 权限检查
  - `apply_world_writable_scan_and_denies()`: 扫描并应用拒绝 ACE

### 客户端处理
- `codex-rs/tui_app_server/src/app_event.rs` (lines 265-273, 341, 354)
  - `OpenWorldWritableWarningConfirmation` 事件
  - `UpdateWorldWritableWarningAcknowledged` 事件
  - `PersistWorldWritableWarningAcknowledged` 事件

- `codex-rs/tui_app_server/src/chatwidget.rs` (lines 6052, 8220-8231)
  - 通知处理和 UI 展示

- `codex-rs/tui_app_server/src/app.rs` (lines 3703, 3990, 4318, 4345, 5149)
  - 应用层事件处理

- `codex-rs/tui_app_server/src/app/app_server_adapter.rs` (line 504)
  - 服务器通知路由

### 配置相关
- `codex-rs/core/src/config/edit.rs` (lines 38, 347, 804)
  - `SetNoticeHideWorldWritableWarning` 配置项

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `windows-sandbox-rs` | Windows ACL 检查和扫描实现 |
| `app-server-protocol` | 通知类型定义和序列化 |
| `tui_app_server` | 客户端 UI 处理和事件路由 |

### Windows API 依赖

- `windows_sys::Win32::Storage::FileSystem`:
  - `FILE_WRITE_DATA`
  - `FILE_APPEND_DATA`
  - `FILE_WRITE_EA`
  - `FILE_WRITE_ATTRIBUTES`

- Windows 安全 API:
  - SID (Security Identifier) 操作
  - ACL (Access Control List) 查询
  - ACE (Access Control Entry) 应用

### 外部交互流程

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│   Windows API   │────▶│ windows-sandbox-rs   │────▶│   app-server    │
│   (ACL Query)   │     │   (audit.rs)         │     │   (notification)│
└─────────────────┘     └──────────────────────┘     └─────────────────┘
                                                              │
                                                              ▼
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│   User Action   │◀────│   TUI/chatwidget     │◀────│  ServerNotification
│  (Acknowledge)  │     │   (UI display)       │     │  (WebSocket/JSONRPC)
└─────────────────┘     └──────────────────────┘     └─────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **扫描失败风险** (`failedScan`):
   - ACL 查询可能因权限不足而失败
   - 失败时 `failedScan=true`，但用户可能忽略此标志
   - 建议：在 UI 中对扫描失败情况提供更明显的警告

2. **性能影响**:
   - 扫描大量目录可能影响启动时间
   - 虽然有时间限制（2秒）和项目限制（50000），但在慢速磁盘上仍可能卡顿

3. **信息不完整**:
   - 只显示 3 个样本路径，用户可能低估风险
   - 建议：提供查看完整列表的选项

### 边界情况

1. **非 Windows 平台**:
   - 此通知仅在 Windows 平台有意义
   - 其他平台使用 `#[cfg_attr(not(target_os = "windows"), allow(dead_code))]` 标记相关代码

2. **符号链接处理**:
   - 扫描时跳过符号链接，避免审计链接目标的 ACL
   - 这可能导致遗漏某些通过链接访问的可写目录

3. **系统目录排除**:
   - 跳过 `/windows/installer`, `/windows/registration`, `/programdata`
   - 这些目录通常有特殊的权限管理

### 改进建议

1. **UI 改进**:
   - 添加"查看全部"按钮，允许用户查看所有检测到的可写目录
   - 对 `failedScan=true` 的情况使用更醒目的警告样式
   - 提供一键修复建议（如调整 ACL）

2. **扫描优化**:
   - 考虑缓存扫描结果，避免每次启动都重新扫描
   - 提供后台扫描选项，不阻塞启动流程

3. **文档完善**:
   - 在用户文档中解释 world-writable 目录的安全风险
   - 提供如何修复这些权限问题的指导

4. **配置增强**:
   - 允许用户配置扫描范围（排除特定目录）
   - 添加忽略特定警告的选项（当前已有 `SetNoticeHideWorldWritableWarning`）

### 测试建议

- 在具有不同 ACL 配置的 Windows 环境中测试
- 验证扫描超时和限制的行为
- 测试 `failedScan=true` 时的 UI 表现
