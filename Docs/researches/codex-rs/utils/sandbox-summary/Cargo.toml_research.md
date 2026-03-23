# Cargo.toml 研究文档

## 场景与职责

该文件是 `codex-utils-sandbox-summary` crate 的 Cargo 包清单，定义了包的元数据、依赖关系和构建配置。该 crate 是 Codex 项目中专门用于生成用户可读的沙箱策略和配置摘要的实用工具库，主要服务于 TUI 和 CLI 的输出格式化需求。

## 功能点目的

1. **包身份标识**: 定义 crate 名称、版本、Rust 版本和许可证信息
2. **依赖管理**: 声明编译时和开发时依赖
3. **工作区集成**: 通过 `workspace = true` 继承项目级统一配置
4. **代码质量**: 通过 `workspace = true` 继承项目级 lint 规则

## 具体技术实现

### 包元数据配置

```toml
[package]
name = "codex-utils-sandbox-summary"
version.workspace = true
edition.workspace = true
license.workspace = true
```

| 字段 | 配置 | 说明 |
|------|------|------|
| `name` | `"codex-utils-sandbox-summary"` | crate 名称，遵循 `codex-*` 前缀约定 |
| `version` | `workspace = true` | 继承工作区版本号，确保所有 crate 版本一致 |
| `edition` | `workspace = true` | 继承工作区 Rust 版本（如 2021 edition） |
| `license` | `workspace = true` | 继承工作区许可证配置 |

### Lint 配置

```toml
[lints]
workspace = true
```

继承项目根目录定义的 Clippy lint 规则，确保代码风格一致性。根据 `AGENTS.md`，项目要求：
- 折叠可合并的 if 语句
- 内联 format! 参数
- 使用方法引用替代闭包

### 依赖声明

```toml
[dependencies]
codex-core = { workspace = true }
codex-protocol = { workspace = true }

[dev-dependencies]
codex-utils-absolute-path = { workspace = true }
pretty_assertions = { workspace = true }
```

#### 编译依赖

| 依赖 | 用途 | 关键类型 |
|------|------|----------|
| `codex-core` | 访问配置类型 | `Config`, `WireApi` |
| `codex-protocol` | 访问协议类型 | `SandboxPolicy`, `NetworkAccess` |

#### 开发依赖

| 依赖 | 用途 |
|------|------|
| `codex-utils-absolute-path` | 测试中创建绝对路径 (`AbsolutePathBuf`) |
| `pretty_assertions` | 生成美观的测试失败 diff |

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/sandbox-summary/Cargo.toml` - 本包清单文件

### 工作区配置来源
- `codex-rs/Cargo.toml` - 工作区根配置，定义共享的 `version`、`edition`、`license` 和依赖版本

### 源码文件（受本配置管理）
- `codex-rs/utils/sandbox-summary/src/lib.rs` - 库入口，导出公共 API
- `codex-rs/utils/sandbox-summary/src/config_summary.rs` - `create_config_summary_entries()` 实现
- `codex-rs/utils/sandbox-summary/src/sandbox_summary.rs` - `summarize_sandbox_policy()` 实现

### 依赖的 crate 源码
- `codex-rs/core/src/config/mod.rs` - `Config` 结构体定义
- `codex-rs/protocol/src/protocol.rs` - `SandboxPolicy` 和 `NetworkAccess` 枚举定义

## 依赖与外部交互

### 类型依赖关系

```
codex-utils-sandbox-summary
├── codex-core::Config (用于读取工作目录、模型配置、权限设置)
├── codex-core::WireApi (用于判断 API 类型以显示 reasoning 配置)
├── codex-protocol::SandboxPolicy (核心类型，生成沙箱摘要)
└── codex-protocol::NetworkAccess (判断网络访问状态)
```

### 使用方（反向依赖）

根据代码搜索，该 crate 被以下组件使用：

| 使用方 | 用途 | 调用点 |
|--------|------|--------|
| `codex-rs/tui` | 状态卡片显示 | `tui/src/status/card.rs` 导入 `summarize_sandbox_policy` |
| `codex-rs/tui_app_server` | 状态显示 | `tui_app_server/src/status/card.rs` |
| `codex-rs/exec` | 人类可读输出 | `exec/src/event_processor_with_human_output.rs` 导入 `create_config_summary_entries` |

### 版本管理

由于工作区继承模式 (`workspace = true`)，该 crate 的版本与工作区保持一致。当发布新版本时：
1. 只需在工作区根 `Cargo.toml` 更新版本号
2. 所有成员 crate 自动继承新版本

## 风险、边界与改进建议

### 当前风险

1. **过度依赖 codex-core**: 
   - 该 crate 仅使用 `Config` 和 `WireApi` 两个类型
   - 但依赖整个 `codex-core` 会引入大量 transitive 依赖
   - 可能增加编译时间和二进制体积

2. **测试依赖的循环风险**:
   - 测试依赖 `codex-utils-absolute-path`
   - 如果 `codex-utils-absolute-path` 反过来依赖 `codex-core`，可能形成间接循环

3. **功能扩展的耦合**:
   - 当前设计紧密耦合 `Config` 结构
   - 如果配置结构重构，可能需要同步更新

### 边界情况

1. **平台差异**:
   - `SandboxPolicy::WorkspaceWrite` 中的 `/tmp` 处理是 Unix 特定的
   - Windows 路径格式在测试中有条件处理（`cfg!(windows)`）

2. **路径编码**:
   - 使用 `to_string_lossy()` 处理路径，可能丢失非 UTF-8 路径信息
   - 这在 `sandbox_summary.rs` 第 41 行处理 `writable_roots` 时体现

3. **可选字段处理**:
   - `Config` 中的 `model_reasoning_effort` 和 `model_reasoning_summary` 是 `Option` 类型
   - 摘要生成使用 `"none"` 作为默认值，这可能与用户的空值预期不同

### 改进建议

1. **依赖瘦身**:
   ```toml
   # 考虑将需要的类型提取到更小的 crate
   codex-config-types = { workspace = true }  # 仅包含配置类型定义
   codex-protocol = { workspace = true, features = ["sandbox"] }  # 可选特性
   ```

2. **功能门控**:
   ```toml
   [features]
   default = ["full"]
   full = ["codex-core", "codex-protocol"]
   minimal = ["codex-protocol"]  # 仅沙箱摘要，无需完整配置支持
   ```

3. **测试改进**:
   - 添加更多边界测试（如非 UTF-8 路径、空 writable_roots）
   - 添加快照测试验证摘要输出格式稳定性

4. **文档依赖**:
   ```toml
   [package]
   description = "Generate human-readable summaries of sandbox policies and configuration"
   keywords = ["codex", "sandbox", "summary", "config"]
   categories = ["command-line-utilities"]
   ```

5. **版本兼容性**:
   - 考虑添加 `rust-version` 字段明确声明最低支持的 Rust 版本
   - 如果协议类型可能变化，考虑添加版本特性门控

### 架构建议

当前 crate 位于 `utils/sandbox-summary`，作为小型工具 crate 是合适的。但如果功能扩展，可以考虑：

1. **合并到 codex-protocol**: 如果摘要逻辑与协议类型紧密耦合，可以作为 `SandboxPolicy` 的 display 方法
2. **拆分为两个 crate**: `config-summary` 和 `sandbox-summary`，分别服务不同使用方
3. **添加 CLI 工具**: 提供独立的命令行工具用于调试配置摘要
