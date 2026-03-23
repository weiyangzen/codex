# lib.rs 研究文档

## 文件信息
- **路径**: `codex-rs/exec/src/lib.rs`
- **大小**: ~68,476 bytes (约 1932 行，含测试)
- **定位**: Codex Exec 库核心，实现非交互式 Agent 执行

---

## 一、场景与职责

### 1.1 核心定位
`lib.rs` 是 `codex-exec` crate 的**库入口**，实现了非交互式（headless）Codex Agent 的完整生命周期管理。与 TUI 版本不同，exec 模式专注于：
- 单次/批量任务执行
- CI/CD 集成
- 脚本化工作流
- JSONL 输出支持

### 1.2 主要职责

| 职责域 | 说明 |
|-------|------|
| **配置管理** | 加载 config.toml，处理 CLI 覆盖，支持 OSS 模式 |
| **会话生命周期** | Thread 启动/恢复，Turn 执行，优雅关闭 |
| **事件处理** | 路由事件到人类可读或 JSONL 处理器 |
| **服务器请求处理** | 处理来自 app-server 的请求（认证刷新、审批等） |
| **信号处理** | Ctrl+C 中断处理，触发 turn/interrupt |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex 架构                                │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │  codex-cli  │    │  codex-tui  │    │    codex-exec       │ │
│  │ (交互式 REPL)│    │ (终端 UI)   │    │  (非交互式/脚本)     │ │
│  └──────┬──────┘    └──────┬──────┘    └──────────┬──────────┘ │
│         │                  │                      │            │
│         └──────────────────┼──────────────────────┘            │
│                            ▼                                   │
│              ┌─────────────────────────┐                       │
│              │ codex-app-server-client │                       │
│              │   (InProcessAppServer)  │                       │
│              └─────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 运行模式支持

```rust
enum InitialOperation {
    UserTurn {
        items: Vec<UserInput>,
        output_schema: Option<Value>,
    },
    Review {
        review_request: ReviewRequest,
    },
}
```

支持两种主要操作模式：
1. **UserTurn**: 标准对话模式，发送用户输入获取响应
2. **Review**: 代码审查模式，针对 Git 变更进行审查

### 2.2 双输出模式

通过 `json_mode` 布尔标志选择事件处理器：

| 模式 | 处理器 | 输出目标 | 用途 |
|-----|-------|---------|------|
| 人类可读 | `EventProcessorWithHumanOutput` | stderr | 终端查看 |
| JSONL | `EventProcessorWithJsonOutput` | stdout | 脚本解析 |

**关键设计**: 默认模式下 stdout 仅输出最终消息，确保管道可用性。

### 2.3 子命令支持

```rust
pub enum Command {
    Resume(ResumeArgs),  // 恢复历史会话
    Review(ReviewArgs),  // 代码审查
}
```

- **Resume**: 支持 `--last`（最近会话）、指定 session_id 或 thread 名称
- **Review**: 支持 `--uncommitted`、 `--base <branch>`、 `--commit <sha>` 或自定义指令

---

## 三、具体技术实现

### 3.1 主入口流程 (`run_main`)

```rust
pub async fn run_main(cli: Cli, arg0_paths: Arg0DispatchPaths) -> anyhow::Result<()> {
    // 1. 设置 originator 标识
    // 2. 解析颜色/ANSI 设置
    // 3. 加载配置 (config.toml + CLI 覆盖)
    // 4. 初始化 OSS 提供者 (如果 --oss)
    // 5. 设置 OpenTelemetry
    // 6. 启动 in-process app-server 客户端
    // 7. 执行 run_exec_session
}
```

### 3.2 会话执行流程 (`run_exec_session`)

```rust
async fn run_exec_session(args: ExecRunArgs) -> anyhow::Result<()> {
    // 1. 创建事件处理器 (人类可读或 JSONL)
    // 2. 检查 Git 仓库 (除非 --skip-git-repo-check)
    // 3. 启动 InProcessAppServerClient
    // 4. 处理 Resume/Start 逻辑，获取 thread_id
    // 5. 发送初始操作 (UserTurn 或 Review)
    // 6. 事件循环处理服务器事件
    // 7. 优雅关闭，处理 error_seen 退出码
}
```

