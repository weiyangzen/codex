# Research: presentation_artifact.md

**File Path:** `codex-rs/core/templates/tools/presentation_artifact.md`  
**Research Date:** 2026-03-23  
**Researcher:** Kimi Code CLI  

---

## 1. 场景与职责

### 1.1 文件定位

`presentation_artifact.md` 是 Codex CLI 工具链中的 **Artifact 工具模板文件**，位于 `codex-rs/core/templates/tools/` 目录下。该文件作为系统提示（system prompt）的一部分，向 AI 模型描述如何使用内置的 Presentation Artifact 工具来创建和编辑 PowerPoint 演示文稿。

### 1.2 核心职责

该模板文件承担以下关键职责：

1. **工具功能说明**：详细说明 `artifacts` 工具中 Presentation 相关 action 的完整功能集
2. **API 契约定义**：定义模型与 Artifact 运行时之间的交互协议（JSON 格式）
3. **使用示例提供**：通过具体示例展示如何调用各种 Presentation 操作
4. **约束与边界说明**：阐明状态管理、路径解析、单位制等关键约束

### 1.3 使用场景

| 场景 | 描述 |
|------|------|
| **创建演示文稿** | 用户请求创建新的 PowerPoint 文件（如季度报告、项目提案） |
| **编辑现有文稿** | 修改已创建的 artifact 中的幻灯片内容、样式、布局 |
| **导入/导出** | 从现有 PPTX 导入或导出为 PPTX/PNG/SVG 格式 |
| **协作审阅** | 添加评论线程、批注、回复等协作功能 |
| **程序化生成** | 基于数据动态生成图表、表格、多幻灯片内容 |

---

## 2. 功能点目的

### 2.1 功能架构概览

```
presentation_artifact.md 描述的功能体系
├── 生命周期管理 (Lifecycle)
│   ├── create - 创建新演示文稿
│   ├── import_pptx - 导入现有 PPTX
│   ├── export_pptx - 导出为 PPTX
│   ├── export_preview - 导出预览图
│   └── delete_artifact - 删除 artifact
├── 状态与元数据 (State & Metadata)
│   ├── get_summary - 获取文稿摘要
│   ├── list_slides - 列出所有幻灯片
│   ├── list_layouts - 列出可用布局
│   ├── inspect - 深度检查元素
│   ├── resolve - 解析元素引用
│   └── to_proto - 导出完整状态
├── 幻灯片操作 (Slide Operations)
│   ├── add_slide - 添加幻灯片
│   ├── insert_slide - 插入幻灯片
│   ├── duplicate_slide - 复制幻灯片
│   ├── move_slide - 移动幻灯片
│   ├── delete_slide - 删除幻灯片
│   ├── set_slide_layout - 设置布局
│   └── set_slide_background - 设置背景
├── 元素操作 (Element Operations)
│   ├── add_text_shape - 添加文本形状
│   ├── add_shape - 添加形状
│   ├── add_image - 添加图片
│   ├── add_table - 添加表格
│   ├── add_chart - 添加图表
│   ├── add_connector - 添加连接线
│   └── delete_element - 删除元素
├── 文本与样式 (Text & Styling)
│   ├── update_text - 更新文本
│   ├── set_rich_text - 设置富文本
│   ├── format_text_range - 格式化文本范围
│   ├── replace_text - 替换文本
│   ├── insert_text_after - 插入文本
│   ├── add_style - 添加命名样式
│   └── update_shape_style - 更新形状样式
├── 布局系统 (Layout System)
│   ├── create_layout - 创建自定义布局
│   ├── add_layout_placeholder - 添加占位符
│   ├── list_layout_placeholders - 列出布局占位符
│   └── list_slide_placeholders - 列出幻灯片占位符
├── 评论与协作 (Comments)
│   ├── set_comment_author - 设置评论作者
│   ├── add_comment_thread - 添加评论线程
│   ├── add_comment_reply - 添加回复
│   ├── toggle_comment_reaction - 切换反应
│   ├── resolve_comment_thread - 解决线程
│   └── reopen_comment_thread - 重新打开线程
├── 演讲者备注 (Speaker Notes)
│   ├── set_notes - 设置备注
│   ├── set_notes_rich_text - 设置富文本备注
│   ├── append_notes - 追加备注
│   ├── clear_notes - 清除备注
│   └── set_notes_visibility - 设置可见性
└── 版本控制 (Versioning)
    ├── record_patch - 记录补丁
    ├── apply_patch - 应用补丁
    ├── undo - 撤销
    └── redo - 重做
```

