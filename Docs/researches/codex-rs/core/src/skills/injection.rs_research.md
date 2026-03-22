# injection.rs 研究文档

## 场景与职责

`injection.rs` 是 Codex 技能系统的**核心注入模块**，负责将用户明确提及的技能（explicit skill mentions）转换为模型可消费的指令内容。该模块在每次用户回合处理中执行以下关键任务：

1. **技能提及收集**：从用户输入（文本和结构化输入）中识别和收集被提及的技能
2. **技能内容加载**：异步读取技能文件（SKILL.md）的内容
3. **指令注入构建**：将技能内容包装为 `SkillInstructions`，最终转换为 `ResponseItem`
4. **遥测指标上报**：记录技能注入的成功/失败状态和调用类型
5. **工具提及解析**：支持 `$skill-name` 语法和 `[$skill-name](path)` 链接语法

该模块是连接用户输入与技能系统的桥梁，确保模型能够获取到相关技能的上下文指令。

## 功能点目的

### 1. `SkillInjections` 结构体
```rust
pub(crate) struct SkillInjections {
    pub(crate) items: Vec<ResponseItem>,  // 注入的指令项
    pub(crate) warnings: Vec<String>,     // 加载失败的警告信息
}
```
封装技能注入的结果，包含成功加载的指令项和加载失败的警告。

### 2. `build_skill_injections` - 构建注入内容
**核心流程：**
1. 遍历所有被提及的技能
2. 异步读取每个技能的 SKILL.md 文件
3. 成功时：创建 `SkillInstructions` 并添加到 items
4. 失败时：生成警告信息
5. 上报遥测指标（OpenTelemetry counter + Analytics 事件）

**遥测指标：**
- `codex.skill.injected`: 计数器，带 `status` (ok/error) 和 `skill` 标签
- Analytics: `SkillInvocation` 事件，记录显式调用

### 3. `collect_explicit_skill_mentions` - 收集显式提及
**复杂的多阶段解析逻辑：**

**阶段1：结构化输入处理**
- 处理 `UserInput::Skill { name, path }` 类型输入
- 通过路径精确匹配技能
- 记录已处理的名称和路径，用于后续去重

**阶段2：文本输入扫描**
- 使用 `extract_tool_mentions` 解析 `$skill-name` 语法
- 支持链接语法 `[$name](path)` 进行精确路径匹配
- 处理歧义名称（同名技能）的冲突解决

**歧义解决策略：**
- 优先使用路径匹配（精确匹配）
- 对于纯名称匹配，仅当名称唯一且不与 connector slug 冲突时才接受
- 被结构化输入阻止的名称不会用于文本回退

### 4. 工具提及解析系统

#### `extract_tool_mentions` / `extract_tool_mentions_with_sigil`
从文本中提取工具提及：
- 支持 `$name` 纯文本提及
- 支持 `[$name](path)` 链接提及
- 过滤常见环境变量（PATH, HOME, USER 等）
- 返回 `ToolMentions` 结构，包含 names、paths 和 plain_names

#### `ToolMentionKind` 枚举
```rust
pub(crate) enum ToolMentionKind {
    App,      // app:// 前缀
    Mcp,      // mcp:// 前缀
    Plugin,   // plugin:// 前缀
    Skill,    // skill:// 前缀或 SKILL.md 文件名
    Other,    // 其他
}
```
用于区分不同类型的工具提及，便于路由到不同的处理逻辑。

#### 路径解析辅助函数
- `app_id_from_path`: 从 `app://id` 提取应用 ID
- `plugin_config_name_from_path`: 从 `plugin://name` 提取插件配置名
- `normalize_skill_path`: 移除 `skill://` 前缀

### 5. `select_skills_from_mentions` - 技能选择逻辑
**两阶段选择：**
1. **路径优先匹配**：遍历所有提及的路径，精确匹配技能路径
2. **名称回退匹配**：对于未通过路径匹配的技能，检查纯名称提及
   - 要求技能名称在启用技能中唯一
   - 要求不与 connector slug 冲突
   - 要求未被结构化输入阻止

## 具体技术实现

### 提及解析算法
```rust
// 字节级扫描，避免正则表达式开销
let text_bytes = text.as_bytes();
let mut index = 0;
while index < text_bytes.len() {
    // 检查链接语法 [$$name](path)
    if byte == b'[' && parse_linked_tool_mention(...) { ... }
    
    // 检查纯提及 $name
    if byte == sigil as u8 { ... }
    
    index += 1;
}
```

### 链接提及解析
格式：`[$$name](path)` 或 `[$name](path)`（取决于 sigil）
- 支持 `$$` 双符号转义（用于技能提及）
- 路径允许前后空白字符
- 路径不能为空