### 3.3 事件循环核心

```rust
loop {
    tokio::select! {
        // 处理 Ctrl+C 中断
        maybe_interrupt = interrupt_rx.recv() => { /* 发送 turn/interrupt */ }
        
        // 接收服务器事件
        maybe_event = client.next_event() => {
            match server_event {
                ServerRequest(request) => handle_server_request(...).await,
                ServerNotification(notification) => { /* 错误处理 */ },
                LegacyNotification(notification) => { /* 主事件处理 */ },
                Lagged { skipped } => { /* 滞后警告 */ },
            }
        }
    }
}
```

### 3.4 服务器请求处理 (`handle_server_request`)

Exec 模式对交互式请求采取**拒绝策略**：

| 请求类型 | 处理方式 | 原因 |
|---------|---------|------|
| `McpServerElicitationRequest` | 自动取消 | 无交互能力 |
| `ChatgptAuthTokensRefresh` | 本地刷新 | 支持外部 ChatGPT 认证 |
| `CommandExecutionRequestApproval` | 拒绝 | 无交互能力 |
| `FileChangeRequestApproval` | 拒绝 | 无交互能力 |
| `ToolRequestUserInput` | 拒绝 | 无交互能力 |
| `DynamicToolCall` | 拒绝 | 无交互能力 |
| `ApplyPatchApproval` | 拒绝 | 无交互能力 |
| `ExecCommandApproval` | 拒绝 | 无交互能力 |
| `PermissionsRequestApproval` | 拒绝 | 无交互能力 |

### 3.5 Prompt 解析与编码

支持多编码输入：

```rust
fn decode_prompt_bytes(input: &[u8]) -> Result<String, PromptDecodeError> {
    // 1. 去除 UTF-8 BOM
    // 2. 拒绝 UTF-32 (LE/BE)
    // 3. 解码 UTF-16 LE/BE
    // 4. 默认 UTF-8
}
```

输入源优先级：
1. 命令行参数直接提供
2. `-` 强制从 stdin 读取
3. 无参数时检查 stdin 是否为管道

### 3.6 会话恢复逻辑 (`resolve_resume_path`)

```rust
async fn resolve_resume_path(config: &Config, args: &ResumeArgs) -> anyhow::Result<Option<PathBuf>> {
    if args.last {
        // 查找最近更新的 thread
        RolloutRecorder::find_latest_thread_path(...)
    } else if let Some(id_str) = args.session_id {
        // 按 UUID 或名称查找
        if Uuid::parse_str(id_str).is_ok() {
            find_thread_path_by_id_str(...)
        } else {
            find_thread_path_by_name_str(...)
        }
    }
}
```

---

## 四、关键代码路径与文件引用

### 4.1 模块结构

```
lib.rs
├── mod cli;                           // 命令行参数定义
├── mod event_processor;               // 事件处理器 trait
├── mod event_processor_with_human_output;  // 人类可读输出
├── mod event_processor_with_jsonl_output;  // JSONL 输出
├── pub mod exec_events;               // 事件类型定义
│
├── pub use cli::{Cli, Command, ReviewArgs};  // 公开导出
│
├── run_main()                         // 异步入口
├── run_exec_session()                 // 会话执行
├── handle_server_request()            // 服务器请求处理
├── resolve_resume_path()              // 会话恢复
├── resolve_prompt()                   // Prompt 解析
├── build_review_request()             // 审查请求构建
└── [测试模块]                          // 单元测试
```

### 4.2 核心依赖 Crate

| Crate | 用途 |
|-------|------|
| `codex-app-server-client` | In-process app-server 通信 |
| `codex-app-server-protocol` | JSON-RPC 协议类型 |
| `codex-core` | 配置、认证、工具函数 |
| `codex-protocol` | 核心协议事件类型 |
| `codex-utils-*` | 各类工具函数 |

### 4.3 配置覆盖链

```
config.toml 默认值
    │
    ▼
config_profile (指定 profile)
    │
    ▼
CLI 参数 (-c key=value)
    │
    ▼
专用参数 (--model, --sandbox 等)
    │
    ▼
HarnessOverrides (代码级覆盖)
```

