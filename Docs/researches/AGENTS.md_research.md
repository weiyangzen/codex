# AGENTS.md 研究文档

## 场景与职责

`AGENTS.md` 是 Codex 项目的核心开发指南文件，专门为 AI 助手（Agents）和自动化工具提供详细的编码规范、最佳实践和工作流程指导。该文件位于项目根目录，是 `README.md` 的补充，专注于机器可读的开发指令而非面向人类的概览信息。

文件的设计理念是：
- `README.md` 面向人类贡献者：快速开始、项目描述、贡献指南
- `AGENTS.md` 面向 AI 助手：构建步骤、测试、编码约定

## 功能点目的

### 1. Rust 代码规范（codex-rs）

#### 1.1 命名约定
- Crate 名称前缀：`codex-`（如 `codex-core`）
- 使用内联变量格式化：`format!("{variable}")` 而非 `format!("{}", variable)`

#### 1.2 工具安装要求
```markdown
- Install any commands the repo relies on (for example `just`, `rg`, or `cargo-insta`)
```

#### 1.3 沙箱环境变量限制
**重要限制**：
```markdown
Never add or modify any code related to `CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR` or `CODEX_SANDBOX_ENV_VAR`.
```

**技术背景**：
- `CODEX_SANDBOX_NETWORK_DISABLED=1`：Shell 工具运行时设置，表示网络被禁用
- `CODEX_SANDBOX=seatbelt`：Seatbelt 沙箱运行时设置
- 这些检查用于在受限环境中提前退出某些测试

#### 1.4 Clippy 规则遵循
强制遵循的 lint 规则：
- `collapsible_if`：合并嵌套 if 语句
- `uninlined_format_args`：内联 format! 参数
- `redundant_closure_for_method_calls`：使用方法引用替代闭包

#### 1.5 API 设计原则
- 避免 `foo(false)` 或 `bar(None)` 这样的模糊参数
- 使用枚举、命名方法、newtypes 等自文档化 API
- 当必须使用位置参数时，使用 `/*param_name*/` 注释

#### 1.6 模块大小限制
```markdown
- Target Rust modules under 500 LoC, excluding tests
- If a file exceeds roughly 800 LoC, add new functionality in a new module
```

**高风险文件列表**（需要特别注意）：
- `codex-rs/tui/src/app.rs`
- `codex-rs/tui/src/bottom_pane/chat_composer.rs`
- `codex-rs/tui/src/bottom_pane/footer.rs`
- `codex-rs/tui/src/chatwidget.rs`
- `codex-rs/tui/src/bottom_pane/mod.rs`

### 2. 开发工作流程

#### 2.1 格式化
```markdown
Run `just fmt` (in `codex-rs` directory) automatically after you have finished making Rust code changes
```

#### 2.2 测试策略
1. 首先运行特定项目的测试：`cargo test -p codex-tui`
2. 然后运行完整测试套件（如果修改了 common/core/protocol）
3. 避免常规使用 `--all-features`（增加构建矩阵和磁盘使用）

#### 2.3 Lint 修复
```markdown
Before finalizing a large change to `codex-rs`, run `just fix -p <project>`
```

### 3. TUI 开发规范

#### 3.1 样式约定
- 使用 ratatui 的 `Stylize` trait
- 基本 spans：`"text".into()`
- 样式 spans：`"text".red()`, `"text".green()`, `"text".dim()`
- 避免硬编码白色（`.white()`）

#### 3.2 代码约定
- 当 `codex-rs/tui` 有变更时，同步更新 `codex-rs/tui_app_server`
- 使用简洁的转换：`vec![...].into()` 构建 Line

#### 3.3 文本换行
- 纯字符串使用 `textwrap::wrap`
- ratatui Line 使用 `tui/src/wrapping.rs` 的辅助函数

### 4. 测试规范

#### 4.1 快照测试（insta）
**要求**：
```markdown
any change that affects user-visible UI (including adding new UI) must include corresponding `insta` snapshot coverage
```

**工作流程**：
```bash
cargo test -p codex-tui
cargo insta pending-snapshots -p codex-tui
cargo insta show -p codex-tui path/to/file.snap.new
cargo insta accept -p codex-tui
```

#### 4.2 测试断言
- 使用 `pretty_assertions::assert_eq`
- 优先比较整个对象而非逐个字段
- 避免在测试中修改进程环境

