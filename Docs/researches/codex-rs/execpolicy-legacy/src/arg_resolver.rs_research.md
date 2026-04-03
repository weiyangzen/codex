# arg_resolver.rs 研究文档

## 场景与职责

`arg_resolver.rs` 是执行策略引擎的核心匹配算法实现，负责将实际的命令行参数与策略定义的模式进行匹配。其主要职责包括：

1. **参数分区**：将参数列表划分为前缀、变参和后缀三部分
2. **模式匹配**：根据 `ArgMatcher` 模式验证每个参数
3. **错误处理**：提供详细的匹配失败原因
4. **结果构建**：生成结构化的 `MatchedArg` 列表

该模块是连接策略定义（`ProgramSpec`）和验证结果（`ValidExec`）的关键桥梁。

## 功能点目的

### 核心函数

| 函数 | 目的 | 输入 | 输出 |
|------|------|------|------|
| `resolve_observed_args_with_patterns` | 主匹配入口 | 程序名、实际参数、模式列表 | `Vec<MatchedArg>` 或错误 |
| `partition_args` | 将模式分区为前缀/变参/后缀 | 程序名、模式列表 | `ParitionedArgs` 结构 |
| `get_range_checked` | 安全的切片访问 | 向量、范围 | 子切片或边界错误 |

### PositionalArg 结构

```rust
pub struct PositionalArg {
    pub index: usize,    // 参数在原始命令中的索引
    pub value: String,   // 参数值
}
```

保留原始索引信息，用于在验证错误时提供精确的位置反馈。

## 具体技术实现

### 分区算法

```rust
fn partition_args(program: &str, arg_patterns: &Vec<ArgMatcher>) -> Result<ParitionedArgs> {
    let mut in_prefix = true;
    let mut partitioned_args = ParitionedArgs::default();

    for pattern in arg_patterns {
        match pattern.cardinality().is_exact() {
            Some(n) => {
                // 固定基数模式：根据当前状态放入前缀或后缀
                if in_prefix {
                    partitioned_args.prefix_patterns.push(pattern.clone());
                    partitioned_args.num_prefix_args += n;
                } else {
                    partitioned_args.suffix_patterns.push(pattern.clone());
                    partitioned_args.num_suffix_args += n;
                }
            }
            None => match partitioned_args.vararg_pattern {
                None => {
                    // 第一个变参模式：标记为变参，切换到后缀状态
                    partitioned_args.vararg_pattern = Some(pattern.clone());
                    in_prefix = false;
                }
                Some(existing_pattern) => {
                    // 多个变参模式：报错
                    return Err(Error::MultipleVarargPatterns { ... });
                }
            },
        }
    }
    Ok(partitioned_args)
}
```

**算法逻辑**：
1. 遍历所有模式
2. 固定基数模式（`One`）进入当前分区（前缀或后缀）
3. 第一个变参模式（`AtLeastOne`/`ZeroOrMore`）成为变参，之后切换为后缀模式
4. 发现第二个变参模式时报错

### 匹配流程

```
实际参数: [a, b, c, d, e, f]
模式:      [Fixed1, Vararg, Fixed2, Fixed2]
          
分区结果:
  前缀: [Fixed1]       → 消耗 1 个参数 [a]
  变参: [Vararg]       → 消耗剩余参数 [b, c, d] (计算方式: 总数 - 前缀 - 后缀)
  后缀: [Fixed2, Fixed2] → 消耗 2 个参数 [e, f]
```

### 匹配实现细节

```rust
// 前缀匹配
let prefix = get_range_checked(&args, 0..num_prefix_args)?;
for pattern in prefix_patterns {
    let n = pattern.cardinality().is_exact().ok_or(...)?;
    for positional_arg in &prefix[prefix_arg_index..prefix_arg_index + n] {
        let matched_arg = MatchedArg::new(
            positional_arg.index,
            pattern.arg_type(),
            &positional_arg.value.clone(),
        )?;
        matched_args.push(matched_arg);
    }
    prefix_arg_index += n;
}
```

**关键步骤**：
1. 使用 `get_range_checked` 安全获取子切片
2. 每个模式通过 `arg_type()` 获取对应的 `ArgType`
3. `MatchedArg::new()` 执行实际验证（如 `ArgType::validate`）
4. 收集所有成功匹配的参数

### 变参处理

```rust
if let Some(pattern) = vararg_pattern {
    let vararg = get_range_checked(&args, prefix_arg_index..initial_suffix_args_index)?;
    match pattern.cardinality() {
        ArgMatcherCardinality::AtLeastOne => {
            if vararg.is_empty() {
                return Err(Error::VarargMatcherDidNotMatchAnything { ... });
            }
            // 处理每个参数...
        }
        ArgMatcherCardinality::ZeroOrMore => {
            // 允许空列表，处理每个参数...
        }
        _ => unreachable!(),
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/execpolicy-legacy/src/arg_resolver.rs` (204 行)

