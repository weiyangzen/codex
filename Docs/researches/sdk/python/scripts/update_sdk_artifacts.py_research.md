# update_sdk_artifacts.py 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`update_sdk_artifacts.py` 是 Codex Python SDK 的**单一维护入口脚本**（Single SDK maintenance entrypoint），负责协调 SDK 代码生成、包打包和发布准备的全流程。它是连接 Rust 端 app-server 协议与 Python SDK 的桥梁。

### 1.2 核心职责

| 职责领域 | 具体任务 |
|---------|---------|
| **类型生成** | 从 JSON Schema 生成 Pydantic v2 模型代码 |
| **通知注册表生成** | 构建服务器通知类型到方法名的映射表 |
| **公共 API 生成** | 为 `Codex`/`AsyncCodex`/`Thread`/`AsyncThread` 生成类型安全的便捷方法 |
| **SDK 包暂存** | 创建可发布的 SDK 包，固定运行时依赖版本 |
| **运行时包暂存** | 创建平台特定的 `codex-cli-bin` 包，包含二进制文件 |

### 1.3 使用场景

1. **开发阶段**: 当 Rust 端 app-server 协议变更时，运行 `generate-types` 同步 Python 端类型
2. **CI/CD 发布流程**: 
   - 运行 `stage-sdk` 创建 SDK 包（一次）
   - 在各平台运行 `stage-runtime` 创建运行时包（每个平台一次）
3. **本地开发**: 通过 `_runtime_setup.py` 调用 `stage_python_runtime_package` 安装运行时

---

## 2. 功能点目的

### 2.1 命令行接口

脚本提供三个子命令：

```bash
# 1. 生成类型（开发者使用）
python scripts/update_sdk_artifacts.py generate-types

# 2. 暂存 SDK 包（CI 发布使用）
python scripts/update_sdk_artifacts.py stage-sdk <staging_dir> \
  --runtime-version <version> \
  [--sdk-version <version>]

# 3. 暂存运行时包（CI 发布使用）
python scripts/update_sdk_artifacts.py stage-runtime <staging_dir> <runtime_binary> \
  --runtime-version <version>
```

### 2.2 各功能点详细说明

#### 2.2.1 `generate-types`: 类型生成

**目的**: 将 Rust 端的 JSON Schema 转换为 Python Pydantic 模型

**生成的文件**:
- `src/codex_app_server/generated/v2_all.py` - 完整的协议类型定义
- `src/codex_app_server/generated/notification_registry.py` - 通知类型注册表
- `src/codex_app_server/api.py` 中的生成代码块 - 公共 API 便捷方法

**关键设计决策**:
- 使用 `datamodel-code-generator` 工具从 JSON Schema 生成代码
- 强制使用 Pydantic v2 (`pydantic_v2.BaseModel`)
- 字段使用 snake_case（`--snake-case-field`），但保留别名映射到 camelCase
- 使用 `Literal` 类型表示枚举（`--enum-field-as-literal one`）

#### 2.2.2 `stage-sdk`: SDK 包暂存

**目的**: 创建准备发布的 SDK 包，固定运行时依赖

**关键操作**:
1. 先运行 `generate-types` 确保类型最新
2. 复制 `sdk/python` 目录到暂存目录
3. 删除 `src/codex_app_server/bin`（SDK 不携带二进制）
4. 重写 `pyproject.toml`:
   - 更新版本号
   - 注入 `codex-cli-bin=={runtime_version}` 精确依赖

#### 2.2.3 `stage-runtime`: 运行时包暂存

**目的**: 创建平台特定的运行时包，包含 codex 二进制

**关键操作**:
1. 复制 `sdk/python-runtime` 模板到暂存目录
2. 重写 `pyproject.toml` 版本
3. 复制二进制到 `src/codex_cli_bin/bin/`
4. 非 Windows 平台设置可执行权限

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 Schema 规范化流程 (`_normalized_schema_bundle_text`)

```python
def _normalized_schema_bundle_text() -> str:
    schema = json.loads(schema_bundle_path().read_text())
    # 1. 展平字符串枚举的 oneOf
    for definition in definitions.values():
        _flatten_string_enum_one_of(definition)
    # 2. 注解 schema，为变体添加稳定的 title
    _annotate_schema(schema)
    return json.dumps(schema, indent=2, sort_keys=True) + "\n"
```

**展平字符串枚举** (`_flatten_string_enum_one_of`):
- 将形如 `{"oneOf": [{"type": "string", "enum": ["a"]}, ...]}` 的冗余结构
- 转换为 `{"type": "string", "enum": ["a", "b", ...]}`
- 影响的类型: `AuthMode`, `CommandExecOutputStream`, `ExperimentalFeatureStage`, `InputModality`, `MessagePhase`

