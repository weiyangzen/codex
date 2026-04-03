# pkce.rs 研究文档

## 场景与职责

`pkce.rs` 实现了 **PKCE（Proof Key for Code Exchange）** 扩展，这是 OAuth 2.0 公共客户端（如移动应用、单页应用、CLI 工具）的标准安全机制，定义于 RFC 7636。

### 核心使用场景

1. **公共 OAuth 客户端**：无法安全存储 client_secret 的客户端
2. **本地回调服务器**：`server.rs` 中的 `http://localhost` 回调
3. **设备码流程**：`device_code_auth.rs` 中的授权码交换

### 模块职责

- 生成符合 RFC 7636 标准的 PKCE 码对（verifier + challenge）
- 使用 S256（SHA-256）变换方法
- 提供 `PkceCodes` 数据结构供其他模块使用

---

## 功能点目的

### 1. PKCE 码对生成 (`generate_pkce`)

**目的**：创建一次性使用的 PKCE 参数，防止授权码拦截攻击

**安全价值**：
- 即使授权码被截获，攻击者没有 `code_verifier` 也无法交换令牌
- 保护公共客户端的授权码流程

### 2. 数据结构 (`PkceCodes`)

**目的**：封装 PKCE 参数，便于在模块间传递

```rust
pub struct PkceCodes {
    pub code_verifier: String,   // 原始随机码（43-128 字符）
    pub code_challenge: String,  // SHA256(verifier) 的 base64url 编码
}
```

---

## 具体技术实现

### 算法实现

```rust
pub fn generate_pkce() -> PkceCodes {
    // 1. 生成 64 字节随机数
    let mut bytes = [0u8; 64];
    rand::rng().fill_bytes(&mut bytes);

    // 2. 创建 code_verifier：URL-safe base64 无填充
    let code_verifier = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes);

    // 3. 创建 code_challenge：SHA256(verifier) + base64url
    let digest = Sha256::digest(code_verifier.as_bytes());
    let code_challenge = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(digest);

    PkceCodes { code_verifier, code_challenge }
}
```

### 技术细节

| 参数 | 规范要求 | 实现 |
|------|----------|------|
| Verifier 长度 | 43-128 字符 | 64 字节 → ~86 字符 base64 |
| Challenge 方法 | S256 或 plain | 仅 S256（更安全） |
| 编码 | base64url | `URL_SAFE_NO_PAD` |
| 随机源 | 密码学安全 | `rand::rng()` |

### 哈希流程

```
随机字节 (64 bytes)
    ↓
URL_SAFE_NO_PAD base64 编码 → code_verifier
    ↓
SHA-256 哈希
    ↓
URL_SAFE_NO_PAD base64 编码 → code_challenge
```

---

## 关键代码路径与文件引用

### 内部使用

| 使用者 | 路径 | 用途 |
|--------|------|------|
| `server.rs` | `crate::pkce::generate_pkce` | 浏览器登录流程 |
| `server.rs` | `crate::pkce::PkceCodes` | 存储和传递 PKCE 参数 |
| `device_code_auth.rs` | `crate::pkce::PkceCodes` | 设备码流程复用 |

### 使用示例（来自 server.rs）

```rust
use crate::pkce::PkceCodes;
use crate::pkce::generate_pkce;

// 生成 PKCE 参数
let pkce = generate_pkce();

// 构建授权 URL（使用 code_challenge）
let auth_url = build_authorize_url(
    &opts.issuer,
    &opts.client_id,
    &redirect_uri,
    &pkce,  // 包含 code_challenge
    &state,
    opts.forced_chatgpt_workspace_id.as_deref(),
);

// 交换令牌（使用 code_verifier）
let tokens = exchange_code_for_tokens(
    &opts.issuer,
    &opts.client_id,
    redirect_uri,
    &pkce,  // 包含 code_verifier
    &code,
).await?;
```

