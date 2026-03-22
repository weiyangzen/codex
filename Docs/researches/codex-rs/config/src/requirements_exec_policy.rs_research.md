# requirements_exec_policy.rs 研究文档

## 场景与职责

`requirements_exec_policy.rs` 是 Codex 配置系统的**执行策略需求模块**，负责：

1. **TOML 执行策略定义**：定义 `requirements.toml` 中 `[rules]` 部分的结构
2. **策略转换**：将 TOML 格式的规则转换为内部 `codex_execpolicy` crate 的 `Policy` 类型
3. **前缀规则匹配**：支持基于命令前缀的执行策略规则
4. **验证和错误处理**：确保 TOML 规则的有效性和一致性

### 在架构中的位置

```
requirements.toml
    │
    ▼
RequirementsExecPolicyToml (TOML 结构)
    │
    ▼
to_policy() / to_requirements_policy()
    │
    ▼
Policy (codex_execpolicy::Policy)
    │
    ▼
命令执行检查
```

## 功能点目的

### 1. 执行策略包装 (`RequirementsExecPolicy`)
```rust
#[derive(Debug, Clone)]
pub struct RequirementsExecPolicy {
    policy: Policy,
}
```

**目的**：
- 包装 `codex_execpolicy::Policy`，提供领域特定的接口
- 实现自定义的 `PartialEq`（基于指纹比较）
- 提供类型安全边界

### 2. 策略相等性比较
```rust
impl PartialEq for RequirementsExecPolicy {
    fn eq(&self, other: &Self) -> bool {
        policy_fingerprint(&self.policy) == policy_fingerprint(&other.policy)
    }
}

fn policy_fingerprint(policy: &Policy) -> Vec<String> {
    let mut entries = Vec::new();
    for (program, rules) in policy.rules().iter_all() {
        for rule in rules {
            entries.push(format!("{program}:{rule:?}"));
        }
    }
    entries.sort();
    entries
}
```

**目的**：
- `Policy` 类型本身可能没有实现 `PartialEq`
- 通过排序后的规则列表指纹实现语义相等性比较

### 3. TOML 规则结构 (`RequirementsExecPolicyToml`)
```rust
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct RequirementsExecPolicyToml {
    pub prefix_rules: Vec<RequirementsExecPolicyPrefixRuleToml>,
}
```

**目的**：
- 定义 `[rules]` 表的结构
- 支持 serde 反序列化
- 目前仅支持前缀规则，未来可扩展

### 4. 前缀规则 (`RequirementsExecPolicyPrefixRuleToml`)
```rust
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct RequirementsExecPolicyPrefixRuleToml {
    pub pattern: Vec<RequirementsExecPolicyPatternTokenToml>,
    pub decision: Option<RequirementsExecPolicyDecisionToml>,
    pub justification: Option<String>,
}
```

**目的**：
- 定义单条前缀规则
- `pattern`：命令前缀匹配模式
- `decision`：匹配后的决策（Allow/Prompt/Forbidden）
- `justification`：规则的理由说明

### 5. 模式标记 (`RequirementsExecPolicyPatternTokenToml`)
```rust
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct RequirementsExecPolicyPatternTokenToml {
    pub token: Option<String>,
    pub any_of: Option<Vec<String>>,
}
```

**目的**：
- 支持单值标记：`{ token = "rm" }`
- 支持多值选择：`{ any_of = ["rm", "del"] }`
- 解决 TOML 不能混合字符串和数组的限制

### 6. 决策枚举 (`RequirementsExecPolicyDecisionToml`)
```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RequirementsExecPolicyDecisionToml {
    Allow,
    Prompt,
    Forbidden,
}
```

**目的**：
- 定义允许的决策类型
- 使用 kebab-case 序列化（`"forbidden"` 而非 `"Forbidden"`）

### 7. 错误类型 (`RequirementsExecPolicyParseError`)
```rust
#[derive(Debug, Error)]
pub enum RequirementsExecPolicyParseError {
    #[error("rules prefix_rules cannot be empty")]
    EmptyPrefixRules,
    
    #[error("rules prefix_rule at index {rule_index} has an empty pattern")]
    EmptyPattern { rule_index: usize },
    
    #[error("... has an invalid pattern token at index {token_index}: {reason}")]
    InvalidPatternToken { rule_index: usize, token_index: usize, reason: String },
    
    #[error("... has an empty justification")]
    EmptyJustification { rule_index: usize },
    
    #[error("... is missing a decision")]
    MissingDecision { rule_index: usize },
    
    #[error("... has decision 'allow', which is not permitted in requirements.toml")]
    AllowDecisionNotAllowed { rule_index: usize },
}
```

