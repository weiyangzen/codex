# 研究文档: codex-rs/core/src/memories/usage.rs

## 场景与职责

本文件是 Codex 核心库中 **Memory 子系统** 的遥测指标模块，负责追踪和上报 Memory 相关文件（如 `MEMORY.md`, `raw_memories.md` 等）被工具读取的使用情况。该模块通过分析工具调用的命令，识别对记忆文件的访问，并生成对应的指标数据。

### 核心职责
1. **命令解析**: 从工具调用中提取 shell 命令
2. **安全检查**: 仅对已知安全的命令进行解析（避免解析危险命令）
3. **路径匹配**: 识别对记忆文件/目录的访问
4. **指标上报**: 通过 OpenTelemetry 上报使用计数

---

## 功能点目的

### 1. Memory 使用指标收集

当 Agent 通过工具（如 `shell`, `shell_command`, `exec_command`）读取 Memory 文件时，系统需要追踪：
- **使用频率**: 哪些记忆文件被频繁访问
- **访问成功率**: 读取操作是否成功
- **工具分布**: 使用哪种工具访问记忆文件

### 2. 命令安全过滤

仅解析已知安全的命令（通过 `is_known_safe_command`），避免：
- 解析复杂/危险的 shell 命令
- 对潜在恶意命令进行不必要的处理
- 性能开销（复杂命令解析成本高）

### 3. 细粒度分类

将记忆文件访问分为 5 个类别：
| 类别 | 路径模式 | 说明 |
|------|---------|------|
| `MemoryMd` | `memories/MEMORY.md` | 主记忆手册 |
| `MemorySummary` | `memories/memory_summary.md` | 记忆摘要 |
| `RawMemories` | `memories/raw_memories.md` | 原始记忆 |
| `RolloutSummaries` | `memories/rollout_summaries/` | Rollout 摘要目录 |
| `Skills` | `memories/skills/` | 技能目录 |

---

## 具体技术实现

### 核心数据结构

```rust
// 指标名称常量
const MEMORIES_USAGE_METRIC: &str = "codex.memories.usage";

// Memory 使用类别枚举
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum MemoriesUsageKind {
    MemoryMd,        // MEMORY.md
    MemorySummary,   // memory_summary.md
    RawMemories,     // raw_memories.md
    RolloutSummaries, // rollout_summaries/ 目录
    Skills,          // skills/ 目录
}

impl MemoriesUsageKind {
    fn as_tag(self) -> &'static str {
        match self {
            Self::MemoryMd => "memory_md",
            Self::MemorySummary => "memory_summary",
            Self::RawMemories => "raw_memories",
            Self::RolloutSummaries => "rollout_summaries",
            Self::Skills => "skills",
        }
    }
}
```

### 主入口函数

```rust
pub(crate) async fn emit_metric_for_tool_read(invocation: &ToolInvocation, success: bool)
```

**调用时机**: 在 `ToolRegistry::dispatch_any()` 中，工具执行完成后调用

**执行流程**:
1. 从工具调用中提取命令
2. 检查是否为已知安全命令
3. 解析命令识别文件操作
4. 匹配记忆文件路径
5. 上报指标

### 命令提取逻辑

```rust
fn shell_command_for_invocation(invocation: &ToolInvocation) -> Option<(Vec<String>, PathBuf)>
```

支持三种工具类型：

| 工具名 | 参数结构 | 命令提取方式 |
|-------|---------|-------------|
| `shell` | `ShellToolCallParams { command, workdir }` | 直接使用 command 数组 |
| `shell_command` | `ShellCommandToolCallParams { command, workdir, login }` | 根据 login 标志派生执行参数 |
| `exec_command` | `ExecCommandArgs { command, workdir }` | 通过 `unified_exec` 模块派生 |

**特殊处理**:
- `shell_command` 支持 login shell 选项，需要检查 `allow_login_shell` 配置
- 使用 `UserShell::derive_exec_args()` 生成实际执行参数

### 命令解析与匹配

```rust
async fn memories_usage_kinds_from_invocation(invocation: &ToolInvocation) -> Vec<MemoriesUsageKind>
```

**解析流程**:
```
ToolInvocation
    ↓
shell_command_for_invocation()  →  Option<(command_vec, workdir)>
    ↓
is_known_safe_command()         →  bool（安全检查）
    ↓
parse_command()                 →  Vec<ParsedCommand>
    ↓
filter_map()                    →  提取 Read/Search 命令
    ↓
get_memory_kind()               →  Option<MemoriesUsageKind>
```

