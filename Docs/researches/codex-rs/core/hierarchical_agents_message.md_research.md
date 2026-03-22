# hierarchical_agents_message.md 研究文档

## 场景与职责

`hierarchical_agents_message.md` 是 Codex CLI 项目中定义**分层 Agent（Hierarchical Agents）**行为规范的提示词片段。该文件内容被动态注入到系统提示词中，用于指导 AI Agent 如何理解和使用 `AGENTS.md` 文件。

**核心定位**：
- 定义 AGENTS.md 文件的发现机制和作用域规则
- 指导 Agent 如何遵守项目级编码规范
- 支持分层配置：深层目录的 AGENTS.md 覆盖高层配置
- 在 `ChildAgentsMd` 功能启用时追加到系统提示词

**使用场景**：
- 多层级项目结构中的编码规范继承
- 大型代码库中不同模块可能有不同的编码标准
- 需要向 Agent 解释 AGENTS.md 的权威性和适用范围

---

## 功能点目的

### 1. AGENTS.md 文件发现机制

明确 AGENTS.md 文件可能出现的位置：
> "Files called AGENTS.md commonly appear in many places inside a container - at \"/\", in "~", deep within git repositories, or in any other directory; their location is not limited to version-controlled folders."

**关键要点**：
- 不限于版本控制文件夹
- 可出现在文件系统任何位置
- 包括根目录、用户主目录、仓库深层目录

### 2. AGENTS.md 核心目的

定义 AGENTS.md 的设计意图：
> "Their purpose is to pass along human guidance to you, the agent."

**指导内容示例**：
- 编码标准（coding standards）
- 项目布局说明（explanations of the project layout）
- 构建或测试步骤（steps for building or testing）
- GitHub PR 描述措辞（wording for GitHub pull-request descriptions）

### 3. 作用域与继承规则

详细定义 AGENTS.md 的适用范围和优先级：

**作用域规则**：
> "Each AGENTS.md governs the entire directory that contains it and every child directory beneath that point."
- 每个 AGENTS.md 管辖其所在目录及所有子目录

**优先级规则**：
> "Whenever you change a file, you have to comply with instructions in any AGENTS.md file whose scope covers that file."
- 修改文件时必须遵守覆盖该文件的所有 AGENTS.md

**命名约定限制**：
> "Instructions about code style, structure, naming, etc. apply only to code that falls inside that AGENTS.md file's scope, unless the document explicitly states otherwise."
- 代码风格、结构、命名等指令仅适用于 AGENTS.md 作用域内的代码
- 除非文档明确说明否则

**冲突解决**：
> "When two AGENTS.md files disagree, the one located deeper in the directory structure overrides the higher-level file"
- 深层 AGENTS.md 优先于高层文件

**最高优先级**：
> "while instructions given directly in the prompt by the system, developer, or user outrank any AGENTS.md content."
- 系统/开发者/用户在提示词中直接给出的指令优先于任何 AGENTS.md 内容

---

## 具体技术实现

### 提示词注入机制

```rust
// codex-rs/core/src/project_doc.rs:31-32
pub(crate) const HIERARCHICAL_AGENTS_MESSAGE: &str =
    include_str!("../hierarchical_agents_message.md");
```

### 条件注入逻辑

```rust
// codex-rs/core/src/project_doc.rs:108-113
if config.features.enabled(Feature::ChildAgentsMd) {
    if !output.is_empty() {
        output.push_str("\n\n");
    }
    output.push_str(HIERARCHICAL_AGENTS_MESSAGE);
}
```

### 完整提示词组装流程

