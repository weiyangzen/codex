# ContextManager 测试模块 (history_tests.rs) 深度研究

## 一、场景与职责

`history_tests.rs` 是 `codex-rs/core/src/context_manager/history.rs` 的配套测试模块，包含 1700+ 行全面的单元测试。该测试文件的核心职责包括：

1. **功能正确性验证**：验证 `ContextManager` 的各项功能行为符合预期
2. **边界条件测试**：覆盖空历史、单一项、超大内容等边界场景
3. **归一化逻辑验证**：测试 call/output 配对、孤儿项处理、图像剥离等归一化操作
4. **Token 估算验证**：验证各种场景下的 token 估算准确性
5. **图像处理测试**：测试 base64 图像解析、Original 细节估算、多图像场景

测试模块使用 `pretty_assertions` 提供清晰的差异输出，使用 `insta` 风格的显式断言进行验证。

## 二、功能点目的

### 2.1 测试分类概览

| 测试类别 | 测试数量 | 覆盖功能 |
|----------|----------|----------|
| 基础功能测试 | ~15 | 记录、过滤、移除、替换 |
| Token 估算测试 | ~10 | 字节估算、推理 token、图像估算 |
| 归一化测试 | ~15 | call/output 配对、孤儿项处理 |
| 图像处理测试 | ~12 | base64 解析、Original 细节、多图像 |
| 截断测试 | ~6 | 文本截断、工具输出截断 |
| 回滚测试 | ~4 | 用户回合回滚、前缀保留 |

### 2.2 测试辅助函数

```rust
// 消息构造辅助函数
fn assistant_msg(text: &str) -> ResponseItem;
fn user_msg(text: &str) -> ResponseItem;
fn user_input_text_msg(text: &str) -> ResponseItem;  // InputText 变体
fn custom_tool_call_output(call_id: &str, output: &str) -> ResponseItem;
fn reasoning_msg(text: &str) -> ResponseItem;
fn reasoning_with_encrypted_content(len: usize) -> ResponseItem;

// 历史构造辅助函数
fn create_history_with_items(items: Vec<ResponseItem>) -> ContextManager;

// 截断辅助函数
fn truncate_exec_output(content: &str) -> String;
fn approx_token_count_for_text(text: &str) -> i64;
fn assert_truncated_message_matches(message: &str, line: &str, expected_removed: usize);
```

## 三、具体技术实现

### 3.1 API 消息过滤测试 (`filters_non_api_messages`)

```rust
#[test]
fn filters_non_api_messages() {
    let mut h = ContextManager::default();
    let policy = TruncationPolicy::Tokens(10_000);
    
    // System 消息被过滤
    let system = ResponseItem::Message { role: "system".to_string(), ... };
    // Reasoning 被保留
    let reasoning = reasoning_msg("thinking...");
    // Other 被过滤
    h.record_items([&system, &reasoning, &ResponseItem::Other], policy);
    
    // User 和 Assistant 被保留
    let u = user_msg("hi");
    let a = assistant_msg("hello");
    h.record_items([&u, &a], policy);
    
    // 验证结果
    assert_eq!(items, vec![reasoning, user_msg, assistant_msg]);
}
```

**验证要点**：
- `role == "system"` 的消息被过滤
- `ResponseItem::Other` 被过滤
- `ResponseItem::GhostSnapshot` 被保留（内部使用）
- 普通用户/助手消息被保留

### 3.2 Token 估算测试

#### 非最后推理 Token 计算
```rust
#[test]
fn non_last_reasoning_tokens_ignore_entries_after_last_user() {
    let history = create_history_with_items(vec![
        reasoning_with_encrypted_content(900),   // 计入
        user_msg("first"),
        reasoning_with_encrypted_content(1_000), // 计入
        user_msg("second"),
        reasoning_with_encrypted_content(2_000), // 不计入（在最后一个用户后）
    ]);
    
    // 计算: (900 * 0.75 - 650) / 4 = 6.25
    //       (1000 * 0.75 - 650) / 4 = 25
    // 总计: ~32 tokens
    assert_eq!(history.get_non_last_reasoning_items_tokens(), 32);
}
```

**算法解析**：
```rust
fn estimate_reasoning_length(encoded_len: usize) -> usize {
    encoded_len
        .saturating_mul(3)
        .checked_div(4)
        .unwrap_or(0)
        .saturating_sub(650)  // 减去固定开销
}
```

