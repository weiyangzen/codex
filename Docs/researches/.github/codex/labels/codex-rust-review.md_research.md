# codex-rust-review.md 深度研究文档

## 场景与职责

`codex-rust-review.md` 是 OpenAI Codex 项目中专门针对 Rust 代码库的详细代码审查提示词模板，位于 `.github/codex/labels/` 目录下。这是四个标签文件中最详细的一个（5951 bytes），当 Pull Request 被标记为 `codex-rust-review` 标签时，Codex AI 将按照此模板的详细规范执行 Rust 代码审查。

**核心职责**：
- 提供 Rust 代码审查的详细指导原则
- 定义代码组织、测试断言、代码风格的具体要求
- 通过丰富的代码示例展示"好"与"坏"的实践对比
- 确保 Rust 代码库保持高质量和一致性

## 功能点目的

### 1. Rust 专用审查标准
相比通用的 `codex-review.md`，本文件提供：
- **详细原则**：涵盖代码组织、断言、Rust 惯用法
- **代码示例**：通过对比展示最佳实践
- **具体检查点**：明确的审查清单

### 2. 代码质量保障
- **代码组织**：确保 crate 结构合理，文件大小适中
- **测试质量**：推广深度比较而非逐字段断言
- **安全性**：禁止使用 `unsafe`（除非有充分理由）
- **可维护性**：鼓励惯用 Rust 表达式和模式

### 3. 团队协作规范
- 统一代码审查标准，减少风格争议
- 作为"活的文档"，持续更新审查准则
- 帮助新贡献者理解项目期望

## 具体技术实现

### 关键流程

```
PR 被标记 codex-rust-review
    ↓
加载 codex-rust-review.md 作为 system prompt
    ↓
AI 分析 PR 中的 Rust 代码变更
    ↓
按照以下维度审查：
  ├── 通用原则（PR 描述、单一职责）
  ├── 代码组织（crate 结构、文件大小）
  ├── 测试断言（深度比较 vs 逐字段）
  └── Rust 战术细节（unsafe、枚举、表达式）
    ↓
生成结构化审查报告
```

### 数据结构

**模板变量**：
- `{CODEX_ACTION_GITHUB_EVENT_PATH}`: GitHub Event JSON 文件路径

**审查维度结构**：
```markdown
## 通用原则
- PR 描述要求
- 变更范围控制
- 代码复用检查

## 代码组织
- Crate 职责划分
- 文件大小限制
- API 结构（倒金字塔）

## 测试断言
- 深度比较模式
- 代码示例（Bad vs Good）

## Rust 战术细节
- unsafe 使用规范
- 类型系统最佳实践
- 代码风格（表达式优先）
- Cargo.toml 管理
```

### 关键代码示例分析

#### 1. 测试断言对比（文件核心内容）

**Bad: 逐字段比较（Piecemeal Comparison）**
```rust
#[test]
fn test_get_latest_messages() {
    let messages = get_latest_messages();
    assert_eq!(messages.len(), 2);

    let m0 = &messages[0];
    match m0 {
        Message::Request { id, method, params } => {
            assert_eq!(id, "123");
            assert_eq!(method, "subscribe");
            assert_eq!(*params, Some(json!({"conversation_id": "x42z86"})))
        }
        Message::Notification { .. } => panic!("expected Request"),
    }
    // ... 更多逐字段断言
}
```
**问题**：
- 冗长且难以阅读
- 覆盖不完整（容易遗漏字段）
- 作为"可执行文档"效果差

**Good: 深度比较（Deep Comparison）**
```rust
use pretty_assertions::assert_eq;

#[test]
fn test_get_latest_messages() {
    let messages = get_latest_messages();
    assert_eq!(
        vec![
            Message::Request {
                id: "123".to_string(),
                method: "subscribe".to_string(),
                params: Some(json!({"conversation_id": "x42z86"})),
            },
            Message::Notification {
                method: "log".to_string(),
                params: Some(json!({"level": "info", "message": "subscribed"})),
            },
        ],
        messages,
    );
}
```
**优势**：
- 简洁明了
- 完整覆盖所有字段
- 优秀的可执行文档
- 使用 `pretty_assertions` 提供清晰的 diff

#### 2. 代码组织原则

**Crate 结构**：
- `core`: 保持最小化
- `common`: 共享非核心逻辑
- 每个 crate 有明确的单一职责

**文件大小限制**：
- 目标：模块小于 500 LoC（不含测试）
- 红线：超过 800 LoC 必须拆分
- 例外：需要文档说明原因

**API 结构（倒金字塔）**：
```rust
// 公共 API 在顶部
pub fn public_function() {}

pub struct PublicStruct;

// 实现和辅助函数在下方
impl PublicStruct {
    pub fn public_method(&self) {}
    fn private_helper(&self) {}  // 私有辅助函数
}

// 内部实现细节在最底部
mod internal {
    // ...
}
```

#### 3. Rust 战术细节

**unsafe 使用规范**：
```rust
// ❌ 禁止：除非有非常好的理由
unsafe { std::env::set_var("KEY", "value") }

// ✅ 推荐：寻找安全的替代方案
// 使用配置对象而非环境变量
```

**表达式优先**：
```rust
// ❌ 避免：不必要的 return
fn calculate(x: i32) -> i32 {
    return x * 2;
}

// ✅ 推荐：使用表达式
fn calculate(x: i32) -> i32 {
    x * 2
}
```

