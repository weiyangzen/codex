# event_mapping_tests.rs 研究文档

## 场景与职责

`event_mapping_tests.rs` 是 `event_mapping.rs` 的配套测试模块，负责验证事件映射的各项功能，包括用户消息解析、助手消息解析、推理内容提取、网页搜索转换和图像标签过滤。

**测试覆盖范围：**
1. 用户消息解析（文本、图像、混合内容）
2. 图像标签过滤（本地图像、命名图像）
3. 上下文片段跳过（AGENTS.md、环境上下文、skill、shell 命令）
4. 助手消息解析
5. 推理内容解析（摘要和原始内容）
6. 网页搜索调用解析（搜索、打开页面、页面内查找）
7. 部分/不完整搜索调用处理

---

## 功能点目的

### 测试用例清单

| 测试函数 | 目的 | 关键验证点 |
|---------|------|-----------|
| `parses_user_message_with_text_and_two_images` | 基本用户消息 | 文本 + 多图像 |
| `skips_local_image_label_text` | 本地图像标签过滤 | `<image1>`, `</image>` |
| `skips_unnamed_image_label_text` | 命名图像标签过滤 | `<image>`, `</image>` |
| `skips_user_instructions_and_env` | 上下文片段跳过 | AGENTS.md, env_ctx, skill, shell_cmd |
| `parses_agent_message` | 助手消息解析 | 文本内容提取 |
| `parses_reasoning_summary_and_raw_content` | 推理内容解析 | 摘要和原始内容 |
| `parses_reasoning_including_raw_content` | 推理内容解析 | 多种内容类型 |
| `parses_web_search_call` | 搜索调用解析 | Search action |
| `parses_web_search_open_page_call` | 打开页面解析 | OpenPage action |
| `parses_web_search_find_in_page_call` | 页面查找解析 | FindInPage action |
| `parses_partial_web_search_call_without_action_as_other` | 不完整调用 | 无 action 时默认为 Other |

---

## 具体技术实现

### 测试基础设施

**图像 URL 构造：**
```rust
let img1 = "https://example.com/one.png".to_string();
let img2 = "https://example.com/two.jpg".to_string();
```

**本地图像标签：**
```rust
let label = codex_protocol::models::local_image_open_tag_text(1);
// 生成: "<image1>"
```

**ResponseItem 构造：**
```rust
let item = ResponseItem::Message {
    id: None,
    role: "user".to_string(),
    content: vec![...],
    end_turn: None,
    phase: None,
};
```

### 关键测试场景

**1. 图像标签过滤测试**
```rust
#[test]
fn skips_local_image_label_text() {
    let item = ResponseItem::Message {
        content: vec![
            ContentItem::InputText { text: "<image1>".to_string() },  // 应被过滤
            ContentItem::InputImage { image_url: "data:image/png;base64,abc".to_string() },
            ContentItem::InputText { text: "</image>".to_string() },  // 应被过滤
            ContentItem::InputText { text: "Please review.".to_string() },  // 应保留
        ],
        ...
    };
    // 验证结果只包含图像和用户文本
}
```
- 验证图像标签文本被正确识别和过滤
- 验证图像内容和用户文本保留

**2. 上下文片段跳过测试**
```rust
#[test]
fn skips_user_instructions_and_env() {
    let items = vec![
        ResponseItem::Message { content: vec![AGENTS_MD_INSTRUCTIONS], ... },
        ResponseItem::Message { content: vec![ENVIRONMENT_CONTEXT], ... },
        ResponseItem::Message { content: vec![SKILL_FRAGMENT], ... },
        ResponseItem::Message { content: vec![USER_SHELL_COMMAND], ... },
        ResponseItem::Message { content: vec![混合内容], ... },
    ];
    // 验证所有都被解析为 None
}
```
- 验证 AGENTS.md 指令被跳过
- 验证环境上下文被跳过
- 验证 skill 片段被跳过
- 验证 shell 命令被跳过

**3. 推理内容解析测试**
```rust
#[test]
fn parses_reasoning_summary_and_raw_content() {
    let item = ResponseItem::Reasoning {
        id: "reasoning_1".to_string(),
        summary: vec![
            ReasoningItemReasoningSummary::SummaryText { text: "Step 1".to_string() },
            ReasoningItemReasoningSummary::SummaryText { text: "Step 2".to_string() },
        ],
        content: Some(vec![
            ReasoningItemContent::ReasoningText { text: "raw details".to_string() },
        ]),
        encrypted_content: None,
    };
    // 验证 summary_text = ["Step 1", "Step 2"]
    // 验证 raw_content = ["raw details"]
}
```
- 验证摘要列表正确提取
- 验证原始内容列表正确提取