**目的**：
- 提供详细的解析错误信息
- 包含规则索引，便于用户定位问题
- 特殊限制：requirements.toml 中不允许 `Allow` 决策（因为策略是限制性的）

## 具体技术实现

### TOML 到 Policy 的转换流程

```rust
impl RequirementsExecPolicyToml {
    pub fn to_policy(&self) -> Result<Policy, RequirementsExecPolicyParseError> {
        // 1. 验证非空
        if self.prefix_rules.is_empty() {
            return Err(RequirementsExecPolicyParseError::EmptyPrefixRules);
        }
        
        let mut rules_by_program: MultiMap<String, RuleRef> = MultiMap::new();
        
        // 2. 遍历规则
        for (rule_index, rule) in self.prefix_rules.iter().enumerate() {
            // 验证理由非空
            if let Some(justification) = &rule.justification
                && justification.trim().is_empty()
            {
                return Err(RequirementsExecPolicyParseError::EmptyJustification { rule_index });
            }
            
            // 验证模式非空
            if rule.pattern.is_empty() {
                return Err(RequirementsExecPolicyParseError::EmptyPattern { rule_index });
            }
            
            // 解析模式标记
            let pattern_tokens = rule
                .pattern
                .iter()
                .enumerate()
                .map(|(token_index, token)| parse_pattern_token(token, rule_index, token_index))
                .collect::<Result<Vec<_>, _>>()?;
            
            // 验证并转换决策
            let decision = match rule.decision {
                Some(RequirementsExecPolicyDecisionToml::Allow) => {
                    return Err(RequirementsExecPolicyParseError::AllowDecisionNotAllowed { rule_index });
                }
                Some(decision) => decision.as_decision(),
                None => return Err(RequirementsExecPolicyParseError::MissingDecision { rule_index }),
            };
            
            // 构建前缀规则
            let (first_token, remaining_tokens) = pattern_tokens
                .split_first()
                .ok_or(RequirementsExecPolicyParseError::EmptyPattern { rule_index })?;
            
            let rest: Arc<[PatternToken]> = remaining_tokens.to_vec().into();
            
            // 为每个首标记变体创建规则
            for head in first_token.alternatives() {
                let rule: RuleRef = Arc::new(PrefixRule {
                    pattern: PrefixPattern {
                        first: Arc::from(head.as_str()),
                        rest: rest.clone(),
                    },
                    decision,
                    justification: justification.clone(),
                });
                rules_by_program.insert(head.clone(), rule);
            }
        }
        
        Ok(Policy::new(rules_by_program))
    }
}
```

### 模式标记解析

```rust
fn parse_pattern_token(
    token: &RequirementsExecPolicyPatternTokenToml,
    rule_index: usize,
    token_index: usize,
) -> Result<PatternToken, RequirementsExecPolicyParseError> {
    match (&token.token, &token.any_of) {
        // 单值标记
        (Some(single), None) => {
            if single.trim().is_empty() {
                return Err(RequirementsExecPolicyParseError::InvalidPatternToken {
                    rule_index,
                    token_index,
                    reason: "token cannot be empty".to_string(),
                });
            }
            Ok(PatternToken::Single(single.clone()))
        }
        
        // 多值选择
        (None, Some(alternatives)) => {
            if alternatives.is_empty() {
                return Err(RequirementsExecPolicyParseError::InvalidPatternToken {
                    rule_index,
                    token_index,
                    reason: "any_of cannot be empty".to_string(),
                });
            }
            if alternatives.iter().any(|alt| alt.trim().is_empty()) {
                return Err(RequirementsExecPolicyParseError::InvalidPatternToken {
                    rule_index,
                    token_index,
                    reason: "any_of cannot include empty tokens".to_string(),
                });
            }
            Ok(PatternToken::Alts(alternatives.clone()))
        }
        
        // 错误：同时设置两者
        (Some(_), Some(_)) => Err(RequirementsExecPolicyParseError::InvalidPatternToken {
            rule_index,
            token_index,
            reason: "set either token or any_of, not both".to_string(),
        }),
        
        // 错误：两者都未设置
        (None, None) => Err(RequirementsExecPolicyParseError::InvalidPatternToken {
            rule_index,
            token_index,
            reason: "set either token or any_of".to_string(),
        }),
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/config/src/requirements_exec_policy.rs` (236 行)

