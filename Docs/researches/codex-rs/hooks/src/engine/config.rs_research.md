# config.rs 深度研究文档

## 场景与职责

`config.rs` 是 Codex Hooks 系统的**配置模型定义层**，负责定义 `hooks.json` 配置文件的反序列化数据结构。它是 Hooks 配置从 JSON 文件到 Rust 类型系统的桥梁，承担着以下关键职责：

1. **配置结构定义**：定义 `HooksFile`、`HookEvents`、`MatcherGroup`、`HookHandlerConfig` 等核心配置类型
2. **反序列化支持**：通过 `serde::Deserialize` 实现从 JSON 到 Rust 类型的映射
3. **默认值处理**：为可选字段提供合理的默认值
4. **类型安全**：使用枚举区分不同类型的 Hook 处理器（Command/Prompt/Agent）

该模块是配置解析的"源头"，其定义直接影响 `discovery.rs` 的配置加载逻辑。

## 功能点目的

### 1. 配置文件根结构 (`HooksFile`)

```rust
#[derive(Debug, Default, Deserialize)]
pub(crate) struct HooksFile {
    #[serde(default)]
    pub hooks: HookEvents,
}
```

**设计意图**：
- 作为 `hooks.json` 的根对象，包裹所有 Hook 配置
- 使用 `#[serde(default)]` 允许空文件或缺失字段
- 支持渐进式配置（先创建空文件，逐步添加内容）

### 2. 事件类型分组 (`HookEvents`)

```rust
#[derive(Debug, Default, Deserialize)]
pub(crate) struct HookEvents {
    #[serde(rename = "SessionStart", default)]
    pub session_start: Vec<MatcherGroup>,
    #[serde(rename = "UserPromptSubmit", default)]
    pub user_prompt_submit: Vec<MatcherGroup>,
    #[serde(rename = "Stop", default)]
    pub stop: Vec<MatcherGroup>,
}
```

**设计意图**：
- 按事件类型分组：会话开始、用户提交、停止事件
- 使用 PascalCase 重命名匹配 JSON 约定
- 每个事件类型包含多个匹配器组，支持条件化 Hook 执行

**支持的事件类型**：
| 事件名 | 触发时机 | 作用域 |
|-------|---------|-------|
| `SessionStart` | 会话启动时（新建或恢复） | Thread |
| `UserPromptSubmit` | 用户提交提示词时 | Turn |
| `Stop` | 停止事件时 | Turn |

### 3. 匹配器组 (`MatcherGroup`)

```rust
#[derive(Debug, Default, Deserialize)]
pub(crate) struct MatcherGroup {
    #[serde(default)]
    pub matcher: Option<String>,
    #[serde(default)]
    pub hooks: Vec<HookHandlerConfig>,
}
```

**设计意图**：
- `matcher`: 可选的正则表达式，用于条件匹配（仅 SessionStart 支持）
- `hooks`: 该匹配条件下要执行的处理器列表
- 支持一个条件触发多个 Hook 的链式执行

### 4. Hook 处理器配置枚举 (`HookHandlerConfig`)

```rust
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type")]
pub(crate) enum HookHandlerConfig {
    #[serde(rename = "command")]
    Command {
        command: String,
        #[serde(default, rename = "timeout", alias = "timeoutSec")]
        timeout_sec: Option<u64>,
        #[serde(default)]
        r#async: bool,
        #[serde(default, rename = "statusMessage")]
        status_message: Option<String>,
    },
    #[serde(rename = "prompt")]
    Prompt {},
    #[serde(rename = "agent")]
    Agent {},
}
```

**设计意图**：
- 使用 **internally tagged** 枚举序列化（通过 `type` 字段区分）
- 支持三种处理器类型：
  - `command`: 执行外部命令（当前唯一实现）
  - `prompt`: LLM 提示模板（预留，未实现）
  - `agent`: 子 Agent 调用（预留，未实现）

**Command 类型字段**：
| 字段 | 类型 | 默认值 | 说明 |
|-----|------|-------|------|
| `command` | String | 必填 | 要执行的 shell 命令 |
| `timeout` / `timeoutSec` | Option<u64> | None | 超时秒数（别名支持两种命名） |
| `async` | bool | false | 是否异步执行（预留） |
| `statusMessage` | Option<String> | None | 状态提示消息 |

## 具体技术实现

### Serde 反序列化配置

```rust
#[serde(tag = "type")]  // Internally tagged enum
pub(crate) enum HookHandlerConfig {
    #[serde(rename = "command")]  // JSON 中的类型名
    Command { ... }
}
```

**反序列化示例**：
```json
{
  "type": "command",
  "command": "echo hello",
  "timeout": 30,
  "async": false,
  "statusMessage": "Running greeting hook"
}
```

