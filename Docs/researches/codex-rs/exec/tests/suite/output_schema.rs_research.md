# output_schema.rs 深度研究文档

## 场景与职责

`output_schema.rs` 是 `codex-exec` CLI 工具的输出格式控制测试模块，专门验证 `--output-schema` 参数的功能。该参数允许用户指定 JSON Schema 来约束模型的输出格式，实现结构化输出。

**核心场景**：
- 用户需要模型返回特定 JSON 格式的响应
- 自动化工具需要解析模型输出
- API 集成场景需要结构化数据

## 功能点目的

### 单测试函数 (`exec_includes_output_schema_in_request`)

验证 `--output-schema` 参数能够：
1. 正确读取 JSON Schema 文件
2. 将 Schema 包含在 API 请求的 `text.format` 字段中
3. 使用正确的格式类型 (`json_schema`)

## 具体技术实现

### JSON Schema 格式

**测试 Schema**:
```json
{
    "type": "object",
    "properties": {
        "answer": { "type": "string" }
    },
    "required": ["answer"],
    "additionalProperties": false
}
```

### API 请求格式

**期望的请求体**:
```json
{
    "text": {
        "format": {
            "name": "codex_output_schema",
            "type": "json_schema",
            "strict": true,
            "schema": { /* 用户提供的 schema */ }
        }
    }
}
```

### 测试流程

```
创建 TestCodexExec 环境
  ↓
构造 JSON Schema
  ├─ type: object
  ├─ properties: { answer: { type: string } }
  ├─ required: ["answer"]
  └─ additionalProperties: false
  ↓
将 Schema 写入临时文件
  ↓
启动 Mock SSE 服务器
  ↓
挂载 Mock 响应并捕获请求
  ↓
执行 codex-exec 命令
  ├─ --skip-git-repo-check
  ├─ -C <cwd>
  ├─ --output-schema <schema_path>
  ├─ -m gpt-5.1
  └─ "tell me a joke"
  ↓
验证命令成功
  ↓
提取捕获的请求体
  ↓
验证 text.format 字段
  ├─ name: "codex_output_schema"
  ├─ type: "json_schema"
  ├─ strict: true
  └─ schema: 与预期 schema 匹配
```

### 关键代码

**Schema 文件创建**:
```rust
let schema_contents = serde_json::json!({
    "type": "object",
    "properties": {
        "answer": { "type": "string" }
    },
    "required": ["answer"],
    "additionalProperties": false
});
let schema_path = test.cwd_path().join("schema.json");
std::fs::write(&schema_path, serde_json::to_vec_pretty(&schema_contents)?)?;
```

**请求验证**:
```rust
let request = response_mock.single_request();
let payload: Value = request.body_json();
let text = payload.get("text").expect("request missing text field");
let format = text.get("format").expect("request missing text.format field");
assert_eq!(format, &serde_json::json!({
    "name": "codex_output_schema",
    "type": "json_schema",
    "strict": true,
    "schema": expected_schema,
}));
```

## 关键代码路径与文件引用

### 被测试代码路径

1. **CLI 参数定义**: `codex-rs/exec/src/cli.rs:78-80`
   ```rust
   /// Path to a JSON Schema file describing the model's final response shape.
   #[arg(long = "output-schema", value_name = "FILE")]
   pub output_schema: Option<PathBuf>,
   ```

2. **Schema 加载**: `codex-rs/exec/src/lib.rs:1446-1470`
   ```rust
   fn load_output_schema(path: Option<PathBuf>) -> Option<Value> {
       let path = path?;
       let schema_str = match std::fs::read_to_string(&path) {
           Ok(contents) => contents,
           Err(err) => { eprintln!(...); std::process::exit(1); }
       };
       match serde_json::from_str::<Value>(&schema_str) {
           Ok(value) => Some(value),
           Err(err) => { eprintln!(...); std::process::exit(1); }
       }
   }
   ```

3. **请求构造**: `codex-rs/exec/src/lib.rs:652-657`
   ```rust
   let output_schema = load_output_schema(output_schema_path);
   InitialOperation::UserTurn {
       items,
       output_schema,
   }
   ```

4. **API 协议**: `codex-app-server-protocol`
   - 将 `output_schema` 转换为 API 请求格式
   - 设置 `text.format` 字段

### 测试依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `test_codex_exec` | `codex-rs/core/tests/common/test_codex_exec.rs` | 测试环境 |
| `responses` | `codex-rs/core/tests/common/responses.rs` | Mock 和请求捕获 |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `serde_json` | JSON 序列化和验证 |
| `wiremock` | HTTP Mock 服务器 |
| `assert_cmd` | CLI 测试断言 |
| `tokio` | 异步运行时 |

### 错误处理

**文件读取失败**:
```rust
eprintln!("Failed to read output schema file {}: {err}", path.display());
std::process::exit(1);
```

**JSON 解析失败**:
```rust
eprintln!("Output schema file {} is not valid JSON: {err}", path.display());
std::process::exit(1);
```

### 平台限制

```rust
#![cfg(not(target_os = "windows"))]
```

## 风险、边界与改进建议

### 当前风险

1. **文件系统依赖**: 需要实际文件系统操作
2. **错误退出**: 使用 `process::exit(1)` 难以测试
3. **Schema 验证**: 不验证 Schema 本身的有效性

### 边界情况

1. **无效 Schema**: 不符合 JSON Schema 规范的输入
2. **大文件**: 大型 Schema 文件的性能和内存使用
3. **嵌套 Schema**: 包含引用的复杂 Schema
4. **并发访问**: 多个进程同时读取 Schema 文件
5. **特殊字符**: 文件名包含特殊字符

### 改进建议

1. **Schema 验证**: 验证提供的 JSON 是有效的 JSON Schema
   ```rust
   // 使用 jsonschema crate 验证
   ```

2. **错误处理改进**: 返回错误而非直接退出，便于测试
   ```rust
   fn load_output_schema(...) -> Result<Option<Value>, Error> { ... }
   ```

3. **增加错误场景测试**:
   ```rust
   #[tokio::test]
   async fn exec_fails_with_invalid_schema_file() { ... }
   
   #[tokio::test]
   async fn exec_fails_with_nonexistent_schema_file() { ... }
   ```

4. **支持内联 Schema**: 允许通过命令行直接提供 Schema
   ```bash
   codex-exec --output-schema-inline '{"type":"object",...}'
   ```

5. **Schema 缓存**: 缓存解析后的 Schema 以提高性能

### 相关文件

- `codex-rs/exec/src/cli.rs` - CLI 参数定义
- `codex-rs/exec/src/lib.rs` - Schema 加载逻辑
- `codex-app-server-protocol` - API 协议定义

### OpenAI API 参考

- [Structured Outputs](https://platform.openai.com/docs/guides/structured-outputs)
- `text.format` 字段支持 `json_schema` 类型