### 路径匹配逻辑

```rust
fn get_memory_kind(path: String) -> Option<MemoriesUsageKind>
```

使用简单的字符串包含匹配：
```rust
if path.contains("memories/MEMORY.md") {
    Some(MemoriesUsageKind::MemoryMd)
} else if path.contains("memories/memory_summary.md") {
    Some(MemoriesUsageKind::MemorySummary)
}
// ... 其他模式
```

**设计选择**: 
- 使用 `contains` 而非精确匹配，支持相对路径和绝对路径
- 路径片段足够独特，避免误匹配

### 指标上报

```rust
invocation.turn.session_telemetry.counter(
    MEMORIES_USAGE_METRIC,
    /*inc*/ 1,
    &[
        ("kind", kind.as_tag()),           // 记忆文件类型
        ("tool", invocation.tool_name.as_str()), // 使用的工具
        ("success", success),              // 是否成功
    ],
);
```

**指标维度**:
- `kind`: memory_md | memory_summary | raw_memories | rollout_summaries | skills
- `tool`: shell | shell_command | exec_command
- `success`: true | false

---

## 关键代码路径与文件引用

### 调用链

```
ToolRegistry::dispatch_any()  [tools/registry.rs:287]
    ↓
emit_metric_for_tool_read()   [memories/usage.rs:34]
    ↓
memories_usage_kinds_from_invocation()
    ↓
shell_command_for_invocation()
    ├── shell          → ShellToolCallParams
    ├── shell_command  → ShellCommandToolCallParams
    └── exec_command   → ExecCommandArgs (unified_exec)
    ↓
is_known_safe_command()       [shell-command/src/command_safety/is_safe_command.rs]
    ↓
parse_command()               [shell-command/src/parse_command.rs]
    ↓
get_memory_kind()
    ↓
counter()                     [otel 遥测]
```

### 依赖模块

```
usage.rs
├── crate::is_safe_command::is_known_safe_command
├── crate::parse_command::parse_command
├── crate::tools::context::ToolInvocation
├── crate::tools::context::ToolPayload
├── crate::tools::handlers::unified_exec::ExecCommandArgs
├── codex_protocol::models::ShellCommandToolCallParams
├── codex_protocol::models::ShellToolCallParams
├── codex_protocol::parse_command::ParsedCommand
└── std::path::PathBuf
```

### ParsedCommand 类型

来自 `codex_protocol::parse_command`:

```rust
pub enum ParsedCommand {
    Read { cmd: String, name: String, path: PathBuf },
    Search { cmd: String, query: Option<String>, path: Option<String> },
    ListFiles { cmd: String, path: Option<String> },
    Unknown { cmd: String },
}
```

**匹配规则**:
- `Read`: 对应 `cat`, `head`, `tail`, `less` 等文件读取命令
- `Search`: 对应 `grep`, `rg` 等搜索命令
- `ListFiles`: 对应 `ls`, `tree`, `rg --files` 等列目录命令
- `Unknown`: 无法解析或包含危险操作的命令

---

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `codex_protocol` | `ParsedCommand`, `ShellToolCallParams`, `ShellCommandToolCallParams` |
| `codex_shell_command` | `parse_command()`, `is_known_safe_command()` |

### 内部模块

| 模块 | 功能 |
|------|------|
| `crate::is_safe_command` | 命令安全验证（re-export from `codex_shell_command`） |
| `crate::parse_command` | 命令解析（re-export from `codex_shell_command`） |
| `crate::tools::context` | `ToolInvocation`, `ToolPayload` |
| `crate::tools::handlers::unified_exec` | `ExecCommandArgs`, `get_command()` |

### 遥测集成

通过 `ToolInvocation` 访问遥测：
```rust
invocation.turn.session_telemetry.counter(...)
```

`session_telemetry` 类型为 `codex_otel::SessionTelemetry`，提供：
- `counter(name, increment, tags)`
- `histogram(name, value, tags)`
- `start_timer(name, tags)`

---

## 风险、边界与改进建议

### 当前风险点

1. **路径匹配过于宽松**
   ```rust
   path.contains("memories/MEMORY.md")
   ```
   - 可能误匹配包含该子串的非记忆文件路径
   - 例如: `/tmp/not_memories/MEMORY.md_backup`