### 2.2 关键功能详解

#### 2.2.1 有状态设计

```markdown
- This is a stateful built-in tool. `artifact_id` values are returned by earlier calls and persist only for the current thread.
- Resume and fork do not restore live artifact state. Export files if you need a durable handoff.
```

**设计意图**：
- **线程级状态隔离**：每个 thread 拥有独立的 artifact 状态空间
- **显式持久化**：通过 `export_pptx` 实现跨会话持久化
- **Resume/Fork 限制**：明确告知模型状态不会在会话恢复时自动还原

#### 2.2.2 坐标与单位系统

```markdown
- Position and size values are in slide points.
```

**技术细节**：
- 使用 **slide points** 作为统一单位（1 point = 1/72 inch）
- 与 PowerPoint 内部单位系统保持一致
- 默认幻灯片尺寸：960×540（16:9 宽屏）或自定义

#### 2.2.3 Action 批处理机制

```markdown
- Every tool call uses a top-level `actions` array of sequential steps.
- Each call operates on a single top-level `artifact_id` when one is needed.
- If a call starts with `create` or `import_pptx`, later steps in the same call automatically reuse the returned artifact id.
```

**设计优势**：
- **原子性操作**：多个 action 在同一个调用中顺序执行
- **自动 ID 传递**：无需手动管理 `artifact_id` 的跨 action 传递
- **减少往返**：降低模型与运行时之间的通信开销

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 Action 请求格式

```json
{
  "artifact_id": "presentation_x",  // 可选，create/import 后自动继承
  "actions": [
    {
      "action": "add_text_shape",
      "args": {
        "slide_index": 0,
        "text": "Revenue up 24%",
        "position": {
          "left": 48,
          "top": 72,
          "width": 260,
          "height": 80
        }
      }
    }
  ]
}
```

#### 3.1.2 Position 结构

```typescript
interface Position {
  left: number;    // 距离左边缘的 points
  top: number;     // 距离上边缘的 points
  width: number;   // 宽度 points
  height: number;  // 高度 points
}
```

#### 3.1.3 Rich Text 结构

```typescript
interface RichTextRun {
  run: string;
  text_style?: {
    bold?: boolean;
    italic?: boolean;
    underline?: boolean;
    color?: string;  // hex color
    font_size?: number;
  };
}

type RichTextContent = RichTextRun[][];  // 段落数组，每段是 run 数组
```

### 3.2 关键流程

#### 3.2.1 Artifact 创建与编辑流程

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   User Request  │────▶│  Model Generates │────▶│  Artifacts Tool │
│  (Create PPT)   │     │  JS/JSON Actions │     │   Runtime       │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                            │
                              ┌─────────────────────────────┘
                              ▼
                       ┌─────────────────┐
                       │  @oai/artifact- │
                       │  tool Package   │
                       │  (Node Runtime) │
                       └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │  PPTX Generation│
                       │  (OOXML Format) │
                       └─────────────────┘
```

#### 3.2.2 运行时执行流程（Rust 侧）

```rust
// codex-rs/core/src/tools/handlers/artifacts.rs

pub struct ArtifactsHandler;

#[async_trait]
impl ToolHandler for ArtifactsHandler {
    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // 1. 解析 freeform JavaScript 输入
        let args = parse_freeform_args(&input)?;
        
        // 2. 创建 ArtifactRuntimeManager
        let client = ArtifactsClient::from_runtime_manager(
            default_runtime_manager(codex_home)
        );
        
        // 3. 执行构建请求
        let result = client.execute_build(ArtifactBuildRequest {
            source: args.source,
            cwd: turn.cwd.clone(),
            timeout: Some(Duration::from_millis(args.timeout_ms.unwrap_or(30000))),
            env: Default::default(),
        }).await;
        
