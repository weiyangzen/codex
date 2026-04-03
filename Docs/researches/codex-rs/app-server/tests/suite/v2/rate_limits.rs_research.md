# rate_limits.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**账户速率限制查询功能** (`account/rateLimits/read`)。该功能允许客户端获取当前账户的 API 使用配额和限制状态，对于需要监控用量和实现客户端限流的场景至关重要。

测试场景覆盖：
1. **认证要求验证** - 确保只有已认证用户可以查询速率限制
2. **ChatGPT 认证要求** - 验证特定认证模式下的访问控制
3. **速率限制数据解析** - 验证从后端 API 获取的复杂速率限制数据结构能正确解析和返回

## 功能点目的

### 1. 认证层验证
- **无认证拒绝**: 当用户未登录时，API 应返回 `-32600` (Invalid Request) 错误
- **API Key 认证不足**: 仅使用 API Key 登录时，应提示需要 ChatGPT 认证
- **ChatGPT 认证通过**: 使用 ChatGPT 认证令牌时，应成功返回速率限制数据

### 2. 速率限制数据结构
测试验证了复杂的速率限制模型：
- **主窗口 (Primary Window)**: 通常是一小时窗口，包含使用百分比、窗口时长、重置时间
- **次窗口 (Secondary Window)**: 通常是24小时窗口
- **多桶视图**: 支持按 `limit_id` (如 "codex", "codex_other") 分桶的速率限制
- **计划类型**: 区分免费/专业/商业账户的不同配额

### 3. 后端 API 集成
测试使用 WireMock 模拟 ChatGPT 后端 API (`/api/codex/usage`)，验证：
- 正确的认证头传递 (`Authorization: Bearer <token>`)
- 账户 ID 头传递 (`chatgpt-account-id`)
- 响应数据到协议类型的正确映射

## 具体技术实现

### 关键流程

```
测试用例: get_account_rate_limits_returns_snapshot
1. 创建临时 CODEX_HOME 目录
2. 写入 ChatGPT 认证信息 (token, account_id, plan_type)
3. 配置 mock ChatGPT 基础 URL
4. 启动 WireMock 服务器，配置 /api/codex/usage 端点期望
5. 启动 MCP 进程，初始化连接
6. 发送 account/rateLimits/read 请求
7. 验证响应包含正确的 RateLimitSnapshot 结构
```

### 核心数据结构

```rust
// 请求参数: 无 (空参数请求)
// 响应结构:
GetAccountRateLimitsResponse {
    rate_limits: RateLimitSnapshot {
        limit_id: Option<String>,
        limit_name: Option<String>,
        primary: Option<RateLimitWindow>,
        secondary: Option<RateLimitWindow>,
        credits: Option<CreditsSnapshot>,
        plan_type: Option<PlanType>,
    },
    rate_limits_by_limit_id: Option<HashMap<String, RateLimitSnapshot>>,
}

RateLimitWindow {
    used_percent: i64,
    window_duration_mins: Option<i64>,
    resets_at: Option<i64>,  // Unix 时间戳
}
```

### 协议映射

| 后端 API 字段 | 协议类型字段 | 说明 |
|-------------|-------------|------|
| `rate_limit.primary_window` | `RateLimitWindow` | 主限制窗口 |
| `rate_limit.secondary_window` | `RateLimitWindow` | 次限制窗口 |
| `plan_type` | `PlanType` (Pro/Free/Business) | 账户计划 |
| `additional_rate_limits[]` | `rate_limits_by_limit_id` HashMap | 额外限制桶 |

后端时间戳 (RFC3339) 被转换为 Unix 时间戳 (i64) 返回给客户端。

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/rate_limits.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs` - MCP 进程管理
  - `send_get_account_rate_limits_request()` - 发送速率限制查询请求
  - `read_stream_until_response_message()` - 读取响应
  - `read_stream_until_error_message()` - 读取错误

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `GetAccountRateLimits => "account/rateLimits/read"` 方法定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `GetAccountRateLimitsResponse` (行1689)
  - `RateLimitSnapshot` (行5726)
  - `RateLimitWindow` (行5748)

### 核心实现
- `codex-rs/codex-api/src/rate_limits.rs` - 速率限制 API 实现
- `codex-rs/backend-client/src/client.rs` - 后端 HTTP 客户端

### 认证相关
- `codex-rs/app-server/tests/common/auth_fixtures.rs` - 测试认证辅助
  - `ChatGptAuthFixture` - ChatGPT 认证配置
  - `write_chatgpt_auth()` - 写入认证文件

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `wiremock` | 模拟 ChatGPT 后端 API |
| `tempfile::TempDir` | 隔离测试环境 |
| `tokio::time::timeout` | 异步测试超时控制 |
| `serde_json` | JSON 响应构造 |

### 外部服务模拟
```rust
// WireMock 配置示例
Mock::given(method("GET"))
    .and(path("/api/codex/usage"))
    .and(header("authorization", "Bearer chatgpt-token"))
    .and(header("chatgpt-account-id", "account-123"))
    .respond_with(ResponseTemplate::new(200).set_body_json(response_body))
```

### 环境变量
- `CODEX_HOME` - 指向临时目录，隔离配置和认证数据

## 风险、边界与改进建议

### 当前风险

1. **时间敏感测试**
   - 测试使用硬编码的时间戳 (RFC3339 解析)
   - 如果后端 API 格式变更，解析会失败
   - 建议: 使用相对时间或更宽松的匹配

2. **Mock 数据与真实 API 漂移**
   - Mock 的 `/api/codex/usage` 响应结构可能与真实后端不同
   - 建议: 定期同步后端 API 文档

3. **认证状态依赖**
   - 测试依赖特定的认证文件格式
   - 如果认证存储格式变更，测试会失败

### 边界情况

1. **空响应处理**
   - 测试未覆盖后端返回空响应或部分字段缺失的情况
   - 建议: 添加 `rate_limits` 为 null 或部分字段缺失的测试

2. **网络超时**
   - 测试使用 10 秒超时，但在慢网络环境下可能不稳定
   - 建议: 使用更长的超时或重试机制

3. **并发访问**
   - 未测试多线程同时查询速率限制的情况
   - 实际场景中客户端可能频繁轮询

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn get_account_rate_limits_handles_backend_500()  // 后端错误
   - async fn get_account_rate_limits_handles_malformed_response()  // 格式错误
   - async fn get_account_rate_limits_rate_limiting()  // 限流行为
   ```

2. **性能测试**
   - 添加基准测试验证速率限制查询的延迟
   - 测试高频轮询对系统的影响

3. **缓存验证**
   - 如果实现添加了速率限制缓存，需要验证缓存行为
   - 测试缓存过期和刷新逻辑

4. **多账户场景**
   - 测试切换账户后速率限制是否正确更新
   - 测试无效/过期认证令牌的优雅处理

### 相关测试文件
- `codex-rs/app-server/tests/suite/v2/account.rs` - 账户相关测试
- `codex-rs/app-server/tests/suite/auth.rs` - 认证流程测试
