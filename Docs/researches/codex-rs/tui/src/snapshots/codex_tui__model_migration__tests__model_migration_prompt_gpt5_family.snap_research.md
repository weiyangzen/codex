# GPT-5 家族模型迁移提示快照研究文档

## 场景与职责

该快照文件记录了 `codex-rs/tui` 项目中针对 **GPT-5 家族基础模型**的强制升级提示界面。当用户当前使用的是 `gpt-5` 模型，而系统推荐使用 `gpt-5.1` 时，显示此提示。这是通用型模型的升级（非 Codex 特化模型），强调广泛的世界知识和通用推理能力。

**核心职责：**
- 通知用户从基础 `gpt-5` 模型迁移到 `gpt-5.1`
- 强调新模型的通用能力优势（"Broad world knowledge with strong general reasoning"）
- 提供模型详情页面的链接
- 强制用户接受升级（`can_opt_out = false`）

## 功能点目的

### 1. 基础模型升级通知
- **模型家族**：针对 GPT-5 基础系列（非 Codex 特化版本）
- **能力描述**：强调通用知识广度和推理能力
- **适用场景**：适合需要广泛知识背景的通用编程任务

### 2. 产品定位区分
- **与 Codex 模型的区别**：
  - GPT-5/GPT-5.1：通用型，广泛知识
  - GPT-5 Codex/GPT-5.1 Codex：特化型，深度代码推理
- **用户教育**：帮助用户理解不同模型家族的适用场景

### 3. 强制升级体验
- **简化流程**：单一回车确认
- **无选择菜单**：与 gpt-5-codex 升级一致的强制模式
- **信息完整**：提供学习链接供用户深入了解

## 具体技术实现

### 内容生成参数

```rust
migration_copy_for_models(
    "gpt-5",                                          // current_model
    "gpt-5.1",                                        // target_model
    Some("https://www.codex.com/models/gpt-5.1".to_string()),  // model_link
    None,                                             // migration_copy
    None,                                             // migration_markdown
    "gpt-5.1".to_string(),                            // target_display_name
    Some("Broad world knowledge with strong general reasoning.".to_string()),  // target_description
    false,                                            // can_opt_out（强制升级）
)
```

### 模型家族分类

```
GPT-5 家族
├── gpt-5 → gpt-5.1（通用基础模型）
│   └── 描述："Broad world knowledge with strong general reasoning"
│
└── GPT-5 Codex 家族
    ├── gpt-5-codex → gpt-5.1-codex-max（旗舰）
    │   └── 描述："Codex-optimized flagship for deep and fast reasoning"
    └── gpt-5-codex-mini → gpt-5.1-codex-mini（轻量）
        └── 描述："Optimized for codex. Cheaper, faster, but less capable"
```

### 描述文本的差异化策略

| 模型 | 描述焦点 | 隐含定位 |
|-----|---------|---------|
| gpt-5.1 | 通用知识 + 推理 | 全能型助手 |
| gpt-5.1-codex-max | 深度代码推理 | 专业编程助手 |
| gpt-5.1-codex-mini | 成本效益 | 轻量级编程助手 |

## 关键代码路径与文件引用

### 测试函数

```rust
#[test]
fn prompt_snapshot_gpt5_family() {
    let backend = VT100Backend::new(65, 22);
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, 65, 22));

    let screen = ModelMigrationScreen::new(
        FrameRequester::test_dummy(),
        migration_copy_for_models(
            "gpt-5",
            "gpt-5.1",
            Some("https://www.codex.com/models/gpt-5.1".to_string()),
            None,
            None,
            "gpt-5.1".to_string(),
            Some("Broad world knowledge with strong general reasoning.".to_string()),
            false,
        ),
    );
    {
        let mut frame = terminal.get_frame();
        frame.render_widget_ref(&screen, frame.area());
    }
    terminal.flush().expect("flush");
    assert_snapshot!("model_migration_prompt_gpt5_family", terminal.backend());
}
```

### 关键差异点

与 `prompt_snapshot_gpt5_codex` 相比：

| 参数 | gpt5_family | gpt5_codex |
|-----|-------------|------------|
| `current_model` | `"gpt-5"` | `"gpt-5-codex"` |
| `target_model` | `"gpt-5.1"` | `"gpt-5.1-codex-max"` |
| `model_link` | `.../gpt-5.1` | `.../gpt-5.1-codex-max` |
| `target_display_name` | `"gpt-5.1"` | `"gpt-5.1-codex-max"` |
| `target_description` | 通用能力 | 代码特化 |

## 依赖与外部交互

### 模型迁移矩阵

| 源模型 | 目标模型 | 类型 | can_opt_out |
|-------|---------|------|-------------|
| gpt-5.1-codex-mini | gpt-5.1-codex-max | 跨级别升级 | true |
| gpt-5 | gpt-5.1 | 版本升级 | false |
| gpt-5-codex | gpt-5.1-codex-max | 版本+级别升级 | false |
| gpt-5-codex-mini | gpt-5.1-codex-mini | 版本升级 | false |

### 共享实现

所有模型迁移提示共享相同的基础设施：
- `ModelMigrationScreen`：屏幕状态和渲染
- `migration_copy_for_models`：内容生成
- `AltScreenGuard`：备用屏幕管理
- `run_model_migration_prompt`：事件循环

## 风险、边界与改进建议

### 已知风险

1. **模型命名混淆**
   - `gpt-5` 和 `gpt-5.1` 的差异不够直观
   - 风险：用户可能不理解升级的具体价值
   - 建议：添加版本对比（如 "5.0 → 5.1: Improved reasoning and knowledge"）

2. **强制升级的合理性**
   - 基础模型用户可能基于特定需求选择该版本
   - 风险：强制升级可能与用户期望冲突
   - 建议：解释升级的兼容性保证

3. **与 Codex 模型的区分**
   - 用户可能混淆 `gpt-5.1` 和 `gpt-5.1-codex-max`
   - 风险：用户可能期望获得代码特化能力
   - 建议：添加 "Not sure which model?" 对比链接

### 边界情况

1. **模型降级场景**
   - 当前实现只处理升级场景
   - 未来可能需要降级提示（如模型退役）

2. **多模型切换**
   - 用户可能在不同项目使用不同模型
   - 强制升级可能影响其他项目的预期行为

3. **API 兼容性**
   - 虽然模型升级，但 API 应保持兼容
   - 需要验证 gpt-5.1 与 gpt-5 的响应格式一致性

### 改进建议

1. **升级价值量化**
   - 添加基准测试结果（如 "15% better on coding benchmarks"）
   - 提供具体的能力改进示例

2. **场景指导**
   - 添加 "When to use GPT-5.1 vs GPT-5.1 Codex" 说明
   - 帮助用户选择正确的模型家族

3. **渐进式升级**
   - 考虑添加 "Try for this session only" 选项
   - 让用户在承诺永久升级前体验新模型

4. **反馈收集**
   - 升级后询问用户满意度
   - 收集关于强制升级策略的反馈

5. **文档链接**
   - 除了模型页面，添加迁移指南链接
   - 解释可能的 API 行为差异

6. **批量升级通知**
   - 如果用户有多个会话使用旧模型
   - 提供 "Upgrade all sessions" 选项
