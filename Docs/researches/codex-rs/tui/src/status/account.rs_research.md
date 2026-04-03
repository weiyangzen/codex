# account.rs 研究文档

## 场景与职责

`account.rs` 是 Codex TUI 状态显示模块中最简单的组件，负责定义账户信息的显示枚举类型。该模块将核心层的认证模式（AuthMode）转换为 TUI 可渲染的显示格式，区分 ChatGPT 账户登录和 API Key 两种认证方式。

## 功能点目的

### StatusAccountDisplay 枚举

```rust
pub(crate) enum StatusAccountDisplay {
    ChatGpt {
        email: Option<String>,
        plan: Option<String>,
    },
    ApiKey,
}
```

该枚举有两个变体：

1. **ChatGpt**: 表示用户通过 ChatGPT 网页版登录
   - `email`: 用户邮箱地址（可选）
   - `plan`: 订阅计划类型（可选，如 Plus、Pro 等）

2. **ApiKey**: 表示用户使用 API Key 认证

## 具体技术实现

### 数据结构

- 使用 `#[derive(Debug, Clone)]` 派生调试和克隆能力
- 字段使用 `Option<String>` 包装，允许信息缺失时的优雅降级

### 使用场景

该枚举在 `helpers.rs` 中的 `compose_account_display` 函数中被创建和使用：

```rust
pub(crate) fn compose_account_display(
    auth_manager: &AuthManager,
    plan: Option<PlanType>,
) -> Option<StatusAccountDisplay> {
    let auth = auth_manager.auth_cached()?;
    match auth.auth_mode() {
        CoreAuthMode::ApiKey => Some(StatusAccountDisplay::ApiKey),
        CoreAuthMode::Chatgpt => {
            let email = auth.get_account_email();
            let plan = plan.map(|plan_type| title_case(format!("{plan_type:?}").as_str()))
                .or_else(|| Some("Unknown".to_string()));
            Some(StatusAccountDisplay::ChatGpt { email, plan })
        }
    }
}
```

## 关键代码路径与文件引用

### 被调用方

- `helpers.rs`: `compose_account_display` 函数创建 `StatusAccountDisplay` 实例
- `card.rs`: 在 `StatusHistoryCell` 中使用，用于渲染账户信息行

### 渲染逻辑（card.rs）

```rust
let account_value = self.account.as_ref().map(|account| match account {
    StatusAccountDisplay::ChatGpt { email, plan } => match (email, plan) {
        (Some(email), Some(plan)) => format!("{email} ({plan})"),
        (Some(email), None) => email.clone(),
        (None, Some(plan)) => plan.clone(),
        (None, None) => "ChatGPT".to_string(),
    },
    StatusAccountDisplay::ApiKey => {
        "API key configured (run codex login to use ChatGPT)".to_string()
    }
});
```

## 依赖与外部交互

### 上游依赖

| 模块/类型 | 来源 | 用途 |
|-----------|------|------|
| `AuthManager` | `codex_core::AuthManager` | 获取认证信息 |
| `PlanType` | `codex_protocol::account::PlanType` | 订阅计划类型 |
| `AuthMode` | `codex_core::auth::AuthMode` | 区分认证模式 |

### 下游使用

- `card.rs`: 在状态卡片中显示账户信息
- 影响 Token 使用量的显示（ChatGPT 用户不显示 Token 使用量）

## 风险、边界与改进建议

### 边界情况

1. **信息缺失处理**: 当 email 和 plan 都缺失时，显示简单的 "ChatGPT" 字符串
2. **API Key 提示**: 使用 API Key 时，提示用户可以运行 `codex login` 切换到 ChatGPT 模式

### 潜在风险

1. **信息泄露风险**: 邮箱地址在状态卡片中明文显示，在屏幕共享场景下可能泄露隐私
2. **计划类型硬编码**: 依赖于 `PlanType` 枚举的 `Debug` 输出格式，如果协议层修改命名风格，显示可能不一致

### 改进建议

1. **隐私保护**: 考虑添加配置选项，允许用户隐藏邮箱地址显示
2. **国际化**: 当前字符串硬编码为英文，后续可考虑支持多语言
3. **扩展性**: 如果未来增加更多认证方式（如 OAuth、SSO），需要扩展该枚举

### 代码度量

- 代码行数: 8 行
- 复杂度: 极低（纯数据结构定义）
- 测试覆盖: 通过 `card.rs` 和 `helpers.rs` 的集成测试间接覆盖