### 直接依赖
| 依赖 | 路径 | 用途 |
|------|------|------|
| `Decision` | `codex-rs/execpolicy/src/decision.rs` | 决策枚举 |
| `Policy` | `codex-rs/execpolicy/src/policy.rs` | 策略类型 |
| `PatternToken` | `codex-rs/execpolicy/src/rule.rs` | 模式标记 |
| `PrefixPattern` | `codex-rs/execpolicy/src/rule.rs` | 前缀模式 |
| `PrefixRule` | `codex-rs/execpolicy/src/rule.rs` | 前缀规则 |
| `RuleRef` | `codex-rs/execpolicy/src/rule.rs` | 规则引用 |
| `MultiMap` | `multimap` crate | 多值映射 |

### 调用方
- `codex-rs/config/src/config_requirements.rs` - 配置需求转换
- `codex-rs/core/src/exec_policy.rs` - 执行策略应用

### 使用示例（TOML 配置）

```toml
[rules]
prefix_rules = [
    # 禁止 rm 命令
    { pattern = [{ token = "rm" }], decision = "forbidden", justification = "删除操作危险" },
    
    # 对 git push/pull 提示确认
    { pattern = [{ token = "git" }, { token = "push" }], decision = "prompt", justification = "可能影响远程仓库" },
    { pattern = [{ token = "git" }, { token = "pull" }], decision = "prompt" },
    
    # 多个命令使用相同规则
    { pattern = [{ any_of = ["vi", "vim", "nano"] }], decision = "prompt", justification = "交互式编辑器" },
]
```

## 依赖与外部交互

### 外部 Crate
- `multimap`：支持一个程序对应多个规则
- `serde`：TOML 反序列化
- `thiserror`：错误派生

### 内部模块
- `codex_execpolicy`：核心执行策略引擎

### 协议/接口
- TOML 配置文件格式
- `codex_execpolicy` 内部 API

## 风险、边界与改进建议

### 潜在风险

1. **规则冲突**：
   - 多个规则可能匹配同一命令
   - 依赖 `codex_execpolicy` 的冲突解决逻辑

2. **性能问题**：
   - `policy_fingerprint` 每次比较都重新计算
   - 规则数量大时可能影响性能

3. **限制性设计**：
   - 不允许 `Allow` 决策可能过于严格
   - 某些场景可能需要显式允许某些命令

### 边界条件

1. **空规则列表**：
   ```rust
   // 返回错误
   RequirementsExecPolicyParseError::EmptyPrefixRules
   ```

2. **空模式**：
   ```rust
   // pattern = [] 返回错误
   RequirementsExecPolicyParseError::EmptyPattern
   ```

3. **通配符支持**：
   - 当前不支持 `*` 通配符
   - 需要使用 `any_of` 枚举所有可能

### 改进建议

1. **缓存指纹**：
   ```rust
   pub struct RequirementsExecPolicy {
       policy: Policy,
       fingerprint: OnceCell<Vec<String>>,  // 懒加载缓存
   }
   ```

2. **通配符支持**：
   ```rust
   #[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
   pub struct RequirementsExecPolicyPatternTokenToml {
       pub token: Option<String>,
       pub any_of: Option<Vec<String>>,
       pub wildcard: Option<bool>,  // { wildcard = true }
   }
   ```

3. **正则表达式支持**：
   ```rust
   pub enum PatternToken {
       Single(String),
       Alts(Vec<String>),
       Regex(String),  // 新增
   }
   ```

4. **规则优先级**：
   ```rust
   pub struct RequirementsExecPolicyPrefixRuleToml {
       pub pattern: Vec<RequirementsExecPolicyPatternTokenToml>,
       pub decision: Option<RequirementsExecPolicyDecisionToml>,
       pub justification: Option<String>,
       pub priority: Option<i32>,  // 新增：优先级，数字越小优先级越高
   }
   ```

5. **条件规则**：
   ```rust
   pub struct RequirementsExecPolicyPrefixRuleToml {
       // ...
       pub when: Option<String>,  // 条件表达式，如 "env.PRODUCTION == 'true'"
   }
   ```

6. **Allow 决策支持**：
   ```rust
   // 考虑允许 Allow，但添加警告或需要额外确认
   pub fn to_policy(&self) -> Result<Policy, RequirementsExecPolicyParseError> {
       // 移除 Allow 检查，或改为警告
   }
   ```

### 测试覆盖

当前测试：
- 主要通过 `config_requirements.rs` 的集成测试覆盖
- 测试用例：`deserialize_exec_policy_requirements`

建议补充：
- 单元测试每个验证分支
- 复杂模式匹配测试
- 性能基准测试（大量规则）
- 错误消息质量测试

### 安全考虑

1. **命令注入**：
   - 模式标记中的特殊字符需要转义
   - 当前实现未明确处理

2. **规则绕过**：
   - 用户可能通过别名、路径遍历等方式绕过规则
   - 需要与 `codex_execpolicy` 协作处理