```rust
// codex-rs/core/src/project_doc.rs:79-120
pub(crate) async fn get_user_instructions(config: &Config) -> Option<String> {
    let project_docs = read_project_docs(config).await;
    let mut output = String::new();

    // 1. 添加用户自定义指令
    if let Some(instructions) = config.user_instructions.clone() {
        output.push_str(&instructions);
    }

    // 2. 添加项目文档（AGENTS.md 等）
    match project_docs {
        Ok(Some(docs)) => {
            if !output.is_empty() {
                output.push_str(PROJECT_DOC_SEPARATOR);
            }
            output.push_str(&docs);
        }
        // ...
    };

    // 3. 添加 JS REPL 指令（如果启用）
    if let Some(js_repl_section) = render_js_repl_instructions(config) {
        // ...
    }

    // 4. 添加分层 Agent 消息（如果启用 ChildAgentsMd 功能）
    if config.features.enabled(Feature::ChildAgentsMd) {
        if !output.is_empty() {
            output.push_str("\n\n");
        }
        output.push_str(HIERARCHICAL_AGENTS_MESSAGE);
    }

    if !output.is_empty() {
        Some(output)
    } else {
        None
    }
}
```

### 功能开关控制

```rust
// codex-rs/core/src/features.rs 中定义
pub enum Feature {
    // ...
    ChildAgentsMd,  // 控制分层 Agent 消息功能
    // ...
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/hierarchical_agents_message.md` | 本文件，分层 Agent 行为规范（7 行） |
| `codex-rs/core/src/project_doc.rs` | 项目文档发现和组装逻辑 |
| `codex-rs/core/src/features.rs` | 功能开关定义（`ChildAgentsMd`） |

### 关键代码引用

```rust
// codex-rs/core/src/project_doc.rs:31-32
pub(crate) const HIERARCHICAL_AGENTS_MESSAGE: &str =
    include_str!("../hierarchical_agents_message.md");

// codex-rs/core/src/project_doc.rs:108-113
if config.features.enabled(Feature::ChildAgentsMd) {
    if !output.is_empty() {
        output.push_str("\n\n");
    }
    output.push_str(HIERARCHICAL_AGENTS_MESSAGE);
}
```

### 相关测试

```rust
// codex-rs/core/tests/suite/hierarchical_agents.rs
// 测试分层 Agent 功能

// codex-rs/core/src/project_doc_tests.rs
// 测试项目文档发现逻辑
```

### AGENTS.md 发现流程

```rust
// codex-rs/core/src/project_doc.rs:186-271
pub fn discover_project_doc_paths(config: &Config) -> std::io::Result<Vec<PathBuf>> {
    // 1. 确定项目根目录
    let project_root_markers = // ...
    
    // 2. 从当前目录向上遍历到项目根
    let search_dirs: Vec<PathBuf> = // ...
    
    // 3. 在每个目录中查找 AGENTS.md
    for d in search_dirs {
        for name in &candidate_filenames {
            let candidate = d.join(name);
            // 检查文件是否存在
        }
    }
    
    Ok(found)
}
```

---

## 依赖与外部交互

### 内部依赖

1. **Project Doc 模块** (`codex-rs/core/src/project_doc.rs`)
   - 核心模块，负责项目文档的发现和组装
   - 定义 `HIERARCHICAL_AGENTS_MESSAGE` 常量
   - 实现 `get_user_instructions` 函数

2. **Features 系统** (`codex-rs/core/src/features.rs`)
   - 定义 `ChildAgentsMd` 功能开关
   - 控制是否注入分层 Agent 消息

3. **Config 系统** (`codex-rs/core/src/config/`)
   - 提供功能开关状态查询
   - 支持用户自定义指令

4. **Config Loader** (`codex-rs/core/src/config_loader/`)
   - 项目根目录标记解析
   - 配置层合并逻辑

### 外部交互

1. **文件系统**
   - 遍历目录查找 AGENTS.md 文件
   - 读取文件内容
   - 支持符号链接

2. **OpenAI API**
   - 组装后的提示词通过 API 发送给模型
   - 作为 `system` 消息的一部分

3. **用户工作区**
   - 扫描用户工作区中的 AGENTS.md 文件
   - 遵守项目特定的编码规范

---

## 风险、边界与改进建议

### 潜在风险

1. **功能开关风险**：
   - `ChildAgentsMd` 功能默认可能未启用
   - 用户可能不知道此功能存在
   - 启用后可能增加提示词长度（虽然本文件只有 7 行）