### 4.4 测试组织

```
tests/
├── all.rs                    # 测试入口
├── event_processor_with_json_output.rs  # JSON 处理器单元测试
└── suite/
    ├── mod.rs
    ├── add_dir.rs            # --add-dir 测试
    ├── apply_patch.rs        # 补丁应用测试
    ├── auth_env.rs           # 认证环境变量测试
    ├── ephemeral.rs          # 临时模式测试
    ├── mcp_required_exit.rs  # MCP 必需服务器失败测试
    ├── originator.rs         # 来源标识测试
    ├── output_schema.rs      # 输出 schema 测试
    ├── resume.rs             # 会话恢复测试
    ├── sandbox.rs            # 沙盒策略测试
    └── server_error_exit.rs  # 服务器错误退出码测试
```

---

## 五、依赖与外部交互

### 5.1 关键外部系统

```
┌─────────────────────────────────────────────────────────────┐
│                      lib.rs (codex-exec)                    │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ InProcessApp    │  │   Config        │  │   Auth      │ │
│  │ ServerClient    │  │   (codex-core)  │  │   Manager   │ │
│  └────────┬────────┘  └─────────────────┘  └──────┬──────┘ │
│           │                                        │        │
│           ▼                                        ▼        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              codex-app-server (in-process)           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │   Agent     │  │   Tools     │  │   MCP       │  │   │
│  │  │   Runtime   │  │   (shell)   │  │   Servers   │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 环境变量依赖

| 变量 | 用途 |
|-----|------|
| `TRACEPARENT` | OpenTelemetry 分布式追踪上下文 |
| `TERM` | 终端类型检测 (影响 ANSI 输出) |
| `CODEX_SANDBOX_NETWORK_DISABLED` | 沙盒网络禁用标志 |

### 5.3 文件系统交互

- `~/.codex/config.toml`: 配置文件
- `~/.codex/threads/`: 会话存储
- `--output-last-message`: 最终消息输出文件
- `--output-schema`: JSON Schema 文件

---

## 六、风险、边界与改进建议

### 6.1 当前风险

1. **审批请求自动拒绝**: Exec 模式对所有审批请求返回拒绝，可能导致任务失败而非暂停
2. **MCP 服务器初始化失败**: 必需 MCP 服务器失败时直接退出，无重试机制
3. **Git 仓库检查**: 默认强制要求 Git 仓库，可能限制某些用例
4. **事件流滞后**: 使用 `tokio::sync::broadcast`，可能丢失事件（已处理但仅警告）

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 空 stdin + 无 prompt 参数 | 错误退出 |
| UTF-32 编码输入 | 明确拒绝，提示转换 |
| 无效 UTF-8 | 报告无效字节位置 |
| 中断信号 (Ctrl+C) | 发送 turn/interrupt，优雅关闭 |
| 服务器错误 + will_retry=true | 不设置 error_seen |
| 子 Agent 关闭 | 不触发主循环退出 |

### 6.3 改进建议

| 优先级 | 建议 | 理由 |
|-------|------|------|
| 高 | 添加 `--approval-policy=auto` 支持 | 当前自动拒绝可能过于严格 |
| 中 | 支持 MCP 服务器重试/等待 | 提高 CI 稳定性 |
| 中 | 分离配置验证与执行 | 提前发现配置错误 |
| 低 | 添加 `--dry-run` 模式 | 验证配置不实际执行 |
| 低 | 支持更多编码 (如 GBK) | 提升兼容性 |

### 6.4 技术债务

1. **Legacy Notification 桥接**: `decode_legacy_notification` 是过渡代码，应迁移到 typed ServerNotification
2. **SessionConfigured 合成**: `session_configured_from_thread_response` 是兼容性桥接，部分字段为占位符
3. **TODO 注释**: 代码中有多个 TODO 标记待改进点

### 6.5 测试建议

当前测试覆盖：
- ✅ Prompt 编码解码
- ✅ Review 请求构建
- ✅ 配置参数转换
- ✅ Thread 启动/恢复参数

建议补充：
- 中断信号处理
- MCP 服务器失败场景
- 事件流滞后处理
- 服务器请求拒绝逻辑
