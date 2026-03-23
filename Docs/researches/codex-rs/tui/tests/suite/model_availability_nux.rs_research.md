# model_availability_nux.rs 研究文档

## 场景与职责

`codex-rs/tui/tests/suite/model_availability_nux.rs` 是一个端到端集成测试，验证 **模型可用性 NUX（New User Experience）** 功能在会话恢复时的正确行为。

该测试确保：当用户恢复一个已存在的会话时，系统**不会**重复消耗模型可用性提示的显示次数配额。这是为了防止用户在切换会话时反复看到相同的"新模型可用"提示。

## 功能点目的

1. **配额保护**: 验证 `resume` 操作不会增加 `model_availability_nux` 的显示计数
2. **回归测试**: 防止未来代码更改破坏此行为
3. **端到端验证**: 通过真实 PTY 进程测试完整用户流程

## 具体技术实现

### 测试流程架构

```
┌─────────────────────────────────────────────────────────────────┐
│  Test: resume_startup_does_not_consume_model_availability_nux   │
├─────────────────────────────────────────────────────────────────┤
│  1. 创建临时 CODEX_HOME 目录                                     │
│  2. 修改 models.json 添加 availability_nux 配置                  │
│  3. 创建 config.toml 设置初始计数为 1                            │
│  4. 执行 `codex exec` 创建种子会话                                │
│  5. 通过 PTY 启动 `codex resume --last`                          │
│  6. 模拟终端交互（响应光标位置查询）                              │
│  7. 验证 config.toml 中计数仍为 1（未被消耗）                     │
└─────────────────────────────────────────────────────────────────┘
```

### 关键代码解析

#### 1. 测试配置准备
```rust
// 读取并修改模型目录，为第一个模型添加 availability_nux
let source_catalog_path = codex_utils_cargo_bin::find_resource!("../core/models.json")?;
let mut source_catalog: JsonValue = serde_json::from_str(&source_catalog)?;
// ... 移除所有模型的 availability_nux，然后为第一个模型添加
first_model_object.insert(
    "availability_nux".to_string(),
    serde_json::json!({
        "message": "Model now available",
    }),
);
```

#### 2. 配置文件生成
```rust
let config_contents = format!(
    r#"model = "{model_slug}"
model_provider = "openai"
model_catalog_json = "{catalog_display}"

[projects."{repo_root_display}"]
trust_level = "trusted"

[tui.model_availability_nux]
"{model_slug}" = 1
"#  // 初始计数设为 1
);
```

#### 3. 种子会话创建
```rust
let exec_output = std::process::Command::new(&codex)
    .arg("exec")
    .arg("--skip-git-repo-check")
    .arg("-C")
    .arg(&repo_root)
    .arg("seed session for resume")
    .env("CODEX_HOME", codex_home.path())
    .env("OPENAI_API_KEY", "dummy")
    .env("CODEX_RS_SSE_FIXTURE", fixture_path)  // 使用 mock SSE 响应
    .env("OPENAI_BASE_URL", "http://unused.local")
    .output()?;
```

#### 4. PTY 会话恢复测试
```rust
let spawned = codex_utils_pty::spawn_pty_process(
    codex.to_string_lossy().as_ref(),
    &args,  // ["resume", "--last", "--no-alt-screen", ...]
    &repo_root,
    &env,
    &None,
    codex_utils_pty::TerminalSize::default(),
).await?;
```

#### 5. 终端交互模拟
```rust
// 响应 TUI 的光标位置查询 ESC[6n，返回位置 ESC[1;1R
if chunk.windows(4).any(|window| window == b"\x1b[6n") {
    let _ = writer_tx.send(b"\x1b[1;1R".to_vec()).await;
}
```

#### 6. 断言验证
```rust
let shown_count = config
    .get("tui")
    .and_then(|tui| tui.get("model_availability_nux"))
    .and_then(|nux| nux.get(&model_slug))
    .and_then(toml::Value::as_integer)
    .context("missing tui.model_availability_nux count")?;

assert_eq!(shown_count, 1);  // 验证计数未被修改
```

## 关键代码路径与文件引用

### 被测代码路径
| 文件 | 相关功能 |
|------|----------|
| `codex-rs/tui/src/app.rs` | `select_model_availability_nux()` 函数 |
| `codex-rs/core/src/config/types.rs` | `ModelAvailabilityNuxConfig` 配置类型 |
| `codex-rs/core/src/config/edit.rs` | `ConfigEditsBuilder::set_model_availability_nux_count()` |

### 依赖工具库
| 库 | 用途 |
|----|------|
| `codex_utils_cargo_bin` | 定位编译后的 codex 二进制文件和资源 |
| `codex_utils_pty` | PTY 进程创建和交互 |
| `tempfile::tempdir` | 临时 CODEX_HOME 隔离 |

### 相关常量
```rust
// 在 app.rs 中定义
const MODEL_AVAILABILITY_NUX_MAX_SHOW_COUNT: u32 = 3;
```

## 依赖与外部交互

### 环境变量
| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 指向临时配置目录 |
| `OPENAI_API_KEY` | 虚拟 API key（dummy） |
| `CODEX_RS_SSE_FIXTURE` | Mock SSE 响应文件路径 |
| `OPENAI_BASE_URL` | 虚拟基础 URL |

### 外部资源
- `../core/models.json` - 模型目录模板
- `../core/tests/cli_responses_fixture.sse` - Mock SSE 响应数据

### 平台限制
```rust
// Windows 不支持 PTY 测试
if cfg!(windows) {
    return Ok(());
}
```

## 风险、边界与改进建议

### 风险
1. **Flaky 测试**: PTY 交互可能因时序问题不稳定
2. **二进制依赖**: 需要预编译的 codex 二进制文件，否则测试跳过
3. **超时风险**: 15 秒超时可能在慢速环境失败

### 边界条件
- 测试仅验证 `resume --last` 场景
- 使用固定 SSE fixture 数据，不测试真实 API 交互
- 计数上限 `MODEL_AVAILABILITY_NUX_MAX_SHOW_COUNT` 硬编码为 3

### 改进建议
1. **稳定性**: 增加重试机制或延长超时时间
2. **覆盖率**: 添加 `fork` 场景的类似测试
3. **诊断**: 失败时保存 PTY 输出日志便于调试
4. **并行**: 考虑使用随机临时目录避免并行冲突
