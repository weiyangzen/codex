# rule.rs 研究文档

## 场景与职责

`rule.rs` 是 `codex-execpolicy` crate 的**规则定义和匹配核心模块**，负责：

1. **规则类型定义**：定义前缀规则、网络规则的数据结构
2. **模式匹配逻辑**：实现前缀匹配算法
3. **模式 token 表示**：支持单值和替代值（alternatives）
4. **规则匹配结果**：定义匹配成功的结果类型
5. **主机名规范化**：网络规则的主机名验证和规范化
6. **示例验证**：验证 `match`/`not_match` 示例的正确性

该模块是策略匹配的基础，定义了"规则是什么"和"如何匹配"。

## 功能点目的

### 1. `PatternToken` - 模式 token

表示模式中的一个位置：

```rust
pub enum PatternToken {
    Single(String),      // 固定值，如 "git"
    Alts(Vec<String>),   // 替代值，如 ["-c", "-l"]
}
```

### 2. `PrefixPattern` - 前缀模式

前缀规则的核心匹配结构：

```rust
pub struct PrefixPattern {
    pub first: Arc<str>,           // 首 token（用于索引）
    pub rest: Arc<[PatternToken]>, // 剩余 token 模式
}
```

### 3. `PrefixRule` - 前缀规则

完整的规则定义：

```rust
pub struct PrefixRule {
    pub pattern: PrefixPattern,
    pub decision: Decision,
    pub justification: Option<String>,
}
```

### 4. `NetworkRule` - 网络规则

网络访问控制规则：

```rust
pub struct NetworkRule {
    pub host: String,
    pub protocol: NetworkRuleProtocol,
    pub decision: Decision,
    pub justification: Option<String>,
}
```

### 5. `RuleMatch` - 匹配结果

规则匹配成功的结果：

```rust
pub enum RuleMatch {
    PrefixRuleMatch {
        matched_prefix: Vec<String>,
        decision: Decision,
        resolved_program: Option<AbsolutePathBuf>,
        justification: Option<String>,
    },
    HeuristicsRuleMatch {
        command: Vec<String>,
        decision: Decision,
    },
}
```

### 6. `Rule` trait - 规则抽象

允许未来扩展更多规则类型：

```rust
pub trait Rule: Any + Debug + Send + Sync {
    fn program(&self) -> &str;
    fn matches(&self, cmd: &[String]) -> Option<RuleMatch>;
    fn as_any(&self) -> &dyn Any;
}
```

## 具体技术实现

### 模式匹配算法

```rust
impl PrefixPattern {
    pub fn matches_prefix(&self, cmd: &[String]) -> Option<Vec<String>> {
        let pattern_length = self.rest.len() + 1;
        
        // 1. 检查长度和首 token
        if cmd.len() < pattern_length || cmd[0] != self.first.as_ref() {
            return None;
        }
        
        // 2. 逐个匹配剩余 token
        for (pattern_token, cmd_token) in self.rest.iter().zip(&cmd[1..pattern_length]) {
            if !pattern_token.matches(cmd_token) {
                return None;
            }
        }
        
        // 3. 返回匹配的前缀
        Some(cmd[..pattern_length].to_vec())
    }
}

impl PatternToken {
    fn matches(&self, token: &str) -> bool {
        match self {
            Self::Single(expected) => expected == token,
            Self::Alts(alternatives) => alternatives.iter().any(|alt| alt == token),
        }
    }
}
```

复杂度：O(pattern_length)，非常高效。

### 主机名规范化

```rust
pub(crate) fn normalize_network_rule_host(raw: &str) -> Result<String> {
    let mut host = raw.trim();
    
    // 1. 基本验证
    if host.is_empty() {
        return Err(Error::InvalidRule("host cannot be empty".to_string()));
    }
    if host.contains("://") || host.contains('/') || host.contains('?') || host.contains('#') {
        return Err(Error::InvalidRule("host must be hostname or IP (no scheme/path)".to_string()));
    }
    
    // 2. 处理 IPv6 字面量 [2001:db8::1]:8080
    if let Some(stripped) = host.strip_prefix('[') {
        let Some((inside, rest)) = stripped.split_once(']') else {
            return Err(Error::InvalidRule("invalid bracketed IPv6 literal".to_string()));
        };
        // 验证端口部分...
        host = inside;
    } 
    // 3. 处理 IPv4:port 或 hostname:port
    else if host.matches(':').count() == 1 {
        if let Some((candidate, port)) = host.rsplit_once(':') {
            // 验证端口...
            host = candidate;
        }
    }
    
    // 4. 最终规范化
    let normalized = host.trim_end_matches('.').trim().to_ascii_lowercase();
    
    // 5. 额外验证
    if normalized.contains('*') {
        return Err(Error::InvalidRule("wildcards are not allowed".to_string()));
    }
    if normalized.chars().any(char::is_whitespace) {
        return Err(Error::InvalidRule("host cannot contain whitespace".to_string()));
    }
    
    Ok(normalized)
}
```

