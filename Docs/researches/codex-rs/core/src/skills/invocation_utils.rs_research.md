# invocation_utils.rs 研究文档

## 场景与职责

`invocation_utils.rs` 是 Codex 技能系统的**隐式调用检测模块**，负责在用户执行 shell 命令时自动检测可能相关的技能，并上报遥测指标。与显式调用（用户主动提及 `$skill-name`）不同，隐式调用通过分析用户的命令行输入来推断可能使用的技能。

**核心职责：**

1. **隐式技能路径索引构建**：为快速查找建立技能路径索引
2. **脚本运行检测**：检测用户是否运行了技能目录下的脚本
3. **技能文档读取检测**：检测用户是否查看了技能文档（SKILL.md）
4. **遥测上报**：记录隐式调用事件用于分析
5. **去重机制**：确保同一回合内同一技能只上报一次

该模块实现了"智能感知"功能，使 Codex 能够理解用户行为与技能之间的潜在关联。

## 功能点目的

### 1. `build_implicit_skill_path_indexes` - 索引构建
```rust
pub(crate) fn build_implicit_skill_path_indexes(
    skills: Vec<SkillMetadata>,
) -> (HashMap<PathBuf, SkillMetadata>, HashMap<PathBuf, SkillMetadata>)
```

构建两个查找索引：
- **`by_scripts_dir`**: 技能脚本目录 → 技能元数据
  - 键：`{skill_dir}/scripts` 的规范化路径
  - 用于检测脚本运行
- **`by_skill_doc_path`**: 技能文档路径 → 技能元数据
  - 键：`SKILL.md` 文件的规范化路径
  - 用于检测文档读取

### 2. `maybe_emit_implicit_skill_invocation` - 隐式调用检测入口
```rust
pub(crate) async fn maybe_emit_implicit_skill_invocation(
    sess: &Session,
    turn_context: &TurnContext,
    command: &str,
    workdir: Option<&str>,
)
```

**执行流程：**
1. 调用 `detect_implicit_skill_invocation_for_command` 检测候选技能
2. 如果没有匹配，直接返回
3. 构建 `seen_key` 用于去重：`{scope}:{path}:{name}`
4. 检查本回合是否已上报过该技能
5. 上报 OpenTelemetry 指标：`codex.skill.injected`（带 `invoke_type=implicit` 标签）
6. 上报 Analytics 事件：`SkillInvocation`（`InvocationType::Implicit`）

### 3. `detect_implicit_skill_invocation_for_command` - 命令检测
协调两种检测策略：

**策略1：脚本运行检测 (`detect_skill_script_run`)**
- 解析命令，提取脚本路径
- 检查脚本路径是否位于某个技能的 `scripts/` 目录下
- 支持绝对路径和相对路径

**策略2：文档读取检测 (`detect_skill_doc_read`)**
- 检查命令是否为文件读取命令（cat, less, head 等）
- 检查读取的文件路径是否匹配某个技能的 SKILL.md

### 4. `script_run_token` - 脚本路径提取
从命令令牌中提取脚本路径：

**支持的运行器：**
```rust
const RUNNERS: [&str; 10] = [
    "python", "python3", "bash", "zsh", "sh", 
    "node", "deno", "ruby", "perl", "pwsh"
];
```

**支持的脚本扩展名：**
```rust
const SCRIPT_EXTENSIONS: [&str; 7] = [
    ".py", ".sh", ".js", ".ts", ".rb", ".pl", ".ps1"
];
```

**解析逻辑：**
1. 获取命令的第一个令牌（运行器）
2. 提取基本名并检查是否在 `RUNNERS` 列表中
3. 跳过以 `-` 开头的选项令牌和 `--` 分隔符
4. 找到第一个非选项令牌，检查扩展名

### 5. `detect_skill_script_run` - 脚本运行匹配
```rust
fn detect_skill_script_run(
    outcome: &SkillLoadOutcome,
    tokens: &[String],
    workdir: &Path,
) -> Option<SkillMetadata>
```

**匹配逻辑：**
1. 提取脚本令牌并解析为绝对路径
2. 规范化路径（使用 `std::fs::canonicalize`）
3. 遍历脚本路径的所有祖先目录
4. 检查每个祖先是否匹配某个技能的 `scripts/` 目录
5. 返回第一个匹配的技能

### 6. `detect_skill_doc_read` - 文档读取匹配
```rust
fn detect_skill_doc_read(
    outcome: &SkillLoadOutcome,
    tokens: &[String],
    workdir: &Path,
) -> Option<SkillMetadata>
```

**匹配逻辑：**
1. 检查命令是否为文件读取命令
2. 遍历命令参数中的路径令牌
3. 规范化每个路径（支持绝对和相对路径）
4. 检查路径是否匹配某个技能的 SKILL.md 路径

### 7. `command_reads_file` - 文件读取命令检测
```rust
fn command_reads_file(tokens: &[String]) -> bool
```

**支持的读取命令：**
```rust
const READERS: [&str; 8] = [
    "cat", "sed", "head", "tail", "less", "more", "bat", "awk"
];
```

## 具体技术实现