### 使用示例（来自 device_code_auth.rs）

```rust
// 设备码流程从服务器获取 code_verifier 和 code_challenge
let pkce = PkceCodes {
    code_verifier: code_resp.code_verifier,
    code_challenge: code_resp.code_challenge,
};

// 复用 server.rs 的交换逻辑
let tokens = crate::server::exchange_code_for_tokens(
    base_url,
    &opts.client_id,
    &redirect_uri,
    &pkce,
    &code_resp.authorization_code,
).await?;
```

---

## 依赖与外部交互

### 依赖 crate

```rust
use base64::Engine;
use rand::RngCore;
use sha2::Digest;
use sha2::Sha256;
```

| Crate | 用途 |
|-------|------|
| `base64` | URL-safe base64 编码（无填充） |
| `rand` | 密码学安全的随机数生成 |
| `sha2` | SHA-256 哈希算法 |

### Cargo.toml

```toml
[dependencies]
base64 = { workspace = true }
rand = { workspace = true }
sha2 = { workspace = true }
```

---

## 风险、边界与改进建议

### 当前实现的优势

1. **简洁性**：仅 27 行代码，职责单一
2. **标准合规**：严格遵循 RFC 7636
3. **安全性**：使用 S256 方法，verifier 长度充足

### 潜在风险

1. **随机数质量**
   - 依赖 `rand::rng()`，假设为密码学安全
   - 风险：如果 `rand` crate 实现有缺陷，会影响安全性
   - 缓解：`rand` 是广泛审计的标准 crate

2. **模块完全私有**
   ```rust
   // lib.rs 中
   mod pkce;  // 未导出任何内容
   ```
   - 外部无法使用 PKCE 功能
   - 如果其他 crate 需要 PKCE，必须重新实现

3. **无验证功能**
   - 没有提供 `verify_challenge(verifier, challenge)` 函数
   - 如果需要服务端验证，需要额外实现

### 边界情况

| 场景 | 行为 |
|------|------|
| 并发调用 | 每次生成独立随机码，安全 |
| 短生命周期 | PKCE 码对仅用于单次授权流程 |
| 编码兼容性 | URL_SAFE_NO_PAD 符合 RFC 7636 要求 |

### 改进建议

1. **导出供外部使用**
   ```rust
   // lib.rs
   pub use pkce::{generate_pkce, PkceCodes};
   ```
   - 允许高级用户自定义 OAuth 流程

2. **添加验证方法**
   ```rust
   impl PkceCodes {
       /// 验证 challenge 是否正确计算自 verifier
       pub fn verify(&self) -> bool {
           let digest = Sha256::digest(self.code_verifier.as_bytes());
           let expected = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(digest);
           expected == self.code_challenge
       }
   }
   ```

3. **添加测试**
   ```rust
   #[cfg(test)]
   mod tests {
       use super::*;
       
       #[test]
       fn pkce_challenge_is_valid_hash() {
           let pkce = generate_pkce();
           assert!(pkce.verify());
       }
       
       #[test]
       fn pkce_verifier_has_correct_length() {
           let pkce = generate_pkce();
           assert!(pkce.code_verifier.len() >= 43);
           assert!(pkce.code_verifier.len() <= 128);
       }
   }
   ```

4. **文档完善**
   ```rust
   //! PKCE (RFC 7636) implementation for OAuth 2.0 public clients.
   //! 
   //! # Example
   //! ```
   //! use codex_login::generate_pkce;
   //! 
   //! let pkce = generate_pkce();
   //! println!("Challenge: {}", pkce.code_challenge);
   //! ```
   ```

### 安全审计要点

1. **随机数熵**：64 字节 = 512 位，远超 RFC 7636 最低要求（256 位）
2. **哈希算法**：SHA-256 是标准选择
3. **编码**：base64url 无填充避免 URL 编码问题
4. **无硬编码**：所有参数随机生成，无静态密钥风险