**Schema 注解** (`_annotate_schema`):
- 为 `oneOf`/`anyOf` 变体生成稳定的 `title` 属性
- 使用 `DISCRIMINATOR_KEYS = ("type", "method", "mode", "state", "status", "role", "reason")` 识别变体类型
- 命名约定转换:
  - `ClientRequest` + `type=thread/start` → `ThreadStartRequest`
  - `ServerNotification` + `method=error` → `ErrorServerNotification`
- 避免命名冲突，检测碰撞并抛出错误

#### 3.1.2 Pydantic 代码生成流程 (`generate_v2_all`)

```python
def generate_v2_all() -> None:
    # 1. 准备输出目录
    out_path = sdk_root() / "src" / "codex_app_server" / "generated" / "v2_all.py"
    
    # 2. 创建临时目录，写入规范化后的 schema
    with tempfile.TemporaryDirectory() as td:
        normalized_bundle = Path(td) / schema_bundle_path().name
        normalized_bundle.write_text(_normalized_schema_bundle_text())
        
        # 3. 调用 datamodel-code-generator
        run_python_module(
            "datamodel_code_generator",
            [
                "--input", str(normalized_bundle),
                "--input-file-type", "jsonschema",
                "--output", str(out_path),
                "--output-model-type", "pydantic_v2.BaseModel",
                "--target-python-version", "3.11",
                "--use-standard-collections",
                "--enum-field-as-literal", "one",
                "--field-constraints",
                "--use-default-kwarg",
                "--snake-case-field",
                "--allow-population-by-field-name",
                "--use-title-as-name",      # 使用 title 作为类名
                "--use-annotated",
                "--use-union-operator",
                "--disable-timestamp",
                "--formatters", "ruff-format",
            ],
            cwd=sdk_root(),
        )
    
    # 4. 规范化时间戳（确保确定性输出）
    _normalize_generated_timestamps(out_path)
```

#### 3.1.3 通知注册表生成流程 (`generate_notification_registry`)

```python
def generate_notification_registry() -> None:
    # 1. 解析 ServerNotification.json 的 oneOf
    server_notifications = json.loads((schema_root_dir() / "ServerNotification.json").read_text())
    one_of = server_notifications.get("oneOf", [])
    
    # 2. 提取 method -> class_name 映射
    specs: list[tuple[str, str]] = []
    for variant in one_of:
        method = variant["properties"]["method"]["enum"][0]  # 如 "turn/completed"
        class_name = ref.split("/")[-1]  # 如 "TurnCompletedNotification"
        specs.append((method, class_name))
    
    # 3. 生成 Python 模块
    # 输出: NOTIFICATION_MODELS: dict[str, type[BaseModel]] = {...}
```

#### 3.1.4 公共 API 生成流程 (`generate_public_api_flat_methods`)

**设计目标**: 为高频操作提供类型安全、IDE 友好的便捷方法

**生成的代码块**:
- `Codex.flat_methods`: `thread_start`, `thread_list`, `thread_resume`, `thread_fork`, `thread_archive`, `thread_unarchive`
- `AsyncCodex.flat_methods`: 上述方法的异步版本
- `Thread.flat_methods`: `turn`
- `AsyncThread.flat_methods`: `turn` 的异步版本

**字段提取逻辑** (`_load_public_fields`):
- 使用 `importlib` 动态导入生成的 Pydantic 模型
- 读取 `model_fields` 获取字段定义
- 应用 `FIELD_ANNOTATION_OVERRIDES` 覆盖特定字段类型（如 `config: JsonObject`）
- 排除特定字段（如 `thread_id`, `input`）

**代码替换机制** (`_replace_generated_block`):
- 使用正则表达式定位标记块:
  ```python
  # BEGIN GENERATED: Codex.flat_methods
  ...  # 旧代码
  # END GENERATED: Codex.flat_methods
  ```
- 替换为新生成的代码

### 3.2 关键数据结构

#### 3.2.1 `PublicFieldSpec`

```python
@dataclass(slots=True)
class PublicFieldSpec:
    wire_name: str      # 序列化后的名称（camelCase）
    py_name: str        # Python 参数名（snake_case）
    annotation: str     # 类型注解字符串
    required: bool      # 是否必填
```

#### 3.2.2 `CliOps`

```python
@dataclass(frozen=True)
class CliOps:
    generate_types: Callable[[], None]
    stage_python_sdk_package: Callable[[Path, str, str], Path]
    stage_python_runtime_package: Callable[[Path, str, Path], Path]
    current_sdk_version: Callable[[], str]
```

用于依赖注入，便于测试时 mock。

### 3.3 协议与命令

#### 3.3.1 依赖的外部命令

| 命令 | 用途 | 来源 |
|-----|------|------|
| `datamodel_code_generator` | 从 JSON Schema 生成 Pydantic 代码 | Python 包 (`datamodel-code-generator==0.31.2`) |
| `ruff-format` | 格式化生成的代码 | Python 包 (`ruff>=0.11`) |

