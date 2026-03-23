# codex-rs/secrets/src/sanitizer.rs 研究文档

## 场景与职责

`sanitizer.rs` 提供了一个简单的敏感信息脱敏（redaction）工具，用于在日志、输出和持久化数据中自动识别并替换可能包含机密信息的文本模式。这是 Codex 项目中防止敏感信息泄露的重要安全机制。

主要使用场景：
1. **记忆系统脱敏**：在 `codex_core::memories::phase1` 中，模型生成的记忆内容在保存到数据库前会被脱敏处理
2. **日志输出保护**：防止 API 密钥、访问令牌等敏感信息出现在日志文件中
3. **用户界面显示**：在展示可能包含机密的文本时进行安全处理
4. **调试信息清理**：确保调试输出不包含敏感凭证

## 功能点目的

### 1. redact_secrets - 敏感信息脱敏函数
- **目的**：识别并替换文本中的常见敏感信息模式
- **输入**：原始字符串（可能包含敏感信息）
- **输出**：脱敏后的字符串，敏感部分替换为 `[REDACTED_SECRET]`
- **处理顺序**：按正则表达式顺序依次匹配替换

### 2. 正则表达式模式定义

模块定义了 4 类敏感信息识别模式：

#### 2.1 OpenAI API 密钥
```rust
static OPENAI_KEY_REGEX: LazyLock<Regex> = 
    LazyLock::new(|| compile_regex(r"sk-[A-Za-z0-9]{20,}"));
```
- **模式**：`sk-` 开头，后跟 20+ 个字母数字字符
- **匹配示例**：`sk-abc123def456ghi789jkl`
- **替换结果**：`[REDACTED_SECRET]`

#### 2.2 AWS 访问密钥 ID
```rust
static AWS_ACCESS_KEY_ID_REGEX: LazyLock<Regex> = 
    LazyLock::new(|| compile_regex(r"\bAKIA[0-9A-Z]{16}\b"));
```
- **模式**：`AKIA` 开头，后跟 16 个大写字母或数字
- **匹配示例**：`AKIAIOSFODNN7EXAMPLE`
- **替换结果**：`[REDACTED_SECRET]`
- **说明**：AWS 访问密钥 ID 以 `AKIA`（IAM 用户）或 `ASIA`（临时凭证）开头

#### 2.3 Bearer 令牌
```rust
static BEARER_TOKEN_REGEX: LazyLock<Regex> = 
    LazyLock::new(|| compile_regex(r"(?i)\bBearer\s+[A-Za-z0-9._\-]{16,}\b"));
```
- **模式**：`Bearer `（不区分大小写）后跟 16+ 个字母数字或 `._-` 字符
- **匹配示例**：`Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9`
- **替换结果**：`Bearer [REDACTED_SECRET]`（保留 `Bearer` 前缀）
- **说明**：OAuth/JWT 令牌的常见格式

#### 2.4 密钥赋值语句
```rust
static SECRET_ASSIGNMENT_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    compile_regex(r#"(?i)\b(api[_-]?key|token|secret|password)\b(\s*[:=]\s*)(["']?)[^\s"']{8,}"#)
});
```
- **模式**：关键词（api_key/api-key/token/secret/password）+ 赋值符号（`:` 或 `=`）+ 可选引号 + 8+ 个非空白字符
- **匹配示例**：
  - `api_key = "secret12345"`
  - `token:abc12345`
  - `password='mysecret'`
- **替换结果**：保留关键词和赋值符号，值替换为 `[REDACTED_SECRET]`
- **说明**：捕获配置文件或代码中的密钥赋值

### 3. compile_regex - 正则编译辅助函数
- **目的**：编译正则表达式，编译失败时 panic
- **设计选择**：使用 panic 而非返回 `Result`，因为这些正则表达式是硬编码的，编译失败表示代码缺陷
- **安全网**：`load_regex` 测试确保所有正则表达式在编译时有效

## 具体技术实现

### 关键数据结构

```rust
// 使用 LazyLock 实现延迟初始化，避免程序启动时编译正则
static OPENAI_KEY_REGEX: LazyLock<Regex> = ...;
static AWS_ACCESS_KEY_ID_REGEX: LazyLock<Regex> = ...;
static BEARER_TOKEN_REGEX: LazyLock<Regex> = ...;
static SECRET_ASSIGNMENT_REGEX: LazyLock<Regex> = ...;
```

