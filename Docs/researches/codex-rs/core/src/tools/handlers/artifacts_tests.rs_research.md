# artifacts_tests.rs 深度研究文档

## 场景与职责

`artifacts_tests.rs` 是 `artifacts.rs` 的单元测试模块，负责验证 Artifact 工具的参数解析、运行时管理和输出格式化功能。该测试文件作为内联测试模块被包含在 `artifacts.rs` 中。

## 功能点目的

### 测试覆盖范围

1. **参数解析测试** - 验证 `parse_freeform_args` 对各种输入格式的处理
2. **运行时管理测试** - 验证 `default_runtime_manager` 配置正确性
3. **缓存运行时测试** - 验证运行时缓存加载逻辑
4. **输出格式化测试** - 验证 `format_artifact_output` 格式化逻辑

## 具体技术实现

### 测试用例详情

#### 1. `parse_freeform_args_without_pragma`

```rust
#[test]
fn parse_freeform_args_without_pragma() {
    let args = parse_freeform_args("console.log('ok');").expect("parse args");
    assert_eq!(args.source, "console.log('ok');");
    assert_eq!(args.timeout_ms, None);
}
```

**测试目的：** 验证无 pragma 的普通 JavaScript 代码正确解析

#### 2. `parse_freeform_args_with_artifact_tool_pragma`

```rust
#[test]
fn parse_freeform_args_with_artifact_tool_pragma() {
    let args = parse_freeform_args("// codex-artifact-tool: timeout_ms=45000\nconsole.log('ok');")
        .expect("parse args");
    assert_eq!(args.source, "console.log('ok');");
    assert_eq!(args.timeout_ms, Some(45_000));
}
```

**测试目的：** 验证 pragma 正确解析，超时设置提取成功

#### 3. `parse_freeform_args_rejects_json_wrapped_code`

```rust
#[test]
fn parse_freeform_args_rejects_json_wrapped_code() {
    let err = parse_freeform_args("{\"code\":\"console.log('ok')\"}").expect_err("expected error");
    assert!(
        err.to_string()
            .contains("artifacts is a freeform tool and expects raw JavaScript source")
    );
}
```

**测试目的：** 验证拒绝 JSON 包装的代码输入

#### 4. `default_runtime_manager_uses_openai_codex_release_base`

```rust
#[test]
fn default_runtime_manager_uses_openai_codex_release_base() {
    let codex_home = TempDir::new().expect("create temp codex home");
    let manager = default_runtime_manager(codex_home.path().to_path_buf());

    assert_eq!(
        manager.config().release().base_url().as_str(),
        "https://github.com/openai/codex/releases/download/"
    );
    assert_eq!(
        manager.config().release().runtime_version(),
        versions::ARTIFACT_RUNTIME
    );
}
```

**测试目的：** 验证运行时管理器使用正确的 GitHub Release 源和版本

#### 5. `load_cached_runtime_reads_pinned_cache_path`

```rust
#[test]
fn load_cached_runtime_reads_pinned_cache_path() {
    let codex_home = TempDir::new().expect("create temp codex home");
    let platform = codex_artifacts::ArtifactRuntimePlatform::detect_current().expect("detect platform");
    let install_dir = codex_home
        .path()
        .join("packages")
        .join("artifacts")
        .join(versions::ARTIFACT_RUNTIME)
        .join(platform.as_str());
    // 创建模拟运行时目录结构
    std::fs::create_dir_all(&install_dir).expect("create install dir");
    std::fs::create_dir_all(install_dir.join("dist")).expect("create build entrypoint dir");
    std::fs::write(
        install_dir.join("package.json"),
        serde_json::json!({...}).to_string(),
    ).expect("write package json");
    std::fs::write(
        install_dir.join("dist/artifact_tool.mjs"),
        "export const ok = true;\n",
    ).expect("write build entrypoint");

    // 验证缓存加载
    let runtime = codex_artifacts::load_cached_runtime(...).expect("resolve runtime");
    assert_eq!(runtime.runtime_version(), versions::ARTIFACT_RUNTIME);
    assert_eq!(runtime.build_js_path(), install_dir.join("dist/artifact_tool.mjs"));
}
```

**测试目的：** 验证运行时缓存加载逻辑，模拟完整的运行时目录结构

#### 6. `format_artifact_output_includes_success_message_when_silent`

```rust
#[test]
fn format_artifact_output_includes_success_message_when_silent() {
    let formatted = format_artifact_output(&ArtifactCommandOutput {
        exit_code: Some(0),
        stdout: String::new(),
        stderr: String::new(),
    });
    assert!(formatted.contains("artifact JS completed successfully."));
}
```

**测试目的：** 验证静默成功时输出包含成功消息

## 关键代码路径与文件引用

| 测试函数 | 被测函数 | 所在文件 |
|---------|---------|---------|
| `parse_freeform_args_without_pragma` | `parse_freeform_args` | artifacts.rs:123 |
| `parse_freeform_args_with_artifact_tool_pragma` | `parse_freeform_args` | artifacts.rs:123 |
| `parse_freeform_args_rejects_json_wrapped_code` | `parse_freeform_args` | artifacts.rs:123 |
| `default_runtime_manager_uses_openai_codex_release_base` | `default_runtime_manager` | artifacts.rs:214 |
| `load_cached_runtime_reads_pinned_cache_path` | `codex_artifacts::load_cached_runtime` | 外部 crate |
| `format_artifact_output_includes_success_message_when_silent` | `format_artifact_output` | artifacts.rs:263 |

## 依赖与外部交互

### 测试依赖

```rust
use super::*;  // 引入 artifacts.rs 的所有私有函数
use crate::packages::versions;  // 版本常量
use tempfile::TempDir;  // 临时目录
```

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_artifacts` | Artifact 运行时管理 |
| `tempfile` | 临时目录创建 |
| `serde_json` | JSON 构造 |

## 风险、边界与改进建议

### 测试覆盖缺口

1. **缺少错误场景测试**
   - 空代码输入
   - 无效 pragma 格式
   - Markdown 代码块拒绝
   - 未知 pragma 键

2. **缺少 Handler 集成测试**
   - `ArtifactsHandler::handle` 完整流程
   - 功能开关检查
   - 事件发射验证

3. **缺少边界测试**
   - 超时场景
   - 执行错误场景
   - 大输出处理

### 改进建议

1. **添加错误场景测试**
   ```rust
   #[test]
   fn parse_freeform_args_rejects_empty_code() {
       let err = parse_freeform_args("").expect_err("expected error");
       assert!(err.to_string().contains("non-empty"));
   }
   
   #[test]
   fn parse_freeform_args_rejects_markdown_fences() {
       let err = parse_freeform_args("```js\nconsole.log('ok');\n```").expect_err("expected error");
       assert!(err.to_string().contains("markdown code fences"));
   }
   ```

2. **添加集成测试**
   ```rust
   #[tokio::test]
   async fn test_artifacts_handler_disabled() {
       // 测试功能禁用场景
   }
   ```

3. **测试组织建议**
   - 当前测试文件 98 行，可保持内联
   - 如添加更多集成测试，建议拆分为独立文件
