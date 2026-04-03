# GPT-5 Codex Mini 模型迁移提示快照研究文档

## 场景与职责

该快照文件记录了 `codex-rs/tui` 项目中针对 **GPT-5 Codex Mini 模型**的强制升级提示界面。当用户当前使用的是 `gpt-5-codex-mini` 模型，而系统推荐使用 `gpt-5.1-codex-mini` 时，显示此提示。这是轻量级/经济型模型的升级提示，强调成本效益和速度优势。

**核心职责：**
- 通知用户从 `gpt-5-codex-mini` 迁移到 `gpt-5.1-codex-mini`
- 强调新模型的优势："Optimized for codex. Cheaper, faster, but less capable"
- 提供模型详情页面的链接
- 强制用户接受升级（`can_opt_out = false`）

## 功能点目的

### 1. 轻量级模型升级通知
- **模型定位**：明确这是 Codex 优化的小型模型
- **成本效益**：强调 "Cheaper, faster" 的优势
- **能力权衡**：诚实告知 "less capable" 的局限性

### 2. 透明的产品沟通
- **优势与劣势并重**：不仅宣传优点，也告知限制
- **适用场景暗示**：适合对成本敏感、速度优先的任务
- **学习资源**：提供模型详情页面的可点击链接

### 3. 一致的强制升级体验
- **简化交互**：与 gpt-5-codex 升级提示一致的单一回车确认
- **视觉一致性**：保持相同的布局和样式
- **品牌对齐**：统一的 "Codex just got an upgrade" 标题格式

## 具体技术实现

### 内容生成参数

```rust
migration_copy_for_models(
    "gpt-5-codex-mini",                                    // current_model
    "gpt-5.1-codex-mini",                                  // target_model
    Some("https://www.codex.com/models/gpt-5.1-codex-mini".to_string()),  // model_link
    None,                                                  // migration_copy
    None,                                                  // migration_markdown
    "gpt-5.1-codex-mini".to_string(),                      // target_display_name
    Some("Optimized for codex. Cheaper, faster, but less capable.".to_string()),  // target_description
    false,                                                 // can_opt_out（强制升级）
)
```

### 描述文本策略

与 gpt-5-codex-max 的 "Codex-optimized flagship for deep and fast reasoning" 不同，gpt-5.1-codex-mini 的描述采用了**平衡式表达**：

| 模型 | 描述策略 | 关键词 |
|-----|---------|--------|
| gpt-5.1-codex-max | 旗舰定位 | "flagship", "deep and fast reasoning" |
| gpt-5.1-codex-mini | 成本效益 | "Cheaper", "faster", "less capable" |

这种差异化描述帮助用户理解不同模型的定位，做出明智的选择。

### 与 gpt-5-codex 升级的代码共享

```rust
// 完全相同的渲染逻辑
impl WidgetRef for &ModelMigrationScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // ... 相同实现
        
        // 由于 can_opt_out = false，不渲染菜单
        if self.copy.can_opt_out {
            self.render_menu(&mut column);
        }
        
        column.render(area, buf);
    }
}
```

## 关键代码路径与文件引用

### 测试函数

```rust
#[test]
fn prompt_snapshot_gpt5_codex_mini() {
    let backend = VT100Backend::new(60, 22);
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, 60, 22));

    let screen = ModelMigrationScreen::new(
        FrameRequester::test_dummy(),
        migration_copy_for_models(
            "gpt-5-codex-mini",
            "gpt-5.1-codex-mini",
            Some("https://www.codex.com/models/gpt-5.1-codex-mini".to_string()),
            None,
            None,
            "gpt-5.1-codex-mini".to_string(),
            Some("Optimized for codex. Cheaper, faster, but less capable.".to_string()),
            false,
        ),
    );
    {
        let mut frame = terminal.get_frame();
        frame.render_widget_ref(&screen, frame.area());
    }
    terminal.flush().expect("flush");
    assert_snapshot!("model_migration_prompt_gpt5_codex_mini", terminal.backend());
}
```

### 测试位置

```
model_migration.rs:510
└── fn prompt_snapshot_gpt5_codex_mini
    ├── VT100Backend::new(60, 22)
    ├── migration_copy_for_models(...)
    └── assert_snapshot!("model_migration_prompt_gpt5_codex_mini", ...)
```

## 依赖与外部交互

### 模型迁移提示家族

| 快照名称 | 模型类型 | 升级性质 | 描述重点 |
|---------|---------|---------|---------|
| `model_migration_prompt` | gpt-5.1-codex-mini → gpt-5.1-codex-max | 可选 | 功能升级 |
| `model_migration_prompt_gpt5_family` | gpt-5 → gpt-5.1 | 强制 | 通用能力提升 |
| `model_migration_prompt_gpt5_codex` | gpt-5-codex → gpt-5.1-codex-max | 强制 | 旗舰性能 |
| `model_migration_prompt_gpt5_codex_mini` | gpt-5-codex-mini → gpt-5.1-codex-mini | 强制 | 成本效益 |

### 共享基础设施

所有模型迁移提示共享：
- `ModelMigrationScreen` 结构体和渲染逻辑
- `AltScreenGuard` 备用屏幕管理
- `migration_copy_for_models` 内容生成函数
- `run_model_migration_prompt` 事件循环

## 风险、边界与改进建议

### 已知风险

1. **"Less capable" 的负面暗示**
   - 明确告知能力限制可能影响用户接受度
   - 风险：用户可能担心升级后体验下降
   - 缓解：强调 "Optimized for codex" 表明这是针对特定场景的优化

2. **模型命名混淆**
   - "mini" 在源模型和目标模型中都存在
   - 风险：用户可能不理解升级的具体改进
   - 建议：添加版本对比（如 "5.0 → 5.1"）

3. **强制升级的合理性**
   - 对于经济型模型用户，成本是主要考虑因素
   - 风险：强制升级可能与用户选择该模型的初衷冲突
   - 建议：解释升级如何进一步降低成本

### 边界情况

1. **企业用户**
   - 企业可能基于成本预算选择 mini 模型
   - 强制升级可能影响预算规划
   - 建议：添加企业策略配置选项

2. **自动化工作流**
   - CI/CD 环境可能使用 mini 模型以节省成本
   - 强制升级提示可能阻塞自动化流程
   - 建议：添加 `--batch-mode` 或环境变量绕过

### 改进建议

1. **量化优势**
   - 当前描述为定性（"Cheaper, faster"）
   - 建议：添加定量数据（如 "30% faster, 20% cheaper"）

2. **场景建议**
   - 添加 "Best for:" 部分，说明适用场景
   - 示例："Best for: quick edits, small projects, cost-sensitive workflows"

3. **对比表格**
   - 添加简短的模型对比，突出 5.1 版本的改进
   - 示例：
     ```
     | Feature | 5.0 | 5.1 |
     |---------|-----|-----|
     | Speed   | ✓✓  | ✓✓✓ |
     | Cost    | $   | $$  |
     ```

4. **用户反馈机制**
   - 添加 "Was this upgrade helpful?" 后续提示
   - 收集用户对强制升级的反馈

5. **回滚指导**
   - 添加如何切换回旧模型的说明（如需要）
   - 增强用户控制感

6. **本地化**
   - 经济型模型的用户可能分布在全球各地
   - 优先添加对主要市场的本地化支持
