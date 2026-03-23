# policy.rs 研究文档

## 场景与职责

`policy.rs` 是 `codex-execpolicy` crate 的**策略评估引擎核心模块**，负责：

1. **规则存储与管理**：高效存储和组织前缀规则、网络规则
2. **命令匹配**：根据命令 token 序列查找匹配的规则
3. **决策聚合**：多规则匹配时选择最严格的决策
4. **主机可执行文件解析**：支持从绝对路径到 basename 的回退匹配
5. **策略合并**：支持叠加多个策略源

这是策略引擎的"运行时"部分，与 `parser.rs` 的"编译时"部分相对应。

## 功能点目的

### 1. `Policy` 结构体

策略的核心数据结构：

```rust
pub struct Policy {
    rules_by_program: MultiMap<String, RuleRef>,  // 前缀规则，按首 token 索引
    network_rules: Vec<NetworkRule>,               // 网络访问规则
    host_executables_by_name: HashMap<String, Arc<[AbsolutePathBuf]>>,  // 主机可执行文件映射
}
```

### 2. 命令匹配

提供多种匹配接口：

| 方法 | 用途 |
|------|------|
| `check()` | 基本检查，带启发式回退 |
| `check_with_options()` | 带选项的检查 |
| `check_multiple()` | 批量检查多个命令 |
| `matches_for_command()` | 获取所有匹配规则 |
| `matches_for_command_with_options()` | 最灵活的匹配接口 |

### 3. 决策聚合

多规则匹配时的决策策略：

```rust
let decision = matched_rules.iter().map(RuleMatch::decision).max();
```

利用 `Decision` 的 `Ord` 派生：`Forbidden > Prompt > Allow`

### 4. 主机可执行文件解析

支持两种匹配模式：

1. **精确匹配**：`/usr/bin/git status` 匹配首 token 为 `/usr/bin/git` 的规则
2. **Basename 回退**：如果启用 `resolve_host_executables`，尝试匹配 `git` 的规则

### 5. 策略合并

```rust
pub fn merge_overlay(&self, overlay: &Policy) -> Policy
```

用于合并多个策略文件，后加载的规则优先。

## 具体技术实现

### 匹配流程

```rust
pub fn matches_for_command_with_options(
    &self,
    cmd: &[String],
    heuristics_fallback: HeuristicsFallback<'_>,
    options: &MatchOptions,
) -> Vec<RuleMatch> {
    // 1. 尝试精确匹配
    let matched_rules = self.match_exact_rules(cmd)
        .filter(|rules| !rules.is_empty())
        // 2. 尝试主机可执行文件回退
        .or_else(|| {
            options.resolve_host_executables
                .then(|| self.match_host_executable_rules(cmd))
                .filter(|rules| !rules.is_empty())
        })
        .unwrap_or_default();
    
    // 3. 无匹配时使用启发式回退
    if matched_rules.is_empty() && let Some(heuristics_fallback) = heuristics_fallback {
        vec![RuleMatch::HeuristicsRuleMatch {
            command: cmd.to_vec(),
            decision: heuristics_fallback(cmd),
        }]
    } else {
        matched_rules
    }
}
```

### 精确匹配

```rust
fn match_exact_rules(&self, cmd: &[String]) -> Option<Vec<RuleMatch>> {
    let first = cmd.first()?;
    Some(
        self.rules_by_program
            .get_vec(first)
            .map(|rules| rules.iter().filter_map(|rule| rule.matches(cmd)).collect())
            .unwrap_or_default(),
    )
}
```

使用 `MultiMap` 实现 O(1) 的首 token 查找。

### 主机可执行文件回退

```rust
fn match_host_executable_rules(&self, cmd: &[String]) -> Vec<RuleMatch> {
    let Some(first) = cmd.first() else { return Vec::new(); };
    let Ok(program) = AbsolutePathBuf::try_from(first.clone()) else {
        return Vec::new();
    };
    let Some(basename) = executable_path_lookup_key(program.as_path()) else {
        return Vec::new();
    };
    let Some(rules) = self.rules_by_program.get_vec(&basename) else {
        return Vec::new();
    };
    
    // 检查是否在允许列表中
    if let Some(paths) = self.host_executables_by_name.get(&basename)
        && !paths.iter().any(|path| path == &program)
    {
        return Vec::new();
    }
    
    // 使用 basename 匹配，但保留原始路径信息
    let basename_command = std::iter::once(basename)
        .chain(cmd.iter().skip(1).cloned())
        .collect::<Vec<_>>();
    rules
        .iter()
        .filter_map(|rule| rule.matches(&basename_command))
        .map(|rule_match| rule_match.with_resolved_program(&program))
        .collect()
}
```

