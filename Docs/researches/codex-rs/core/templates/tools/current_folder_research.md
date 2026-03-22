# codex-rs/core/templates/tools 目录研究文档

## 目录概述

`codex-rs/core/templates/tools` 是 Codex CLI 项目中用于存放 **Artifact 工具（演示文稿/电子表格生成工具）** 相关模板文档的目录。该目录目前包含单个文件 `presentation_artifact.md`，它是 `artifacts` 内置工具的完整使用说明文档。

---

## 一、场景与职责

### 1.1 业务场景

该目录服务于 **Artifact 工具功能**，允许 AI 模型在 Codex CLI 会话中：

1. **创建和编辑 PowerPoint 演示文稿** - 通过 JavaScript API 操作幻灯片、形状、表格、图表等元素
2. **创建和编辑电子表格** - 通过 `@oai/artifact-tool` 包的 Workbook API
3. **导出为 PPTX/XLSX 文件** - 将内存中的 artifact 持久化为标准 Office 格式
4. **支持富文本、注释、主题样式** - 提供高级文档编辑能力

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **工具描述模板** | 为 `artifacts` 工具提供完整的自然语言使用说明 |
| **API 文档** | 详细描述所有支持的 actions 及其参数 |
| **使用示例** | 提供 JSON 格式的调用示例，供模型学习 |
| **功能边界说明** | 明确说明状态管理、路径解析、单位等约束 |

### 1.3 与相关组件的关系

```
┌─────────────────────────────────────────────────────────────────┐
│                     Codex CLI Core                               │
│  ┌─────────────────┐    ┌──────────────────┐    ┌─────────────┐ │
│  │  features.rs    │───▶│  tools/spec.rs   │───▶│ artifacts   │ │
│  │  Feature::Artifact│   │ create_artifacts_│    │   tool      │ │
│  └─────────────────┘    │     tool()       │    └──────┬──────┘ │
│                         └──────────────────┘           │        │
│                                 ▲                      │        │
│                                 │                      ▼        │
│  ┌─────────────────┐    ┌──────┴───────┐    ┌─────────────────┐ │
│  │ templates/tools/│    │ tools/handlers│    │ codex-artifacts │ │
│  │presentation_artifact│  │/artifacts.rs │───▶│     crate       │ │
│  │    .md          │────▶│ ArtifactsHandler│   │ (JS runtime)    │ │
│  └─────────────────┘    └──────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 presentation_artifact.md 内容结构

该文件包含以下功能模块的详细说明：

#### A. 生命周期管理 Actions
| Action | 用途 |
|--------|------|
| `create` | 创建新演示文稿，可指定幻灯片尺寸 |
| `import_pptx` | 从现有 PPTX 文件导入 |
| `export_pptx` | 导出为 PPTX 文件 |
| `export_preview` | 导出幻灯片预览图（PNG/JPEG/SVG） |
| `delete_artifact` | 删除 artifact |

#### B. 幻灯片管理 Actions
| Action | 用途 |
|--------|------|
| `add_slide` | 添加新幻灯片 |
| `insert_slide` | 在指定位置插入幻灯片 |
| `duplicate_slide` | 复制幻灯片 |
| `move_slide` | 移动幻灯片顺序 |
| `delete_slide` | 删除幻灯片 |
| `set_slide_layout` | 应用布局模板 |
| `set_slide_background` | 设置背景填充 |
| `set_active_slide` | 设置当前活动幻灯片 |

#### C. 元素操作 Actions
| Action | 用途 |
|--------|------|
| `add_text_shape` | 添加文本框 |
| `add_shape` | 添加形状（矩形、椭圆等） |
| `add_image` / `replace_image` | 添加/替换图片（支持本地路径、URI、base64） |
| `add_table` / `update_table_cell` / `merge_table_cells` | 表格操作 |
| `add_chart` / `update_chart` / `add_chart_series` | 图表操作 |
| `add_connector` | 添加连接线（直线/肘形/曲线） |

#### D. 文本与样式 Actions
| Action | 用途 |
|--------|------|
| `update_text` | 更新文本内容 |
| `set_rich_text` | 设置富文本（带格式） |
| `format_text_range` | 格式化文本范围（子串高亮） |
| `replace_text` / `insert_text_after` | 文本替换/插入 |
| `set_hyperlink` | 设置超链接（URL、幻灯片跳转、邮件等） |
| `update_shape_style` | 更新形状样式（位置、大小、填充、边框） |
| `bring_to_front` / `send_to_back` | 图层顺序调整 |

#### E. 布局与主题 Actions
| Action | 用途 |
|--------|------|
| `create_layout` | 创建自定义布局 |
| `add_layout_placeholder` | 向布局添加占位符 |
| `set_theme` | 设置主题 |
| `add_style` / `get_style` / `describe_styles` | 命名样式管理 |

#### F. 注释与协作 Actions
| Action | 用途 |
|--------|------|
| `set_comment_author` | 设置评论作者 |
| `add_comment_thread` / `add_comment_reply` | 添加评论/回复 |
| `resolve_comment_thread` / `reopen_comment_thread` | 解决/重新打开评论 |
| `toggle_comment_reaction` | 评论表情反应 |

#### G. 历史与状态 Actions
| Action | 用途 |
|--------|------|
| `undo` / `redo` | 撤销/重做 |
| `record_patch` / `apply_patch` | 记录/应用补丁 |
| `inspect` | 检查 artifact 结构 |
| `resolve` | 解析元素引用 |
| `to_proto` | 导出完整 JSON 快照 |

### 2.2 关键设计约束

1. **状态管理**
   - `artifact_id` 仅在当前线程内有效
   - Resume 和 fork 操作不恢复 live artifact 状态
   - 需要持久化时必须显式导出文件

2. **路径解析**
   - 相对路径从当前工作目录解析
   - 图片支持本地路径、远程 URI、base64 data_url

3. **单位系统**
   - 位置和尺寸值使用 "slide points"（幻灯片点）
   - 不随幻灯片尺寸变化而缩放

4. **执行模式**
   - 每个 tool call 使用顶层 `actions` 数组
   - 同一 call 中的 steps 按顺序执行
   - 以 `create` 或 `import_pptx` 开头的 call 会自动重用返回的 artifact_id

---

## 三、具体技术实现

### 3.1 工具注册流程

#### Step 1: Feature 开关检查 (`features.rs`)

```rust
// codex-rs/core/src/features.rs
pub enum Feature {
    // ...
    /// Enable native artifact tools.
    Artifact,  // key: "artifact", stage: UnderDevelopment, default: false
}

