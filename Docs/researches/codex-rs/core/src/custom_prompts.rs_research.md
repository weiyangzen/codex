# custom_prompts.rs 研究文档

## 场景与职责

`custom_prompts.rs` 是 Codex CLI 的**自定义提示词管理模块**，负责从文件系统加载和管理用户自定义的 prompt 模板。这些 prompt 模板可以通过 `/prompts:name` 的 slash 命令在 TUI 中快速调用。

**核心职责：**
1. 发现并加载用户自定义 prompt 文件（Markdown 格式）
2. 解析 YAML-like frontmatter 元数据（description, argument-hint）
3. 提供排除机制（用于过滤内置 prompt）
4. 支持按名称排序的 prompt 列表

**使用场景：**
- TUI 的 `/prompts` 命令补全和提示
- Chat composer 中插入预定义 prompt 模板
- 用户自定义工作流和常用指令的快速调用

---

## 功能点目的

### 1. 默认 Prompt 目录定位
```rust
pub fn default_prompts_dir() -> Option<PathBuf>
```
- 基于 `CODEX_HOME` 环境变量定位 `$CODEX_HOME/prompts` 目录
- 如果无法解析 `CODEX_HOME`，返回 `None`

### 2. Prompt 文件发现
```rust
pub async fn discover_prompts_in(dir: &Path) -> Vec<CustomPrompt>
pub async fn discover_prompts_in_excluding(dir: &Path, exclude: &HashSet<String>) -> Vec<CustomPrompt>
```
- 异步扫描指定目录下的 `.md` 文件
- 过滤非文件项（目录、符号链接等）
- 支持排除列表（用于过滤内置 prompt）
- 返回按文件名排序的 `CustomPrompt` 列表

### 3. Frontmatter 解析
```rust
fn parse_frontmatter(content: &str) -> (Option<String>, Option<String>, String)
```
- 支持 YAML-like frontmatter 格式（`---` 分隔）
- 提取 `description` 和 `argument-hint`/`argument_hint` 字段
- 支持引号包裹的值（自动去除引号）
- 返回 `(description, argument_hint, body_without_frontmatter)`

---

## 具体技术实现

### 数据结构

```rust
// 来自 codex_protocol::custom_prompts
pub struct CustomPrompt {
    pub name: String,           // 文件名（不含扩展名）
    pub path: PathBuf,          // 完整文件路径
    pub content: String,        // prompt 内容（不含 frontmatter）
    pub description: Option<String>,    // 描述（用于 UI 展示）
    pub argument_hint: Option<String>,  // 参数提示（如 "[file] [priority]"）
}
```

### 关键流程

**Prompt 发现流程：**
1. 使用 `tokio::fs::read_dir` 异步读取目录
2. 对每个条目检查：
   - 是否为文件（`metadata().is_file()`）
   - 扩展名是否为 `.md`（不区分大小写）
   - 文件名是否能解析为有效 UTF-8
   - 是否在排除列表中
3. 读取文件内容并解析 frontmatter
4. 收集所有有效 prompt 并按名称排序

**Frontmatter 解析流程：**
1. 检查首行是否为 `---`
2. 逐行解析直到遇到闭合的 `---`
3. 跳过空行和 `#` 开头的注释行
4. 解析 `key: value` 格式，支持 `"value"` 或 `'value'` 引号包裹
5. 提取 `description` 和 `argument-hint`/`argument_hint`
6. 返回剩余内容作为 body

### 错误处理策略

- 目录不存在或无法读取 → 返回空列表（静默处理）
- 文件读取失败 → 跳过该文件
- Frontmatter 未闭合 → 返回原始内容作为 body
- 非 UTF-8 内容 → 跳过该文件

---

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/custom_prompts.rs` (149 行)
- `/home/sansha/Github/codex/codex-rs/core/src/custom_prompts_tests.rs` (95 行，测试模块)

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/protocol/src/custom_prompts.rs` - `CustomPrompt` 结构体定义
- `/home/sansha/Github/codex/codex-rs/core/src/config.rs` - `find_codex_home()` 函数

### 调用方
- `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` - TUI 应用层调用
- `/home/sansha/Github/codex/codex-rs/tui/src/chatwidget.rs` - Chat 组件
- `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/mod.rs` - 底部面板
- `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/chat_composer.rs` - 聊天输入
- `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/command_popup.rs` - 命令弹窗
- `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/prompt_args.rs` - Prompt 参数处理
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/command_popup.rs` - App Server 命令弹窗
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` - App Server Chat
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/prompt_args.rs` - App Server Prompt 参数

### 协议定义
```rust
// codex_protocol::custom_prompts
pub const PROMPTS_CMD_PREFIX: &str = "prompts";
```

---

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `tokio::fs` | 异步文件系统操作 |
| `std::collections::HashSet` | 排除列表存储 |
| `codex_protocol::custom_prompts::CustomPrompt` | Prompt 数据结构 |

### 环境依赖
- `CODEX_HOME` 环境变量（通过 `crate::config::find_codex_home()` 读取）

### 文件系统约定
- Prompt 文件存放于 `$CODEX_HOME/prompts/*.md`
- 文件名（不含扩展名）作为 prompt 名称
- 支持标准 Markdown 格式，可包含 YAML frontmatter

**Frontmatter 示例：**
```markdown
---
description: "Quick review command"
argument-hint: "[file] [priority]"
---
请审查以下代码文件并提供反馈：$1
优先级：$2
```

---

## 风险、边界与改进建议

### 已知风险

1. **无缓存机制**
   - 每次调用都重新扫描目录和读取文件
   - 高频调用可能导致 I/O 性能问题
   - 建议：添加文件系统监听或缓存层

2. **Frontmatter 解析简单**
   - 仅支持基本的 `key: value` 格式
   - 不支持嵌套结构、数组等复杂 YAML 特性
   - 引号去除逻辑简单，可能处理边界情况不当

3. **无内容验证**
   - 不验证 prompt 内容是否为空
   - 不检查内容长度限制
   - 恶意构造的大文件可能导致内存问题

4. **并发安全**
   - 异步读取目录，但无锁保护
   - 多任务同时调用可能产生重复工作

### 边界情况

1. **符号链接**
   - Unix 系统支持符号链接（测试用例 `discovers_symlinked_md_files` 验证）
   - 可能循环链接导致无限遍历（未处理）

2. **非 UTF-8 文件**
   - 自动跳过包含无效 UTF-8 的文件
   - 测试用例 `skips_non_utf8_files` 验证

3. **Frontmatter 未闭合**
   - 返回原始内容作为 body
   - 不报错，静默处理

4. **空目录/缺失目录**
   - 返回空列表，不报错

### 改进建议

1. **添加文件系统监听**
   ```rust
   // 使用 notify crate 监听目录变化
   // 实现增量更新，避免重复扫描
   ```

2. **增强 Frontmatter 解析**
   - 考虑使用 `serde_yaml` 或 `toml` 解析器
   - 支持更多元数据字段

3. **添加内容校验**
   - 最大文件大小限制
   - 内容长度限制
   - 必填字段验证

4. **性能优化**
   - 添加内存缓存
   - 实现懒加载策略
   - 支持异步批量读取

5. **错误报告**
   - 提供详细的加载失败原因
   - 支持诊断日志输出
   - 帮助用户排查配置问题
