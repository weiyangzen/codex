# user_instructions_tests.rs 研究文档

## 场景与职责

`codex-rs/core/src/instructions/user_instructions_tests.rs` 是 `user_instructions.rs` 的配套单元测试文件，使用 Rust 内置测试框架和 `pretty_assertions` 库验证：

1. `UserInstructions` 结构体的序列化和 `ResponseItem` 转换
2. `SkillInstructions` 结构体的序列化和 `ResponseItem` 转换
3. 片段匹配器（`AGENTS_MD_FRAGMENT` 和 `SKILL_FRAGMENT`）的正向和负向匹配

这些测试确保指令格式化逻辑的正确性，是 Codex 核心消息构造逻辑的质量保障。

## 功能点目的

| 测试函数 | 测试目的 |
|---------|---------|
| `test_user_instructions()` | 验证 `UserInstructions` 到 `ResponseItem` 的完整转换流程 |
| `test_is_user_instructions()` | 验证 `AGENTS_MD_FRAGMENT.matches_text()` 能正确识别 AGENTS.md 格式消息 |
| `test_skill_instructions()` | 验证 `SkillInstructions` 到 `ResponseItem` 的完整转换流程 |
| `test_is_skill_instructions()` | 验证 `SKILL_FRAGMENT.matches_text()` 能正确识别 Skill 格式消息 |

## 具体技术实现

### 测试框架

```rust
use super::*;  // 导入被测模块
use codex_protocol::models::ContentItem;
use pretty_assertions::assert_eq;  // 提供清晰的 diff 输出
```

### 测试用例详解

#### 1. `test_user_instructions()` - AGENTS.md 指令转换测试

```rust
#[test]
fn test_user_instructions() {
    let user_instructions = UserInstructions {
        directory: "test_directory".to_string(),
        text: "test_text".to_string(),
    };
    let response_item: ResponseItem = user_instructions.into();

    // 解构验证 ResponseItem::Message 变体
    let ResponseItem::Message { role, content, .. } = response_item else {
        panic!("expected ResponseItem::Message");
    };

    assert_eq!(role, "user");  // 角色必须是 "user"

    // 验证内容结构
    let [ContentItem::InputText { text }] = content.as_slice() else {
        panic!("expected one InputText content item");
    };

    // 验证完整输出格式
    assert_eq!(
        text,
        "# AGENTS.md instructions for test_directory\n\n<INSTRUCTIONS>\ntest_text\n</INSTRUCTIONS>",
    );
}
```

**验证点**：
- 结构体正确转换为 `ResponseItem::Message`
- 角色固定为 `"user"`
- 内容包装为单个 `ContentItem::InputText`
- 文本格式符合预期模板

#### 2. `test_is_user_instructions()` - AGENTS.md 片段匹配测试

```rust
#[test]
fn test_is_user_instructions() {
    assert!(AGENTS_MD_FRAGMENT.matches_text(
        "# AGENTS.md instructions for test_directory\n\n<INSTRUCTIONS>\ntest_text\n</INSTRUCTIONS>"
    ));
    assert!(!AGENTS_MD_FRAGMENT.matches_text("test_text"));  // 负向测试
}
```

**验证点**：
- 正确识别符合格式的 AGENTS.md 消息
- 正确拒绝不符合格式的普通文本

#### 3. `test_skill_instructions()` - Skill 指令转换测试

```rust
#[test]
fn test_skill_instructions() {
    let skill_instructions = SkillInstructions {
        name: "demo-skill".to_string(),
        path: "skills/demo/SKILL.md".to_string(),
        contents: "body".to_string(),
    };
    let response_item: ResponseItem = skill_instructions.into();

    let ResponseItem::Message { role, content, .. } = response_item else {
        panic!("expected ResponseItem::Message");
    };

    assert_eq!(role, "user");

    let [ContentItem::InputText { text }] = content.as_slice() else {
        panic!("expected one InputText content item");
    };

    // 验证 XML 包装格式
    assert_eq!(
        text,
        "<skill>\n<name>demo-skill</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>",
    );
}
```

**验证点**：
- Skill 结构体正确转换
- XML 格式包含 name、path 和 contents
- 整体包裹在 `<skill>` 标签内

#### 4. `test_is_skill_instructions()` - Skill 片段匹配测试

```rust
#[test]
fn test_is_skill_instructions() {
    assert!(SKILL_FRAGMENT.matches_text(
        "<skill>\n<name>demo-skill</name>\n<path>skills/demo/SKILL.md</path>\nbody\n</skill>"
    ));
    assert!(!SKILL_FRAGMENT.matches_text("regular text"));  // 负向测试
}
```

## 关键代码路径与文件引用

### 被测代码

