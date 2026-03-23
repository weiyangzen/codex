# BUILD.bazel 研究文档

## 场景与职责

该文件是 `codex-rs/utils/json-to-toml` 目录的 Bazel 构建配置文件，负责定义该 Rust crate 的 Bazel 构建规则。它是 Bazel 构建系统识别和编译该工具库的核心入口点。

该 crate 是一个小型工具库，提供 JSON 到 TOML 的数据格式转换功能，被 `mcp-server` 和 `app-server` 等上游组件依赖使用。

## 功能点目的

1. **声明 Bazel 构建目标**：通过 `codex_rust_crate` 宏定义该 crate 的构建规则
2. **统一构建配置**：复用项目根目录 `defs.bzl` 中定义的 `codex_rust_crate` 宏，确保与整个工作区的构建标准一致
3. **指定 crate 名称**：将 Bazel 目标名 `json-to-toml` 映射到 Rust crate 名 `codex_utils_json_to_toml`

## 具体技术实现

### 关键流程

```bazel
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "json-to-toml",
    crate_name = "codex_utils_json_to_toml",
)
```

1. **加载宏定义**：从项目根目录的 `defs.bzl` 加载 `codex_rust_crate` 宏
2. **调用宏创建目标**：
   - `name`: Bazel 目标标识符，使用目录名 `json-to-toml`
   - `crate_name`: Rust crate 名称，遵循 `codex_utils_*` 命名规范

### 数据结构

该文件本身是一个简单的 Bazel 构建文件，依赖外部宏实现。关键数据结构在 `defs.bzl` 中定义：

```python
def codex_rust_crate(
    name,                    # Bazel 目标名
    crate_name,              # Rust crate 名
    crate_features = [],     # Cargo features
    crate_srcs = None,       # 源码文件（默认 src/**/*.rs）
    build_script_enabled = True,  # 是否启用 build.rs
    ...
)
```

### 构建产物

根据 `defs.bzl` 的实现，该宏会生成以下 Bazel 目标：
- `json-to-toml`: 主库目标（rust_library）
- `json-to-toml-unit-tests-bin`: 单元测试二进制
- `json-to-toml-unit-tests`: 单元测试包装目标（workspace_root_test）

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/utils/json-to-toml/BUILD.bazel` - 本文件

### 依赖文件
- `/home/sansha/Github/codex/defs.bzl` - 提供 `codex_rust_crate` 宏定义
- `/home/sansha/Github/codex/codex-rs/utils/json-to-toml/Cargo.toml` - Cargo 配置（被宏隐式读取）
- `/home/sansha/Github/codex/codex-rs/utils/json-to-toml/src/lib.rs` - 源码文件

### 调用方（上游依赖）
- `/home/sansha/Github/codex/codex-rs/mcp-server/BUILD.bazel` - 依赖此 crate
- `/home/sansha/Github/codex/codex-rs/app-server/BUILD.bazel` - 依赖此 crate

## 依赖与外部交互

### Bazel 依赖

| 类型 | 依赖项 | 说明 |
|------|--------|------|
| 加载 | `//:defs.bzl` | 项目级 Rust crate 宏定义 |
| 外部 | `@crates//:defs.bzl` | 通过宏间接依赖，用于解析 Cargo 依赖 |
| 外部 | `@rules_rust//rust:defs.bzl` | 通过宏间接依赖，Rust 规则集 |

### Cargo 依赖（通过 Cargo.toml）
- `serde_json` - JSON 序列化/反序列化
- `toml` - TOML 序列化/反序列化
- `pretty_assertions` - 测试断言（dev 依赖）

### 上游调用方

1. **mcp-server** (`codex-rs/mcp-server/Cargo.toml`):
   ```toml
   codex-utils-json-to-toml = { workspace = true }
   ```
   用途：将 MCP 工具调用中的 JSON 配置覆盖转换为 TOML 格式

2. **app-server** (`codex-rs/app-server/Cargo.toml`):
   ```toml
   codex-utils-json-to-toml = { workspace = true }
   ```
   用途：处理配置覆盖的格式转换

## 风险、边界与改进建议

### 风险点

1. **依赖传递风险**：
   - 该 crate 被 `mcp-server` 和 `app-server` 两个核心服务依赖
   - 任何 API 变更都需要同步更新所有调用方

2. **宏抽象风险**：
   - 构建逻辑高度依赖 `defs.bzl` 宏的实现细节
   - 宏的变更可能影响该 crate 的构建行为

3. **命名一致性**：
   - Bazel 目标名 `json-to-toml` 与 crate 名 `codex_utils_json_to_toml` 不一致
   - 需要在引用时注意区分（Bazel 使用短横线，Rust 使用下划线）

### 边界条件

1. **无自定义构建脚本**：该 crate 没有 `build.rs`，`build_script_enabled` 默认为 true 但宏会检测文件存在性
2. **无二进制产出**：纯库 crate，不生成可执行文件
3. **无特性标志**：`crate_features` 为空列表，使用默认特性编译

### 改进建议

1. **文档增强**：
   - 在 BUILD.bazel 中添加注释说明该 crate 的用途
   - 添加上游调用方引用注释，便于追踪影响范围

2. **构建优化**：
   - 考虑显式设置 `build_script_enabled = False` 以避免不必要的文件检测

3. **测试覆盖**：
   - 确保单元测试在 Bazel 和 Cargo 两种构建方式下都能正常运行
   - 考虑添加集成测试验证与上游调用方的兼容性

4. **版本管理**：
   - 该 crate 目前使用 workspace 统一版本管理（`version.workspace = true`）
   - 若未来独立演进，需要考虑版本兼容性策略
