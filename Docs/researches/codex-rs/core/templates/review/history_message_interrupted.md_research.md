# history_message_interrupted.md 研究文档

## 场景与职责

`history_message_interrupted.md` 是 Codex 代码审查（Review）功能的模板文件，用于在审查任务被中断时生成历史消息。该文件与 `exit_interrupted.xml` 功能相似，但采用 Markdown 格式（尽管内容实际为 XML 结构）。根据代码库分析，该模板**当前未被直接使用**，可能是遗留文件或用于未来扩展。

### 预期使用场景
1. **审查任务中断**：用户取消审查、网络中断或其他异常导致审查未完成
2. **Markdown 格式偏好**：如果系统需要 Markdown 格式的历史记录
3. **与 history_message_completed.md 配对**：作为中断状态的对应模板

## 功能点目的

该模板的设计目的是：
1. **状态记录**：在对话历史中标记审查任务的中断状态
2. **用户引导**：提示用户如果需要完成审查，需要重新发起 `/review` 命令
3. **格式一致性**：与 `history_message_completed.md` 保持一致的格式风格

### 模板内容解析

```markdown
<user_action>
  <context>User initiated a review task, but was interrupted. If user asks about this, tell them to re-initiate a review with `/review` and wait for it to complete.</context>
  <action>review</action>
  <results>
  None.
  </results>
</user_action>
```

**注意**：尽管文件扩展名为 `.md`，内容实际上是 XML 格式，与 `exit_interrupted.xml` 完全相同。

### 与 exit_interrupted.xml 的对比

| 特性 | exit_interrupted.xml | history_message_interrupted.md |
|------|----------------------|-------------------------------|
| 格式 | XML | XML（尽管扩展名为 .md） |
| 内容 | 完全相同 | 完全相同 |
| 当前使用状态 | ✅ 活跃使用 | ❓ 未找到直接引用 |
| 文件扩展名 | .xml | .md |

## 具体技术实现

### 模板未直接使用的证据

通过全局代码搜索，未找到 `history_message_interrupted.md` 的直接引用：

```bash
# 搜索结果
$ grep -r "history_message_interrupted" --include="*.rs" codex-rs/
# 无结果
```

相比之下，`exit_interrupted.xml` 有明确的引用：

```rust
// codex-rs/core/src/client_common.rs 第22-23行
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str =
    include_str!("../templates/review/exit_interrupted.xml");
```

### 文件内容对比

两个文件内容完全一致：

```bash
$ diff codex-rs/core/templates/review/exit_interrupted.xml \
       codex-rs/core/templates/review/history_message_interrupted.md
# 无输出，表示文件内容相同
```

### 可能的用途分析

1. **完全重复的遗留文件**：可能是复制粘贴后未被清理的重复文件
2. **命名规范化过渡**：可能是在从 `history_message_*.md` 命名迁移到 `exit_*.xml` 命名时的遗留
3. **未来多格式支持**：为支持多种历史消息格式预留
4. **构建系统依赖**：可能在某些构建配置或脚本中被引用

## 关键代码路径与文件引用

### 文件位置
- **模板文件**：`codex-rs/core/templates/review/history_message_interrupted.md`

### 相关文件（基于功能相似性）
- `codex-rs/core/templates/review/exit_interrupted.xml`：内容完全相同的活跃使用模板
- `codex-rs/core/templates/review/history_message_completed.md`：对应的完成状态模板
- `codex-rs/core/src/client_common.rs`：活跃模板的加载位置
- `codex-rs/core/src/tasks/review.rs`：审查任务实现，使用 `REVIEW_EXIT_INTERRUPTED_TMPL`

### 模板目录完整结构
```
codex-rs/core/templates/review/
├── exit_interrupted.xml           # ✅ 活跃使用（REVIEW_EXIT_INTERRUPTED_TMPL）
├── exit_success.xml               # ✅ 活跃使用（REVIEW_EXIT_SUCCESS_TMPL）
├── history_message_completed.md   # ❓ 未直接使用
└── history_message_interrupted.md # ❓ 未直接使用（本文件）
```

### 活跃使用模板的代码路径

