# experimental_api.rs 研究文档

## 场景与职责

`experimental_api.rs` 是 Codex App Server v2 API 的集成测试文件，专注于**实验性 API 功能开关（Experimental API Capability）**的验证。该机制允许 Codex 团队在不破坏向后兼容性的前提下，逐步推出新功能，同时让客户端明确选择是否启用这些可能不稳定的功能。

该测试文件的核心职责包括：
1. 验证实验性 API 方法需要客户端声明 `experimentalApi` 能力才能调用
2. 验证实验性字段（如 `mock_experimental_field`）需要能力声明
3. 验证稳定 API 方法（如普通 `thread/start`）不需要实验性能力
4. 测试细粒度审批策略（Granular Approval Policy）的实验性特性

## 功能点目的

### 1. 实验性方法能力检查 (`mock_experimental_method_requires_experimental_api_capability`)
- **目的**：验证标记为实验性的 API 方法（如 `mock/experimentalMethod`）需要客户端在初始化时声明 `experimentalApi: true`
- **业务价值**：
  - 防止客户端意外使用不稳定 API
  - 为 API 演进提供安全网，允许在不破坏现有客户端的情况下修改实验性 API
- **关键验证点**：
  - 未声明 `experimentalApi` 时返回 `-32600` 错误码
  - 错误消息格式为 `"{reason} requires experimentalApi capability"`

### 2. 实时对话功能能力检查 (`realtime_conversation_start_requires_experimental_api_capability`)
- **目的**：验证实时对话功能（`thread/realtime/start`）需要实验性能力
- **业务价值**：实时对话是高级功能，可能涉及复杂的音频处理和状态管理，需要谨慎推出
- **关键验证点**：
  - 错误码和消息格式一致性
  - 验证该功能被正确标记为实验性

### 3. 实验性字段能力检查 (`thread_start_mock_field_requires_experimental_api_capability`)
- **目的**：验证 API 请求中的实验性字段（如 `mock_experimental_field`）需要能力声明
- **业务价值**：
  - 允许在稳定 API 中逐步引入新字段
  - 客户端必须明确选择才能使用新字段
- **关键验证点**：
  - 字段级粒度控制
  - 错误消息指示具体字段（`thread/start.mockExperimentalField`）

### 4. 稳定 API 无需能力声明 (`thread_start_without_dynamic_tools_allows_without_experimental_api_capability`)
- **目的**：验证普通 `thread/start` 调用（使用稳定字段）不需要实验性能力
- **业务价值**：确保向后兼容性，现有客户端不受影响
- **关键验证点**：
  - 仅使用稳定字段时调用成功
  - 响应类型正确（`ThreadStartResponse`）

### 5. 细粒度审批策略实验性检查 (`thread_start_granular_approval_policy_requires_experimental_api_capability`)
- **目的**：验证 `AskForApproval::Granular` 变体需要实验性能力
- **业务价值**：
  - 细粒度审批是复杂功能，允许用户按类别控制审批行为
  - 需要充分测试后再稳定化
- **关键验证点**：
  - 嵌套结构中的实验性标记检测
  - 错误消息指示具体路径（`askForApproval.granular`）

## 具体技术实现

### 实验性 API 机制

#### 能力声明（InitializeCapabilities）
```rust
pub struct InitializeCapabilities {
    pub experimental_api: bool,  // 是否启用实验性 API
    pub opt_out_notification_methods: Option<HashSet<String>>, // 选择退出的通知
}
```

#### 实验性标记宏（ExperimentalApi）
```rust
// 在协议类型上使用 #[experimental("reason")] 标记
#[derive(ExperimentalApi)]
pub struct AskForApproval {
    #[experimental("askForApproval.granular")]
    Granular { ... },
    // 其他稳定变体...
}
```

#### 运行时检查流程
```
Client Request
    |
    v
MessageProcessor::handle_request
    |
    v
检查 ClientRequest::experimental_reason()
    |
    +-- 返回 Some(reason) --> 检查 experimental_api_enabled
    |                           |
    |                           +-- false --> 返回错误 -32600
    |                           |
    |                           +-- true --> 继续处理
    |
    +-- 返回 None --> 继续处理
```

### 错误处理

