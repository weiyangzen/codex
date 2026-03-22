# SDK Python Scripts 深度研究文档

## 1. 场景与职责

### 1.1 目录定位

`sdk/python/scripts/` 是 Codex Python SDK 的构建与代码生成脚本目录，当前包含核心维护脚本 `update_sdk_artifacts.py`。该脚本是整个 Python SDK 与 Rust 后端协议之间的桥梁，负责将 Rust 端定义的 JSON Schema 协议转换为 Python 类型定义和 API 代码。

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **协议代码生成** | 将 Rust 端的 JSON Schema 转换为 Python Pydantic 模型 |
| **类型注册表生成** | 自动生成通知类型到模型类的映射注册表 |
| **公共 API 生成** | 基于协议参数自动生成高层 `Codex` / `AsyncCodex` 类的便捷方法 |
| **SDK 打包准备** | 为发布准备 SDK 和运行时包的分阶段构建 |
| **版本管理** | 处理 SDK 版本与运行时版本的依赖关系 |

### 1.3 调用关系

```
调用方:
├── justfile / CI 流程
│   └── python scripts/update_sdk_artifacts.py generate-types
│   └── python scripts/update_sdk_artifacts.py stage-sdk
│   └── python scripts/update_sdk_artifacts.py stage-runtime
├── _runtime_setup.py (运行时安装脚本)
│   └── 导入并调用 stage_python_runtime_package()
└── 测试 (test_contract_generation.py, test_artifact_workflow_and_binaries.py)
    └── 验证生成产物一致性

被调用方/依赖:
├── codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json
│   └── Rust 端导出的 JSON Schema 协议定义
├── datamodel-code-generator (Python 包)
│   └── 用于将 JSON Schema 转换为 Pydantic 模型
└── ruff-format
    └── 代码格式化
```

---

## 2. 功能点目的

### 2.1 代码生成功能 (`generate-types`)

#### 2.1.1 Schema 归一化 (`_normalized_schema_bundle_text`)

**目的**: 解决 `datamodel-code-generator` 生成不稳定类名的问题。

**关键问题**: Rust 协议中的 `oneOf` 联合类型在默认情况下会生成 `...1`, `...2` 这样的匿名辅助类名，当协议变更时类名会漂移，破坏 API 兼容性。

**解决方案**:
- 识别并扁平化字符串枚举的 `oneOf` 定义 (`_flatten_string_enum_one_of`)
- 为联合类型的每个分支注入稳定的 `title` 属性 (`_annotate_schema`)
- 基于判别键 (`type`, `method`, `mode`, `state`, `status`, `role`, `reason`) 生成语义化类名

**示例转换**:
```python
# 转换前 (不稳定)
class ErrorNotification1(BaseModel): ...
class ThreadStartedNotification2(BaseModel): ...

# 转换后 (稳定)
class ErrorServerNotification(BaseModel): ...
class ThreadStartedServerNotification(BaseModel): ...
```

#### 2.1.2 Pydantic 模型生成 (`generate_v2_all`)

**目的**: 生成完整的协议类型定义文件 `src/codex_app_server/generated/v2_all.py`。

**关键参数**:
| 参数 | 说明 |
|-----|------|
| `--output-model-type pydantic_v2.BaseModel` | 使用 Pydantic v2 |
| `--use-title-as-name` | 使用 schema title 作为类名 |
| `--snake-case-field` | 字段名转换为 snake_case |
| `--allow-population-by-field-name` | 支持按字段名填充 |
| `--enum-field-as-literal one` | 单值枚举作为 Literal |

#### 2.1.3 通知注册表生成 (`generate_notification_registry`)

**目的**: 建立通知方法名到模型类的映射，支持运行时通知反序列化。

**生成的数据结构** (`notification_registry.py`):
```python
NOTIFICATION_MODELS: dict[str, type[BaseModel]] = {
    "account/login/completed": AccountLoginCompletedNotification,
    "item/agentMessage/delta": AgentMessageDeltaNotification,
    "turn/completed": TurnCompletedNotification,
    ...
}
```

#### 2.1.4 公共 API 方法生成 (`generate_public_api_flat_methods`)

**目的**: 基于协议参数自动生成高层 API 方法，避免手动维护重复代码。