#### 4.3 二进制文件生成
- 使用 `codex_utils_cargo_bin::cargo_bin("...")` 替代 `assert_cmd`
- 使用 `codex_utils_cargo_bin::find_resource!` 定位测试资源

#### 4.4 集成测试（core）
- 使用 `core_test_support::responses` 工具
- `mount_sse*` 辅助函数返回 `ResponseMock`
- 使用 `ev_*` 构造器和 `sse(...)` 构建 SSE payload

### 5. App-server API 开发规范

#### 5.1 版本策略
```markdown
All active API development should happen in app-server v2. Do not add new API surface area to v1.
```

#### 5.2 命名约定
- `*Params`：请求 payload
- `*Response`：响应
- `*Notification`：通知
- RPC 方法格式：`<resource>/<method>`（如 `thread/read`, `app/list`）

#### 5.3 序列化规范
- 使用 `#[serde(rename_all = "camelCase")]`（config RPC 除外，使用 snake_case）
- 使用 `#[ts(export_to = "v2/")]` 导出 TypeScript 类型
- **禁止** `#[serde(skip_serializing_if = "Option::is_none")]`（v2 API）

#### 5.4 请求参数规范
- 可选字段使用 `#[ts(optional = nullable)]`
- 可选集合使用 `Option<Vec<T>>` + `#[ts(optional = nullable)]`
- 布尔字段省略表示 `false`：
  ```rust
  #[serde(default, skip_serializing_if = "std::ops::Not::not")]
  pub field: bool
  ```

#### 5.5 列表方法分页
```rust
// 请求
pub cursor: Option<String>
pub limit: Option<u32>

// 响应
pub data: Vec<...>
pub next_cursor: Option<String>
```

#### 5.6 开发工作流程
- API 变更时更新 `app-server/README.md`
- 运行 `just write-app-server-schema` 重新生成 schema fixtures
- 运行 `cargo test -p codex-app-server-protocol` 验证

## 具体技术实现

### 文件结构

```markdown
# Rust/codex-rs
## 开发规范
## TUI 样式约定
## TUI 代码约定
## 测试规范
### 快照测试
### 测试断言
### 二进制文件生成
### 集成测试
## App-server API 开发规范
### 核心规则
### 请求参数规范
### 开发工作流程
```

### 与其他文件的关联

| 文件 | 关系 |
|------|------|
| `README.md` | 人类可读的项目概览 |
| `codex-rs/tui/styles.md` | TUI 样式详细文档 |
| `app-server/README.md` | App-server API 文档 |
| `codex-rs/core/config.schema.json` | Config 类型 schema |
| `codex-rs/Cargo.toml` | 依赖定义 |
| `justfile` | 命令定义 |

## 关键代码路径与文件引用

### 核心代码路径