2. **AGENTS.md 冲突风险**：
   - 深层 AGENTS.md 覆盖高层配置可能导致意外行为
   - 用户可能不理解优先级规则
   - 多个 AGENTS.md 的指令可能相互矛盾

3. **提示词注入风险**：
   - AGENTS.md 内容被直接包含进提示词
   - 恶意 AGENTS.md 可能尝试提示词注入
   - 需要验证 AGENTS.md 内容的来源可信度

4. **性能风险**：
   - 遍历目录查找 AGENTS.md 可能耗时
   - 大型代码库中可能有大量 AGENTS.md 文件
   - 文件读取和组装增加启动延迟

### 边界条件

1. **功能开关边界**：
   ```rust
   // 仅当 Feature::ChildAgentsMd 启用时注入
   if config.features.enabled(Feature::ChildAgentsMd) { ... }
   ```

2. **项目根目录边界**：
   - 默认使用 `.git` 作为项目根标记
   - 可通过 `project_root_markers` 配置自定义
   - 空标记列表禁用父目录遍历

3. **文件大小边界**：
   ```rust
   // codex-rs/core/src/project_doc.rs:129
   let max_total = config.project_doc_max_bytes;
   if max_total == 0 {
       return Ok(None);  // 禁用项目文档
   }
   ```

4. **作用域边界**：
   - AGENTS.md 仅管辖其目录及子目录
   - 不适用于父目录或兄弟目录
   - 直接提示词指令优先于 AGENTS.md

### 改进建议

1. **功能发现性**：
   - 在文档中明确说明 `ChildAgentsMd` 功能
   - 添加 CLI 命令查看当前启用的功能
   - 考虑默认启用此功能（因为文件很小，只有 7 行）

2. **安全性增强**：
   - 添加 AGENTS.md 内容验证
   - 限制 AGENTS.md 的最大大小
   - 考虑添加 AGENTS.md 来源验证（如只允许特定路径）

3. **性能优化**：
   - 缓存 AGENTS.md 发现结果
   - 使用文件系统监听（watcher）检测变更
   - 异步并行读取多个 AGENTS.md 文件

4. **调试支持**：
   - 添加日志记录哪些 AGENTS.md 被加载
   - 提供命令查看最终组装的提示词
   - 显示 AGENTS.md 优先级决策过程

5. **文档化**：
   - 在 `hierarchical_agents_message.md` 文件头添加注释：
     ```markdown
     <!-- Purpose: Explain AGENTS.md scope and precedence rules to the agent -->
     <!-- Injected when: Feature::ChildAgentsMd is enabled -->
     <!-- Location: Appended to system prompt after project docs -->
     ```

6. **功能扩展**：
   - 支持 AGENTS.md 的语法验证
   - 提供 AGENTS.md 模板生成命令
   - 添加 AGENTS.md 冲突检测和报告

### 与 AGENTS.md 根文件的关系

| 文件 | 位置 | 用途 |
|------|------|------|
| `AGENTS.md`（项目根） | 仓库根目录 | 项目级编码规范 |
| `hierarchical_agents_message.md` | `codex-rs/core/` | 向 Agent 解释 AGENTS.md 规则 |
| `AGENTS.override.md` | 任意目录 | 本地覆盖，优先于 `AGENTS.md` |

**工作流程**：
1. Codex CLI 扫描工作区发现 AGENTS.md 文件
2. 按从根到当前目录的顺序组装内容
3. 如果启用 `ChildAgentsMd`，追加 `hierarchical_agents_message.md`
4. 将组装后的内容作为系统提示词的一部分发送给模型

### 结论

`hierarchical_agents_message.md` 是一个小而关键的提示词片段，它向 AI Agent 解释了 AGENTS.md 文件的作用、发现机制和优先级规则。通过 `ChildAgentsMd` 功能开关控制，该文件确保 Agent 能够正确理解和遵守项目级的编码规范。虽然文件只有 7 行，但它在分层配置系统中扮演着重要的角色，建议考虑默认启用此功能以提高 Agent 对项目规范的理解能力。