        // 4. 格式化输出
        Ok(FunctionToolOutput::from_text(
            format_artifact_output(&output),
            Some(success),
        ))
    }
}
```

### 3.3 协议与命令

#### 3.3.1 Pragma 指令系统

```markdown
// codex-artifact-tool: timeout_ms=15000
```

**解析逻辑**（`artifacts.rs` 第 136-188 行）：

```rust
fn parse_freeform_args(input: &str) -> Result<ArtifactsToolArgs, FunctionCallError> {
    // 1. 检查首行是否以 "// codex-artifact-tool:" 开头
    let first_line = lines.next().unwrap_or_default();
    let Some(pragma) = parse_pragma_prefix(trimmed) else {
        // 无 pragma，直接返回整个输入作为 source
        return Ok(args);
    };
    
    // 2. 解析 key=value 对
    for token in directive.split_whitespace() {
        let (key, value) = token.split_once('=').ok_or_else(...)?;
        match key {
            "timeout_ms" => { /* 解析为 u64 */ }
            _ => { /* 返回错误：仅支持 timeout_ms */ }
        }
    }
    
    // 3. 剩余内容作为 JavaScript source
    args.source = rest.to_string();
    Ok(args)
}
```

#### 3.3.2 JavaScript 运行时封装

```rust
// codex-rs/artifacts/src/client.rs

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
    wrapped
}
```

### 3.4 运行时依赖

#### 3.4.1 JavaScript 运行时选择

```rust
// codex-rs/artifacts/src/runtime/js_runtime.rs

pub fn resolve_js_runtime_from_candidates(
    node_runtime: Option<JsRuntime>,
    electron_runtime: Option<JsRuntime>,
    codex_app_candidates: Vec<PathBuf>,
) -> Option<JsRuntime> {
    // 优先级：系统 Node > 系统 Electron > Codex App 内置 Electron
    node_runtime
        .or(electron_runtime)
        .or_else(|| {
            codex_app_candidates
                .into_iter()
                .find_map(|candidate| electron_runtime_from_path(&candidate))
        })
}
```

**运行时类型**：

| 类型 | 可执行文件 | 特殊要求 |
|------|-----------|---------|
| Node.js | `node` | 无 |
| Electron | `electron` | 需设置 `ELECTRON_RUN_AS_NODE=1` |
| Codex Desktop App | 应用 bundle 内 Electron | 自动检测各平台安装位置 |

#### 3.4.2 Artifact Runtime 包管理

```rust
// codex-rs/core/src/packages/versions.rs
pub(crate) const ARTIFACT_RUNTIME: &str = "2.5.6";
```

**包结构**：
```
~/.codex/packages/artifacts/
└── 2.5.6/
    ├── darwin-arm64/
    │   ├── package.json
    │   └── dist/artifact_tool.mjs
    ├── darwin-x64/
    ├── linux-arm64/
    ├── linux-x64/
    └── win32-x64/
```

---

## 4. 关键代码路径与文件引用

### 4.1 模板文件本身

| 文件 | 作用 |
|------|------|
| `codex-rs/core/templates/tools/presentation_artifact.md` | **本文件**，包含完整的 Presentation Artifact API 文档 |

### 4.2 工具注册与处理

| 文件 | 关键内容 |
|------|---------|
| `codex-rs/core/src/tools/handlers/artifacts.rs` | `ArtifactsHandler` 实现，处理 artifact 工具调用 |
| `codex-rs/core/src/tools/handlers/artifacts_tests.rs` | 单元测试，覆盖参数解析、运行时管理 |
| `codex-rs/core/src/tools/spec.rs` | `create_artifacts_tool()` 函数，定义工具 schema |
| `codex-rs/core/src/tools/handlers/mod.rs` | 模块导出，`pub use artifacts::ArtifactsHandler;` |

### 4.3 Artifact 运行时 crate

| 文件 | 关键内容 |
|------|---------|
| `codex-rs/artifacts/src/lib.rs` | crate 入口，导出公共 API |
| `codex-rs/artifacts/src/client.rs` | `ArtifactsClient`，执行 JS 构建请求 |
| `codex-rs/artifacts/src/runtime/manager.rs` | `ArtifactRuntimeManager`，运行时下载/缓存管理 |
| `codex-rs/artifacts/src/runtime/installed.rs` | `InstalledArtifactRuntime`，已安装运行时操作 |
| `codex-rs/artifacts/src/runtime/js_runtime.rs` | JavaScript 运行时检测与选择 |
| `codex-rs/artifacts/src/runtime/manifest.rs` | `ReleaseManifest`，发布清单结构 |
| `codex-rs/artifacts/src/runtime/error.rs` | 错误类型定义 |
| `codex-rs/artifacts/src/tests.rs` | 集成测试 |

### 4.4 功能开关

| 文件 | 关键内容 |
|------|---------|
| `codex-rs/core/src/features.rs` | `Feature::Artifact` 定义，默认 `default_enabled: false` |
| `codex-rs/core/src/tools/spec.rs:335-336` | 功能检查：`features.enabled(Feature::Artifact) && codex_artifacts::can_manage_artifact_runtime()` |

### 4.5 关键代码片段

#### 4.5.1 工具 Schema 定义

```rust
// codex-rs/core/src/tools/spec.rs:2069-2094

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