**Cargo.toml 管理**：
- 依赖列表按字母顺序排序
- 正确区分 `[dependencies]` 和 `[dev-dependencies]`

## 关键代码路径与文件引用

### 直接相关文件
- **当前文件**: `.github/codex/labels/codex-rust-review.md` (5951 bytes)
- **配置文件**: `.github/codex/home/config.toml`

### 相关标签文件对比

| 文件 | 大小 | 详细程度 | 适用场景 |
|------|------|----------|----------|
| `codex-review.md` | 443 bytes | 通用简洁 | 所有语言的快速审查 |
| `codex-rust-review.md` | 5951 bytes | 详细专业 | Rust 代码深度审查 |
| `codex-attempt.md` | 275 bytes | 任务导向 | Issue 自动解决 |
| `codex-triage.md` | 177 bytes | 极简 | Issue 初步分类 |

### 项目 Rust 代码结构
根据审查文件中的引用，项目 Rust 代码位于：
- `codex-rs/` - Rust 工作区根目录
- `codex-rs/core` - 核心 crate
- `codex-rs/common` - 共享逻辑
- `codex-rs/tui` - 终端用户界面

### AGENTS.md 关联
项目根目录的 `AGENTS.md` 文件与本审查模板高度一致：
- 相同的测试断言原则
- 相同的代码组织规范
- 相同的 Rust 惯用法建议
- 这表明 `codex-rust-review.md` 是 `AGENTS.md` 中审查相关内容的提炼

## 依赖与外部交互

### 上游依赖
1. **GitHub Actions** - 工作流执行
2. **openai/codex-action@main** - AI Agent 执行
3. **OpenAI API** - GPT 模型

### 下游交互
1. **GitHub PR API** - 读取变更、发布评论
2. **Git** - 获取 diff
3. **Rust 工具链** - 可选的 `cargo check`、`cargo clippy` 集成

### 内部依赖
- 与 `AGENTS.md` 的规范保持一致
- 与 `codex-rs/` 目录的代码结构对应

## 风险、边界与改进建议

### 风险

1. **审查疲劳**
   - 过于详细的审查标准可能导致 AI 输出过长
   - 建议：增加输出长度限制或优先级分级

2. **与 AGENTS.md 的同步问题**
   - 两个文件包含相似的规范
   - 更新时可能遗漏同步
   - 风险：AI 审查标准与实际项目规范不一致

3. **示例代码过时**
   - 文件中的代码示例可能随语言版本更新而过时
   - 建议：定期审查和更新示例

4. **过度严格**
   - "禁止 unsafe" 等绝对化表述可能过于严格
   - 某些系统编程场景确实需要 unsafe
   - 建议：增加例外情况的判断标准

### 边界

1. **语言范围**
   - 仅适用于 Rust 代码
   - 不涵盖项目中的 TypeScript/JavaScript 代码（CLI 部分）

2. **审查深度**
   - 侧重代码风格和结构
   - 不涉及架构设计或算法效率（除非明显问题）

3. **自动化限制**
   - AI 无法执行实际编译或测试
   - 无法验证代码是否真正可运行

### 改进建议

1. **与 AGENTS.md 整合**
   ```markdown
   ## 参考文档
   本审查标准与项目根目录的 AGENTS.md 保持一致。
   如有冲突，以 AGENTS.md 为准。
   ```

2. **增加自动化检查集成**
   ```markdown
   ## 自动化检查
   在人工审查前，确保以下检查通过：
   - `cargo fmt` - 代码格式化
   - `cargo clippy` - 静态分析
   - `cargo test` - 单元测试
   - `cargo deny` - 依赖审计
   ```

3. **增加审查优先级**
   ```markdown
   ## 审查优先级
   按以下顺序审查，如时间有限可提前终止：
   1. 🔴 安全问题（unsafe、panic、unwrap）
   2. 🟡 正确性问题（逻辑错误、边界条件）
   3. 🟢 风格问题（命名、格式化）
   4. ⚪ 优化建议（性能、可读性）
   ```

4. ** unsafe 使用指南细化**
   ```markdown
   ## unsafe 使用指南
   原则上避免 unsafe，但以下情况可接受：
   - 调用操作系统 API 且无安全包装器
   - 与 C 代码 FFI 交互
   - 性能关键路径且已充分测试
   
   使用 unsafe 时必须：
   - 添加详细的安全注释说明不变量
   - 由至少两名维护者审查
   - 包含专门的测试用例
   ```

5. **增加性能审查要点**
   ```markdown
   ## 性能审查
   关注以下常见性能陷阱：
   - 不必要的克隆（.clone()）
   - 在循环中分配内存
   - 未使用迭代器方法（如使用 for 循环而非 filter/map）
   - 过度的动态分发（Box<dyn Trait>）
   ```

6. **增加文档要求**
   ```markdown
   ## 文档要求
   - 公共 API 必须有文档注释（///）
   - 复杂算法需要说明时间/空间复杂度
   - unsafe 代码块必须有安全说明（// SAFETY: ...）
   - 模块级别的文档（//!）说明模块用途
   ```

---

**文件元数据**
- 路径: `.github/codex/labels/codex-rust-review.md`
- 大小: 5951 bytes
- 最后修改: 2025-03-19
- 关联系统: GitHub Actions + OpenAI Codex + Rust 代码审查
- 相关文档: AGENTS.md（项目级代理规范）
