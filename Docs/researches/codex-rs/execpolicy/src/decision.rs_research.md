# decision.rs 研究文档

## 场景与职责

`decision.rs` 是 `codex-execpolicy` crate 中最基础的模块之一，定义了**策略决策枚举类型**。它代表了命令执行策略引擎的核心输出——对某个命令或网络请求应该采取什么行动。

该模块的设计目标是：
1. 提供清晰、有限的决策选项
2. 支持序列化/反序列化（用于配置和 API）
3. 支持决策的优先级比较（用于多规则匹配时的冲突解决）

## 功能点目的

### Decision 枚举

定义三种可能的决策：

| 决策 | 含义 | 使用场景 |
|------|------|----------|
| `Allow` | 允许执行，无需进一步确认 | 已知安全的命令 |
| `Prompt` | 请求用户明确批准 | 可能存在风险的命令 |
| `Forbidden` | 禁止执行 | 已知危险的命令 |

### 决策解析

提供从字符串解析决策的能力，支持以下输入：
- `"allow"` → `Decision::Allow`
- `"prompt"` → `Decision::Prompt`
- `"forbidden"` → `Decision::Forbidden`

### 决策排序

通过派生 `Ord` 和 `PartialOrd`，决策具有自然的优先级顺序：

```
Forbidden > Prompt > Allow
```

这个顺序用于多规则匹配时的冲突解决——最严格的决策获胜。

## 具体技术实现

### 数据结构

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Decision {
    Allow,
    Prompt,
    Forbidden,
}
```

关键设计选择：
- `Clone + Copy`：决策是轻量值类型，可以廉价复制
- `Eq + PartialEq`：支持相等比较
- `Ord + PartialOrd`：支持排序，派生顺序遵循枚举定义顺序
- `Serialize + Deserialize`：支持 JSON/配置序列化
- `#[serde(rename_all = "camelCase")]`：JSON 中使用驼峰命名

### 解析实现

```rust
impl Decision {
    pub fn parse(raw: &str) -> Result<Self> {
        match raw {
            "allow" => Ok(Self::Allow),
            "prompt" => Ok(Self::Prompt),
            "forbidden" => Ok(Self::Forbidden),
            other => Err(Error::InvalidDecision(other.to_string())),
        }
    }
}
```

解析是大小写敏感的，只接受小写形式。

### 序列化行为

由于 `#[serde(rename_all = "camelCase")]`，序列化结果为：
- `Decision::Allow` → `"allow"`
- `Decision::Prompt` → `"prompt"`
- `Decision::Forbidden` → `"forbidden"`

注意：虽然枚举变体是 PascalCase，但序列化结果是 camelCase（在这个特定情况下与小写相同）。

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::error::Error` | 解析失败时的错误类型 |
| `crate::error::Result` | 结果类型别名 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化派生 |

### 被依赖方

几乎所有其他模块都依赖 `Decision`：
- `policy.rs`：评估结果包含决策
- `rule.rs`：规则匹配结果包含决策
- `parser.rs`：解析策略文件中的决策字段
- `amend.rs`：追加规则时指定决策
- `execpolicycheck.rs`：输出决策结果

## 风险、边界与改进建议

### 风险点

1. **决策顺序依赖**：`Ord` 派生顺序依赖枚举定义顺序，如果将来添加新决策或调整顺序，需要谨慎评估影响
2. **大小写敏感**：解析是大小写敏感的，用户输入 `"Allow"` 会失败
3. **无默认值**：解析不提供默认值，无效输入直接返回错误

### 边界条件

1. **空字符串**：返回 `Error::InvalidDecision("")`
2. **未知值**：返回 `Error::InvalidDecision(other.to_string())`
3. **前后空格**：不会自动 trim，包含空格的输入会失败

### 改进建议

1. **大小写不敏感解析**：考虑支持 `"Allow"`、`"ALLOW"` 等变体
2. **默认值支持**：提供 `parse_or_default` 变体
3. **字符串表示**：考虑提供 `as_str()` 方法获取字符串表示
4. **文档生成**：考虑使用 `strum` crate 生成变体列表，用于文档/补全
5. **i18n 支持**：如果需要，可以考虑支持本地化显示名称

### 相关代码示例

决策优先级比较的实际应用（来自 `policy.rs`）：

```rust
let decision = matched_rules.iter().map(RuleMatch::decision).max();
```

这行代码利用 `Ord` 派生，自动选择最严格的决策。