#### 模型生成项后的 Token
```rust
#[test]
fn items_after_last_model_generated_tokens_include_user_and_tool_output() {
    let history = create_history_with_items(vec![
        assistant_msg("already counted by API"),  // 模型生成
        user_msg("new user message"),             // 之后添加
        custom_tool_call_output("call-tail", "new tool output"), // 之后添加
    ]);
    
    // 验证只计算模型生成项之后的项
    let tokens = history.items_after_last_model_generated_item()
        .iter()
        .map(estimate_item_token_count)
        .fold(0i64, i64::saturating_add);
    
    assert_eq!(tokens, expected_tokens);
}
```

### 3.3 图像处理测试

#### 图像剥离测试
```rust
#[test]
fn for_prompt_strips_images_when_model_does_not_support_images() {
    let items = vec![
        ResponseItem::Message {
            content: vec![
                ContentItem::InputText { text: "look".to_string() },
                ContentItem::InputImage { image_url: "https://...".to_string() },
            ],
            ...
        },
        // FunctionCallOutput 中的图像
        ResponseItem::FunctionCallOutput { ... },
        // CustomToolCallOutput 中的图像
        ResponseItem::CustomToolCallOutput { ... },
    ];
    
    let history = create_history_with_items(items);
    let text_only_modalities = vec![InputModality::Text];
    let stripped = history.for_prompt(&text_only_modalities);
    
    // 验证图像被替换为占位文本
    assert!(matches!(stripped[0].content[1], ContentItem::InputText { ... }));
}
```

#### 图像 Token 估算测试
```rust
#[test]
fn image_data_url_payload_does_not_dominate_message_estimate() {
    let payload = "A".repeat(100_000);  // 100KB base64
    let image_url = format!("data:image/png;base64,{payload}");
    let image_item = ResponseItem::Message {
        content: vec![
            ContentItem::InputText { text: "Here is the screenshot".to_string() },
            ContentItem::InputImage { image_url },
        ],
        ...
    };
    
    let raw_len = serde_json::to_string(&image_item).unwrap().len() as i64;
    let estimated = estimate_response_item_model_visible_bytes(&image_item);
    let expected = raw_len - payload.len() as i64 + RESIZED_IMAGE_BYTES_ESTIMATE;
    
    assert_eq!(estimated, expected);
    assert!(estimated < raw_len);  // 估算值应小于原始大小
}
```

#### Original 细节图像测试
```rust
#[test]
fn original_detail_images_scale_with_dimensions() {
    const EXPECTED_ORIGINAL_DETAIL_IMAGE_BYTES: i64 = 7_776;
    
    // 创建 2304x864 的测试图像
    let image = ImageBuffer::from_pixel(width, height, Rgba([12u8, 34, 56, 255]));
    let mut bytes = std::io::Cursor::new(Vec::new());
    image.write_to(&mut bytes, ImageFormat::Png).expect("encode png");
    let payload = BASE64_STANDARD.encode(bytes.get_ref());
    
    // 计算: (2304/32) * (864/32) = 72 * 27 = 1,944 patches
    // 1,944 * 4 bytes/token = 7,776 bytes
    assert_eq!(estimated, expected);
}
```

### 3.4 归一化测试

#### 缺失 Output 自动插入
```rust
#[cfg(not(debug_assertions))]
#[test]
fn normalize_adds_missing_output_for_function_call() {
    let items = vec![ResponseItem::FunctionCall {
        call_id: "call-x".to_string(),
        ...
    }];
    let mut h = create_history_with_items(items);
    h.normalize_history(&default_input_modalities());
    
    // 验证自动插入了 "aborted" output
    assert_eq!(h.raw_items().len(), 2);
    assert!(matches!(h.raw_items()[1], ResponseItem::FunctionCallOutput { ... }));
}
```

**条件编译说明**：
- `#[cfg(not(debug_assertions))]`：Release 模式下测试自动修复
- `#[cfg(debug_assertions)]` + `#[should_panic]`：Debug 模式下测试 panic 行为

#### 孤儿 Output 移除
```rust
#[cfg(not(debug_assertions))]
#[test]
fn normalize_removes_orphan_function_call_output() {
    let items = vec![ResponseItem::FunctionCallOutput {
        call_id: "orphan-1".to_string(),  // 没有对应的 call
        ...
    }];
    let mut h = create_history_with_items(items);
    h.normalize_history(&default_input_modalities());
    
    assert_eq!(h.raw_items(), vec![]);  // 被移除
}
```