**4. 网页搜索动作测试**
```rust
#[test]
fn parses_web_search_find_in_page_call() {
    let item = ResponseItem::WebSearchCall {
        action: Some(WebSearchAction::FindInPage {
            url: Some("https://example.com".to_string()),
            pattern: Some("needle".to_string()),
        }),
        ...
    };
    // 验证 query = "'needle' in https://example.com"
}
```
- 验证不同搜索动作的查询字符串格式

**5. 不完整调用处理**
```rust
#[test]
fn parses_partial_web_search_call_without_action_as_other() {
    let item = ResponseItem::WebSearchCall {
        action: None,  // 无动作
        ...
    };
    // 验证 action = WebSearchAction::Other
    // 验证 query = ""
}
```
- 验证缺失数据时的默认行为

---

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/event_mapping_tests.rs` (405 行)

### 被测试文件
- `/home/sansha/Github/codex/codex-rs/core/src/event_mapping.rs` - 主实现

### 测试依赖
- `pretty_assertions::assert_eq` - 清晰的断言输出
- `codex_protocol::items` - TurnItem 类型
- `codex_protocol::models` - ResponseItem, ContentItem 类型

---

## 依赖与外部交互

### 测试框架
| 依赖 | 用途 |
|------|------|
| `pretty_assertions` | 清晰的结构体比较 |

### 被测模块导入
```rust
use super::parse_turn_item;
use codex_protocol::items::{AgentMessageContent, TurnItem, WebSearchItem, ...};
use codex_protocol::models::{ContentItem, ReasoningItemContent, ...};
use codex_protocol::user_input::UserInput;
```

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **图像生成调用测试**
   - 无 `ImageGenerationCall` 解析测试
   - 无图像生成状态处理测试

2. **系统消息测试**
   - 无 `role: "system"` 消息测试
   - 系统消息应返回 None

3. **未知角色测试**
   - 无未知角色消息测试
   - 应返回 None 但可能需验证

4. **边界索引测试**
   - 无图像在首项/末项的标签过滤测试
   - 无空内容列表测试

5. **多图像混合测试**
   - 无多个图像和文本交错测试
   - 无图像标签不匹配测试

6. **推理内容边界**
   - 无空摘要测试
   - 无空原始内容测试
   - 无加密内容测试

7. **UUID 生成测试**
   - 无 ID 缺失时的 UUID 生成验证

### 改进建议

1. **添加图像生成测试**
   ```rust
   #[test]
   fn parses_image_generation_call() {
       let item = ResponseItem::ImageGenerationCall {
           status: Some("completed".to_string()),
           revised_prompt: Some("...".to_string()),
           result: Some(ImageResult { ... }),
           ...
       };
       // 验证解析
   }
   ```

2. **添加系统消息测试**
   ```rust
   #[test]
   fn system_message_returns_none() {
       let item = ResponseItem::Message { role: "system".to_string(), ... };
       assert!(parse_turn_item(&item).is_none());
   }
   ```

3. **添加边界索引测试**
   ```rust
   #[test]
   fn image_at_first_position_handled_correctly() {
       // 图像在第一项，无前项可检查
   }
   
   #[test]
   fn image_at_last_position_handled_correctly() {
       // 图像在最后一项，无后项可检查
   }
   ```

4. **添加空内容测试**
   ```rust
   #[test]
   fn empty_content_returns_empty_user_message() {
       let item = ResponseItem::Message { content: vec![], ... };
       // 验证行为
   }
   ```

5. **使用快照测试**
   - 复杂消息结构可使用 `insta` 快照测试
   - 便于检测意外变更

6. **添加性能测试**
   ```rust
   #[test]
   fn large_message_parsing_performance() {
       // 测试大量内容项的解析性能
   }
   ```

### 测试代码质量

**优点：**
- 使用 `pretty_assertions` 改善结构体比较
- 清晰的测试命名和结构
- 覆盖主要功能路径
- 使用 `panic!` 提供清晰的失败信息

**可改进点：**
- 可提取公共的 ResponseItem 构造辅助函数
- 可添加属性测试生成随机内容组合
- 可添加模糊测试验证解析器鲁棒性
