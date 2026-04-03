# discovery.rs 深度研究文档

## 场景与职责

`discovery.rs` 是 Codex Hooks 系统的**配置发现与加载引擎**，负责从配置文件系统中扫描、解析、验证并构建运行时 Hook 配置。它是连接静态配置（`hooks.json` 文件）与动态执行的桥梁，承担着以下关键职责：

1. **配置层遍历**：遍历 `ConfigLayerStack` 中的所有配置层
2. **文件发现**：在每个配置层的配置目录中查找 `hooks.json` 文件
3. **配置解析**：解析 JSON 配置并转换为 Rust 类型
4. **验证与过滤**：验证正则表达式、过滤无效配置、处理未支持的特性
5. **运行时构建**：构建 `ConfiguredHandler` 列表供执行引擎使用

该模块实现了**分层配置**理念，允许在不同层级（用户级、项目级、工作区级）定义 Hook，并按优先级合并。

## 功能点目的

### 1. 发现结果封装 (`DiscoveryResult`)

```rust
pub(crate) struct DiscoveryResult {
    pub handlers: Vec<ConfiguredHandler>,
    pub warnings: Vec<String>,
}
```

**设计意图**：
- 分离正常结果（handlers）与非致命错误（warnings）
- 允许部分配置失败时继续加载其他有效配置
- 为上层提供诊断信息展示能力

### 2. 配置发现入口 (`discover_handlers`)

**核心流程**：
1. 检查 `config_layer_stack` 是否存在
2. 按优先级顺序遍历配置层（`LowestPrecedenceFirst`）
3. 在每个层的配置目录中查找 `hooks.json`
4. 读取、解析、处理配置文件
5. 收集所有 handler 和警告信息

**配置层优先级**：
```
低优先级 → 高优先级
系统级 → 用户级 → 项目级 → 工作区级
```

### 3. 匹配器有效性处理 (`effective_matcher`)

```rust
fn effective_matcher(
    event_name: HookEventName,
    matcher: Option<&str>,
) -> Option<&str> {
    match event_name {
        HookEventName::SessionStart => matcher,  // SessionStart 支持匹配器
        HookEventName::UserPromptSubmit | HookEventName::Stop => None,  // 其他事件忽略匹配器
    }
}
```

**设计决策**：
- 仅 `SessionStart` 支持条件匹配（如区分启动/恢复）
- `UserPromptSubmit` 和 `Stop` 的匹配器被忽略（但配置中可存在）
- 这种设计简化了事件处理逻辑，避免复杂的条件判断

### 4. Handler 构建与验证 (`append_group_handlers`)

**验证逻辑**：
1. **正则验证**：验证 `matcher` 是否为合法正则表达式
2. **异步检查**：`async: true` 的 Hook 被跳过（暂不支持）
3. **空命令检查**：空命令被跳过
4. **类型检查**：`Prompt` 和 `Agent` 类型被跳过（暂不支持）
5. **超时处理**：默认 600 秒，最小 1 秒

**Display Order 分配**：
- 使用递增的 `i64` 值确保 Handler 按声明顺序执行
- 跨配置文件保持全局顺序

## 具体技术实现

### 配置层遍历

```rust
for layer in config_layer_stack.get_layers(
    ConfigLayerStackOrdering::LowestPrecedenceFirst,
    /*include_disabled*/ false,
) {
    let Some(folder) = layer.config_folder() else { continue };
    let source_path = match folder.join("hooks.json") { ... };
    // 读取并解析...
}
```

**关键设计**：
- `LowestPrecedenceFirst` 确保低优先级配置先加载
- 相同事件的多层配置会合并（而非覆盖）
- `include_disabled: false` 跳过禁用层

### 事件分组处理

```rust
for group in parsed.hooks.session_start {
    append_group_handlers(
        &mut handlers,
        &mut warnings,
        &mut display_order,
        source_path.as_path(),
        HookEventName::SessionStart,
        effective_matcher(HookEventName::SessionStart, group.matcher.as_deref()),
        group.hooks,
    );
}
// 类似处理 user_prompt_submit 和 stop
```

**代码结构特点**：
- 三个事件类型的处理逻辑几乎相同
- 重复代码便于未来针对不同事件类型定制处理

### Handler 构建细节

```rust
HookHandlerConfig::Command {
    command,
    timeout_sec,
    r#async,
    status_message,
} => {
    if r#async {
        warnings.push("skipping async hook...".to_string());
        continue;
    }
    if command.trim().is_empty() {
        warnings.push("skipping empty hook command...".to_string());
        continue;
    }
    let timeout_sec = timeout_sec.unwrap_or(600).max(1);
    handlers.push(ConfiguredHandler {
        event_name,
        matcher: matcher.map(ToOwned::to_owned),
        command,
        timeout_sec,
        status_message,
        source_path: source_path.to_path_buf(),
        display_order,
    });
    display_order += 1;
}
```

## 关键代码路径与文件引用