#### 4.5.2 功能检查

```rust
// codex-rs/core/src/tools/handlers/artifacts.rs:67-71

if !session.enabled(Feature::Artifact) {
    return Err(FunctionCallError::RespondToModel(
        "artifacts is disabled by feature flag".to_string(),
    ));
}
```

#### 4.5.3 工具注册

```rust
// codex-rs/core/src/tools/spec.rs:2922-2930

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

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-rs/core/templates/tools/presentation_artifact.md
    │
    ├── (被引用) codex-rs/core/src/tools/spec.rs
    │       └── create_artifacts_tool() 将模板内容作为工具描述
    │
    ├── (运行时) codex-rs/core/src/tools/handlers/artifacts.rs
    │       └── ArtifactsHandler::handle() 执行 artifact 构建
    │
    └── (运行时) codex-rs/artifacts crate
            ├── ArtifactsClient::execute_build()
            ├── ArtifactRuntimeManager (包管理)
            └── JsRuntime (Node/Electron 检测)
```

### 5.2 外部依赖

| 依赖 | 用途 | 版本/来源 |
|------|------|----------|
| `@oai/artifact-tool` | Artifact 运行时 JS 包 | GitHub Releases (v2.5.6) |
| Node.js | 首选 JS 运行时 | >= v22.22.0 (推荐) |
| Electron | 备选 JS 运行时 | 任意可用版本 |
| Codex Desktop App | 内置 Electron 备选 | macOS/Windows/Linux 安装版 |

### 5.3 交互协议

#### 5.3.1 模型 → Artifact 工具

```javascript
// 输入格式：Freeform JavaScript
// codex-artifact-tool: timeout_ms=30000

const presentation = await Presentation.create({ name: "Q2 Update" });
await presentation.addSlide({});
await presentation.addTextShape({
  slide_index: 0,
  text: "Revenue Growth",
  position: { left: 48, top: 72, width: 400, height: 60 }
});
const result = await presentation.exportPptx({ path: "q2-update.pptx" });
console.log(result);
```

#### 5.3.2 Artifact 工具 → 运行时

```rust
// Rust 侧构建请求
ArtifactBuildRequest {
    source: "// 上述 JavaScript 代码",
    cwd: "/current/working/dir",
    timeout: Some(Duration::from_secs(30)),
    env: BTreeMap::new(),
}
```

#### 5.3.3 运行时 → @oai/artifact-tool

```javascript
// 运行时生成的包装脚本
const artifactTool = await import("file:///path/to/artifact_tool.mjs");
globalThis.artifactTool = artifactTool;
// ... 导出挂载到 globalThis
// 用户代码在此执行
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 平台兼容性风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 运行时不可用 | 用户系统未安装 Node/Electron，且 Codex App 未安装 | 检测时返回友好错误，提示安装 Node |
| 平台检测失败 | `ArtifactRuntimePlatform::detect_current()` 返回 Err | 功能自动禁用，不暴露工具给模型 |
| 网络下载失败 | 首次使用需下载 runtime，可能因网络失败 | 支持离线缓存，提供手动安装指南 |

#### 6.1.2 安全与沙箱

```rust
// codex-rs/artifacts/src/client.rs:76-86

