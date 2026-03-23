# token_data_tests.rs 研究文档

## 场景与职责

`token_data_tests.rs` 是 `token_data.rs` 的配套测试模块，负责验证 JWT 解析和计划类型识别的正确性：

1. **标准 JWT 解析测试**：验证正常 JWT 的 email 和 plan 提取
2. **Go 计划测试**：验证 "go" 计划类型的特殊处理
3. **缺失字段处理**：验证 JWT 缺少可选字段时的降级行为
4. **工作区账户检测**：验证 `is_workspace_account()` 方法的正确性

该模块使用内联测试方式（`#[path = "token_data_tests.rs"]`）。

## 功能点目的

### 1. 标准解析测试 (`id_token_info_parses_email_and_plan`)

验证：
- Email 从顶级 `email` 字段提取
- Plan 从 `https://api.openai.com/auth.chatgpt_plan_type` 提取
- Pro 计划正确映射到 `KnownPlan::Pro`

### 2. Go 计划测试 (`id_token_info_parses_go_plan`)

验证 "go" 计划类型（可能是特定市场/推广类型）的正确解析。

### 3. 缺失字段测试 (`id_token_info_handles_missing_fields`)

验证：
- 最小 JWT（仅含 `sub`）可正常解析
- 可选字段返回 `None` 而非 panic

### 4. 工作区检测测试 (`workspace_account_detection_matches_workspace_plans`)

验证：
- Business 计划识别为工作区账户
- Pro 计划识别为个人账户

## 具体技术实现

### JWT 构造辅助

```rust
#[derive(Serialize)]
struct Header {
    alg: &'static str,
    typ: &'static str,
}

fn b64url_no_pad(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

// 构造测试 JWT
let header_b64 = b64url_no_pad(&serde_json::to_vec(&header).unwrap());
let payload_b64 = b64url_no_pad(&serde_json::to_vec(&payload).unwrap());
let signature_b64 = b64url_no_pad(b"sig");
let fake_jwt = format!("{header_b64}.{payload_b64}.{signature_b64}");
```

### 测试断言模式

```rust
let info = parse_chatgpt_jwt_claims(&fake_jwt).expect("should parse");
assert_eq!(info.email.as_deref(), Some("user@example.com"));
assert_eq!(info.get_chatgpt_plan_type().as_deref(), Some("Pro"));
```

注意：`get_chatgpt_plan_type()` 返回格式化字符串（首字母大写）。

### 工作区检测断言

```rust
let workspace = IdTokenInfo {
    chatgpt_plan_type: Some(PlanType::Known(KnownPlan::Business)),
    ..IdTokenInfo::default()
};
assert_eq!(workspace.is_workspace_account(), true);

let personal = IdTokenInfo {
    chatgpt_plan_type: Some(PlanType::Known(KnownPlan::Pro)),
    ..IdTokenInfo::default()
};
assert_eq!(personal.is_workspace_account(), false);
```

## 关键代码路径与文件引用

### 被测函数

| 函数 | 路径 | 测试 |
|------|------|------|
| `parse_chatgpt_jwt_claims` | `token_data.rs:130` | `id_token_info_parses_email_and_plan` |
| `parse_chatgpt_jwt_claims` | `token_data.rs:130` | `id_token_info_parses_go_plan` |
| `parse_chatgpt_jwt_claims` | `token_data.rs:130` | `id_token_info_handles_missing_fields` |
| `IdTokenInfo::is_workspace_account` | `token_data.rs:46` | `workspace_account_detection_matches_workspace_plans` |

### 测试依赖

| crate | 用途 |
|-------|------|
| `serde::Serialize` | 构造 JWT header/payload |
| `base64` | Base64 URL 编码 |
| `pretty_assertions` | 友好断言输出 |

## 依赖与外部交互

### 测试数据

测试使用构造的 JWT，不涉及：
- 真实认证服务
- 文件系统
- 网络请求

### 纯单元测试

所有测试均为纯计算，无异步操作，使用 `#[test]` 而非 `#[tokio::test]`。

## 风险、边界与改进建议

### 当前覆盖缺口

1. **无效 JWT 格式**：未测试缺少段、空段、非 Base64 字符
2. **Base64 解码失败**：未测试损坏的编码
3. **JSON 解析失败**：未测试非 JSON payload
4. **备用 email 路径**：未测试 `https://api.openai.com/profile.email`
5. **备用 user_id 路径**：未测试 `user_id` 作为 `chatgpt_user_id` 备用
6. **所有计划类型**：仅测试 Pro、Go、Business，缺少 Free/Team/Enterprise/Edu

### 改进建议

1. **添加错误场景测试**：
```rust
#[test]
fn rejects_malformed_jwt() {
    assert!(parse_chatgpt_jwt_claims("not.a.jwt").is_err());
    assert!(parse_chatgpt_jwt_claims("only.two").is_err());
}

#[test]
fn rejects_invalid_base64() {
    let bad_jwt = "header.!!!invalid!!!.sig";
    assert!(matches!(
        parse_chatgpt_jwt_claims(bad_jwt),
        Err(IdTokenInfoError::Base64(_))
    ));
}
```

2. **添加 profile email 路径测试**：
```rust
#[test]
fn extracts_email_from_profile_claims() {
    let payload = json!({
        "https://api.openai.com/profile": { "email": "profile@example.com" }
    });
    // 验证 email 提取
}
```

3. **添加所有计划类型测试**：
```rust
#[test_case("free", "Free")]
#[test_case("plus", "Plus")]
#[test_case("pro", "Pro")]
#[test_case("team", "Team")]
#[test_case("business", "Business")]
#[test_case("enterprise", "Enterprise")]
#[test_case("education", "Edu")]
#[test_case("edu", "Edu")]
#[test_case("unknown_plan", "unknown_plan")]  // Unknown 变体
fn parses_plan_type(raw: &str, expected: &str) { ... }
```

4. **使用 `test-case` crate**：简化参数化测试

### 代码统计

- 测试行数：109 行
- 测试函数：4 个
- 辅助函数：2 个（`b64url_no_pad` 在每个测试中重复定义）

### 代码异味

1. **重复代码**：`b64url_no_pad` 和 `Header` 结构体在每个测试中重复定义，建议提取为模块级辅助
2. **魔法字符串**：`"Pro"`、`"Go"` 等预期值应与实现同步