#### 3.3.2 输入文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 主 schema bundle |
| `codex-rs/app-server-protocol/schema/json/ServerNotification.json` | 服务器通知定义 |
| `sdk/python/pyproject.toml` | SDK 包配置模板 |
| `sdk/python-runtime/pyproject.toml` | 运行时包配置模板 |

#### 3.3.3 输出文件

| 文件路径 | 说明 |
|---------|------|
| `sdk/python/src/codex_app_server/generated/v2_all.py` | 生成的 Pydantic 模型 |
| `sdk/python/src/codex_app_server/generated/notification_registry.py` | 通知类型注册表 |
| `sdk/python/src/codex_app_server/api.py` | 包含生成的公共 API 方法 |

---

## 4. 关键代码路径与文件引用

### 4.1 调用关系图

```
update_sdk_artifacts.py
├── main()
│   ├── parse_args()
│   ├── run_command()
│   │   ├── generate-types → generate_types()
│   │   │   ├── generate_v2_all()
│   │   │   │   ├── _normalized_schema_bundle_text()
│   │   │   │   │   ├── _flatten_string_enum_one_of()
│   │   │   │   │   └── _annotate_schema()
│   │   │   │   └── run_python_module("datamodel_code_generator", ...)
│   │   │   ├── generate_notification_registry()
│   │   │   │   └── _notification_specs()
│   │   │   └── generate_public_api_flat_methods()
│   │   │       ├── _load_public_fields()
│   │   │       ├── _render_codex_block()
│   │   │       ├── _render_async_codex_block()
│   │   │       ├── _render_thread_block()
│   │   │       ├── _render_async_thread_block()
│   │   │       └── _replace_generated_block()
│   │   ├── stage-sdk → stage_python_sdk_package()
│   │   │   ├── _copy_package_tree()
│   │   │   ├── _rewrite_project_version()
│   │   │   └── _rewrite_sdk_runtime_dependency()
│   │   └── stage-runtime → stage_python_runtime_package()
│   │       ├── _copy_package_tree()
│   │       └── staged_runtime_bin_path()
```

### 4.2 被调用方

| 调用者 | 调用方式 | 用途 |
|-------|---------|------|
| `sdk/python/_runtime_setup.py` | `importlib.util.spec_from_file_location` + `exec_module` | 在运行时安装流程中复用 `stage_python_runtime_package` |
| CI/CD 工作流 | 命令行直接调用 | 发布流程 |
| 开发者 | 命令行直接调用 | 本地类型更新 |

### 4.3 测试覆盖