**生成目标**:
- `Codex.thread_start()`, `Codex.thread_list()`, `Codex.thread_resume()`, `Codex.thread_fork()`
- `AsyncCodex` 的异步版本
- `Thread.turn()`, `AsyncThread.turn()`

**代码块标记**:
```python
# BEGIN GENERATED: Codex.flat_methods
# END GENERATED: Codex.flat_methods
```

### 2.2 SDK 打包功能 (`stage-sdk`)

**目的**: 准备可发布的 SDK 包，包含正确的版本和运行时依赖。

**关键操作**:
1. 复制 SDK 源码到临时目录
2. 移除 `src/codex_app_server/bin` 目录（避免包含开发时二进制文件）
3. 重写 `pyproject.toml`:
   - 更新 `version` 字段
   - 注入 `codex-cli-bin=={runtime_version}` 依赖

### 2.3 运行时打包功能 (`stage-runtime`)

**目的**: 为当前平台准备包含 Codex 二进制文件的可发布运行时包。

**关键操作**:
1. 复制运行时包模板到临时目录
2. 将指定的 Codex 二进制文件复制到 `src/codex_cli_bin/bin/`
3. 设置可执行权限 (非 Windows)
4. 更新 `pyproject.toml` 版本

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 路径定义

```python
def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]  # 上溯3层到仓库根

def sdk_root() -> Path:
    return repo_root() / "sdk" / "python"

def schema_bundle_path() -> Path:
    return (
        repo_root()
        / "codex-rs"
        / "app-server-protocol"
        / "schema"
        / "json"
        / "codex_app_server_protocol.v2.schemas.json"
    )
```

#### 3.1.2 CLI 操作抽象 (`CliOps`)

```python
@dataclass(frozen=True)
class CliOps:
    generate_types: Callable[[], None]
    stage_python_sdk_package: Callable[[Path, str, str], Path]
    stage_python_runtime_package: Callable[[Path, str, Path], Path]
    current_sdk_version: Callable[[], str]
```

此抽象允许测试注入 mock 实现，实现可测试性。

### 3.2 关键流程

#### 3.2.1 Schema 注解流程 (`_annotate_schema`)

```
输入: JSON Schema (来自 Rust 协议)
  │
  ▼
_flatten_string_enum_one_of  ──► 扁平化字符串枚举 oneOf
  │
  ▼
_annotate_schema  ──► 递归遍历 schema
  │
  ├── 为联合类型分支设置 title (_variant_definition_name)
  │     └── 基于 DISCRIMINATOR_KEYS 生成语义化名称
  │
  ├── 为判别键属性设置 title (_set_discriminator_titles)
  │
  └── 递归处理嵌套定义 (definitions, $defs)
  │
  ▼
输出: 归一化后的 JSON Schema
```

#### 3.2.2 代码生成流程 (`generate_types`)

```
generate_types()
  │
  ├──► generate_v2_all()
  │      ├── 创建临时目录
  │      ├── 写入归一化 schema
  │      ├── 调用 datamodel-code-generator
  │      └── 规范化时间戳注释
  │
  ├──► generate_notification_registry()
  │      ├── 解析 ServerNotification.json
  │      ├── 匹配 method 与 params $ref
  │      └── 生成 NOTIFICATION_MODELS 字典
  │
  └──► generate_public_api_flat_methods()
         ├── 动态导入生成的 v2_all 模块
         ├── 提取 ThreadStartParams 等参数字段
         ├── 渲染方法签名模板
         └── 替换 api.py 中的标记块
```

#### 3.2.3 变体命名算法 (`_variant_definition_name`)

```python
DISCRIMINATOR_KEYS = ("type", "method", "mode", "state", "status", "role", "reason")

# 算法逻辑:
# 1. 查找 properties 中的判别键
# 2. 提取 const/enum 值作为字面量
# 3. 转换为 PascalCase
# 4. 根据基础类型添加后缀:
#    - ClientRequest → {Pascal}Request
#    - ServerRequest → {Pascal}ServerRequest
#    - ClientNotification → {Pascal}ClientNotification
#    - ServerNotification → {Pascal}ServerNotification
#    - EventMsg → {Pascal}EventMsg
#    - 其他 → {Pascal}{base}
```

### 3.3 命令行接口

