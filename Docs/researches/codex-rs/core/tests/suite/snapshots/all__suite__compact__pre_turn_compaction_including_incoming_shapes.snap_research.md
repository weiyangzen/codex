# Research: pre_turn_compaction_including_incoming_shapes.snap

## 场景与职责

该快照文件记录了**带上下文覆盖的轮前压缩（Pre-turn Compaction with Context Override）**场景，验证当用户在轮前压缩时提供上下文覆盖（如 cwd 变更）时的请求结构。

**测试场景**：用户进行两轮对话后，第三轮发送图片消息并变更 cwd，触发轮前自动压缩。

---

## 功能点目的

1. **上下文差异处理**：在压缩请求中体现上下文覆盖（如 cwd 变更）
2. **多媒体支持**：验证图片输入在压缩后的正确处理
3. **环境上下文更新**：压缩后使用新的环境上下文

---

## 具体技术实现

### 关键流程

```
USER_ONE → USER_TWO → OverrideTurnContext(cwd+image) + USER_THREE → 轮前压缩 → 跟进请求
```

### 数据结构

**压缩请求（Local Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:USER_ONE
03:message/assistant:FIRST_REPLY
04:message/user:USER_TWO
05:message/assistant:SECOND_REPLY
06:message/user:<SUMMARIZATION_PROMPT>
```

**压缩后历史布局（Local Post-Compaction History Layout）**:
```
00:message/user:USER_ONE
01:message/user:USER_TWO
02:message/user:<COMPACTION_SUMMARY>\nPRE_TURN_SUMMARY
03:message/developer:<PERMISSIONS_INSTRUCTIONS>
04:message/user:<ENVIRONMENT_CONTEXT:cwd=PRETURN_CONTEXT_DIFF_CWD>
05:message/user[4]:
    [01] <image>
    [02] <input_image:image_url>
    [03] </image>
    [04] USER_THREE
```

### 关键观察

1. **压缩请求特点**：
   - 包含前两轮完整历史
   - 使用原始环境上下文（`<CWD>`）
   - 不包含新用户消息（USER_THREE）和图片

2. **跟进请求特点**：
   - 压缩摘要替代助手回复
   - 更新环境上下文（`PRETURN_CONTEXT_DIFF_CWD`）
   - 包含图片输入（`<image>`...`</image>`）
   - 新用户消息（USER_THREE）追加

3. **上下文差异**：
   - cwd 从 `<CWD>` 变更为 `PRETURN_CONTEXT_DIFF_CWD`
   - 通过 `OverrideTurnContext` 操作触发

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact.rs`
- **测试函数**: `snapshot_request_shape_pre_turn_compaction_including_incoming_user_message` (行 2964-3080)
- **快照生成**: 行 3051-3060

### 测试流程
```rust
// 第一轮
submit(Op::UserInput { text: "USER_ONE" })

// 第二轮
submit(Op::UserInput { text: "USER_TWO" })

// 第三轮：先覆盖上下文，再发送图片+文字
submit(Op::OverrideTurnContext { 
    cwd: Some(PathBuf::from(PRETURN_CONTEXT_DIFF_CWD)),
    ...
});
submit(Op::UserInput { 
    items: [
        UserInput::Image { image_url },
        UserInput::Text { text: "USER_THREE" }
    ]
});
```

### 关键断言
```rust
// 验证压缩请求不包含新用户消息
let compact_request_user_texts = requests[2].message_input_texts("user");
assert!(!compact_request_user_texts.iter().any(|text| text == "USER_THREE"));

// 验证跟进请求包含新用户消息和图片
let follow_up_user_texts = requests[3].message_input_texts("user");
assert!(follow_up_user_texts.iter().any(|text| text == "USER_THREE"));
let follow_up_user_images = requests[3].message_input_image_urls("user");
assert!(follow_up_user_images.iter().any(|url| url == image_url.as_str()));
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **SSE 序列**: 4 阶段响应（USER_ONE, USER_TWO, 压缩, 跟进）

### 操作类型
- `Op::UserInput`: 用户输入
- `Op::OverrideTurnContext`: 上下文覆盖（cwd, approval_policy, sandbox_policy 等）

### 图片处理
```rust
let image_url = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=";
```

---

## 风险、边界与改进建议

### 风险点
1. **上下文不一致**：压缩请求和跟进请求使用不同上下文可能导致混淆
2. **图片令牌计算**：图片令牌计算复杂，可能导致压缩判断不准确
3. **覆盖操作丢失**：若压缩失败，覆盖操作可能丢失

### 边界情况
1. **多次覆盖**：单轮多次上下文覆盖的合并处理
2. **覆盖与压缩冲突**：覆盖的参数影响压缩决策
3. **图片过大**：图片本身超出上下文窗口

### 改进建议
1. **上下文差异提示**：向用户展示上下文变更（如 cwd 变更）
2. **图片压缩**：支持图片压缩或缩略图以减少令牌
3. **覆盖原子性**：确保上下文覆盖与压缩的原子性
4. **预览模式**：压缩前预览将要发送的内容

### 相关测试
- `pre_turn_compaction_strips_incoming_model_switch_shapes`: 模型切换场景
- `model_visible_layout_turn_overrides`: 上下文覆盖通用测试