### 3.5 关联项移除测试

```rust
#[test]
fn remove_first_item_removes_matching_output_for_function_call() {
    let items = vec![
        ResponseItem::FunctionCall { call_id: "call-1".to_string(), ... },
        ResponseItem::FunctionCallOutput { call_id: "call-1".to_string(), ... },
    ];
    let mut h = create_history_with_items(items);
    h.remove_first_item();  // 移除第一个 call
    
    assert_eq!(h.raw_items(), vec![]);  // output 也被移除
}

#[test]
fn remove_first_item_handles_local_shell_pair() {
    let items = vec![
        ResponseItem::LocalShellCall { call_id: Some("call-3".to_string()), ... },
        ResponseItem::FunctionCallOutput { call_id: "call-3".to_string(), ... },
    ];
    let mut h = create_history_with_items(items);
    h.remove_first_item();
    
    assert_eq!(h.raw_items(), vec![]);
}
```

### 3.6 用户回合回滚测试

```rust
#[test]
fn drop_last_n_user_turns_preserves_prefix() {
    let items = vec![
        assistant_msg("session prefix item"),
        user_msg("u1"),
        assistant_msg("a1"),
        user_msg("u2"),
        assistant_msg("a2"),
    ];
    
    let mut history = create_history_with_items(items);
    history.drop_last_n_user_turns(1);  // 回滚 1 个用户回合
    
    // 保留: prefix + u1 + a1
    assert_eq!(history.for_prompt(&modalities), vec![
        assistant_msg("session prefix item"),
        user_msg("u1"),
        assistant_msg("a1"),
    ]);
}

#[test]
fn drop_last_n_user_turns_ignores_session_prefix_user_messages() {
    // 测试上下文用户消息（如 <environment_context>）不被视为回滚边界
    let items = vec![
        user_input_text_msg("<environment_context>ctx</environment_context>"),
        user_input_text_msg("# AGENTS.md instructions..."),
        user_input_text_msg("turn 1 user"),  // 真正的用户回合
        assistant_msg("turn 1 assistant"),
        user_input_text_msg("turn 2 user"),
        assistant_msg("turn 2 assistant"),
    ];
    
    let mut history = create_history_with_items(items);
    history.drop_last_n_user_turns(1);
    
    // 上下文消息被保留，只回滚 "turn 2 user"
}
```

### 3.7 截断测试

```rust
#[test]
fn record_items_truncates_function_call_output_content() {
    let mut history = ContextManager::new();
    let policy = TruncationPolicy::Tokens(1_000);
    let long_line = "a very long line to trigger truncation\n";
    let long_output = long_line.repeat(2_500);  // 远超限制
    
    let item = ResponseItem::FunctionCallOutput {
        output: FunctionCallOutputPayload::from_text(long_output.clone()),
        ...
    };
    history.record_items([&item], policy);
    
    // 验证截断标记存在
    let content = history.items[0].output.text_content().unwrap();
    assert!(content.contains("tokens truncated"));
}
```

#### 截断模式匹配测试
```rust
fn truncated_message_pattern(line: &str) -> String {
    let escaped_line = regex_lite::escape(line);
    format!(r"(?s)^(?P<body>{escaped_line}.*?)(?:\r?)?…(?P<removed>\d+) tokens truncated…(?:.*)?$")
}

fn assert_truncated_message_matches(message: &str, line: &str, expected_removed: usize) {
    let pattern = truncated_message_pattern(line);
    let regex = Regex::new(&pattern).unwrap();
    let captures = regex.captures(message).unwrap();
    
    let body = captures.name("body").expect("missing body capture").as_str();
    let removed: usize = captures.name("removed").expect("missing removed capture").as_str().parse().unwrap();
    
    assert!(body.len() <= EXEC_FORMAT_MAX_BYTES);
    assert_eq!(removed, expected_removed);
}
```

## 四、关键代码路径与文件引用

### 4.1 测试模块结构

```
history_tests.rs
├── 辅助函数区 (lines 26-111)
│   ├── 消息构造函数
│   ├── 历史构造函数
│   └── 截断辅助函数
├── 基础功能测试 (lines 113-498)
│   ├── filters_non_api_messages
│   ├── non_last_reasoning_tokens_*
│   ├── items_after_last_model_generated_*
│   └── for_prompt_* 系列
├── 图像处理测试 (lines 1477-1763)
│   ├── image_data_url_payload_*
│   ├── original_detail_images_*
│   └── non_base64_image_urls_*
├── 归一化测试 (lines 1037-1475)
│   ├── normalize_adds_missing_output_*
│   ├── normalize_removes_orphan_*
│   └── normalize_mixed_inserts_and_removals
└── 截断测试 (lines 849-1036)
    ├── record_items_truncates_*
    └── format_exec_output_*
```

