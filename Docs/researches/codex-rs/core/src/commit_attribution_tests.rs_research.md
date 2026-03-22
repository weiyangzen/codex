# commit_attribution_tests.rs 深度研究文档

## 场景与职责

`commit_attribution_tests.rs` 是 `commit_attribution.rs` 的配套测试文件，负责验证 Git 提交归属功能的正确性。测试覆盖了归属值的解析、默认行为、禁用场景以及指令生成等各个方面。

### 测试覆盖范围

1. **空归属禁用** - 验证空字符串和空白字符串正确禁用归属
2. **默认归属** - 验证未配置时使用默认归属值
3. **归属值解析** - 验证各种输入格式的正确处理
4. **指令生成** - 验证生成的模型指令包含正确的归属信息

## 功能点目的

### 1. 验证配置解析正确性

确保 `resolve_attribution_value` 函数正确处理：
- `None` → 默认值
- `Some("valid")` → 自定义值
- `Some("")` / `Some("  ")` → 禁用

### 2. 验证指令格式

确保生成的指令：
- 包含正确的 `Co-authored-by` 标记
- 包含格式规则说明
- 不包含已弃用的 `Generated-with` 标记

### 3. 防止回归

通过全面的测试用例，防止未来的代码变更破坏：
- 默认归属行为
- 禁用逻辑
- 指令格式

## 具体技术实现

### 测试用例 1: 空归属禁用

**测试函数**: `blank_attribution_disables_trailer_prompt`

**测试代码**:
```rust
#[test]
fn blank_attribution_disables_trailer_prompt() {
    assert_eq!(build_commit_message_trailer(Some("")), None);
    assert_eq!(commit_message_trailer_instruction(Some("   ")), None);
}
```

**验证点**:
- 空字符串 `""` 返回 `None`
- 仅空白字符 `"   "` 返回 `None`
- 两个相关函数行为一致

### 测试用例 2: 默认归属

**测试函数**: `default_attribution_uses_codex_trailer`

**测试代码**:
```rust
#[test]
fn default_attribution_uses_codex_trailer() {
    assert_eq!(
        build_commit_message_trailer(None).as_deref(),
        Some("Co-authored-by: Codex <noreply@openai.com>")
    );
}
```

**验证点**:
- `None` 输入使用默认归属
- 输出格式为 `Co-authored-by: {value}`

### 测试用例 3: 归属值解析

**测试函数**: `resolve_value_handles_default_custom_and_blank`

**测试代码**:
```rust
#[test]
fn resolve_value_handles_default_custom_and_blank() {
    assert_eq!(
        resolve_attribution_value(None),
        Some("Codex <noreply@openai.com>".to_string())
    );
    assert_eq!(
        resolve_attribution_value(Some("MyAgent <me@example.com>")),
        Some("MyAgent <me@example.com>".to_string())
    );
    assert_eq!(
        resolve_attribution_value(Some("MyAgent")),
        Some("MyAgent".to_string())
    );
    assert_eq!(resolve_attribution_value(Some("   ")), None);
}
```

**验证矩阵**:

| 输入 | 期望输出 | 说明 |
|------|----------|------|
| `None` | `Some("Codex <noreply@openai.com>")` | 默认值 |
| `Some("MyAgent <me@example.com>")` | `Some("MyAgent <me@example.com>")` | 完整邮箱 |
| `Some("MyAgent")` | `Some("MyAgent")` | 仅名称 |
| `Some("   ")` | `None` | 空白禁用 |

### 测试用例 4: 指令内容验证

**测试函数**: `instruction_mentions_trailer_and_omits_generated_with`

**测试代码**:
```rust
#[test]
fn instruction_mentions_trailer_and_omits_generated_with() {
    let instruction = commit_message_trailer_instruction(Some("AgentX <agent@example.com>"))
        .expect("instruction expected");
    assert!(instruction.contains("Co-authored-by: AgentX <agent@example.com>"));
    assert!(instruction.contains("exactly once"));
    assert!(!instruction.contains("Generated-with"));
}
```

**验证点**:
- 指令包含指定的归属标记
- 包含 "exactly once" 规则提示
- 不包含已弃用的 "Generated-with" 标记

## 关键代码路径与文件引用