### 核心数据结构

```rust
#[derive(Default)]
struct ParitionedArgs {
    num_prefix_args: usize,      // 前缀参数总数
    num_suffix_args: usize,      // 后缀参数总数
    prefix_patterns: Vec<ArgMatcher>,
    suffix_patterns: Vec<ArgMatcher>,
    vararg_pattern: Option<ArgMatcher>,
}
```

### 调用链

```
program.rs:ProgramSpec::check()
    ↓ 调用
arg_resolver.rs:resolve_observed_args_with_patterns()
    ├── partition_args()          // 分区模式
    ├── get_range_checked()       // 安全切片
    └── MatchedArg::new()         // 验证每个参数
        ↓ 调用
valid_exec.rs:MatchedArg::new()
    ↓ 调用
arg_type.rs:ArgType::validate()
```

### 错误类型

| 错误 | 触发条件 | 位置 |
|------|----------|------|
| `MultipleVarargPatterns` | 模式列表中有多个变参 | `partition_args:177` |
| `NotEnoughArgs` | 实际参数少于模式要求 | `resolve:66` |
| `PrefixOverlapsSuffix` | 前缀和后缀参数范围重叠 | `resolve:75` |
| `VarargMatcherDidNotMatchAnything` | `AtLeastOne` 变参匹配到空列表 | `resolve:88` |
| `UnexpectedArguments` | 匹配后仍有剩余参数 | `resolve:138` |
| `RangeStartExceedsEnd` / `RangeEndOutOfBounds` | 切片越界 | `get_range_checked` |

## 依赖与外部交互

### 模块依赖
```
arg_resolver.rs
    ↑ 使用 arg_matcher::{ArgMatcher, ArgMatcherCardinality}
    ↑ 使用 error::{Error, Result}
    ↑ 使用 valid_exec::MatchedArg
    ↓ 被 program.rs::ProgramSpec::check 调用
```

### 外部 crate
- `serde`：`PositionalArg` 实现 `Serialize` 用于错误序列化

## 风险、边界与改进建议

### 当前限制

1. **单变参限制**：只能有一个变参模式，限制了复杂命令的支持
   ```rust
   // 不支持: cp [sources...] [dest_dir/]
   // 其中 sources 是多个源文件，dest_dir 是目标目录
   // 需要: [ReadableFiles, ReadableFileOrCwd] 两个变参
   ```

2. **无模式回溯**：匹配失败时不会尝试其他可能的匹配方式
   ```rust
   // 对于模糊模式，可能错误地拒绝有效输入
   ```

3. **索引计算复杂**：`prefix_arg_index` 和 `initial_suffix_args_index` 的手动计算容易出错

### 边界情况

1. **空参数列表**：
   - 如果模式全为 `ZeroOrMore` 类型，空列表是有效的
   - 如果有 `AtLeastOne` 或固定模式，空列表会触发 `NotEnoughArgs`

2. **参数数量恰好匹配**：
   ```rust
   // 模式: [Fixed, Fixed], 参数: [a, b]
   // 无前缀/变参/后缀，直接匹配
   ```

3. **重叠检测**：
   ```rust
   if prefix_arg_index > initial_suffix_args_index {
       return Err(Error::PrefixOverlapsSuffix {});
   }
   ```

### 改进建议

1. **支持多变参模式**：
   ```rust
   // 允许: [Fixed, Vararg1, Fixed, Vararg2]
   // 需要更复杂的分区算法和约束求解
   ```

2. **添加贪婪/非贪婪选项**：
   ```rust
   pub enum VarargMode {
       Greedy,      // 尽可能多地匹配
       NonGreedy,   // 尽可能少地匹配
   }
   ```

3. **模式组合**：
   ```rust
   // 支持 OR 语义
   ArgMatcher::AnyOf(vec![ArgMatcher::ReadableFile, ArgMatcher::Literal("-")])
   ```

4. **性能优化**：
   - 当前实现多次克隆字符串，可以使用引用减少分配
   - 预计算模式信息避免重复匹配

5. **更好的错误信息**：
   ```rust
   // 当前: "not enough args"
   // 改进: "expected at least 3 args for pattern [ReadableFile, ReadableFile, WriteableFile], got 2"
   ```

### 测试建议

1. **边界测试**：
   - 空参数列表
   - 恰好匹配的参数数量
   - 前缀/后缀边界重叠

2. **复杂模式测试**：
   - 只有变参模式
   - 只有固定模式
   - 混合模式的各种组合

3. **错误恢复测试**：
   - 验证错误信息包含足够上下文
   - 确保部分失败不会留下脏状态