```bash
# 生成协议类型
python scripts/update_sdk_artifacts.py generate-types

# 准备 SDK 发布包
python scripts/update_sdk_artifacts.py stage-sdk <staging_dir> \
    --runtime-version <version> \
    [--sdk-version <version>]

# 准备运行时发布包
python scripts/update_sdk_artifacts.py stage-runtime <staging_dir> <runtime_binary> \
    --runtime-version <version>
```

---

## 4. 关键代码路径与文件引用

### 4.1 脚本文件

| 文件 | 行数 | 核心功能 |
|-----|------|---------|
| `sdk/python/scripts/update_sdk_artifacts.py` | ~998 | 代码生成与打包的主入口 |

### 4.2 生成的产物

| 文件 | 说明 |
|-----|------|
| `src/codex_app_server/generated/v2_all.py` | Pydantic 模型定义 (由 datamodel-code-generator 生成) |
| `src/codex_app_server/generated/notification_registry.py` | 通知方法到模型类的映射 |
| `src/codex_app_server/api.py` | 包含生成的 `Codex` / `AsyncCodex` / `Thread` / `AsyncThread` 方法 |

### 4.3 输入依赖

| 文件 | 说明 |
|-----|------|
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | Rust 端导出的完整协议 schema |
| `codex-rs/app-server-protocol/schema/json/ServerNotification.json` | 服务器通知类型定义 |

### 4.4 关键函数索引

| 函数 | 行号 | 功能 |
|-----|------|------|
| `repo_root()` | 21-23 | 定位仓库根目录 |
| `_normalized_schema_bundle_text()` | 399-409 | Schema 归一化主入口 |
| `_flatten_string_enum_one_of()` | 163-194 | 扁平化字符串枚举 oneOf |
| `_annotate_schema()` | 358-396 | 递归注解 schema |
| `_variant_definition_name()` | 236-278 | 生成联合类型分支的稳定名称 |
| `generate_v2_all()` | 412-455 | 生成 Pydantic 模型文件 |
| `generate_notification_registry()` | 497-530 | 生成通知注册表 |
| `generate_public_api_flat_methods()` | 836-901 | 生成公共 API 方法 |
| `stage_python_sdk_package()` | 127-140 | 准备 SDK 发布包 |
| `stage_python_runtime_package()` | 143-160 | 准备运行时发布包 |

---

## 5. 依赖与外部交互

### 5.1 Python 依赖

| 包 | 用途 | 安装方式 |
|---|------|---------|
| `datamodel-code-generator` | JSON Schema → Pydantic 转换 | pip (dev 依赖) |
| `ruff-format` | 代码格式化 | pip (dev 依赖) |
| `pydantic>=2.12` | 运行时模型基类 | pip (运行时依赖) |

### 5.2 Rust 端依赖

| 组件 | 输出 | 消费方式 |
|-----|------|---------|
| `app-server-protocol` crate | JSON Schema 文件 | 文件系统读取 |
| `export.rs` (Rust) | Schema 导出逻辑 | 间接依赖 |

### 5.3 运行时依赖

| 包 | 说明 |
|---|------|
| `codex-cli-bin` | 包含 Codex 二进制文件的 Python 包，由 `stage-runtime` 生成 |

### 5.4 交互流程