// 在 FEATURES 数组中定义
FeatureSpec {
    id: Feature::Artifact,
    key: "artifact",
    stage: Stage::UnderDevelopment,
    default_enabled: false,
},
```

#### Step 2: ToolsConfig 构建 (`tools/spec.rs`)

```rust
// codex-rs/core/src/tools/spec.rs:335-336
let include_artifact_tools =
    features.enabled(Feature::Artifact) && codex_artifacts::can_manage_artifact_runtime();

// 在 ToolsConfig 中存储
artifact_tools: include_artifact_tools,
```

#### Step 3: Tool Spec 创建 (`tools/spec.rs:2069-2094`)

```rust
fn create_artifacts_tool() -> ToolSpec {
    const ARTIFACTS_FREEFORM_GRAMMAR: &str = r#"
start: pragma_source | plain_source
pragma_source: PRAGMA_LINE NEWLINE js_source
plain_source: PLAIN_JS_SOURCE
js_source: JS_SOURCE
PRAGMA_LINE: /[ \t]*\/\/ codex-artifact-tool:[^\r\n]*/
NEWLINE: /\r?\n/
PLAIN_JS_SOURCE: /(?:\s*)(?:[^\s{\"`]|`[^`]|``[^`])[\s\S]*/
JS_SOURCE: /(?:\s*)(?:[^\s{\"`]|`[^`]|``[^`])[\s\S]*/
"#;

    ToolSpec::Freeform(FreeformTool {
        name: "artifacts".to_string(),
        description: "Runs raw JavaScript against the installed `@oai/artifact-tool` package...",
        format: FreeformToolFormat {
            r#type: "grammar".to_string(),
            syntax: "lark".to_string(),
            definition: ARTIFACTS_FREEFORM_GRAMMAR.to_string(),
        },
    })
}
```

#### Step 4: Handler 注册 (`tools/spec.rs:2922-2929`)

```rust
if config.artifact_tools {
    push_tool_spec(
        &mut builder,
        create_artifacts_tool(),
        /*supports_parallel_tool_calls*/ false,
        config.code_mode_enabled,
    );
    builder.register_handler("artifacts", artifacts_handler);
}
```

### 3.2 ArtifactsHandler 实现 (`tools/handlers/artifacts.rs`)

#### 核心数据结构

```rust
// 工具参数解析结构
#[derive(Debug, Clone, PartialEq, Eq)]
struct ArtifactsToolArgs {
    source: String,       // JavaScript 源代码
    timeout_ms: Option<u64>, // 可选超时（毫秒）
}

// Pragma 前缀常量
const ARTIFACT_TOOL_PRAGMA_PREFIX: &str = "// codex-artifact-tool:";
const DEFAULT_EXECUTION_TIMEOUT: Duration = Duration::from_secs(30);
```

#### 参数解析流程

```rust
fn parse_freeform_args(input: &str) -> Result<ArtifactsToolArgs, FunctionCallError> {
    // 1. 检查空输入
    if input.trim().is_empty() { ... }
    
    // 2. 尝试解析 pragma 行
    // 格式: // codex-artifact-tool: timeout_ms=15000
    let mut lines = input.splitn(2, '\n');
    let first_line = lines.next().unwrap_or_default();
    let rest = lines.next().unwrap_or_default();
    
    // 3. 解析 key=value 对
    for token in directive.split_whitespace() {
        let (key, value) = token.split_once('=').ok_or_else(...)?;
        match key {
            "timeout_ms" => { ... }
            _ => { ... }
        }
    }
    
    // 4. 拒绝 JSON 或带引号的源代码
    reject_json_or_quoted_source(rest)?;
}
```

#### 执行流程

```rust
async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
    // 1. 检查 Feature 开关
    if !session.enabled(Feature::Artifact) {
        return Err(FunctionCallError::RespondToModel(
            "artifacts is disabled by feature flag".to_string(),
        ));
    }
    
    // 2. 解析参数
    let args = parse_freeform_args(&input)?;
    
    // 3. 创建 ArtifactsClient
    let client = ArtifactsClient::from_runtime_manager(default_runtime_manager(
        turn.config.codex_home.clone(),
    ));
    
    // 4. 执行构建
    let result = client.execute_build(ArtifactBuildRequest {
        source: args.source,
        cwd: turn.cwd.clone(),
        timeout: Some(Duration::from_millis(args.timeout_ms.unwrap_or(...))),
        env: Default::default(),
    }).await;
    
    // 5. 格式化输出
    Ok(FunctionToolOutput::from_text(
        format_artifact_output(&output),
        Some(success),
    ))
}
```

### 3.3 codex-artifacts Crate 架构

#### 目录结构

```
codex-rs/artifacts/
├── src/
│   ├── lib.rs              # 公共 API 导出
│   ├── client.rs           # ArtifactsClient 实现
│   └── runtime/
│       ├── mod.rs          # Runtime 模块导出
│       ├── manager.rs      # ArtifactRuntimeManager
│       ├── installed.rs    # InstalledArtifactRuntime
│       ├── js_runtime.rs   # JS 运行时检测
│       ├── manifest.rs     # ReleaseManifest
│       └── error.rs        # 错误类型
```

#### 核心组件

**ArtifactsClient** (`client.rs`)

```rust
pub struct ArtifactsClient {
    runtime_source: RuntimeSource,
}

enum RuntimeSource {
    Managed(ArtifactRuntimeManager),    // 懒加载/下载运行时
    Installed(InstalledArtifactRuntime), // 已固定的运行时
}

pub async fn execute_build(
    &self,
    request: ArtifactBuildRequest,
) -> Result<ArtifactCommandOutput, ArtifactsError> {
    // 1. 解析运行时
    let runtime = self.resolve_runtime().await?;
    let js_runtime = runtime.resolve_js_runtime()?;
    
    // 2. 创建 staging 目录和脚本
    let staging_dir = TempDir::new()?;
    let script_path = staging_dir.path().join("artifact-build.mjs");
    let wrapped_script = build_wrapped_script(&build_entrypoint_url, &request.source);
    fs::write(&script_path, wrapped_script).await?;
    
    // 3. 执行 Node/Electron 进程
    let mut command = Command::new(js_runtime.executable_path());
    command.arg(&script_path).current_dir(&request.cwd);
    if js_runtime.requires_electron_run_as_node() {
        command.env("ELECTRON_RUN_AS_NODE", "1");
    }
    
    // 4. 运行并捕获输出
    run_command(command, timeout).await
}
```

**ArtifactRuntimeManager** (`runtime/manager.rs`)

```rust
pub struct ArtifactRuntimeManager {
    package_manager: PackageManager<ArtifactRuntimePackage>,
    config: ArtifactRuntimeManagerConfig,
}

pub struct ArtifactRuntimeManagerConfig {
    package_manager: PackageManagerConfig<ArtifactRuntimePackage>,
    release: ArtifactRuntimeReleaseLocator,
}

// 默认从 GitHub releases 下载
pub const DEFAULT_RELEASE_BASE_URL: &str = "https://github.com/openai/codex/releases/download/";
pub const DEFAULT_RELEASE_TAG_PREFIX: &str = "artifact-runtime-v";
```

**JS 运行时检测** (`runtime/js_runtime.rs`)

```rust
pub enum JsRuntimeKind {
    Node,      // 系统 Node.js
    Electron,  // 系统 Electron 或 Codex 桌面应用
}

pub struct JsRuntime {
    executable_path: PathBuf,
    kind: JsRuntimeKind,
}

// 运行时查找优先级：
// 1. 系统 node (which("node"))
// 2. 系统 electron (which("electron"))
// 3. Codex 桌面应用 bundle 中的 electron
//    - macOS: /Applications/Codex.app/Contents/MacOS/Codex
//    - Windows: %LOCALAPPDATA%/Programs/Codex/Codex.exe
//    - Linux: /opt/Codex/Codex 或 /usr/lib/Codex/Codex
```

### 3.4 脚本包装机制

```rust
fn build_wrapped_script(build_entrypoint_url: &Url, source: &str) -> String {
    let mut wrapped = String::new();
    
    // 1. 动态导入 artifact-tool 包
    wrapped.push_str("const artifactTool = await import(");
    wrapped.push_str(&serde_json::to_string(build_entrypoint_url.as_str()).unwrap());
    wrapped.push_str(");\n");
    
    // 2. 将导出内容挂载到 globalThis
    wrapped.push_str(r#"
globalThis.artifactTool = artifactTool;
for (const [name, value] of Object.entries(artifactTool)) {
  if (name === "default" || Object.prototype.hasOwnProperty.call(globalThis, name)) {
    continue;
  }
  globalThis[name] = value;
}
"#);
    
    // 3. 追加用户代码
    wrapped.push_str(source);
    wrapped.push('\n');
    wrapped
}
```

---

## 四、关键代码路径与文件引用

### 4.1 模板文件

| 文件路径 | 用途 | 引用位置 |
|---------|------|---------|
| `codex-rs/core/templates/tools/presentation_artifact.md` | Artifact 工具完整使用说明 | 通过 `create_artifacts_tool()` 嵌入到 ToolSpec::Freeform 的 description 字段 |

### 4.2 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/tools/spec.rs` | 定义 `create_artifacts_tool()`，构建 ToolSpec::Freeform |
| `codex-rs/core/src/tools/handlers/artifacts.rs` | `ArtifactsHandler` 实现，处理工具调用 |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs` | 单元测试 |
| `codex-rs/core/src/tools/handlers/mod.rs` | 导出 `ArtifactsHandler` |
| `codex-rs/core/src/tools/registry.rs` | 工具注册表，Handler 注册逻辑 |
| `codex-rs/core/src/features.rs` | `Feature::Artifact` 定义 |
| `codex-rs/core/src/packages/versions.rs` | 运行时版本号 `ARTIFACT_RUNTIME = "2.5.6"` |

### 4.3 codex-artifacts Crate 文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/artifacts/src/lib.rs` | 公共 API 导出 |
| `codex-rs/artifacts/src/client.rs` | `ArtifactsClient`，脚本执行主逻辑 |
| `codex-rs/artifacts/src/runtime/manager.rs` | `ArtifactRuntimeManager`，运行时下载/管理 |
| `codex-rs/artifacts/src/runtime/installed.rs` | `InstalledArtifactRuntime`，已安装运行时操作 |
| `codex-rs/artifacts/src/runtime/js_runtime.rs` | JS 运行时（Node/Electron）检测 |
| `codex-rs/artifacts/src/runtime/manifest.rs` | Release 清单结构 |
| `codex-rs/artifacts/src/runtime/error.rs` | 错误类型定义 |

### 4.4 关键代码流程图

```
用户输入 artifacts 工具调用
         │
         ▼
┌─────────────────────┐
│  tools/router.rs    │ ──▶ 路由到 ArtifactsHandler
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│ tools/handlers/     │ ──▶ 1. 检查 Feature::Artifact
│   artifacts.rs      │    2. 解析 pragma 参数
│                     │    3. 创建 ArtifactsClient
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│  artifacts/src/     │ ──▶ 1. resolve_runtime()
│    client.rs        │    2. 创建 staging 目录
│                     │    3. build_wrapped_script()
│                     │    4. spawn Node/Electron 进程
└─────────┬───────────┘
          ▼
┌─────────────────────┐
│  runtime/manager.rs │ ──▶ 1. 检查本地缓存
│                     │    2. 如缺失，从 GitHub releases 下载
│                     │    3. 返回 InstalledArtifactRuntime
└─────────────────────┘
```

---

## 五、依赖与外部交互

### 5.1 内部依赖

| 依赖 Crate | 用途 |
|-----------|------|
| `codex-artifacts` | Artifact 运行时管理和脚本执行 |
| `codex-package-manager` | 包下载、缓存、版本管理 |
| `codex-protocol` | ToolSpec、FreeformTool 等类型定义 |

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `@oai/artifact-tool` npm 包 | 实际的 PPTX/XLSX 生成逻辑（从 GitHub releases 下载） |
| Node.js 或 Electron | JavaScript 运行时 |

### 5.3 运行时版本管理

```rust
// codex-rs/core/src/packages/versions.rs
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6";
```

运行时下载 URL 格式：
```
https://github.com/openai/codex/releases/download/artifact-runtime-v{VERSION}/
```

### 5.4 平台支持

| 平台 | 支持状态 | 运行时查找路径 |
|------|---------|---------------|
| macOS | ✅ | `/Applications/Codex.app`, `~/Applications/Codex.app`,系统 node/electron |
| Windows | ✅ | `%LOCALAPPDATA%\Programs\Codex`, `%ProgramFiles%\Codex`，系统 node/electron |
| Linux | ✅ | `/opt/Codex`, `/usr/lib/Codex`，系统 node/electron |

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| **Feature 默认关闭** | `Feature::Artifact` 默认 `default_enabled: false`，用户需手动启用 | 文档说明启用方式：`[features].artifact = true` |
| **运行时下载失败** | 网络问题导致无法下载 `@oai/artifact-tool` | 提供离线安装指南；支持从 Codex 桌面应用复用 Electron |
| **JS 运行时不可用** | 系统未安装 Node/Electron，且未安装 Codex 桌面应用 | 清晰的错误提示，引导用户安装 Node.js |
| **状态不持久化** | Resume/fork 后 artifact 状态丢失 | 文档明确说明；建议用户及时 export |
| **超时风险** | 默认 30 秒超时可能不足以完成复杂 PPTX | 支持 `// codex-artifact-tool: timeout_ms=60000` pragma |

### 6.2 边界情况

1. **并发限制**: `supports_parallel_tool_calls: false`，同一时刻只能执行一个 artifacts 调用
2. **内存限制**: 大型 PPTX 可能占用大量内存，无显式内存限制
3. **路径安全**: 脚本在 `cwd` 下执行，受 sandbox 策略约束
4. **版本锁定**: 运行时版本硬编码在 `versions.rs`，升级需发版

### 6.3 改进建议

| 优先级 | 建议 | 理由 |
|--------|------|------|
| P1 | **增加模板引用内联检查** | 当前 `presentation_artifact.md` 内容通过字符串硬编码在 `create_artifacts_tool()`，建议增加编译时检查确保文档与代码同步 |
| P2 | **支持从模板文件动态加载** | 当前为编译时嵌入，可考虑运行时从 `codex_home/templates/` 加载，允许用户自定义 |
| P3 | **增加 Spreadsheet 专用模板** | 当前仅 `presentation_artifact.md`，建议增加 `spreadsheet_artifact.md` 专门说明 Workbook API |
| P4 | **优化运行时检测逻辑** | 当前优先系统 node，建议优先使用 Codex 桌面应用 bundle 的 Electron，版本更可控 |
| P5 | **增加 artifact 状态持久化** | 考虑将 artifact 状态保存到 SQLite，支持 resume 恢复 |
| P6 | **支持并发执行** | 评估 `supports_parallel_tool_calls: true` 的可行性，提升批量操作性能 |

### 6.4 测试覆盖

当前测试位于 `codex-rs/core/src/tools/handlers/artifacts_tests.rs`：

- ✅ 参数解析（无 pragma、有 pragma、拒绝 JSON）
- ✅ 运行时管理器配置验证
- ✅ 缓存运行时加载
- ✅ 输出格式化

建议补充：
- 集成测试：实际执行简单 JS 脚本
- 错误场景测试：运行时缺失、超时、语法错误
- 并发测试：验证串行执行约束

---

## 七、总结

`codex-rs/core/templates/tools/presentation_artifact.md` 是 Codex CLI **Artifact 工具功能** 的核心文档模板，它：

1. **为 AI 模型提供完整 API 参考** - 75+ 个 actions 的详细说明和示例
2. **通过 Freeform Tool 机制暴露** - 模型直接输出 JavaScript 代码执行
3. **依赖 codex-artifacts crate 实现** - 管理运行时下载和脚本执行
4. **受 Feature::Artifact 开关控制** - 默认关闭，需用户显式启用

该目录结构简单但承载复杂功能，是 Codex CLI 从"代码助手"向"文档生成助手"扩展的关键基础设施。