支持的格式：
- `example.com`
- `api.github.com`
- `[2001:db8::1]`
- `[::1]:8080`
- `localhost:3000`

拒绝的格式：
- `*.example.com`（通配符）
- `https://example.com`（含 scheme）
- `example.com/path`（含 path）

### 规则 trait 实现

```rust
impl Rule for PrefixRule {
    fn program(&self) -> &str {
        self.pattern.first.as_ref()
    }

    fn matches(&self, cmd: &[String]) -> Option<RuleMatch> {
        self.pattern
            .matches_prefix(cmd)
            .map(|matched_prefix| RuleMatch::PrefixRuleMatch {
                matched_prefix,
                decision: self.decision,
                resolved_program: None,
                justification: self.justification.clone(),
            })
    }

    fn as_any(&self) -> &dyn Any {
        self
    }
}
```

### 示例验证

```rust
pub(crate) fn validate_match_examples(
    policy: &Policy,
    rules: &[RuleRef],
    matches: &[Vec<String>],
) -> Result<()> {
    let mut unmatched_examples = Vec::new();
    
    for example in matches {
        // 使用启用了主机可执行文件解析的选项
        if !policy.matches_for_command_with_options(example, None, &options).is_empty() {
            continue;
        }
        unmatched_examples.push(shlex::join(example.iter().map(String::as_str))?);
    }
    
    if !unmatched_examples.is_empty() {
        Err(Error::ExampleDidNotMatch {
            rules: rules.iter().map(|r| format!("{r:?}")).collect(),
            examples: unmatched_examples,
            location: None,
        })
    } else {
        Ok(())
    }
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `decision` | `Decision` 枚举 |
| `error` | 错误类型 |
| `policy` | `Policy` 用于示例验证（循环依赖风险）|

### 外部依赖

| Crate | 用途 |
|-------|------|
| `serde` | 序列化 |
| `shlex` | 示例字符串格式化 |
| `codex_utils_absolute_path` | 绝对路径类型 |

### 协议支持

```rust
pub enum NetworkRuleProtocol {
    Http,
    Https,
    Socks5Tcp,
    Socks5Udp,
}
```

解析时支持别名：
- `https`, `https_connect`, `http-connect` → `Https`

## 风险、边界与改进建议

### 风险点

1. **与 policy.rs 的循环依赖**：示例验证需要 `Policy`，而 `Policy` 使用 `Rule`
2. **Arc 克隆成本**：`PrefixPattern` 使用 `Arc`，克隆便宜但创建有成本
3. **主机名验证复杂度**：IPv6 和端口的处理容易出错
4. **通配符拒绝**：严格拒绝通配符可能限制某些用例

### 边界条件

1. **空模式**：在解析层拒绝，不会到达匹配阶段
2. **空 token**：`PatternToken::Alts` 拒绝空列表
3. **超长主机名**：未限制长度，可能内存问题
4. **Unicode 主机名**：使用 `to_ascii_lowercase`，IDN 可能处理不正确

### 改进建议

1. **正则表达式支持**：
   ```rust
   pub enum PatternToken {
       Single(String),
       Alts(Vec<String>),
       Regex(Regex),  // 新增
   }
   ```

2. **通配符支持**（可选）：
   - 子域通配符：`*.example.com`
   - 需要仔细考虑安全性

3. **CIDR 支持**：
   - 网络规则支持 IP 范围：`192.168.0.0/16`

4. **性能优化**：
   - 使用 `smallvec` 避免小数组的堆分配
   - 对 `Alts` 使用 `HashSet` 加速查找

5. **主机名验证**：
   - 使用 `idna` crate 正确处理国际化域名
   - 验证主机名符合 RFC 规范

6. **规则元数据**：
   - 添加规则 ID、创建时间等元数据
   - 支持规则注释

### 代码示例

定义规则：

```rust
let rule = PrefixRule {
    pattern: PrefixPattern {
        first: Arc::from("git"),
        rest: vec![
            PatternToken::Single("status".to_string()),
        ].into(),
    },
    decision: Decision::Allow,
    justification: Some("Safe read-only command".to_string()),
};
```

匹配命令：

```rust
if let Some(match_result) = rule.matches(&["git", "status"]) {
    assert_eq!(match_result.decision(), Decision::Allow);
}
```

网络规则：

```rust
let network_rule = NetworkRule {
    host: "api.github.com".to_string(),
    protocol: NetworkRuleProtocol::Https,
    decision: Decision::Allow,
    justification: Some("Required for GitHub integration".to_string()),
};
```

### 序列化格式

`RuleMatch` 的 JSON 表示：

```json
{
  "prefixRuleMatch": {
    "matchedPrefix": ["git", "status"],
    "decision": "allow",
    "resolvedProgram": "/usr/bin/git",
    "justification": "Safe read-only command"
  }
}
```

或启发式匹配：

```json
{
  "heuristicsRuleMatch": {
    "command": ["unknown-cmd", "arg"],
    "decision": "prompt"
  }
}
```
