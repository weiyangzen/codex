# Model Migration Prompt - GPT-5 Family 快照研究文档

## 快照文件信息

- **文件名**: `codex_tui__model_migration__tests__model_migration_prompt_gpt5_family.snap`
- **源文件**: `tui/src/model_migration.rs`
- **测试函数**: `prompt_snapshot_gpt5_family`

---

## 场景与职责

### 业务场景
此快照捕获了从基础版 `gpt-5` 迁移到 `gpt-5.1` 的升级提示界面。这是针对通用 GPT-5 系列模型的升级场景，而非专门的 Codex 优化版本。

### 用户场景
适用于使用标准 GPT-5 模型的用户，系统推荐升级到改进版本 GPT-5.1。这是面向普通用户的通用模型升级提示。

### 核心职责
1. **通用模型升级通知**: 针对基础 GPT-5 用户的升级提示
2. **通用能力说明**: 强调"广泛的世界知识和强大的通用推理能力"
3. **非专业用户友好**: 避免使用专业术语（如"codex-optimized"）
4. **简洁明了的界面**: 相比 Codex 版本更加简洁

---

## 功能点目的

### 1. 通用版升级标题
```
> Codex just got an upgrade. Introducing gpt-5.1.
```
- 简洁的模型名称 `gpt-5.1`（无 codex 后缀）
- 与 Codex 版本保持一致的标题格式

### 2. 迁移路径
```
  We recommend switching from gpt-5 to gpt-5.1.
```
- 源模型: `gpt-5`（基础版）
- 目标模型: `gpt-5.1`（升级版）
- 单行显示，更加简洁

### 3. 通用能力描述
```
  Broad world knowledge with strong general reasoning.
```
**与 Codex 版本的关键区别**:
- **Broad world knowledge**: 强调知识广度
- **strong general reasoning**: 强调通用推理能力
- 无 "codex"、"cheaper"、"faster" 等专业或成本相关描述

### 4. 文档链接
```
  Learn more about gpt-5.1 at https://www.codex.com/models/gpt-5.1
```
- 链接到通用模型页面
- 保持与其他版本一致的样式

### 5. 强制继续提示
```
  Press enter to continue
```
- 与其他版本一致，使用 `can_opt_out: false`

---

## 具体技术实现

### 与 Codex 版本的差异对比

| 方面 | Codex 版本 | GPT-5 Family 版本 |
|-----|-----------|-------------------|
| 源模型 | `gpt-5-codex` / `gpt-5-codex-mini` | `gpt-5` |
| 目标模型 | `gpt-5.1-codex-max` / `gpt-5.1-codex-mini` | `gpt-5.1` |
| 描述 | 专业特性（优化、成本、速度） | 通用能力（知识、推理） |
| 目标用户 | 开发者/代码工作者 | 通用用户 |
| 链接 | `/models/gpt-5.1-codex-*` | `/models/gpt-5.1` |

### 测试代码实现

```rust
#[test]
fn prompt_snapshot_gpt5_family() {
    let backend = VT100Backend::new(65, 22);  // 注意：宽度 65（比其他版本宽）
    let mut terminal = Terminal::with_options(backend).expect("terminal");
    terminal.set_viewport_area(Rect::new(0, 0, 65, 22));

    let screen = ModelMigrationScreen::new(
        FrameRequester::test_dummy(),
        migration_copy_for_models(
            "gpt-5",                         // 基础版源模型
            "gpt-5.1",                       // 基础版目标模型
            Some("https://www.codex.com/models/gpt-5.1".to_string()),
            None,
            None,
            "gpt-5.1".to_string(),
            Some("Broad world knowledge with strong general reasoning.".to_string()),
            false,
        ),
    );
    // ... 渲染和断言
}
```

### 关键差异：终端宽度

注意到此测试使用 **65x22** 的终端尺寸，而其他版本使用 **60x22**：

