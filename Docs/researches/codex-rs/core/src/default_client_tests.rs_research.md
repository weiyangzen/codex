# default_client_tests.rs 研究文档

## 场景与职责

`default_client_tests.rs` 是 `default_client.rs` 的配套测试模块，负责验证 HTTP 客户端配置的各项功能，包括 User-Agent 生成、Originator 分类、HTTP 头设置和 User-Agent 清理逻辑。

**测试覆盖范围：**
1. User-Agent 字符串格式验证
2. Originator 分类逻辑（第一方/聊天客户端）
3. HTTP 客户端默认头设置
4. Residency 头设置
5. User-Agent 非法字符清理
6. 平台特定 UA 格式（macOS）

---

## 功能点目的

### 测试用例清单

| 测试函数 | 目的 | 关键验证点 |
|---------|------|-----------|
| `test_get_codex_user_agent` | 验证 UA 格式 | 以 originator 开头，包含版本号 |
| `is_first_party_originator_matches_known_values` | 验证第一方 originator 识别 | `codex_cli_rs`, `codex_vscode`, `Codex *` |
| `is_first_party_chat_originator_matches_known_values` | 验证聊天客户端识别 | `codex_atlas`, `codex_chatgpt_desktop` |
| `test_create_client_sets_default_headers` | 验证 HTTP 客户端头设置 | originator, User-Agent, residency 头 |
| `test_invalid_suffix_is_sanitized` | 验证 UA suffix 清理（CR） | `\r` 替换为 `_` |
| `test_invalid_suffix_is_sanitized2` | 验证 UA suffix 清理（NULL） | `\0` 替换为 `_` |
| `test_macos` | 验证 macOS UA 格式 | 正则匹配版本、架构、终端信息 |

---

## 具体技术实现

### 测试基础设施

**网络跳过宏：**
```rust
use core_test_support::skip_if_no_network;
```
- 在无网络环境下跳过需要网络连接的测试

**Mock 服务器：**
```rust
use wiremock::MockServer;
use wiremock::Mock;
use wiremock::ResponseTemplate;
use wiremock::matchers::{method, path};
```
- 使用 `wiremock` 创建本地 HTTP 服务器
- 拦截和验证发出的 HTTP 请求

### 关键测试场景

**1. HTTP 头验证测试**
```rust
#[tokio::test]
async fn test_create_client_sets_default_headers() {
    skip_if_no_network!();
    set_default_client_residency_requirement(Some(ResidencyRequirement::Us));
    
    // 创建客户端并发送请求到 mock 服务器
    // 验证收到的请求包含正确的头：
    // - originator: codex_cli_rs
    // - user-agent: Codex/... (版本/OS/架构/终端)
    // - x-openai-internal-codex-residency: us
}
```
- 集成测试，需要网络连接
- 验证 residency 要求被正确转换为 HTTP 头
- 测试后清理全局状态（`set_default_client_residency_requirement(None)`）

**2. Originator 分类测试**
```rust
#[test]
fn is_first_party_originator_matches_known_values() {
    assert_eq!(is_first_party_originator(DEFAULT_ORIGINATOR), true);
    assert_eq!(is_first_party_originator("codex_vscode"), true);
    assert_eq!(is_first_party_originator("Codex Something Else"), true);
    assert_eq!(is_first_party_originator("codex_cli"), false);
    assert_eq!(is_first_party_originator("Other"), false);
}
```
- 验证第一方客户端识别逻辑
- 测试前缀匹配（`Codex `）和精确匹配

**3. User-Agent 清理测试**
```rust
#[test]
fn test_invalid_suffix_is_sanitized() {
    let prefix = "codex_cli_rs/0.0.0";
    let suffix = "bad\rsuffix";  // 包含回车符
    
    assert_eq!(
        sanitize_user_agent(format!("{prefix} ({suffix})"), prefix),
        "codex_cli_rs/0.0.0 (bad_suffix)"  // \r 被替换为 _
    );
}
```
- 验证非法 HTTP 头字符被替换为 `_`
- 测试 `\r`（回车）和 `\0`（NULL）字符