| 被测元素 | 定义位置 | 测试覆盖 |
|---------|---------|---------|
| `UserInstructions` | `user_instructions.rs` 行 11-28 | `test_user_instructions` |
| `SkillInstructions` | `user_instructions.rs` 行 36-53 | `test_skill_instructions` |
| `AGENTS_MD_FRAGMENT.matches_text()` | `contextual_user_message.rs` 行 31-41 | `test_is_user_instructions` |
| `SKILL_FRAGMENT.matches_text()` | `contextual_user_message.rs` 行 31-41 | `test_is_skill_instructions` |

### 依赖的匹配逻辑

`matches_text()` 实现（来自 `contextual_user_message.rs`）：

```rust
pub(crate) fn matches_text(&self, text: &str) -> bool {
    let trimmed = text.trim_start();
    let starts_with_marker = trimmed
        .get(..self.start_marker.len())
        .is_some_and(|candidate| candidate.eq_ignore_ascii_case(self.start_marker));
    let trimmed = trimmed.trim_end();
    let ends_with_marker = trimmed
        .get(trimmed.len().saturating_sub(self.end_marker.len())..)
        .is_some_and(|candidate| candidate.eq_ignore_ascii_case(self.end_marker));
    starts_with_marker && ends_with_marker
}
```

**特点**：
- 忽略首尾空白
- 大小写不敏感匹配
- 同时检查起始和结束标记

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|-----|------|
| `super::*` | 被测模块的所有导出 |
| `codex_protocol::models::ContentItem` | 解构消息内容 |
| `pretty_assertions::assert_eq` | 清晰的测试失败 diff |

### 外部类型
| 类型 | 来源 | 用途 |
|-----|------|------|
| `ResponseItem` | `codex_protocol::models` | 验证转换结果 |
| `ContentItem::InputText` | `codex_protocol::models` | 验证内容结构 |

## 风险、边界与改进建议

### 当前测试覆盖情况

| 场景 | 覆盖状态 | 说明 |
|-----|---------|------|
| 正常 AGENTS.md 转换 | ✅ 已覆盖 | `test_user_instructions` |
| 正常 Skill 转换 | ✅ 已覆盖 | `test_skill_instructions` |
| 片段匹配正向测试 | ✅ 已覆盖 | `test_is_*` |
| 片段匹配负向测试 | ✅ 已覆盖 | `test_is_*` 中的 `!matches_text` |
| 空内容处理 | ❌ 未覆盖 | `text: ""` 的情况 |
| 特殊字符处理 | ❌ 未覆盖 | XML 特殊字符 `<`, `>`, `&` 等 |
| 多行内容 | ⚠️ 部分覆盖 | `test_user_instructions` 使用简单文本 |
| 非 UTF-8 路径 | ❌ 未覆盖 | 路径中的特殊字符 |

### 风险

1. **测试数据简单**：所有测试使用简单字符串（`"test_text"`, `"body"`），未覆盖复杂内容
2. **无模糊测试**：片段匹配逻辑可能被精心构造的输入绕过
3. **硬编码预期**：测试中的预期字符串与实现硬编码格式耦合，修改格式需要同步更新测试

### 边界情况未覆盖

1. **空字符串**：
   - `directory: ""`
   - `text: ""`
   - `contents: ""`

2. **特殊字符**：
   - XML/HTML 元字符：`<`, `>`, `&`, `"`, `'`
   - Unicode 字符
   - 控制字符

3. **空白处理**：
   - 首尾空白
   - 多行空白
   - 制表符 vs 空格

4. **路径边界**：
   - 绝对路径 vs 相对路径
   - 包含空格的路径
   - 非 UTF-8 路径

### 改进建议

1. **增加边界测试**：
   ```rust
   #[test]
   fn test_user_instructions_empty_text() {
       let ui = UserInstructions {
           directory: "/path".to_string(),
           text: "".to_string(),
       };
       // 验证空内容的处理行为
   }
   ```

2. **增加特殊字符测试**：
   ```rust
   #[test]
   fn test_skill_instructions_xml_escaping() {
       let si = SkillInstructions {
           name: "test".to_string(),
           path: "path".to_string(),
           contents: "if x < 0 && y > 0".to_string(),  // 包含 < 和 &
       };
       // 验证是否正确转义或处理
   }
   ```

3. **增加模糊测试**：
   - 使用 `proptest` 生成随机输入验证片段匹配鲁棒性

4. **测试数据外部化**：
   - 将预期输出提取为常量或文件，便于批量更新

5. **测试命名优化**：
   - `test_is_user_instructions` 可改为 `test_agents_md_fragment_matching` 更清晰

### 维护建议

- 当修改 `contextual_user_message.rs` 中的 `matches_text()` 逻辑时，必须同步更新本测试
- 当添加新的指令类型时，应遵循相同的测试模式（转换测试 + 片段匹配测试）
- 考虑使用 insta 快照测试替代硬编码预期字符串，简化格式变更时的维护
