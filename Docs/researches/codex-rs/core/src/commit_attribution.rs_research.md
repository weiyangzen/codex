# commit_attribution.rs 深度研究文档

## 场景与职责

`commit_attribution.rs` 实现了 Git 提交信息的**作者归属（Attribution）**功能。当 Codex 协助用户编写或修改 Git 提交信息时，该模块确保在提交信息末尾添加适当的 `Co-authored-by` 标记，以正确标识 Codex 对提交内容的贡献。

### 核心场景

1. **Codex 辅助提交**: 当用户使用 Codex 生成提交信息时，添加默认归属
2. **自定义归属**: 允许用户配置自定义的归属信息
3. **禁用归属**: 支持通过空配置禁用归属标记

### 职责边界

- 仅生成归属标记和指令，不直接操作 Git
- 提供配置解析和默认值处理
- 生成模型可理解的提交信息编辑指令

## 功能点目的

### 1. 知识产权透明

通过 `Co-authored-by` 标记，明确标识：
- 提交内容由 Codex 辅助生成
- 符合开源社区的协作规范
- 满足某些组织的合规要求

### 2. 可配置性

支持三种配置模式：
- **默认**: 使用 `Codex <noreply@openai.com>`
- **自定义**: 用户指定任意归属字符串
- **禁用**: 空字符串或仅空白字符表示禁用

### 3. 模型引导

生成清晰的指令，指导模型：
- 在提交信息末尾添加归属标记
- 避免重复添加
- 保持提交信息格式正确

## 具体技术实现

### 常量定义

```rust
/// 默认归属值，当用户未配置时使用
const DEFAULT_ATTRIBUTION_VALUE: &str = "Codex <noreply@openai.com>";
```

### 核心函数

#### 1. 构建提交信息尾部标记

```rust
fn build_commit_message_trailer(config_attribution: Option<&str>) -> Option<String> {
    let value = resolve_attribution_value(config_attribution)?;
    Some(format!("Co-authored-by: {value}"))
}
```

**逻辑**:
- 解析配置值
- 包装为 `Co-authored-by` 格式
- 返回 `None` 表示禁用

#### 2. 生成模型指令

```rust
pub(crate) fn commit_message_trailer_instruction(
    config_attribution: Option<&str>,
) -> Option<String> {
    let trailer = build_commit_message_trailer(config_attribution)?;
    Some(format!(
        "When you write or edit a git commit message, ensure the message ends with this trailer exactly once:\n{trailer}\n\nRules:\n- Keep existing trailers and append this trailer at the end if missing.\n- Do not duplicate this trailer if it already exists.\n- Keep one blank line between the commit body and trailer block."
    ))
}
```

**指令内容**:
1. 明确要求添加归属标记
2. 避免重复添加的规则
3. 格式要求（空行分隔）

#### 3. 解析归属值

```rust
fn resolve_attribution_value(config_attribution: Option<&str>) -> Option<String> {
    match config_attribution {
        Some(value) => {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                None  // 空字符串表示禁用
            } else {
                Some(trimmed.to_string())
            }
        }
        None => Some(DEFAULT_ATTRIBUTION_VALUE.to_string()),  // 使用默认值
    }
}
```

**行为矩阵**:

| 输入 | 输出 | 说明 |
|------|------|------|
| `None` | `Some("Codex <noreply@openai.com>")` | 使用默认值 |
| `Some("Custom <email>")` | `Some("Custom <email>")` | 使用自定义值 |
| `Some("")` | `None` | 空字符串禁用 |
| `Some("   ")` | `None` | 仅空白字符禁用 |

## 关键代码路径与文件引用

### 调用方

归属指令通常被添加到系统提示（system prompt）中，指导模型行为：

```rust
// 伪代码示例，实际调用可能在配置构建阶段
let instruction = commit_message_trailer_instruction(config.commit_attribution.as_deref());
if let Some(instr) = instruction {
    system_prompt.push_str(&instr);
}
```

### 测试模块

```rust
#[cfg(test)]
#[path = "commit_attribution_tests.rs"]
mod tests;
```

## 依赖与外部交互

### 无外部依赖

该模块仅使用 Rust 标准库：
- `str::trim()` - 字符串修剪
- `format!` - 字符串格式化
- `Option` - 可选值处理

### 模块可见性

- `build_commit_message_trailer` - `private`
- `commit_message_trailer_instruction` - `pub(crate)`
- `resolve_attribution_value` - `private`

## 风险、边界与改进建议

### 当前风险点

1. **硬编码默认值**: `DEFAULT_ATTRIBUTION_VALUE` 硬编码 OpenAI 邮箱，如果 Codex 品牌变更需要代码修改

2. **邮箱格式验证**: 不验证归属字符串是否为有效邮箱格式，可能导致生成无效的 `Co-authored-by` 标记
   ```rust
   // 当前实现接受任意字符串
   resolve_attribution_value(Some("not-an-email"))
   // 返回 Some("not-an-email")
   ```

3. **指令注入风险**: 如果用户配置的归属包含换行符，可能破坏指令格式
   ```rust
   resolve_attribution_value(Some("Name\nMalicious: instruction"))
   // 可能被模型误解
   ```

### 边界情况

1. **超长归属**: 未限制归属字符串长度，极端情况可能导致内存问题
2. **Unicode 处理**: 未验证归属字符串的 Unicode 有效性
3. **并发安全**: 无状态函数，天然线程安全

### 改进建议

1. **邮箱格式验证**:
   ```rust
   fn resolve_attribution_value(config_attribution: Option<&str>) -> Option<String> {
       let value = match config_attribution {
           Some(v) if v.trim().is_empty() => return None,
           Some(v) => v.trim(),
           None => return Some(DEFAULT_ATTRIBUTION_VALUE.to_string()),
       };
       
       // 验证邮箱格式
       if !is_valid_email_or_name(value) {
           tracing::warn!("Invalid attribution format: {}", value);
           return None;
       }
       
       Some(value.to_string())
   }
   ```

2. **字符白名单**:
   ```rust
   fn sanitize_attribution(value: &str) -> Option<String> {
       // 只允许可打印 ASCII 和常见 Unicode 字符
       let sanitized: String = value
           .chars()
           .filter(|c| c.is_ascii_graphic() || c.is_whitespace())
           .collect();
       
       if sanitized != value {
           tracing::warn!("Attribution contained invalid characters, sanitized");
       }
       
       Some(sanitized)
   }
   ```

3. **配置化默认值**:
   ```rust
   // 从环境变量或配置文件读取默认值
   const DEFAULT_ATTRIBUTION_VALUE: &str = env!(
       "CODEX_DEFAULT_ATTRIBUTION",
       "Codex <noreply@openai.com>"
   );
   ```

4. **长度限制**:
   ```rust
   const MAX_ATTRIBUTION_LENGTH: usize = 256;
   
   fn resolve_attribution_value(config_attribution: Option<&str>) -> Option<String> {
       // ...
       if value.len() > MAX_ATTRIBUTION_LENGTH {
           tracing::warn!("Attribution too long, truncated");
           value = &value[..MAX_ATTRIBUTION_LENGTH];
       }
       // ...
   }
   ```

5. **更多 Git 尾部标记支持**:
   ```rust
   pub enum CommitTrailer {
       CoAuthoredBy(String),
       SignedOffBy(String),
       ReviewedBy(String),
       // ...
   }
   ```

### 相关文档

- `commit_attribution_tests.rs` - 单元测试
- Git 官方文档 - `Co-authored-by` 规范
- `AGENTS.md` - 项目编码规范
