# Model Migration Prompt - GPT-5 Codex Mini 快照研究文档

## 快照文件信息

- **文件名**: `codex_tui__model_migration__tests__model_migration_prompt_gpt5_codex_mini.snap`
- **源文件**: `tui/src/model_migration.rs`
- **测试函数**: `prompt_snapshot_gpt5_codex_mini`

---

## 场景与职责

### 业务场景
此快照捕获了从 `gpt-5-codex-mini` 迁移到 `gpt-5.1-codex-mini` 的升级提示界面。这是 Codex CLI 轻量级版本的模型升级场景。

### 用户场景
针对使用轻量级 Codex 模型的用户，系统推荐升级到更新版本的轻量级模型 `gpt-5.1-codex-mini`。

### 核心职责
1. **轻量模型升级通知**: 专门针对 codex-mini 系列的升级提示
2. **成本效益说明**: 强调新模型"更便宜、更快"的特点
3. **能力权衡提示**: 诚实告知用户"能力较低"的权衡
4. **无缝迁移引导**: 提供清晰的升级路径

---

## 功能点目的

### 1. 轻量版升级标题
```
> Codex just got an upgrade. Introducing gpt-5.1-codex-mini.
```
- 明确标识这是 `codex-mini` 系列的升级
- 使用粗体标题吸引注意力

### 2. 迁移路径
```
  We recommend switching from gpt-5-codex-mini to
  gpt-5.1-codex-mini.
```
- 源模型: `gpt-5-codex-mini`
- 目标模型: `gpt-5.1-codex-mini`
- 保持与 codex 系列命名一致性

### 3. 特性描述（关键差异点）
```
  Optimized for codex. Cheaper, faster, but less capable.
```
**与 GPT-5 Codex Max 的关键区别**:
- **Cheaper**: 成本更低，适合预算敏感场景
- **Faster**: 响应速度更快
- **but less capable**: 诚实告知能力限制

### 4. 文档链接
```
  Learn more about gpt-5.1-codex-mini at
  https://www.codex.com/models/gpt-5.1-codex-mini
```
- 独立的模型文档页面
- 使用相同的链接样式（青色下划线）

### 5. 强制继续提示
```
  Press enter to continue
```
- `can_opt_out: false` 表示用户必须接受升级
- 适用于关键安全更新或兼容性修复场景

---

## 具体技术实现

### 与 GPT-5 Codex 的差异对比

| 方面 | GPT-5 Codex | GPT-5 Codex Mini |
|-----|-------------|------------------|
| 源模型 | `gpt-5-codex` | `gpt-5-codex-mini` |
| 目标模型 | `gpt-5.1-codex-max` | `gpt-5.1-codex-mini` |
| 描述 | "Codex-optimized flagship..." | "Optimized for codex. Cheaper..." |
| 定位 | 旗舰版 | 轻量版 |

### 测试代码实现

```rust
#[test]
fn prompt_snapshot_gpt5_codex_mini() {
    let backend = VT100Backend::new(60, 22);
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, 60, 22));

    let screen = ModelMigrationScreen::new(
        FrameRequester::test_dummy(),
        migration_copy_for_models(
            "gpt-5-codex-mini",              // 当前模型：轻量版
            "gpt-5.1-codex-mini",            // 目标模型：轻量版升级
            Some("https://www.codex.com/models/gpt-5.1-codex-mini".to_string()),
            None,
            None,
            "gpt-5.1-codex-mini".to_string(),
            Some("Optimized for codex. Cheaper, faster, but less capable.".to_string()),
            false,  // 不允许退出
        ),
    );
    // ... 渲染和断言
}
```

### 文案生成逻辑

```rust
// 行 92-100: 描述行生成
let description_line = target_description
    .filter(|desc| !desc.is_empty())
    .map(Line::from)
    .unwrap_or_else(|| {
        Line::from(format!(
            "{target_display_name} is recommended for better performance and reliability."
        ))
    });
```

由于测试提供了 `target_description: Some("Optimized for codex...")`，所以使用提供的描述而非默认值。

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/model_migration.rs` | 完整实现，行 510-535 包含此测试 |

### 测试特定代码
- **行 510-535**: `prompt_snapshot_gpt5_codex_mini` 测试函数
- **行 519-527**: 测试参数配置

### 复用的核心组件
- **行 60-135**: `migration_copy_for_models` 函数（与 GPT-5 Codex 相同）
- **行 171-250**: `ModelMigrationScreen` 状态管理
- **行 252-270**: 渲染实现

---

## 依赖与外部交互

### 与 GPT-5 Codex 相同的依赖
- `ratatui`: TUI 渲染
- `crossterm`: 事件处理
- `tokio_stream`: 异步流

### 内部模块
所有内部依赖与 GPT-5 Codex 场景完全相同，体现良好的代码复用设计。

### 模型配置来源
模型描述可能来自：
1. 硬编码（当前测试方式）
2. 模型目录 (`model_catalog.rs`)
3. 远程配置服务

---

## 风险、边界与改进建议

### 特定于此场景的风险

1. **"less capable" 描述的潜在负面影响**
   - 风险：用户可能因"能力较低"而犹豫升级
   - 建议：添加具体场景说明，如"适合简单代码审查任务"

2. **轻量版与旗舰版混淆**
   - 风险：用户可能不理解 codex-mini 和 codex-max 的区别
   - 建议：在提示中添加简短对比或链接到对比页面

### 边界情况

1. **从 codex-mini 升级到 codex-max**
   - 当前测试仅覆盖 mini → mini
   - 建议：添加跨系列升级测试（如 codex-mini → codex-max）

2. **降级场景**
   - 如果用户当前使用 codex-max，是否应推荐 codex-mini？
   - 当前实现不支持降级提示

### 改进建议

1. **动态成本显示**
   ```rust
   // 当前：静态文本 "Cheaper, faster"
   // 建议：显示具体成本对比
   format!("{}% cheaper, {}% faster than {}", 
           cost_savings_pct, speed_improvement_pct, current_model)
   ```

2. **使用场景提示**
   ```
   Optimized for codex. Cheaper, faster, but less capable.
   Best for: quick code reviews, simple edits, and prototyping.
   ```

3. **一键切换回退**
   - 即使 `can_opt_out: false`，也应在设置中提供回退选项
   - 避免用户因强制升级而产生负面情绪

4. **性能指标展示**
   - 添加预期的延迟/成本改进百分比
   - 帮助用户做出知情决策

### 测试改进

1. **添加对比测试**
   ```rust
   #[test]
   fn compare_codex_max_and_mini_prompts() {
       // 验证两种提示的样式一致性
       // 验证关键差异点（如"less capable"仅出现在mini）
   }
   ```

2. **添加响应式测试**
   - 测试不同终端宽度下的换行行为
   - 确保 "Cheaper, faster, but less capable" 不被截断
