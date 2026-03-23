# list_dir.rs 研究文档

## 场景与职责

`list_dir.rs` 是 Codex Rust 核心库的集成测试套件，专注于验证 **`list_dir` 工具** 的功能正确性。该工具允许模型列出指定目录的内容，支持分页（offset/limit）和深度控制（depth），是文件系统操作的核心工具之一。

### 核心职责
1. **验证 list_dir 工具的基本功能**：目录条目列出、分页、深度控制
2. **测试不同深度参数的行为**：depth=1（仅当前目录）、depth=2（包含子目录）、depth=3（包含孙目录）
3. **验证输出格式**：确保输出格式符合预期（`E{n}: [type] name`）

### 重要说明
当前所有测试都被标记为 `#[ignore = "disabled until we enable list_dir tool"]`，表明 `list_dir` 工具目前处于禁用状态，等待后续启用。

---

## 功能点目的

### 1. 基本目录列出测试 (`list_dir_tool_returns_entries`)
- **目的**：验证基本的目录列出功能
- **测试场景**：
  - 创建目录结构：`sample_dir/alpha.txt`、`sample_dir/nested/`
  - 调用 `list_dir` 工具，参数：`offset=1, limit=2`
  - 验证输出格式：`E1: [file] alpha.txt\nE2: [dir] nested`

### 2. 深度一级测试 (`list_dir_tool_depth_one_omits_children`)
- **目的**：验证 `depth=1` 只列出当前目录内容，不包含子目录内容
- **测试场景**：
  - 创建目录结构：`depth_one/alpha.txt`、`depth_one/nested/beta.txt`
  - 调用 `list_dir` 工具，参数：`depth=1`
  - 验证输出只包含 `alpha.txt` 和 `nested` 目录，不包含 `beta.txt`

### 3. 深度二级测试 (`list_dir_tool_depth_two_includes_children_only`)
- **目的**：验证 `depth=2` 列出当前目录和子目录内容
- **测试场景**：
  - 创建目录结构：`depth_two/alpha.txt`、`depth_two/nested/beta.txt`、`depth_two/nested/grand/gamma.txt`
  - 调用 `list_dir` 工具，参数：`depth=2`
  - 验证输出包含到孙目录层级，但不包含曾孙目录内容
  - 期望输出：`E1: [file] alpha.txt`、`E2: [dir] nested`、`E3: [file] nested/beta.txt`、`E4: [dir] nested/grand`

### 4. 深度三级测试 (`list_dir_tool_depth_three_includes_grandchildren`)
- **目的**：验证 `depth=3` 列出当前目录、子目录和孙目录内容
- **测试场景**：
  - 与 depth=2 测试相同的目录结构
  - 调用 `list_dir` 工具，参数：`depth=3`
  - 验证输出包含 `nested/grand/gamma.txt`
  - 期望输出包含 5 个条目，包括最深的文件

---

## 具体技术实现

### 测试基础设施

#### Mock 设置

```rust
let mocks = mount_function_call_agent_response(&server, call_id, &arguments, "list_dir").await;
```

使用 `mount_function_call_agent_response` 设置两阶段 Mock：
1. 第一阶段：模型调用 `list_dir` 工具
2. 第二阶段：模型返回完成消息

#### 参数构造

```rust
let arguments = json!({
    "dir_path": dir_path,
    "offset": 1,
    "limit": 2,
}).to_string();
```

#### 结果验证

```rust
let req = mocks.completion.single_request();
let (content_opt, _) = req
    .function_call_output_content_and_success(call_id)
    .expect("function_call_output present");
let output = content_opt.expect("output content present in tool output");
assert_eq!(output, "E1: [file] alpha.txt\nE2: [dir] nested");
```

### 工具参数定义

```rust
// list_dir 工具参数（推测）
{
    "dir_path": string,  // 目录路径
    "offset": number,    // 起始偏移量（1-based）
    "limit": number,     // 返回条目数上限
    "depth": number,     // 递归深度（可选，默认 1）
}
```

### 输出格式

```
E{n}: [type] name
```

其中：
- `{n}`：条目序号（从 offset 开始）
- `[type]`：`file` 或 `dir`
- `name`：文件名或目录名（相对路径）

---

## 关键代码路径与文件引用

### 测试文件
- **当前文件**：`codex-rs/core/tests/suite/list_dir.rs` (167 行)

### 实现文件（推测）
- **`codex-rs/core/src/tools/handlers/list_dir.rs`**：list_dir 工具处理器（如果存在）
- **`codex-rs/core/src/tools/spec.rs`**：工具定义和参数规范

### 测试支持库
- **`codex-rs/core/tests/common/responses.rs`**：
  - `mount_function_call_agent_response`：函数调用响应 Mock
- **`codex-rs/core/tests/common/test_codex.rs`**：
  - `test_codex().build()`：测试环境构建
  - `submit_turn`：提交用户输入

---

## 依赖与外部交互

### 外部依赖
1. **wiremock**：HTTP Mock 服务器
2. **tokio**：异步运行时
3. **serde_json**：JSON 序列化/反序列化
4. **pretty_assertions**：测试断言美化

### 内部依赖
1. **codex_protocol**：协议类型定义
2. **core_test_support**：测试支持库

### 网络依赖
- 使用 `skip_if_no_network!` 宏在沙箱环境中跳过测试
- 测试通过 Mock 服务器运行，不依赖真实网络

---

## 风险、边界与改进建议

### 已知风险

1. **工具禁用状态**：
   - 所有测试被标记为 `#[ignore]`，工具当前不可用
   - 可能存在实现与测试不同步的风险

2. **平台限制**：
   - 使用 `#![cfg(not(target_os = "windows"))]` 排除 Windows 平台
   - 路径处理可能在 Windows 上有差异

3. **路径处理**：
   - 测试使用 `to_string_lossy()` 转换路径
   - 非 UTF-8 路径可能导致问题

### 边界情况

1. **空目录**：
   - 当前测试未覆盖空目录场景
   - 建议增加空目录返回空列表的测试

2. **权限不足**：
   - 当前测试未覆盖权限不足场景
   - 建议增加错误处理测试

3. **符号链接**：
   - 当前测试未涉及符号链接处理
   - 建议增加符号链接遍历测试

4. **循环引用**：
   - 符号链接导致的目录循环
   - 建议增加循环检测测试

5. **大目录**：
   - 当前测试使用小目录
   - 建议增加大目录分页性能测试

### 改进建议

1. **启用测试**：
   - 移除 `#[ignore]` 属性，启用测试
   - 确保工具实现与测试同步

2. **增加测试覆盖**：
   - 空目录测试
   - 权限错误测试
   - 不存在的路径测试
   - 符号链接测试
   - 特殊字符文件名测试

3. **边界值测试**：
   - `offset=0` 和负数 offset 的处理
   - `limit=0` 的处理
   - 超大 offset/limit 的处理
   - `depth=0` 的处理

4. **性能测试**：
   - 大目录列出性能
   - 深层递归性能

5. **跨平台测试**：
   - 在 Windows 上启用测试
   - 验证路径分隔符处理