```rust
// codex-rs/core/src/client_common.rs
pub const REVIEW_EXIT_SUCCESS_TMPL: &str = include_str!("../templates/review/exit_success.xml");
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str =
    include_str!("../templates/review/exit_interrupted.xml");

// codex-rs/core/src/tasks/review.rs 第228行
let rendered = crate::client_common::REVIEW_EXIT_INTERRUPTED_TMPL.to_string();
```

## 依赖与外部交互

### 当前状态
该模板**没有活跃的外部依赖或交互**，因为它未被代码直接引用。

### 潜在依赖（如果启用）
1. **协议层**：`ExitedReviewModeEvent` 事件
2. **会话管理**：`Session::record_conversation_items()`
3. **任务系统**：`CancellationToken` 取消机制

### 与 exit_interrupted.xml 的完全重复问题

两个文件内容完全一致，包括：
- XML 标签结构
- 文本内容（context、action、results）
- 换行和缩进

这种完全重复增加了维护成本，任何对中断消息内容的修改都需要同步更新两个文件（如果 `history_message_interrupted.md` 被使用的话）。

## 风险、边界与改进建议

### 当前风险

1. **维护混乱**：维护者可能不确定应该修改哪个文件
2. **不一致风险**：如果未来 `history_message_interrupted.md` 被启用，而内容已与 `exit_interrupted.xml` 不同步，可能导致行为不一致
3. **构建产物膨胀**：重复文件增加了仓库大小和构建复杂度

### 边界情况

由于该模板未被直接使用，以下分析基于假设启用的情况：

1. **文件扩展名混淆**：`.md` 扩展名暗示 Markdown 格式，但内容为 XML
2. **重复定义**：与 `exit_interrupted.xml` 完全重复，可能导致符号冲突
3. **模板选择逻辑**：如果同时存在两种格式，需要额外的逻辑来选择使用哪个

### 改进建议

1. **立即行动 - 添加注释**：
   ```xml
   <!-- 
     NOTE: This file is currently NOT actively used in the codebase.
     The active template is exit_interrupted.xml.
     This file is kept for potential future use or backward compatibility.
   -->
   ```

2. **短期 - 文件清理决策**：
   - **选项 A**：删除该文件（如果确定不需要）
   - **选项 B**：移动到 `archive/` 或 `legacy/` 目录
   - **选项 C**：保留但添加明确的文档说明

3. **中期 - 统一模板系统**：
   ```rust
   // 建议的模板枚举设计
   pub enum ReviewTemplate {
       ExitSuccess,
       ExitInterrupted,
   }
   
   impl ReviewTemplate {
       pub fn content(&self) -> &'static str {
           match self {
               Self::ExitSuccess => include_str!("../templates/review/exit_success.xml"),
               Self::ExitInterrupted => include_str!("../templates/review/exit_interrupted.xml"),
           }
       }
   }
   ```

4. **长期 - 模板引擎化**：
   - 使用 Handlebars 或 Tera 模板引擎
   - 支持条件渲染和格式选择
   - 统一的模板管理配置

5. **文档改进**：
   ```markdown
   <!-- 建议在 templates/review/ 目录添加 README.md -->
   # Review Templates

   ## Active Templates
   - `exit_success.xml` - Used when review completes successfully
   - `exit_interrupted.xml` - Used when review is interrupted

   ## Legacy/Unused Templates
   - `history_message_completed.md` - Not currently used, kept for reference
   - `history_message_interrupted.md` - Not currently used, kept for reference
   ```

6. **构建系统检查**：
   ```bash
   # 检查 BUILD.bazel 是否有引用
   grep -r "history_message_interrupted" codex-rs/core/
   
   # 检查任何配置文件
   find codex-rs -name "*.toml" -o -name "*.yaml" -o -name "*.json" | \
     xargs grep -l "history_message_interrupted" 2>/dev/null
   ```

### 结论

`history_message_interrupted.md` 是一个**与 `exit_interrupted.xml` 完全重复且未被使用的模板文件**。建议采取以下行动：

1. **验证无用性**：确认没有测试、脚本或文档引用该文件
2. **删除或归档**：如果确认无用，建议删除以减少维护负担
3. **更新文档**：在删除前更新任何相关文档，说明模板位置的变更

如果决定保留，必须添加明确的文件头注释说明其状态，避免维护者困惑。