### 关键流程

#### 脱敏处理流程
```
redact_secrets(input: String) -> String
  ├── OPENAI_KEY_REGEX.replace_all(input, "[REDACTED_SECRET]")
  ├── AWS_ACCESS_KEY_ID_REGEX.replace_all(result, "[REDACTED_SECRET]")
  ├── BEARER_TOKEN_REGEX.replace_all(result, "Bearer [REDACTED_SECRET]")
  ├── SECRET_ASSIGNMENT_REGEX.replace_all(result, "$1$2$3[REDACTED_SECRET]")
  │   └── $1=关键词, $2=赋值符号, $3=引号
  └── 返回最终字符串
```

#### 正则编译流程
```
compile_regex(pattern: &str) -> Regex
  ├── Regex::new(pattern)
  ├── Ok(regex) → 返回 regex
  └── Err(err) → panic!("invalid regex pattern `{pattern}`: {err}")
```

### 替换模式详解

| 正则 | 替换模板 | 说明 |
|------|----------|------|
| `OPENAI_KEY_REGEX` | `[REDACTED_SECRET]` | 完全替换 |
| `AWS_ACCESS_KEY_ID_REGEX` | `[REDACTED_SECRET]` | 完全替换 |
| `BEARER_TOKEN_REGEX` | `Bearer [REDACTED_SECRET]` | 保留 `Bearer` 前缀 |
| `SECRET_ASSIGNMENT_REGEX` | `$1$2$3[REDACTED_SECRET]` | 保留关键词、赋值符、引号 |

`SECRET_ASSIGNMENT_REGEX` 的捕获组：
- `$1`：关键词（`api_key`/`api-key`/`token`/`secret`/`password`）
- `$2`：赋值符号及周围空白（` = `、`:` 等）
- `$3`：可选的引号（`"` 或 `'`）

## 关键代码路径与文件引用

### 核心定义
| 类型/函数 | 位置 | 说明 |
|-----------|------|------|
| `OPENAI_KEY_REGEX` | `sanitizer.rs:4` | OpenAI 密钥匹配 |
| `AWS_ACCESS_KEY_ID_REGEX` | `sanitizer.rs:5-6` | AWS 密钥 ID 匹配 |
| `BEARER_TOKEN_REGEX` | `sanitizer.rs:7-8` | Bearer 令牌匹配 |
| `SECRET_ASSIGNMENT_REGEX` | `sanitizer.rs:9-11` | 密钥赋值语句匹配 |
| `redact_secrets` | `sanitizer.rs:15-22` | 主脱敏函数 |
| `compile_regex` | `sanitizer.rs:24-30` | 正则编译辅助 |

### 测试
| 测试 | 位置 | 说明 |
|------|------|------|
| `load_regex` | `sanitizer.rs:36-40` | 验证所有正则表达式可编译 |

## 依赖与外部交互

### 外部 Crate 依赖
| Crate | 用途 |
|-------|------|
| `regex` | 正则表达式引擎 |
| `std::sync::LazyLock` | 延迟初始化（Rust 1.80+ 标准库） |

### 调用方
| 调用者 | 位置 | 用途 |
|--------|------|------|
| `codex_core::memories::phase1` | `phase1.rs:385-387` | 记忆内容脱敏 |
| 潜在调用者 | - | 日志输出、调试信息、UI 显示 |

### 公开接口
```rust
// 在 lib.rs 中重导出
pub use sanitizer::redact_secrets;  // lib.rs:19
```

## 风险、边界与改进建议

### 风险点

1. **误报（False Positives）**
   - `SECRET_ASSIGNMENT_REGEX` 可能匹配非敏感的配置项
   - 例如：`password = "none"` 或 `token = ""` 也会被脱敏
   - **影响**：可能导致合法信息被隐藏

2. **漏报（False Negatives）**
   - 正则表达式覆盖有限，无法识别所有敏感信息格式
   - 例如：
     - GitHub Personal Access Token（`ghp_`、`github_pat_` 开头）
     - Slack Token（`xoxb-`、`xoxp-` 开头）
     - 其他云服务提供商的密钥格式
   - **影响**：新型或小众格式的敏感信息可能泄露