| 测试文件 | 测试内容 |
|---------|---------|
| `sdk/python/tests/test_contract_generation.py` | 验证生成文件与重新生成结果一致 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py` | 测试脚本功能、schema 规范化、包暂存逻辑 |

---

## 5. 依赖与外部交互

### 5.1 Python 依赖

**运行时依赖**（脚本自身）:
- Python >= 3.10
- 标准库: `argparse`, `importlib`, `json`, `pathlib`, `re`, `shutil`, `subprocess`, `sys`, `tempfile`, `types`, `typing`

**开发依赖**（通过 `datamodel-code-generator` 使用）:
- `datamodel-code-generator==0.31.2`
- `ruff>=0.11`

### 5.2 外部文件依赖

| 路径 | 类型 | 说明 |
|-----|------|------|
| `codex-rs/app-server-protocol/schema/json/*.json` | 输入 | Rust 端生成的 JSON Schema |
| `sdk/python/pyproject.toml` | 输入/模板 | SDK 包配置 |
| `sdk/python-runtime/` | 输入/模板 | 运行时包模板 |
| `sdk/python/src/codex_app_server/api.py` | 输入/输出 | 公共 API 文件（包含生成代码块） |

### 5.3 包结构依赖

```
sdk/
├── python/                          # SDK 包源代码
│   ├── pyproject.toml              # 包配置
│   ├── src/codex_app_server/
│   │   ├── __init__.py             # 公共导出
│   │   ├── api.py                  # 包含生成代码块
│   │   ├── client.py               # 同步客户端
│   │   ├── async_client.py         # 异步客户端
│   │   ├── models.py               # 手动定义模型
│   │   └── generated/              # 生成代码目录
│   │       ├── __init__.py
│   │       ├── v2_all.py           # 由 generate_v2_all 生成
│   │       └── notification_registry.py  # 由 generate_notification_registry 生成
│   └── scripts/
│       └── update_sdk_artifacts.py # 本脚本
│
└── python-runtime/                  # 运行时包模板
    ├── pyproject.toml              # 运行时包配置
    ├── hatch_build.py              # 自定义构建钩子
    └── src/codex_cli_bin/
        └── __init__.py             # 提供 bundled_codex_path()
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Schema 变更导致生成代码断裂

**风险**: 当 Rust 端 schema 发生重大变更（如字段重命名、类型变更），生成的 Pydantic 模型可能与 SDK 其他部分不兼容。

**缓解措施**:
- `test_contract_generation.py` 确保生成文件是最新的
- CI 在 PR 阶段运行类型生成并检查是否有 diff

#### 6.1.2 变体命名冲突

**风险**: `_variant_definition_name` 生成的类名可能冲突。

**缓解措施**:
- `_variant_collision_key` 检测冲突
- 发现冲突时抛出 `RuntimeError`，强制人工介入

#### 6.1.3 平台二进制文件缺失

**风险**: `stage-runtime` 需要平台特定的 codex 二进制文件，如果路径错误或文件损坏会导致发布失败。

**缓解措施**:
- 脚本检查文件存在性（通过 `Path.resolve()`）
- CI 在各平台独立构建二进制

### 6.2 边界情况

#### 6.2.1 字段类型覆盖

`FIELD_ANNOTATION_OVERRIDES` 硬编码了两个字段的覆盖:
```python
FIELD_ANNOTATION_OVERRIDES: dict[str, str] = {
    "config": "JsonObject",
    "output_schema": "JsonObject",
}
```

如果 schema 新增类似 `Any` 类型的字段，需要手动添加覆盖以保持公共 API 类型安全。

#### 6.2.2 生成代码块标记

`_replace_generated_block` 依赖精确的标记格式:
```python
# BEGIN GENERATED: {block_name}
...
# END GENERATED: {block_name}
```

如果手动编辑导致标记丢失或格式错误，生成会失败并抛出 `RuntimeError`。

#### 6.2.3 Windows vs Unix 路径处理

脚本通过 `_is_windows()` 检测平台，影响:
- 二进制文件名 (`codex.exe` vs `codex`)
- 可执行权限设置（仅非 Windows）

### 6.3 改进建议

#### 6.3.1 增加 Schema 版本校验

**建议**: 在 schema bundle 中嵌入版本信息，生成时校验兼容性。

```python
# 伪代码
def _validate_schema_version(schema: dict) -> None:
    version = schema.get("$version", "1.0.0")
    if not semver_compatible(version, SUPPORTED_SCHEMA_VERSION):
        raise RuntimeError(f"Schema version {version} not compatible")
```

#### 6.3.2 优化字段覆盖机制

**建议**: 将 `FIELD_ANNOTATION_OVERRIDES` 改为基于 schema 注解的自动检测，而非硬编码。

```python
# 例如，检测 schema 中的 "type": "object" 且无 properties 的字段
# 自动映射为 JsonObject
```

#### 6.3.3 增强错误信息

**建议**: 在变体命名冲突时，输出更详细的诊断信息，包括:
- 冲突的 schema 定义位置
- 建议的 title 值

#### 6.3.4 支持增量生成

**建议**: 当前 `generate_v2_all` 总是全量生成。可考虑:
- 比较 schema hash，无变化时跳过
- 仅变更相关模型时，减少格式化时间

#### 6.3.5 类型注解完善

**建议**: 脚本本身的部分函数缺少类型注解（如 `_annotate_schema` 的参数 `value: Any`），可进一步完善以提高可维护性。

#### 6.3.6 配置化生成选项

**建议**: 将 `datamodel-code-generator` 的参数提取到配置文件，便于调整而无需修改脚本。

---

## 7. 附录

### 7.1 相关文件速查

| 文件 | 作用 |
|-----|------|
| `sdk/python/scripts/update_sdk_artifacts.py` | 本脚本 |
| `sdk/python/_runtime_setup.py` | 运行时安装辅助，调用本脚本功能 |
| `sdk/python/tests/test_artifact_workflow_and_binaries.py` | 本脚本的功能测试 |
| `sdk/python/tests/test_contract_generation.py` | 生成文件一致性测试 |
| `codex-rs/app-server-protocol/schema/json/` | JSON Schema 来源 |

### 7.2 关键常量

| 常量 | 值 | 说明 |
|-----|-----|------|
| `DISCRIMINATOR_KEYS` | `("type", "method", "mode", "state", "status", "role", "reason")` | 用于识别变体类型的字段 |
| `FIELD_ANNOTATION_OVERRIDES` | `{"config": "JsonObject", "output_schema": "JsonObject"}` | 字段类型覆盖 |

### 7.3 版本信息

- 当前研究基于仓库 commit: 最新 main 分支
- SDK 版本: `0.2.0`（`sdk/python/pyproject.toml`）
- 运行时版本: `0.116.0-alpha.1`（`sdk/python/_runtime_setup.py` 中 `PINNED_RUNTIME_VERSION`）