### 性能考虑
- 时间复杂度：O(T + (N_s + N_t) * S)
  - T: 总文本长度
  - N_s: 结构化技能输入数量
  - N_t: 文本输入数量
  - S: 技能总数
- 空间复杂度：O(S + M)
  - M: 单个文本输入中解析的最大提及数

## 关键代码路径与文件引用

### 本文件关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `build_skill_injections` | 24-71 | 主入口，构建技能注入内容 |
| `collect_explicit_skill_mentions` | 100-153 | 收集显式技能提及 |
| `extract_tool_mentions` | 235-237 | 提取工具提及（默认 $ 符号） |
| `extract_tool_mentions_with_sigil` | 239-300 | 带自定义符号的提及提取 |
| `select_skills_from_mentions` | 303-378 | 根据提及选择技能 |
| `parse_linked_tool_mention` | 380-435 | 解析链接语法提及 |

### 调用路径
```
codex-rs/core/src/codex.rs:5508
    └── build_skill_injections(&mentioned_skills, ...).await
        
调用前置步骤:
    codex.rs:5487 -> resolve_skill_dependencies_for_turn (环境变量依赖)
    codex.rs:5490-5496 -> maybe_prompt_and_install_mcp_dependencies (MCP 依赖)
```

### 数据结构依赖
| 类型 | 定义位置 | 用途 |
|------|----------|------|
| `SkillMetadata` | model.rs | 技能元数据 |
| `SkillInstructions` | instructions/mod.rs | 技能指令包装 |
| `ResponseItem` | codex_protocol | 响应项类型 |
| `UserInput` | codex_protocol | 用户输入类型 |
| `SkillInvocation` | analytics_client.rs | 分析事件 |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `crate::analytics_client::*` | 遥测指标上报 |
| `crate::instructions::SkillInstructions` | 指令包装结构 |
| `crate::mention_syntax::TOOL_MENTION_SIGIL` | 提及符号常量（'$'） |
| `crate::mentions::build_skill_name_counts` | 构建技能名称计数 |
| `codex_otel::SessionTelemetry` | OpenTelemetry 指标 |
| `codex_protocol::*` | 协议类型定义 |

### 标准库和外部 crate
- `tokio::fs`: 异步文件读取
- `std::collections::{HashMap, HashSet}`: 去重和映射

## 风险、边界与改进建议

### 已知风险

1. **文件 I/O 阻塞**
   - 每个技能文件都进行独立的异步读取
   - 大量技能提及可能导致 I/O 延迟累积
   - 风险：在高延迟文件系统（如网络存储）上性能下降

2. **歧义名称处理**
   - 同名技能仅通过路径区分，用户可能困惑
   - 如果用户输入 `$skill-name` 而同名技能存在多个，会被静默忽略
   - 风险：用户期望技能被调用但实际上未被注入

3. **路径匹配大小写敏感**
   - 文件系统路径匹配依赖于底层 OS 行为
   - Windows 不区分大小写，Unix 区分
   - 风险：跨平台行为不一致

4. **循环依赖风险**
   - 技能文件可能引用其他技能
   - 当前无循环依赖检测机制

### 边界情况

1. **空技能列表**
   - 早期返回 `SkillInjections::default()`，避免不必要处理

2. **文件读取失败**
   - 记录警告但不中断其他技能加载
   - 遥测上报 error 状态

3. **环境变量过滤**
   - `is_common_env_var` 函数过滤常见变量（PATH, HOME 等）
   - 防止误将环境变量引用解析为技能提及

4. **技能名称字符限制**
   - `is_mention_name_char` 限制允许字符：`a-zA-Z0-9_-:`
   - 冒号支持命名空间（如 `slack:search`）

### 改进建议

1. **批量文件读取优化**
   ```rust
   // 建议：使用 FuturesUnordered 并行读取
   use futures::stream::{FuturesUnordered, StreamExt};
   let mut futures: FuturesUnordered<_> = skills
       .iter()
       .map(|s| fs::read_to_string(&s.path))
       .collect();
   ```

2. **歧义提示改进**
   - 当检测到歧义名称时，向用户返回警告
   - 建议用户使用路径链接语法 `[$name](path)`

3. **缓存机制**
   - 缓存技能文件内容，避免重复读取
   - 添加文件修改时间检查，支持热更新

4. **技能依赖图**
   - 实现技能依赖解析和循环检测
   - 自动注入被依赖的技能

5. **测试覆盖**
   - 当前测试在 `injection_tests.rs` 中
   - 建议添加更多边界情况测试（如特殊字符、Unicode）
