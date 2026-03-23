# apply_patch.rs 深度研究文档

## 场景与职责

`apply_patch.rs` 是 `codex-exec` CLI 工具的核心集成测试模块，专门验证 `apply_patch` 功能的多种调用方式。该模块测试两种主要场景：

1. **独立 CLI 模式**: 直接使用 `codex-exec` 作为 `apply_patch` 命令行工具
2. **AI 工具调用模式**: 模拟 Codex 模型通过 function call 或 custom tool call 触发 patch 应用

**核心场景**：
- 用户需要直接应用 patch 文件而不启动完整 Codex 会话
- 验证 AI 生成的 patch 能够被正确解析和应用
- 测试多种 patch 格式（标准格式、自由格式）

## 功能点目的

### 1. 独立 CLI 测试 (`test_standalone_exec_cli_can_use_apply_patch`)
验证 `codex-exec` 可以直接作为 `apply_patch` 工具使用，无需启动完整 AI 会话。

**测试流程**：
- 创建临时目录和测试文件
- 直接调用 `codex-exec` 并传入 `CODEX_CORE_APPLY_PATCH_ARG1` 参数
- 验证文件被正确修改

### 2. 工具调用测试 (`test_apply_patch_tool`)
验证 Codex 通过 function call 触发 patch 应用的功能。

**测试流程**：
- 模拟 SSE 流包含 `apply_patch` function call
- 验证文件创建和更新操作

### 3. 自由格式 Patch 测试 (`test_apply_patch_freeform_tool`)
验证非标准格式的 patch 也能被正确应用。

## 具体技术实现

### Patch 格式规范

**标准格式**（`add_patch`）：
```
*** Begin Patch
*** Add File: test.md
+Hello world
*** End Patch
```

**更新格式**（`update_patch`）：
```
*** Begin Patch
*** Update File: test.md
@@
-Hello world
+Final text
*** End Patch
```

**自由格式**（`freeform_update_patch`）：
```
*** Begin Patch
*** Update File: app.py
@@  def method():
-    return False
+
+    return True
*** End Patch
```

### 关键数据结构

**ApplyPatchModelOutput 枚举**（来自 `codex_apply_patch` crate）：
```rust
pub enum ApplyPatchModelOutput {
    Freeform,              // 自由格式
    Function,              // Function call 格式
    Shell,                 // Shell 调用格式
    ShellViaHeredoc,       // Heredoc 格式
    ShellCommandViaHeredoc,// Shell command 格式
}
```

**SSE 事件构造**（来自 `core_test_support::responses`）：
```rust
// Custom tool call 格式
pub fn ev_apply_patch_custom_tool_call(call_id: &str, patch: &str) -> Value

// Function call 格式  
pub fn ev_apply_patch_function_call(call_id: &str, patch: &str) -> Value
```

### 测试执行流程

```
测试启动
  ↓
创建临时目录和初始文件
  ↓
构造 SSE 响应序列（多轮交互）
  ├─ 第1轮: apply_patch 调用（创建文件）
  ├─ 第2轮: apply_patch 调用（更新文件）
  └─ 第3轮: 完成
  ↓
启动 Mock SSE 服务器
  ↓
执行 codex-exec 命令
  ├─ --skip-git-repo-check
  ├─ -s danger-full-access（危险模式，允许文件修改）
  └─ <prompt>
  ↓
验证文件内容符合预期
```

## 关键代码路径与文件引用

### 被测试代码路径

1. **Apply Patch 库**: `codex-rs/apply_patch/src/lib.rs`
   - Patch 解析和应用的核心逻辑
   - `CODEX_CORE_APPLY_PATCH_ARG1` 常量定义

2. **工具调用处理**: `codex-rs/core/src/tools/apply_patch.rs`
   - 处理 AI 触发的 apply_patch 调用
   - 将模型输出转换为文件操作

3. **Exec CLI 集成**: `codex-rs/exec/src/lib.rs`
   - 处理 `--dangerously-bypass-approvals-and-sandbox` 模式
   - 允许直接文件系统操作

### 测试依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `codex_apply_patch` | workspace | Patch 解析库 |
| `core_test_support::responses` | `codex-rs/core/tests/common/responses.rs` | SSE Mock 工具 |
| `test_codex_exec` | `codex-rs/core/tests/common/test_codex_exec.rs` | 测试环境构造 |

### 预期结果文件

**`codex-rs/exec/tests/fixtures/apply_patch_freeform_final.txt`**:
```python
class BaseClass:
  def method():

    return True
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `codex-apply-patch` | Patch 解析和应用 |
| `assert_cmd` | CLI 测试断言 |
| `tempfile` | 临时目录 |
| `wiremock` | HTTP Mock |

### 环境要求

- **非 Windows 平台**: 使用 `#!cfg(not(target_os = "windows"))]`
- **网络检查**: `skip_if_no_network!` 宏检查网络可用性

### 命令行参数

```rust
// 独立模式调用
codex-exec "CODEX_CORE_APPLY_PATCH_ARG1" "<patch_content>"

// AI 模式调用
codex-exec --skip-git-repo-check -s danger-full-access "<prompt>"
```

## 风险、边界与改进建议

### 当前风险

1. **沙箱模式依赖**: 测试使用 `danger-full-access` 模式，可能掩盖沙箱限制问题
2. **Mock 简化**: 使用预设 SSE 响应，不测试真实模型交互
3. **格式覆盖不全**: 仅测试部分 patch 格式变体

### 边界情况

1. **Patch 冲突**: 未测试与现有文件内容冲突的情况
2. **大文件处理**: 未测试大文件 patch 应用
3. **编码问题**: 未测试非 UTF-8 编码文件
4. **权限问题**: 未测试只读文件系统

### 改进建议

1. **增加错误场景测试**:
   ```rust
   // Patch 格式错误
   // 目标文件不存在
   // 权限不足
   ```

2. **沙箱集成测试**: 在 `workspace-write` 模式下测试，而非仅 `danger-full-access`

3. **并发测试**: 验证多个并发 patch 应用

4. **性能测试**: 大文件 patch 应用性能基准

5. **模糊测试**: 对 patch 解析器进行模糊测试，发现潜在崩溃

### 相关文件

- `codex-rs/exec/tests/fixtures/apply_patch_freeform_final.txt` - 预期输出
- `codex-rs/apply_patch/src/lib.rs` - Patch 解析实现
- `codex-rs/core/src/tools/apply_patch.rs` - 工具集成