### 4.2 依赖的外部模块

| 模块 | 用途 |
|------|------|
| `super::*` | 导入被测试的 `history.rs` 所有导出项 |
| `crate::truncate` | 截断策略和函数 |
| `codex_protocol::models::*` | ResponseItem 类型定义 |
| `codex_protocol::openai_models::*` | InputModality 等 |
| `image::*` | 测试图像生成 |
| `pretty_assertions::assert_eq` | 清晰的差异输出 |
| `regex_lite::Regex` | 截断消息模式匹配 |

## 五、依赖与外部交互

### 5.1 测试数据构造

测试使用硬编码的测试数据，避免外部依赖：

```rust
const EXEC_FORMAT_MAX_BYTES: usize = 10_000;
const EXEC_FORMAT_MAX_TOKENS: usize = 2_500;

// 使用 InputText 变体区分上下文消息
fn user_input_text_msg(text: &str) -> ResponseItem {
    ResponseItem::Message {
        content: vec![ContentItem::InputText { text: text.to_string() }],
        ...
    }
}
```

### 5.2 条件编译测试

```rust
// Release 模式：测试自动修复行为
#[cfg(not(debug_assertions))]
#[test]
fn normalize_adds_missing_output_for_function_call() { ... }

// Debug 模式：测试 panic 行为
#[cfg(debug_assertions)]
#[test]
#[should_panic]
fn normalize_adds_missing_output_for_custom_tool_call_panics_in_debug() { ... }
```

### 5.3 图像测试资源

使用 `image` crate 动态生成测试图像，避免静态资源文件：

```rust
let image = ImageBuffer::from_pixel(width, height, Rgba([12u8, 34, 56, 255]));
let mut bytes = std::io::Cursor::new(Vec::new());
image.write_to(&mut bytes, ImageFormat::Png).expect("encode png");
let payload = BASE64_STANDARD.encode(bytes.get_ref());
```

## 六、风险、边界与改进建议

### 6.1 测试覆盖分析

| 功能 | 覆盖度 | 备注 |
|------|--------|------|
| 基础记录/过滤 | ✅ 高 | 完整覆盖 |
| Token 估算 | ✅ 高 | 多种场景 |
| 图像处理 | ✅ 高 | base64、Original、多图像 |
| 归一化 | ✅ 高 | 包括 debug/release 差异 |
| 关联项移除 | ✅ 高 | 多种 call 类型 |
| 用户回滚 | ✅ 高 | 包括上下文消息处理 |
| 截断 | ✅ 高 | 字节/token 限制 |

### 6.2 潜在改进点

1. **并发测试缺失**：
   - `BlockingLruCache` 的线程安全未测试
   - 建议：添加多线程并发访问测试

2. **大历史性能测试**：
   - 缺乏大历史（10k+ 项）的性能基准
   - 建议：添加 `#[ignore]` 标记的性能测试

3. **错误处理测试**：
   - 部分错误路径未覆盖（如 base64 解码失败）
   - 建议：使用 `std::io::ErrorKind` 模拟失败场景

4. **测试重复**：
   - `FunctionCallOutput` 和 `CustomToolCallOutput` 测试逻辑相似
   - 可考虑使用参数化测试（如 `rstest` crate）

### 6.3 测试风格观察

1. **优点**：
   - 清晰的命名：`filters_non_api_messages`、`drop_last_n_user_turns_preserves_prefix`
   - 丰富的辅助函数，减少样板代码
   - 显式断言，避免隐式行为

2. **可改进点**：
   - 部分测试数据较长，可考虑使用 `include_str!` 加载外部文件
   - 正则模式匹配测试依赖硬编码格式，可能与实际输出脱节

### 6.4 与生产代码的同步风险

1. **截断标记格式**：
   - 测试中的 `…{removed} tokens truncated…` 模式与实际代码同步
   - 风险：修改标记格式时需要同步更新测试

2. **图像估算常量**：
   - `RESIZED_IMAGE_BYTES_ESTIMATE` 在测试中被硬编码验证
   - 风险：修改常量值时需要同步更新测试期望值