3. **性能问题**
   - 每条正则都扫描整个输入字符串
   - 长文本或多模式匹配时可能有性能开销
   - **当前场景**：主要用于记忆内容（通常较短），风险较低

4. **大小写敏感问题**
   - `OPENAI_KEY_REGEX` 和 `AWS_ACCESS_KEY_ID_REGEX` 大小写敏感
   - 如果密钥以小写形式出现（如用户输入错误），可能无法识别
   - `BEARER_TOKEN_REGEX` 和 `SECRET_ASSIGNMENT_REGEX` 使用 `(?i)` 不区分大小写

5. **正则表达式拒绝服务（ReDoS）**
   - 当前正则表达式较为简单，ReDoS 风险较低
   - 但 `{20,}` 和 `{16,}` 量词在极端输入下可能有性能问题

### 边界条件

1. **空字符串处理**
   - 空字符串输入返回空字符串（无匹配）
   - 这是正常行为

2. **重叠匹配**
   - 多个正则可能匹配同一文本的不同部分
   - 处理顺序很重要，后续正则在前一个替换结果上工作

3. **部分匹配**
   - `SECRET_ASSIGNMENT_REGEX` 要求值至少 8 个字符
   - 短密码/令牌不会被识别（如 `pwd=123`）

4. **多行文本**
   - 正则默认不匹配换行符（`.` 不匹配 `\n`）
   - 多行密钥（如 PEM 格式）不会被完整匹配

### 改进建议

1. **扩展正则覆盖**
   - 添加更多常见密钥格式：
     ```rust
     // GitHub
     static GITHUB_TOKEN_REGEX: LazyLock<Regex> = 
         LazyLock::new(|| compile_regex(r"\b(ghp_|github_pat_)[A-Za-z0-9_]{36,}\b"));
     
     // Slack
     static SLACK_TOKEN_REGEX: LazyLock<Regex> = 
         LazyLock::new(|| compile_regex(r"\bxox[baprs]-[0-9]{10,13}-[0-9]{10,13}(-[a-zA-Z0-9]{24})?\b"));
     
     // Generic JWT
     static JWT_REGEX: LazyLock<Regex> = 
         LazyLock::new(|| compile_regex(r"\beyJ[A-Za-z0-9_-]*\.eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\b"));
     ```

2. **配置化正则列表**
   - 允许用户自定义正则表达式
   - 支持启用/禁用特定脱敏规则
   - 从配置文件加载额外模式

3. **智能阈值**
   - `SECRET_ASSIGNMENT_REGEX` 的 8 字符阈值可配置
   - 根据上下文调整敏感度

4. **性能优化**
   - 使用 `regex::RegexSet` 同时匹配多个模式
   - 对长文本进行分块处理
   - 添加短路逻辑（如无可疑关键词则跳过正则匹配）

5. **改进替换策略**
   - 保留部分信息以便调试（如 `sk-...last4`）
   - 对不同类型的机密使用不同的替换标记（如 `[REDACTED_API_KEY]`）

6. **机器学习增强**
   - 使用简单的启发式或 ML 模型识别潜在的敏感信息
   - 作为正则的补充而非替代

7. **审计和统计**
   - 记录脱敏操作统计（脱敏次数、类型分布）
   - 支持调试模式查看原始内容（仅限授权用户）

### 测试覆盖

当前测试：
- `load_regex`：验证正则表达式可编译

建议补充：
- 各正则表达式的正向匹配测试（应匹配）
- 负向匹配测试（不应匹配）
- 复杂文本场景测试（多模式、重叠）
- 性能基准测试（大文本处理）
- 边界值测试（最短/最长匹配）

示例测试用例：
```rust
#[test]
fn test_redact_openai_key() {
    let input = "My key is sk-abc123def456ghi789jkl012mn".to_string();
    let result = redact_secrets(input);
    assert_eq!(result, "My key is [REDACTED_SECRET]");
}

#[test]
fn test_redact_bearer_token() {
    let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9".to_string();
    let result = redact_secrets(input);
    assert_eq!(result, "Authorization: Bearer [REDACTED_SECRET]");
}

#[test]
fn test_redact_assignment() {
    let input = r#"api_key = "secret123456789""#.to_string();
    let result = redact_secrets(input);
    assert_eq!(result, r#"api_key = "[REDACTED_SECRET]""#);
}
```