```rust
// GPT-5 Family: 65列
let backend = VT100Backend::new(65, 22);

// GPT-5 Codex: 60列
let backend = VT100Backend::new(60, 22);

// GPT-5 Codex Mini: 60列
let backend = VT100Backend::new(60, 22);
```

**原因分析**:
- GPT-5 Family 的描述文本较长："Broad world knowledge with strong general reasoning."
- 需要更宽的终端以避免不必要的换行
- 测试设计者考虑了文本长度和可读性

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 职责 |
|-----|------|
| `codex-rs/tui/src/model_migration.rs` | 完整实现，行 456-481 包含此测试 |

### 测试特定代码
- **行 456-481**: `prompt_snapshot_gpt5_family` 测试函数
- **行 457**: 使用 65x22 终端尺寸
- **行 465-473**: 测试参数配置

### 文案生成路径
```
migration_copy_for_models()
    ├── heading: "Codex just got an upgrade. Introducing gpt-5.1."
    ├── content[0]: "We recommend switching from gpt-5 to gpt-5.1."
    ├── content[1]: ""
    ├── content[2]: "Broad world knowledge... Learn more..."
    └── content[3]: ""
    └── content[4]: "Press enter to continue"
```

---

## 依赖与外部交互

### 与其他版本完全一致的依赖
所有技术依赖与 Codex 版本完全相同，体现了良好的抽象设计：
- 相同的渲染引擎 (`ratatui`)
- 相同的事件处理 (`crossterm`)
- 相同的内部模块依赖

### 模型分类体系

```
GPT-5 系列
├── gpt-5 → gpt-5.1 (通用版)
│   └── 描述: "Broad world knowledge..."
│
└── gpt-5-codex → gpt-5.1-codex-max (旗舰版)
    └── 描述: "Codex-optimized flagship..."
    
└── gpt-5-codex-mini → gpt-5.1-codex-mini (轻量版)
    └── 描述: "Optimized for codex. Cheaper..."
```

---

## 风险、边界与改进建议

### 特定于此场景的风险

1. **模型命名混淆**
   - 风险：用户可能混淆 `gpt-5`、`gpt-5.1` 与 `gpt-5-codex`、`gpt-5.1-codex-max`
   - 建议：在提示中添加简短说明，如"This is the general-purpose version"

2. **缺乏具体优势说明**
   - 风险：相比 Codex 版本的成本/速度优势，通用描述可能不够吸引人
   - 建议：添加具体改进指标，如"20% better reasoning accuracy"

### 边界情况

1. **企业用户场景**
   - 企业用户可能更关心合规性和稳定性
   - 当前描述未涉及这些方面

2. **多模态能力**
   - 如果 gpt-5.1 支持图像等新能力，当前描述未体现
   - 建议：根据模型能力动态调整描述

### 改进建议

1. **版本对比表格**
   ```
   GPT-5.1 improvements over GPT-5:
   • 20% better reasoning on complex tasks
   • 15% faster response times
   • Improved multilingual support
   ```

2. **用户类型检测**
   ```rust
   // 根据用户使用模式推荐不同描述
   match user_profile {
       Developer => "Better code understanding...",
       Writer => "Improved creative writing...",
       Analyst => "Enhanced data analysis...",
       _ => "Broad world knowledge...",
   }
   ```

3. **渐进式披露**
   - 简洁版本（当前）用于快速提示
   - 详细版本（按 `?` 键）显示完整改进列表

4. **A/B 测试支持**
   - 测试不同描述对用户接受率的影响
   - 例如："Broad world knowledge" vs "Smarter and faster"

### 测试改进

1. **添加响应式测试**
   ```rust
   #[test]
   fn prompt_fits_in_narrow_terminal() {
       // 测试在 50 列终端下的渲染
       // 确保关键信息不被截断
   }
   ```

2. **添加多语言测试**
   - 验证描述文本的国际化支持
   - 测试不同语言下的换行行为

3. **添加可访问性测试**
   - 验证颜色对比度
   - 测试屏幕阅读器兼容性