**4. macOS 平台特定测试**
```rust
#[test]
#[cfg(target_os = "macos")]
fn test_macos() {
    use regex_lite::Regex;
    let user_agent = get_codex_user_agent();
    let originator = regex_lite::escape(originator().value.as_str());
    let re = Regex::new(&format!(
        r"^{originator}/\d+\.\d+\.\d+ \(Mac OS \d+\.\d+\.\d+; (x86_64|arm64)\) (\S+)$"
    )).unwrap();
    assert!(re.is_match(&user_agent));
}
```
- 仅 macOS 平台运行
- 使用正则表达式验证 UA 格式
- 验证版本号、OS 版本、架构、终端信息

---

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/default_client_tests.rs` (123 行)

### 被测试文件
- `/home/sansha/Github/codex/codex-rs/core/src/default_client.rs` - 主实现

### 测试依赖
- `core_test_support::skip_if_no_network` - 网络检查
- `wiremock` - HTTP mock 服务器
- `pretty_assertions::assert_eq` - 更好的断言输出
- `regex_lite` - 正则匹配（macOS 测试）

---

## 依赖与外部交互

### 测试框架
| 依赖 | 用途 |
|------|------|
| `tokio::test` | 异步测试支持 |
| `wiremock` | HTTP mock 服务器 |
| `pretty_assertions` | 清晰的断言失败输出 |
| `regex_lite` | 正则表达式匹配 |

### 被测模块导入
```rust
use super::*;  // default_client.rs 的所有公开项
use crate::config_loader::ResidencyRequirement;
```

### 平台特定代码
- `#[cfg(target_os = "macos")]` - macOS 特定 UA 格式测试

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **Linux/Windows 平台测试**
   - 仅有 macOS 平台特定测试
   - 建议：添加 Linux 和 Windows 的 UA 格式测试

2. **并发测试**
   - 无全局状态并发访问测试
   - `set_default_originator` 和 `originator()` 的并发安全性未验证

3. **自定义 CA 测试**
   - 无自定义 CA 证书加载测试
   - 无 CA 加载失败回退测试

4. **Residency 边界**
   - 仅测试 `ResidencyRequirement::Us`
   - 无 `None` 情况的头缺失验证

5. **User-Agent 长度边界**
   - 无超长 UA 测试
   - 无空 suffix 测试

6. **错误处理测试**
   - 无 `SetOriginatorError::InvalidHeaderValue` 触发测试
   - 无 `SetOriginatorError::AlreadyInitialized` 触发测试

### 改进建议

1. **添加平台特定测试**
   ```rust
   #[test]
   #[cfg(target_os = "linux")]
   fn test_linux() { ... }
   
   #[test]
   #[cfg(target_os = "windows")]
   fn test_windows() { ... }
   ```

2. **添加并发安全测试**
   ```rust
   #[tokio::test]
   async fn concurrent_originator_access() {
       // 多任务同时调用 originator()
       // 验证无数据竞争
   }
   ```

3. **添加错误场景测试**
   ```rust
   #[test]
   fn test_invalid_originator_rejected() {
       let result = set_default_originator("invalid\nvalue".to_string());
       assert!(matches!(result, Err(SetOriginatorError::InvalidHeaderValue)));
   }
   ```

4. **添加集成测试**
   - 测试与 `codex-client` crate 的集成
   - 测试真实 HTTP 请求（可选，需要网络）

### 测试代码质量

**优点：**
- 使用 `wiremock` 进行真实的 HTTP 测试
- 平台特定测试使用条件编译
- 使用 `pretty_assertions` 改善断言输出
- 网络依赖测试使用 `skip_if_no_network!` 宏

**可改进点：**
- 部分测试依赖全局状态（residency 设置），需要清理
- 可添加更多边界值测试
- 可添加性能测试（UA 生成性能）