1. **codex-rs/tui/src/**
   - `app.rs` - TUI 主应用（大文件，需要拆分）
   - `bottom_pane/chat_composer.rs` - 聊天编辑器
   - `bottom_pane/footer.rs` - 底部栏
   - `chatwidget.rs` - 聊天组件
   - `wrapping.rs` - 文本换行辅助函数

2. **codex-rs/tui_app_server/**
   - 与 `codex-rs/tui` 并行实现

3. **codex-rs/core/**
   - `config.schema.json` - 配置 schema
   - 测试支持：`core/tests/common/`

4. **app-server-protocol/src/protocol/**
   - `common.rs` - 通用协议定义
   - `v2.rs` - v2 API 定义

5. **codex-rs/utils/cargo-bin/**
   - `README.md` - runfiles 策略说明
   - 测试二进制工具

### 工具链依赖

```bash
# 必需工具
just        # 命令运行器
rg          # ripgrep（可能用于搜索）
cargo-insta # 快照测试工具

# 开发工具
cargo-dylint      # 自定义 lint
cargo-shear       # 未使用依赖检查
cargo-nextest     # 更快的测试运行器
cargo-chef        # Docker 构建优化
```

## 依赖与外部交互

### 外部服务

1. **BuildBuddy**
   - 远程缓存和远程执行
   - 配置在 `.bazelrc` 中

2. **GitHub**
   - CI/CD 工作流（`.github/workflows/`）
   - 代码审查

### 工具链

1. **Rust 工具链**
   - 版本：1.93.0（来自 `MODULE.bazel`）
   - Edition：2024（来自 `codex-rs/Cargo.toml`）

2. **Bazel**
   - 版本：9.0.0（来自 `.bazelversion`）
   - 与 Cargo 并行使用

3. **pnpm**
   - 版本：10.29.3（来自 `package.json`）
   - 用于 Node.js 部分

### 沙箱环境

```rust
// 代码中检查的环境变量
CODEX_SANDBOX_NETWORK_DISABLED  // 网络禁用检查
CODEX_SANDBOX=seatbelt          // Seatbelt 沙箱检查
```

**用途**：
- 在受限环境中提前退出某些测试
- 确保测试在适当的环境中运行

## 风险、边界与改进建议

### 潜在风险

1. **文件过大**
   - 当前 `AGENTS.md` 约 15KB，195 行
   - 随着项目发展可能变得难以维护

2. **信息重复**
   - 某些内容可能在 `README.md` 或其他文档中重复
   - 需要保持同步

3. **规范执行**
   - 依赖开发者/AI 助手主动阅读
   - 没有自动化检查确保遵循

4. **版本漂移**
   - 工具版本更新（如 Rust 1.93.0 -> 新版本）
   - 需要更新相关指令

### 边界情况

1. **多语言项目**
   - 当前主要关注 Rust（codex-rs）
   - TypeScript/JavaScript 部分的规范较少

2. **Bazel vs Cargo**
   - 两者都可以构建项目
   - 某些指令可能只适用于一种工具链

3. **平台差异**
   - macOS、Linux、Windows 的差异
   - 某些工具可能在特定平台不可用

### 改进建议

1. **添加目录和索引**
   ```markdown
   ## 目录
   - [Rust 开发规范](#rust-开发规范)
   - [TUI 开发](#tui-开发)
   - [测试规范](#测试规范)
   - [API 开发](#api-开发)
   
   <!-- 添加锚点链接 -->
   ```

2. **添加 TypeScript/JavaScript 规范**
   ```markdown
   ## TypeScript/codex-cli
   - 代码风格（Prettier 配置）
   - 测试规范（Jest/Vitest）
   - 构建流程
   ```

3. **添加检查清单**
   ```markdown
   ## PR 提交检查清单
   - [ ] 运行 `just fmt`
   - [ ] 运行相关测试
   - [ ] 更新文档（如果修改 API）
   - [ ] 更新 schema（如果修改 ConfigToml）
   ```

4. **自动化验证**
   ```bash
   # 添加脚本检查 AGENTS.md 中的指令是否被遵循
   # 例如：检查模块大小、检查命名约定等
   ```

5. **版本信息**
   ```markdown
   ## 工具版本
   - Rust: 1.93.0
   - Bazel: 9.0.0
   - pnpm: 10.29.3
   - Node.js: >=22
   ```

6. **添加故障排除**
   ```markdown
   ## 常见问题
   ### 测试失败
   - 检查沙箱环境变量
   - 确保安装了所有工具
   
   ### 构建失败
   - Bazel: 检查 MODULE.bazel.lock
   - Cargo: 检查 Cargo.lock
   ```

7. **定期审查流程**
   - 每季度审查 AGENTS.md 的相关性
   - 随着项目演进更新规范
   - 收集开发者反馈

### 使用示例

```bash
# 新开发者/AI 助手入门流程
1. 阅读 README.md 了解项目概览
2. 阅读 AGENTS.md 了解开发规范
3. 安装必需工具（just, cargo-insta 等）
4. 运行 just install 设置环境
5. 运行 just test 验证设置

# 开发工作流程
1. 修改代码
2. 运行 just fmt 格式化
3. 运行 cargo test -p <project> 测试
4. 运行 just fix -p <project> 修复 lint
5. 提交 PR
```

### 与其他项目的对比

| 项目 | 类似文件 | 说明 |
|------|---------|------|
| React | CONTRIBUTING.md | 人类导向的贡献指南 |
| Rust | rustc-dev-guide | 详细的开发文档 |
| Kubernetes | community/ | 社区和贡献指南 |
| Codex | AGENTS.md | AI 助手专用的开发指南 |

**AGENTS.md 的独特之处**：
- 明确面向 AI 助手
- 包含具体的命令和工具
- 强调自动化和可重现性