### 当前文件结构

```
codex-rs/hooks/src/engine/discovery.rs
├── DiscoveryResult (struct) - 发现结果
├── discover_handlers (fn) - 主入口
├── effective_matcher (fn) - 匹配器过滤
├── append_group_handlers (fn) - Handler 构建
└── tests (mod) - 单元测试
```

### 调用方（上游）

```
codex-rs/hooks/src/engine/mod.rs
└── ClaudeHooksEngine::new()
    ├── schema_loader::generated_hook_schemas()  // 预加载 schema
    └── discovery::discover_handlers(config_layer_stack)  // 发现配置
```

### 被调用方（下游）

```
codex-rs/hooks/src/engine/config.rs
├── HooksFile (解析目标)
├── HookEvents (事件分组)
├── MatcherGroup (匹配器组)
└── HookHandlerConfig (处理器配置)
```

### 依赖类型

```
codex-rs/protocol/src/protocol.rs
├── HookEventName (事件类型枚举)

codex-rs/config/src/state.rs
├── ConfigLayerStack (配置层栈)
└── ConfigLayerStackOrdering (遍历顺序)

codex-rs/hooks/src/engine/mod.rs
└── ConfiguredHandler (运行时 Handler 结构)
```

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `serde_json` | JSON 解析 |
| `regex` | 正则表达式验证 |
| `codex_config` | 配置层管理 |
| `codex_protocol` | 协议类型（HookEventName） |

### 文件系统交互

| 路径模式 | 用途 |
|---------|------|
| `{config_folder}/hooks.json` | 配置文件查找 |

### 错误处理策略

| 错误场景 | 处理方式 | 是否中断 |
|---------|---------|---------|
| 配置层栈为空 | 返回空结果 | 否 |
| 路径解析失败 | 记录警告，继续 | 否 |
| 文件不存在 | 跳过，继续 | 否 |
| 文件读取失败 | 记录警告，继续 | 否 |
| JSON 解析失败 | 记录警告，继续 | 否 |
| 正则表达式无效 | 记录警告，跳过该组 | 否 |
| 异步 Hook | 记录警告，跳过 | 否 |
| 空命令 | 记录警告，跳过 | 否 |
| Prompt/Agent 类型 | 记录警告，跳过 | 否 |

## 风险、边界与改进建议

### 已知风险

1. **重复配置风险**
   - 多层配置可能导致同一 Hook 被多次执行
   - 当前设计是"追加"而非"覆盖"
   - **缓解**：`display_order` 确保可预测顺序

2. **性能问题**
   - 每个配置文件都进行完整的 JSON 解析
   - 大量配置文件时启动延迟增加
   - **建议**：考虑配置缓存或懒加载

3. **警告信息丢失**
   - 警告仅存储在内存中，不持久化
   - 用户可能忽略重要的配置问题
   - **建议**：添加日志记录或启动时警告展示

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 多个配置文件定义相同事件 | 全部加载，按顺序执行 | ✅ 符合分层配置理念 |
| 同一文件内重复事件名 | 按 JSON 数组顺序执行 | ✅ 合理 |
| 正则匹配器编译失败 | 整组 Hook 被跳过 | ⚠️ 过于严格？ |
| timeout 为 0 | 强制设为 1 秒 | ✅ 防止立即超时 |
| 超大配置文件 | 完整读入内存解析 | ⚠️ 可能存在 OOM 风险 |

### 改进建议

1. **配置合并策略**
   ```rust
   // 添加配置冲突检测
   pub enum MergeStrategy {
       Append,      // 当前行为
       Override,    // 高优先级覆盖低优先级
       Error,       // 冲突时报错
   }
   ```

2. **性能优化**
   - 添加配置文件修改时间缓存
   - 仅在文件变更时重新解析
   - 支持配置预编译（将 JSON 编译为二进制）

3. **诊断增强**
   ```rust
   pub struct DiscoveryDiagnostics {
       pub loaded_files: Vec<PathBuf>,
       pub warnings: Vec<Warning>,
       pub skipped_handlers: Vec<SkippedHandler>,
   }
   ```

4. **安全加固**
   - 添加配置文件数字签名验证
   - 限制可执行命令的白名单
   - 防止路径遍历攻击（`../hooks.json`）

### 测试覆盖

当前测试：
```rust
#[test]
fn user_prompt_submit_ignores_invalid_matcher_during_discovery() {
    // 验证 UserPromptSubmit 事件的无效匹配器被忽略
}
```

建议添加：
- 多层配置合并测试
- 错误处理测试（权限拒绝、损坏的 JSON）
- 大规模配置性能测试
- 并发安全测试

### 相关文件

- **配置定义**: `codex-rs/hooks/src/engine/config.rs`
- **引擎核心**: `codex-rs/hooks/src/engine/mod.rs`
- **配置层管理**: `codex-rs/config/src/state.rs`
- **协议类型**: `codex-rs/protocol/src/protocol.rs`