2. **仅支持安全命令**
   - 如果用户通过复杂管道读取记忆文件，可能无法识别
   - 例如: `cat memories/MEMORY.md | grep foo` 中的 `cat` 会被识别，但 `grep memories/MEMORY.md` 如果不在允许列表中则不会

3. **无递归目录检测**
   - 读取 `memories/skills/subdir/SKILL.md` 会被识别为 `Skills`
   - 但具体读取了哪个技能文件的信息丢失

4. **硬编码路径模式**
   - 记忆目录结构变更需要同步修改此文件
   - 无集中配置点

### 边界情况

| 场景 | 当前行为 | 说明 |
|------|---------|------|
| 相对路径 `cat memories/MEMORY.md` | ✅ 识别 | 标准场景 |
| 绝对路径 `cat /home/user/.codex/memories/MEMORY.md` | ✅ 识别 | 包含子串即可 |
| 符号链接 `cat link_to_memories/MEMORY.md` | ❌ 可能遗漏 | 路径不包含 "memories/" |
| 子目录读取 `cat memories/skills/foo/SKILL.md` | ✅ 识别为 Skills | 正确 |
| 非安全命令 `vim memories/MEMORY.md` | ❌ 不识别 | `vim` 不在安全列表 |
| 管道 `cat memories/MEMORY.md \| wc -l` | ✅ 识别 | `cat` 被解析 |
| 重定向 `cat < memories/MEMORY.md` | ❌ 可能遗漏 | 重定向解析依赖具体实现 |

### 改进建议

1. **使用路径规范化匹配**
   ```rust
   fn get_memory_kind(path: &Path) -> Option<MemoriesUsageKind> {
       let canonical = path.canonicalize().ok()?;
       let memory_root = get_memory_root(); // 从配置获取
       
       if let Ok(rel) = canonical.strip_prefix(&memory_root) {
           match rel.components().next()? {
               Component::Normal(name) if name == "MEMORY.md" => Some(MemoryMd),
               // ...
           }
       }
   }
   ```

2. **支持更多命令类型**
   - 增加对编辑器类命令的检测（即使不完全解析）
   - 支持 `find memories/ -name "*.md"` 这类目录遍历命令

3. **增加详细度配置**
   ```rust
   enum MemoryUsageDetailLevel {
       None,      // 不上报
       Category,  // 当前行为
       File,      // 具体到文件
       Full,      // 文件 + 命令详情
   }
   ```

4. **缓存解析结果**
   - 相同命令的解析结果可以缓存
   - 减少重复的 `parse_command` 调用

5. **增加错误处理**
   ```rust
   // 当前实现忽略所有错误
   serde_json::from_str::<ShellToolCallParams>(arguments).ok()
   
   // 建议增加日志
   match serde_json::from_str::<ShellToolCallParams>(arguments) {
       Ok(params) => Some(...),
       Err(e) => {
           tracing::debug!("Failed to parse shell params: {}", e);
           None
       }
   }
   ```

6. **单元测试覆盖**
   当前文件无直接测试，建议增加：
   ```rust
   #[cfg(test)]
   mod tests {
       #[test]
       fn test_get_memory_kind_various_paths() {
           assert_eq!(
               get_memory_kind("memories/MEMORY.md".to_string()),
               Some(MemoriesUsageKind::MemoryMd)
           );
           assert_eq!(
               get_memory_kind("/abs/path/to/memories/MEMORY.md".to_string()),
               Some(MemoriesUsageKind::MemoryMd)
           );
           assert_eq!(
               get_memory_kind("other/MEMORY.md".to_string()),
               None
           );
       }
   }
   ```

### 性能考虑

1. **解析开销**: `parse_command` 可能涉及复杂的 shell 解析
   - 已在入口处通过 `is_known_safe_command` 过滤
   - 仅对简单命令进行完整解析

2. **字符串分配**: 当前实现有多次 `to_string()` 转换
   - 可考虑使用 `&str` 减少分配

3. **异步开销**: 函数标记为 `async` 但无实际 await 点
   - 可考虑改为同步函数
   - 或保留 async 以便未来扩展（如异步缓存查询）

### 安全考虑

1. **命令注入防护**: 依赖 `is_known_safe_command` 的过滤
   - 确保危险命令（如包含 `rm`, `>` 重定向等）不会被解析

2. **路径遍历**: 不直接处理用户输入路径
   - 仅从已解析的 `ParsedCommand` 中提取路径
   - 路径解析在命令解析阶段已完成