### 被测试函数

```rust
use super::build_commit_message_trailer;
use super::commit_message_trailer_instruction;
use super::resolve_attribution_value;
```

来自父模块 `commit_attribution.rs`。

### 测试断言库

无外部断言库依赖，使用标准库 `assert_eq!` 和 `assert!`。

### 测试模块结构

```rust
// commit_attribution.rs
#[cfg(test)]
#[path = "commit_attribution_tests.rs"]
mod tests;
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `commit_attribution` | 被测试的归属函数 |

### 无外部 Crate 依赖

测试仅依赖 Rust 标准库。

## 风险、边界与改进建议

### 当前风险点

1. **测试覆盖有限**: 仅覆盖 4 个基本场景，缺少边界情况
   - 超长归属字符串
   - 特殊字符处理
   - 换行符处理
   - Unicode 字符

2. **硬编码期望值**: 测试依赖硬编码的默认归属值
   ```rust
   Some("Codex <noreply@openai.com>".to_string())
   ```
   如果默认值变更，测试需要同步更新

3. **部分函数未测试**: `commit_message_trailer_instruction` 的 `None` 返回场景未直接测试

### 边界情况未覆盖

1. **超长归属**:
   ```rust
   let long_name = "a".repeat(1000);
   resolve_attribution_value(Some(&long_name));
   // 未测试
   ```

2. **特殊字符**:
   ```rust
   resolve_attribution_value(Some("Name\n<script>alert(1)</script>"));
   // 未测试
   ```

3. **Unicode**:
   ```rust
   resolve_attribution_value(Some("用户 <用户@例子.中国>"));
   // 未测试
   ```

4. **指令格式边界**:
   ```rust
   // 验证指令包含所有必要规则
   // 验证换行符数量
   // 未测试
   ```

### 改进建议

1. **增加边界测试**:
   ```rust
   #[test]
   fn handles_long_attribution() {
       let long = "a".repeat(10000);
       let result = resolve_attribution_value(Some(&long));
       assert!(result.is_some());
       assert_eq!(result.unwrap().len(), 10000);
   }

   #[test]
   fn handles_unicode_attribution() {
       let unicode = "用户 <用户@例子.中国>";
       assert_eq!(
           resolve_attribution_value(Some(unicode)),
           Some(unicode.to_string())
       );
   }
   ```

2. **增加安全测试**:
   ```rust
   #[test]
   fn sanitizes_newline_in_attribution() {
       let malicious = "Name\nCo-authored-by: Attacker";
       let result = resolve_attribution_value(Some(malicious));
       // 验证换行符被处理或拒绝
   }
   ```

3. **参数化测试**:
   ```rust
   #[rstest]
   #[case(None, Some("Codex <noreply@openai.com>"))]
   #[case(Some(""), None)]
   #[case(Some("  "), None)]
   #[case(Some("Test"), Some("Test"))]
   fn test_resolve_attribution(
       #[case] input: Option<&str>,
       #[case] expected: Option<&str>,
   ) {
       assert_eq!(resolve_attribution_value(input), expected.map(String::from));
   }
   ```

4. **指令结构测试**:
   ```rust
   #[test]
   fn instruction_has_correct_structure() {
       let instruction = commit_message_trailer_instruction(Some("Test"))
           .unwrap();
       
       // 验证包含所有必要部分
       assert!(instruction.contains("Co-authored-by:"));
       assert!(instruction.contains("Rules:"));
       assert!(instruction.contains("exactly once"));
       assert!(instruction.contains("do not duplicate"));
       assert!(instruction.contains("blank line"));
       
       // 验证格式（行数、空行等）
       let lines: Vec<_> = instruction.lines().collect();
       assert!(lines.len() >= 5);
   }
   ```

5. **默认值常量测试**:
   ```rust
   #[test]
   fn default_attribution_is_valid() {
       // 验证默认值符合预期格式
       let default = resolve_attribution_value(None).unwrap();
       assert!(default.contains("Codex"));
       assert!(default.contains('@'));
       assert!(default.contains('>'));
   }
   ```

### 相关文档

- `commit_attribution.rs` - 主实现文件
- Git 官方文档 - Commit trailer 规范
- `AGENTS.md` - 项目编码规范