### 命令令牌化
使用 `shlex::split` 进行类 shell 的令牌化，失败时回退到简单的空白分割：
```rust
fn tokenize_command(command: &str) -> Vec<String> {
    shlex::split(command).unwrap_or_else(|| {
        command.split_whitespace().map(ToString::to_string).collect()
    })
}
```

### 路径规范化
```rust
fn normalize_path(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}
```
- 优先使用 `canonicalize` 获取绝对路径并解析符号链接
- 失败时回退到原始路径

### 去重机制
使用 `TurnContext` 中的 `implicit_invocation_seen_skills` Mutex 集合：
```rust
let seen_key = format!("{skill_scope}:{skill_path}:{skill_name}");
let inserted = {
    let mut seen_skills = turn_context
        .turn_skills
        .implicit_invocation_seen_skills
        .lock()
        .await;
    seen_skills.insert(seen_key)
};
if !inserted {
    return; // 已上报过
}
```

## 关键代码路径与文件引用

### 本文件关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `build_implicit_skill_path_indexes` | 13-32 | 构建隐式调用查找索引 |
| `maybe_emit_implicit_skill_invocation` | 56-116 | 主入口，协调检测和上报 |
| `detect_implicit_skill_invocation_for_command` | 34-54 | 命令级检测协调 |
| `script_run_token` | 127-160 | 从命令提取脚本路径 |
| `detect_skill_script_run` | 162-183 | 脚本运行匹配 |
| `detect_skill_doc_read` | 185-210 | 文档读取匹配 |
| `command_reads_file` | 212-219 | 文件读取命令检测 |

### 调用路径
```
codex-rs/core/src/tools/handlers/shell.rs:288
    └── maybe_emit_implicit_skill_invocation(session, turn, &params.command, ...)

codex-rs/core/src/tools/handlers/unified_exec.rs:148
    └── maybe_emit_implicit_skill_invocation(session, turn, command, ...)
```

### 索引构建调用
```
codex-rs/core/src/skills/manager.rs
    └── build_implicit_skill_path_indexes(skills)
        └── 存储到 SkillLoadOutcome.implicit_skills_by_*
```

### 数据结构依赖
| 类型 | 定义位置 | 用途 |
|------|----------|------|
| `SkillLoadOutcome` | model.rs | 包含隐式技能索引 |
| `SkillMetadata` | model.rs | 技能元数据 |
| `SkillInvocation` | analytics_client.rs | 分析事件 |
| `InvocationType::Implicit` | analytics_client.rs | 调用类型标记 |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `crate::analytics_client::*` | 遥测上报 |
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |
| `crate::skills::{SkillLoadOutcome, SkillMetadata}` | 技能数据 |

### 外部 crate
- `shlex`: 类 shell 命令令牌化
- `std::fs::canonicalize`: 路径规范化

## 风险、边界与改进建议

### 已知风险

1. **误报风险**
   - 用户可能偶然运行与技能同名的脚本
   - 路径匹配可能过于宽泛（如 `/tmp/scripts/foo.py` 匹配任何技能的 scripts 目录）
   - 风险：产生大量无意义的隐式调用事件

2. **路径规范化失败**
   - `canonicalize` 要求路径存在，对于将要创建的文件会失败
   - 符号链接处理可能不符合预期

3. **命令解析局限**
   - 仅支持简单的命令结构
   - 复杂的 shell 管道、子 shell、命令替换无法正确解析
   - 示例：`bash -c "python script.py"` 无法检测

4. **并发去重竞态**
   - 去重检查和使用之间可能存在竞态条件
   - 虽然概率极低，但理论上可能重复上报

### 边界情况

1. **相对路径解析**
   - 依赖 `turn_context.resolve_path` 和 `workdir` 参数
   - 如果工作目录信息缺失，相对路径可能解析错误

2. **脚本扩展名大小写**
   - 使用 `to_ascii_lowercase()` 进行大小写不敏感匹配
   - 但路径的其他部分仍区分大小写（Unix）

3. **命令别名**
   - 无法识别 shell 别名（如 `alias py=python3`）
   - 仅检查基本命令名

4. **空命令处理**
   - `tokenize_command` 返回空向量，后续函数优雅处理

### 改进建议

1. **增强命令解析**
   ```rust
   // 建议：支持嵌套命令检测
   fn detect_nested_script_run(command: &str) -> Option<PathBuf> {
       // 解析 bash -c, sh -c, eval 等嵌套结构
   }
   ```

2. **模糊匹配改进**
   ```rust
   // 建议：添加路径相似度评分
   fn path_similarity(a: &Path, b: &Path) -> f64 {
       // 使用编辑距离或路径组件匹配
   }
   ```

3. **配置化支持**
   - 允许用户配置额外的运行器和读取命令
   - 支持自定义脚本扩展名

4. **上下文感知**
   - 结合最近的显式技能提及进行加权
   - 如果用户刚提及某技能，其隐式调用权重增加

5. **性能优化**
   - 使用前缀树（Trie）替代 HashMap 进行路径匹配
   - 对于大量技能场景，提高查找效率

6. **测试增强**
   - 添加更多边界情况测试（见 `invocation_utils_tests.rs`）
   - 添加模糊测试，随机生成命令验证鲁棒性