### 网络规则编译

```rust
pub fn compiled_network_domains(&self) -> (Vec<String>, Vec<String>) {
    let mut allowed = Vec::new();
    let mut denied = Vec::new();
    
    for rule in &self.network_rules {
        match rule.decision {
            Decision::Allow => {
                denied.retain(|entry| entry != &rule.host);
                upsert_domain(&mut allowed, &rule.host);
            }
            Decision::Forbidden => {
                allowed.retain(|entry| entry != &rule.host);
                upsert_domain(&mut denied, &rule.host);
            }
            Decision::Prompt => {}
        }
    }
    
    (allowed, denied)
}
```

将网络规则编译为允许/拒绝列表，用于快速查找。

### 评估结果

```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Evaluation {
    pub decision: Decision,
    #[serde(rename = "matchedRules")]
    pub matched_rules: Vec<RuleMatch>,
}
```

包含最终决策和所有匹配规则详情。

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `decision` | `Decision` 枚举 |
| `error` | 错误类型 |
| `executable_name` | 可执行文件名处理 |
| `rule` | 规则类型和匹配逻辑 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `multimap` | 多值映射 |
| `serde` | 序列化 |
| `codex_utils_absolute_path` | 绝对路径类型 |

### 被依赖方

- `parser.rs`：构建 `Policy`
- `execpolicycheck.rs`：评估命令
- `amend.rs`：修改策略（间接通过文件）

## 风险、边界与改进建议

### 风险点

1. **MultiMap 性能**：`MultiMap` 使用 `Vec` 存储值，规则多时线性查找
2. **主机可执行文件查找**：每次匹配都进行路径解析和查找
3. **网络规则编译**：每次调用都重新编译，可缓存结果
4. **启发式回退依赖**：外部传入的函数可能 panic 或阻塞

### 边界条件

1. **空命令**：返回空结果或启发式回退
2. **无匹配规则**：返回空或启发式回退
3. **多个匹配**：返回所有匹配，决策取最严格
4. **主机可执行文件空列表**：显式空列表表示不允许任何路径
5. **路径不匹配 basename**：拒绝匹配

### 改进建议

1. **索引优化**：
   - 对规则使用更高效的数据结构（如 Trie）
   - 缓存编译后的网络规则

2. **并行匹配**：
   - 批量检查时并行处理
   - 使用 `rayon` 等并行库

3. **缓存**：
   - 缓存命令到决策的映射
   - LRU 缓存最近检查的命令

4. **统计信息**：
   - 记录规则命中率
   - 提供未使用规则报告

5. **模糊匹配**：
   - 支持编辑距离的模糊匹配
   - 提供 "你是不是想..." 建议

6. **规则优先级**：
   - 支持显式规则优先级
   - 更精细的覆盖控制

### 性能考虑

当前复杂度：
- 精确匹配：O(1) 首 token 查找 + O(n) 规则匹配（n = 该首 token 的规则数）
- Basename 回退：额外 O(1) 查找
- 网络规则编译：O(m)（m = 网络规则数）

优化方向：
- 对高频命令使用缓存
- 预编译网络规则为 HashSet
- 使用 Aho-Corasick 等多模式匹配算法

### 代码示例

基本使用：

```rust
let policy = parser.build();
let evaluation = policy.check(&["git", "status"], &|_| Decision::Prompt);

assert_eq!(evaluation.decision, Decision::Allow);
assert!(evaluation.is_match());
```

带选项：

```rust
let evaluation = policy.check_with_options(
    &["/usr/bin/git", "status"],
    &|_| Decision::Prompt,
    &MatchOptions {
        resolve_host_executables: true,
    },
);
```

批量检查：

```rust
let commands = vec![
    vec!["git".to_string(), "status".to_string()],
    vec!["rm".to_string(), "-rf".to_string(), "/".to_string()],
];
let evaluation = policy.check_multiple(&commands, &|_| Decision::Forbidden);
// 决策为 Forbidden（最严格）
```