let mut command = Command::new(js_runtime.executable_path());
command.arg(&script_path).current_dir(&request.cwd);
command.stdout(Stdio::piped()).stderr(Stdio::piped());
if js_runtime.requires_electron_run_as_node() {
    command.env("ELECTRON_RUN_AS_NODE", "1");
}
```

**风险**：
- JS 代码在宿主系统直接执行，**无额外沙箱**
- 依赖 Node.js/Electron 的安全模型
- 用户代码可访问 `node:fs`, `node:child_process` 等模块

**建议**：
- 考虑引入 VM2 或类似沙箱机制
- 限制 `require()` 可访问的模块白名单

#### 6.1.3 状态隔离风险

```markdown
- Resume and fork do not restore live artifact state.
```

**风险**：
- 会话恢复后，`artifact_id` 引用失效
- 模型可能尝试操作已不存在的 artifact
- 用户期望的"继续编辑"可能无法实现

### 6.2 边界条件

#### 6.2.1 输入验证边界

```rust
// codex-rs/core/src/tools/handlers/artifacts.rs:190-208

fn reject_json_or_quoted_source(code: &str) -> Result<(), FunctionCallError> {
    let trimmed = code.trim();
    if trimmed.starts_with("```") {
        return Err(FunctionCallError::RespondToModel(
            "artifacts expects raw JavaScript source, not markdown code fences..."
        ));
    }
    // 拒绝 JSON 包装（{"code": "..."}）
    // ...
}
```

**边界**：
- 不接受 Markdown 代码块
- 不接受 JSON 包装
- 仅接受纯 JavaScript 源码

#### 6.2.2 超时边界

```rust
const DEFAULT_EXECUTION_TIMEOUT: Duration = Duration::from_secs(30);
```

- 默认 30 秒超时
- 可通过 `timeout_ms` pragma 自定义
- 超时后进程被强制终止

#### 6.2.3 资源限制

| 资源 | 限制 | 说明 |
|------|------|------|
| 内存 | 无显式限制 | 依赖系统 OOM 处理 |
| 磁盘 | 缓存目录空间 | `~/.codex/packages/artifacts/` |
| 网络 | 首次下载需外网 | GitHub Releases 访问 |

### 6.3 改进建议

#### 6.3.1 功能增强

1. **沙箱化执行**
   ```rust
   // 建议：使用 deno_core 或 quickjs 替代 Node.js
   // 提供更细粒度的权限控制
   ```

2. **状态持久化**
   ```rust
   // 建议：将会话状态序列化到 SQLite
   // 支持 Resume 时恢复 artifact 状态
   ```

3. **增量更新协议**
   ```rust
   // 当前：每次调用传递完整 actions 数组
   // 建议：支持增量 patch，减少数据传输
   ```

#### 6.3.2 模板文档改进

1. **添加版本信息**
   ```markdown
   - Artifact Tool Version: 2.5.6
   - Minimum Node Version: 22.22.0
   ```

2. **错误处理示例**
   ```markdown
   Example error handling:
   ```javascript
   try {
     await presentation.exportPptx({ path: "/invalid/path/file.pptx" });
   } catch (error) {
     console.error("Export failed:", error.message);
   }
   ```

3. **性能最佳实践**
   ```markdown
   - Batch multiple actions in a single call when possible
   - Use `record_patch` for complex multi-step edits
   - Prefer `update_text` over `set_rich_text` for simple text changes
   ```

#### 6.3.3 监控与可观测性

```rust
// 建议：添加 OpenTelemetry 埋点
// - artifact_build_duration
// - artifact_build_success/failure
// - artifact_runtime_download_duration
// - js_runtime_type (node/electron)
```

---

## 7. 附录

### 7.1 相关配置项

```toml
# ~/.codex/config.toml
[features]
artifact = true  # 启用 Artifact 工具
```

### 7.2 环境变量

| 变量 | 作用 |
|------|------|
| `ELECTRON_RUN_AS_NODE` | 强制 Electron 以 Node 模式运行 |
| `HOME`/`LOCALAPPDATA` | 检测 Codex App 安装位置 |

### 7.3 调试命令

```bash
# 检查 artifact runtime 是否可用
cargo test -p codex-artifacts can_manage_artifact_runtime

# 运行 artifact 测试
cargo test -p codex-core artifacts_tests

# 查看工具注册
cargo test -p codex-core spec_tests -- --nocapture
```

---

**End of Research Document**
