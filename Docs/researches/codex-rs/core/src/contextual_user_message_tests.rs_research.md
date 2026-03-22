# contextual_user_message_tests.rs 研究文档

## 场景与职责

`contextual_user_message_tests.rs` 是 `contextual_user_message.rs` 的配套测试文件，提供对上下文用户消息片段识别功能的单元测试覆盖。测试使用 Rust 标准测试框架，验证片段检测、大小写不敏感匹配和内存排除分类等核心功能。

### 测试目标
1. 验证各种上下文片段类型的正确识别
2. 验证大小写不敏感匹配行为
3. 验证普通用户输入不会被误判
4. 验证内存排除分类逻辑

---

## 功能点目的

### 1. 片段类型检测测试
测试每种预定义片段类型的识别：
- 环境上下文片段（`<environment_context>`）
- AGENTS.md 指令片段
- 子代理通知片段

### 2. 大小写不敏感测试
验证标记匹配不区分大小写：
- `<SUBAGENT_NOTIFICATION>` 应匹配 `<subagent_notification>`
- 混合大小写应正常处理

### 3. 负向测试
确保普通用户文本不会被误判为上下文片段

### 4. 内存排除分类测试
验证哪些片段类型应从记忆中排除：
- 应排除：AGENTS.md、Skill
- 应保留：环境上下文、子代理通知

---

## 具体技术实现

### 测试结构

```rust
use super::*;  // 导入被测模块的所有内容

#[test]
fn detects_environment_context_fragment() { ... }

#[test]
fn detects_agents_instructions_fragment() { ... }

#[test]
fn detects_subagent_notification_fragment_case_insensitively() { ... }

#[test]
fn ignores_regular_user_text() { ... }

#[test]
fn classifies_memory_excluded_fragments() { ... }
```

### 测试用例详解

#### 1. 环境上下文检测
```rust
#[test]
fn detects_environment_context_fragment() {
    assert!(is_contextual_user_fragment(&ContentItem::InputText {
        text: "<environment_context>\n<cwd>/tmp</cwd>\n</environment_context>".to_string(),
    }));
}
```
**验证点**：
- 正确的 XML 格式标记被识别
- 标记内的内容不影响识别

#### 2. AGENTS.md 指令检测
```rust
#[test]
fn detects_agents_instructions_fragment() {
    assert!(is_contextual_user_fragment(&ContentItem::InputText {
        text: "# AGENTS.md instructions for /tmp\n\n<INSTRUCTIONS>\nbody\n</INSTRUCTIONS>"
            .to_string(),
    }));
}
```
**验证点**：
- 特殊前缀 `# AGENTS.md instructions for ` 被识别
- 结束标记 `</INSTRUCTIONS>` 正确匹配

#### 3. 大小写不敏感匹配
```rust
#[test]
fn detects_subagent_notification_fragment_case_insensitively() {
    assert!(
        SUBAGENT_NOTIFICATION_FRAGMENT
            .matches_text("<SUBAGENT_NOTIFICATION>{}</subagent_notification>")
    );
}
```
**验证点**：
- 开始标记全大写、结束标记全小写仍能匹配
- `eq_ignore_ascii_case` 实现正确

#### 4. 普通文本忽略
```rust
#[test]
fn ignores_regular_user_text() {
    assert!(!is_contextual_user_fragment(&ContentItem::InputText {
        text: "hello".to_string(),
    }));
}
```
**验证点**：
- 普通用户输入返回 false
- 不会误判为上下文片段

#### 5. 内存排除分类
```rust
#[test]
fn classifies_memory_excluded_fragments() {
    let cases = [
        (
            "# AGENTS.md instructions for /tmp\n\n<INSTRUCTIONS>\nbody\n</INSTRUCTIONS>",
            true,  // 应排除
        ),
        (
            "<skill>\n<name>demo</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>",
            true,  // 应排除
        ),
        (
            "<environment_context>\n<cwd>/tmp</cwd>\n</environment_context>",
            false, // 应保留
        ),
        (
            "<subagent_notification>{\"agent_id\":\"a\",\"status\":\"completed\"}</subagent_notification>",
            false, // 应保留
        ),
    ];

    for (text, expected) in cases {
        assert_eq!(
            is_memory_excluded_contextual_user_fragment(&ContentItem::InputText {
                text: text.to_string(),
            }),
            expected,
            "{text}",  // 失败时显示测试文本
        );
    }
}
```
**验证点**：
- AGENTS.md 和 Skill 应被排除（返回 true）
- 环境上下文和子代理通知应被保留（返回 false）
- 批量测试多种场景

---

## 关键代码路径与文件引用

### 被测试文件
| 文件 | 被测功能 |
|------|----------|
| `contextual_user_message.rs` | `is_contextual_user_fragment`, `is_memory_excluded_contextual_user_fragment`, `ContextualUserFragmentDefinition::matches_text` |