```
Rust 协议定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
  │
  ▼ (编译时)
Rust Schema 导出 (export.rs)
  │
  ▼ (cargo run)
JSON Schema 文件 (schema/json/*.json)
  │
  ▼ (python scripts/update_sdk_artifacts.py)
Python 代码生成
  │
  ▼
生成的 Python 类型 (v2_all.py, notification_registry.py)
  │
  ▼ (被导入)
SDK 客户端 (client.py, async_client.py, api.py)
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 Schema 变更敏感性

**风险**: 当 Rust 端协议发生变更时，生成的 Python 类名可能意外变化，破坏 API 兼容性。

**缓解措施**:
- `_variant_definition_name` 算法基于稳定的判别键生成名称
- `test_contract_generation.py` 检测生成产物漂移
- CI 中运行 `generate-types` 并验证无变更

#### 6.1.2 命名冲突

**风险**: 不同联合类型分支可能生成相同的 title，导致冲突。

**检测**: `_variant_collision_key` 生成冲突键，重复时抛出 `RuntimeError`。

#### 6.1.3 运行时版本不匹配

**风险**: SDK 与 `codex-cli-bin` 版本不匹配可能导致协议不兼容。

**缓解措施**:
- `stage-sdk` 强制注入精确的 `codex-cli-bin=={runtime_version}` 依赖
- `_runtime_setup.py` 中的 `PINNED_RUNTIME_VERSION` 锁定版本

### 6.2 边界情况

#### 6.2.1 平台差异

| 平台 | 特殊处理 |
|-----|---------|
| Windows | 二进制名称为 `codex.exe`，使用 `zip` 压缩包 |
| macOS/Linux | 二进制名称为 `codex`，使用 `tar.gz` 压缩包，设置可执行权限 |

#### 6.2.2 并发限制

- `AsyncAppServerClient` 使用 `_transport_lock` 序列化传输层调用
- `TurnHandle.stream()` 不支持并发消费者（显式检查并抛出错误）

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增量生成支持**
   - 当前每次生成完整文件，可添加 mtime 检查避免不必要的重写
   - 受益: 提升开发迭代速度

2. **更详细的生成日志**
   - 当前仅输出 "Done."，可添加生成的类/方法计数
   - 受益: 便于调试生成问题

3. **Schema 版本校验**
   - 在生成前检查 schema 版本兼容性
   - 受益: 早期发现协议不兼容问题

#### 6.3.2 中期改进

1. **类型注解完善**
   - 当前 `FIELD_ANNOTATION_OVERRIDES` 硬编码 `config` 和 `output_schema` 为 `JsonObject`
   - 可考虑从 schema 的 `additionalProperties` 标记自动推断

2. **生成代码分割**
   - 当前 `v2_all.py` 可能非常大，可按命名空间分割为多个文件
   - 受益: 改善 IDE 性能和导入速度

3. **文档生成集成**
   - 将 schema 中的 `description` 字段提取到生成的 Python docstring
   - 受益: 改善 SDK 文档体验

#### 6.3.3 长期改进

1. **双向绑定**
   - 当前仅 Rust → Python 单向生成
   - 可考虑 Python 端实验性 API 反馈到 Rust 协议定义

2. **运行时协议协商**
   - 当前 SDK 与运行时版本必须严格匹配
   - 可考虑添加协议版本协商，支持一定范围的兼容性

3. **生成器插件化**
   - 将生成逻辑拆分为可插拔的生成器
   - 受益: 支持其他语言/框架的代码生成

---

## 7. 测试覆盖

### 7.1 相关测试文件

| 测试文件 | 覆盖范围 |
|---------|---------|
| `test_contract_generation.py` | 验证生成产物与 schema 同步 |
| `test_artifact_workflow_and_binaries.py` | 验证打包流程和运行时解析 |
| `test_client_rpc_methods.py` | 验证 RPC 方法和通知处理 |
| `test_public_api_signatures.py` | 验证公共 API 签名一致性 |
| `test_public_api_runtime_behavior.py` | 验证运行时行为 |
| `test_async_client_behavior.py` | 验证异步客户端序列化 |
| `test_real_app_server_integration.py` | 集成测试（需真实 Codex 运行时）|

### 7.2 关键测试场景

```python
# test_contract_generation.py::test_generated_files_are_up_to_date
def test_generated_files_are_up_to_date():
    # 快照生成前的文件状态
    # 运行 generate-types
    # 验证文件无变更

# test_artifact_workflow_and_binaries.py::test_stage_sdk_release_injects_exact_runtime_pin
def test_stage_sdk_release_injects_exact_runtime_pin(tmp_path: Path):
    # 验证 stage-sdk 正确注入 codex-cli-bin=={version} 依赖
```

---

## 8. 附录

### 8.1 术语表

| 术语 | 说明 |
|-----|------|
| App Server | Codex 的 JSON-RPC 服务端，通过 stdio 与 SDK 通信 |
| v2 协议 | 当前主要的 API 协议版本，camelCase 命名 |
| Pydantic | Python 数据验证库，用于运行时类型检查 |
| datamodel-code-generator | 从 OpenAPI/JSON Schema 生成 Pydantic 模型的工具 |
| Notification | 服务器主动推送的事件通知 |
| Turn | 用户与 AI 的一次交互回合 |
| Thread | 对话线程，包含多个 Turn |

### 8.2 相关文档

- `sdk/python/README.md` - SDK 使用文档
- `codex-rs/app-server-protocol/README.md` - 协议定义文档
- `sdk/python/examples/` - 使用示例