### 默认值处理

```rust
#[serde(default)]           // 使用类型的 Default 实现
#[serde(default = "path")]  // 使用指定函数（本文件未使用）
```

**默认值逻辑**：
- `HooksFile::default()`: `hooks: HookEvents::default()`
- `HookEvents::default()`: 三个空 Vec
- `MatcherGroup::default()`: `matcher: None`, `hooks: []`
- `timeout_sec`: None（在 discovery 阶段处理为 600）
- `r#async`: false
- `status_message`: None

### 字段别名支持

```rust
#[serde(rename = "timeout", alias = "timeoutSec")]
timeout_sec: Option<u64>
```

支持两种 JSON 写法：
```json
{ "timeout": 30 }
{ "timeoutSec": 30 }
```

这是为了向后兼容或支持不同命名风格。

## 关键代码路径与文件引用

### 当前文件结构

```
codex-rs/hooks/src/engine/config.rs
├── HooksFile (struct) - 配置根
├── HookEvents (struct) - 事件分组
├── MatcherGroup (struct) - 匹配器组
└── HookHandlerConfig (enum) - 处理器配置
    ├── Command { ... }
    ├── Prompt { }
    └── Agent { }
```

### 消费者（下游）

```
codex-rs/hooks/src/engine/discovery.rs
└── discover_handlers()
    ├── HooksFile (解析根)
    ├── HookEvents (遍历事件)
    ├── MatcherGroup (处理匹配器)
    └── HookHandlerConfig (转换为 ConfiguredHandler)
```

### 配置流转路径

```
hooks.json (磁盘文件)
    ↓ serde_json::from_str
HooksFile (Rust 类型)
    ↓ discovery::discover_handlers
Vec<ConfiguredHandler> (运行时配置)
    ↓ ClaudeHooksEngine
Hook 执行
```

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `serde` | 反序列化派生宏 |

### 输入来源

- **文件系统**: `hooks.json` 配置文件（在 `discovery.rs` 中读取）

### 输出消费

| 消费者 | 消费内容 |
|-------|---------|
| `discovery.rs` | 所有配置类型，用于构建 `ConfiguredHandler` |

## 风险、边界与改进建议

### 已知风险

1. **预留类型未实现**
   - `Prompt` 和 `Agent` 类型在配置中可定义，但会被 `discovery.rs` 跳过并产生警告
   - 用户可能误以为配置了有效 Hook
   - **建议**：在文档中明确标注，或添加编译时警告

2. **正则表达式验证延迟**
   - `matcher` 字段在配置解析阶段不验证正则合法性
   - 非法正则在 `discovery.rs` 的 `append_group_handlers` 中才被发现
   - **建议**：可考虑在反序列化时验证（但会增加复杂性）

3. **布尔字段命名冲突**
   - `r#async` 使用原始标识符避免与 Rust 关键字冲突
   - JSON 中对应字段名为 `async`，可能导致某些 JSON 解析器困惑

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| JSON 缺少 `type` 字段 | 反序列化失败 | ✅ 合理，类型必须明确 |
| `type` 为未知值 | 反序列化失败 | ✅ 合理，拒绝未知类型 |
| `command` 为空字符串 | 在 discovery 阶段过滤 | ✅ 合理，提前发现无效配置 |
| `timeout` 为 0 | 在 discovery 阶段处理为 `max(1, timeout)` | ✅ 合理，防止立即超时 |
| `async: true` | 在 discovery 阶段跳过并警告 | ⚠️ 用户可能困惑 |

### 改进建议

1. **配置验证增强**
   ```rust
   // 添加验证方法
   impl HookHandlerConfig {
       pub fn validate(&self) -> Result<(), ValidationError> { ... }
   }
   ```

2. **文档内嵌**
   - 使用 `serde(deserialize_with)` 添加字段级文档
   - 生成 JSON Schema 供编辑器自动补全

3. **向后兼容策略**
   - 考虑添加 `version` 字段到 `HooksFile`
   - 为未来配置格式演进预留空间

4. **类型安全增强**
   - `timeout_sec` 可使用 `std::time::Duration` 类型
   - 添加 `NonZeroU64` 确保超时时间有效

### 配置示例

**完整配置示例**（`hooks.json`）：
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'Session started'",
            "timeout": 10,
            "statusMessage": "Initializing session"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "./validate-prompt.sh",
            "timeoutSec": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "./cleanup.sh"
          }
        ]
      }
    ]
  }
}
```

### 相关文件

- **Schema 定义**: `codex-rs/hooks/schema/generated/*.schema.json`
- **配置发现**: `codex-rs/hooks/src/engine/discovery.rs`
- **运行时配置**: `codex-rs/hooks/src/engine/mod.rs` (`ConfiguredHandler`)