#### 错误码定义
- **代码**：`-32600`（JSON-RPC 标准中的 Invalid Request）
- **消息格式**：`"{reason} requires experimentalApi capability"`
- **示例**：`"mock/experimentalMethod requires experimentalApi capability"`

#### 断言辅助函数
```rust
fn assert_experimental_capability_error(error: JSONRPCError, reason: &str) {
    assert_eq!(error.error.code, -32600);
    assert_eq!(error.error.message, format!("{reason} requires experimentalApi capability"));
    assert_eq!(error.error.data, None);
}
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v1.rs` | `InitializeCapabilities` 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `AskForApproval` 等实验性类型定义 |
| `codex-rs/app-server-protocol/src/experimental_api.rs` | `ExperimentalApi` trait 和宏定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | `ClientRequest` 实验性检查实现 |

### 宏实现
| 文件 | 说明 |
|------|------|
| `codex-rs/codex-experimental-api-macros/src/lib.rs` | `#[experimental(...)]` 派生宏实现 |

### 运行时检查
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/message_processor.rs` | 请求处理中的实验性能力检查 |
| `codex-rs/app-server/src/transport.rs` | 连接状态管理（`experimental_api_enabled`） |

### 测试支持
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/common/mcp_process.rs` | `initialize_with_capabilities` 辅助方法 |

## 依赖与外部交互

### 内部依赖
1. **app_test_support**：`McpProcess` 测试客户端
2. **codex_app_server_protocol**：协议类型和 `ExperimentalApi` trait
3. **codex_core**：配置和核心类型

### 关键类型依赖
```rust
use codex_app_server_protocol::{
    AskForApproval,                    // 实验性枚举
    ClientInfo,                        // 客户端信息
    InitializeCapabilities,            // 能力声明
    JSONRPCError,                      // 错误响应
    MockExperimentalMethodParams,      // 实验性方法参数
    ThreadRealtimeStartParams,         // 实时对话参数
    ThreadStartParams,                 // 线程启动参数
};
```

### 测试基础设施
- **McpProcess**：封装 MCP 子进程，提供 `initialize_with_capabilities` 方法
- **Timeout 控制**：使用 `tokio::time::timeout` 防止测试挂起

## 风险、边界与改进建议

### 风险点

1. **测试覆盖不完整**
   - 当前仅测试了部分实验性方法和字段
   - 未覆盖 `inspect_params: true` 的复杂场景
   - **建议**：添加更多边界测试，如嵌套实验性结构

2. **错误消息硬编码**
   - 测试中的错误消息格式是硬编码的
   - 如果协议变更，测试可能失败
   - **建议**：从协议库导入错误消息模板

3. **能力传播机制**
   - 测试仅验证直接调用
   - 未验证能力在多级调用中的传播
   - **建议**：添加子线程、fork 等场景的能力继承测试

### 边界情况

1. **部分实验性字段**
   - `ThreadStartParams` 使用 `inspect_params: true`
   - 某些字段需要能力，某些不需要
   - **风险**：边界判断可能出错
   - **建议**：添加仅使用稳定字段的详细测试

2. **枚举变体实验性**
   - `AskForApproval::Granular` 是实验性的，其他变体是稳定的
   - 需要确保仅在使用实验性变体时才检查能力
   - **建议**：添加枚举变体切换的测试

3. **动态工具与实验性**
   - 动态工具本身是稳定的，但某些字段可能是实验性的
   - **建议**：明确文档化动态工具的实验性边界

### 改进建议

1. **自动化测试生成**
   - 从协议定义自动生成实验性 API 测试
   - 确保所有标记为 `#[experimental]` 的项都有测试覆盖

2. **能力版本控制**
   - 考虑引入实验性能力版本（如 `experimentalApi: "v2"`）
   - 允许客户端选择特定版本的实验性功能

3. **遥测和监控**
   - 记录实验性 API 的使用情况
   - 帮助决定何时将功能稳定化

4. **文档和示例**
   - 提供启用实验性 API 的示例代码
   - 文档化每个实验性功能的风险和使用场景

5. **弃用流程**
   - 建立实验性 API 的弃用和迁移流程
   - 在功能稳定化后，提供从实验性到稳定的迁移路径