### 测试依赖
| 模块 | 用途 |
|------|------|
| `codex_protocol::models::ContentItem` | 创建测试用的内容项 |

### 测试覆盖
- **测试函数数量**：5 个
- **断言数量**：约 10 个
- **测试风格**：表格驱动测试（`classifies_memory_excluded_fragments`）

---

## 依赖与外部交互

### 测试框架
- **标准测试框架**：`#[test]`
- **无外部断言库**：使用标准 `assert!` 和 `assert_eq!`

### 被测类型
```rust
use super::*;  // 导入父模块的所有公开内容
```

### 无模拟依赖
- 测试直接构造 `ContentItem::InputText` 进行验证
- 无外部服务或文件系统依赖

---

## 风险、边界与改进建议

### 测试覆盖分析

#### 已充分覆盖
- ✅ 环境上下文片段检测
- ✅ AGENTS.md 片段检测
- ✅ 大小写不敏感匹配
- ✅ 普通文本负向测试
- ✅ 内存排除分类（4 种场景）

#### 覆盖不足/潜在风险
- ⚠️ 其他片段类型（USER_SHELL_COMMAND, TURN_ABORTED）未直接测试
- ⚠️ 边界情况：空字符串、空白字符、部分标记
- ⚠️ 极端情况：超长文本、特殊 Unicode 字符
- ⚠️ `wrap` 和 `into_message` 方法未测试

### 改进建议

1. **补充片段类型测试**
   ```rust
   #[test]
   fn detects_user_shell_command_fragment() {
       assert!(is_contextual_user_fragment(&ContentItem::InputText {
           text: "<user_shell_command>ls -la</user_shell_command>".to_string(),
       }));
   }
   
   #[test]
   fn detects_turn_aborted_fragment() {
       assert!(is_contextual_user_fragment(&ContentItem::InputText {
           text: "<turn_aborted>User cancelled</turn_aborted>".to_string(),
       }));
   }
   ```

2. **添加边界情况测试**
   ```rust
   #[test]
   fn handles_empty_string() {
       assert!(!is_contextual_user_fragment(&ContentItem::InputText {
           text: "".to_string(),
       }));
   }
   
   #[test]
   fn handles_partial_marker() {
       // 只有开始标记
       assert!(!is_contextual_user_fragment(&ContentItem::InputText {
           text: "<environment_context>".to_string(),
       }));
       // 只有结束标记
       assert!(!is_contextual_user_fragment(&ContentItem::InputText {
           text: "</environment_context>".to_string(),
       }));
   }
   
   #[test]
   fn handles_whitespace_variations() {
       // 前导空白
       assert!(is_contextual_user_fragment(&ContentItem::InputText {
           text: "   <environment_context></environment_context>".to_string(),
       }));
       // 尾随空白
       assert!(is_contextual_user_fragment(&ContentItem::InputText {
           text: "<environment_context></environment_context>   ".to_string(),
       }));
   }
   ```

3. **添加方法测试**
   ```rust
   #[test]
   fn wrap_creates_properly_formatted_fragment() {
       let result = SKILL_FRAGMENT.wrap("content".to_string());
       assert_eq!(result, "<skill>\ncontent\n</skill>");
   }
   
   #[test]
   fn into_message_creates_correct_response_item() {
       let message = SKILL_FRAGMENT.into_message("content".to_string());
       match message {
           ResponseItem::Message { role, content, .. } => {
               assert_eq!(role, "user");
               assert_eq!(content, vec![ContentItem::InputText { text: "content".to_string() }]);
           }
           _ => panic!("Expected Message variant"),
       }
   }
   ```

4. **添加 Unicode 测试**
   ```rust
   #[test]
   fn handles_unicode_content() {
       assert!(is_contextual_user_fragment(&ContentItem::InputText {
           text: "<environment_context>当前目录: /tmp/中文</environment_context>".to_string(),
       }));
   }
   ```

5. **性能测试（可选）**
   ```rust
   #[test]
   fn handles_large_text_efficiently() {
       let large_text = format!("<environment_context>{}</environment_context>", 
                                "x".repeat(1000000));
       let start = std::time::Instant::now();
       assert!(is_contextual_user_fragment(&ContentItem::InputText {
           text: large_text,
       }));
       let elapsed = start.elapsed();
       assert!(elapsed < std::time::Duration::from_millis(10), "Too slow!");
   }
   ```

### 测试风格建议

1. **使用参数化测试**
   - 对于多种片段类型的测试，可以使用宏或测试框架的参数化功能
   
2. **添加测试文档注释**
   ```rust
   /// Test that AGENTS.md fragments are correctly identified.
   /// 
   /// This ensures project-specific instructions injected by the system
   /// are properly categorized as contextual fragments.
   #[test]
   fn detects_agents_instructions_fragment() { ... }
   ```

3. **分离正负面测试**
   - 当前 `classifies_memory_excluded_fragments` 混合了正面和负面测试
   - 建议拆分为更细粒度的测试函数
