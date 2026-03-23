# apply_patch_cli.rs 研究文档

## 场景与职责

`apply_patch_cli.rs` 是 Codex Core 的集成测试文件，专注于测试 **apply_patch 工具** 的完整功能。该工具允许模型通过声明式补丁语法安全地修改文件系统，是 Codex 最核心的代码编辑能力。

核心测试场景包括：
1. 多操作类型（Add/Update/Delete/Move）的补丁应用
2. 多 chunk 更新（单个文件的多个修改区域）
3. 文件移动与重命名（支持跨目录）
4. 各种模型输出格式（Freeform/Function/Shell/Heredoc）
5. 错误处理与验证（缺失上下文、路径遍历、空补丁等）
6. 差异事件（TurnDiff）生成与聚合

## 功能点目的

### 1. 补丁操作类型
- **Add File**: 创建新文件
- **Update File**: 修改现有文件，支持多个 hunks
- **Delete File**: 删除文件
- **Move to**: 与 Update 配合使用，实现文件移动/重命名

### 2. 模型输出格式支持
支持多种方式接收模型的补丁输出：
- **Freeform**: 直接文本输出（GPT-5 模型）
- **Function**: JSON 包裹的函数调用参数
- **Shell**: 通过 `shell` 工具调用 `apply_patch` 命令
- **ShellViaHeredoc**: 使用 heredoc 传递补丁
- **ShellCommandViaHeredoc**: 通过 `shell_command` 工具

### 3. 安全验证
- 路径遍历防护（阻止 `../` 跳出工作区）
- 沙箱策略检查
- 上下文匹配验证（确保修改基于最新文件内容）

### 4. 差异追踪
- `PatchApplyBegin`/`PatchApplyEnd` 事件
- `TurnDiff` 统一差异格式输出
- 多补丁聚合（单次对话中的多个 apply_patch 调用）

## 具体技术实现

### 补丁语法

```
*** Begin Patch
*** Add File: new.txt
+content line 1
+content line 2
*** Update File: existing.txt
*** Move to: renamed.txt
@@ context hint
-old line
+new line
*** Delete File: obsolete.txt
*** End Patch
```

### 关键流程

```
模型输出补丁
    ↓
解析补丁（codex_apply_patch crate）
    ↓
验证补丁语法和上下文
    ↓
计算文件路径和权限
    ↓
检查沙箱策略
    ↓
委托给 ApplyPatchRuntime
    ↓
执行文件系统操作
    ↓
生成 TurnDiff 事件
    ↓
返回结果给模型
```

### 核心数据结构

**ApplyPatchModelOutput 枚举**（测试用）:
```rust
pub enum ApplyPatchModelOutput {
    Freeform,           // 自由文本格式
    Function,           // JSON 函数调用
    Shell,              // shell 工具
    ShellViaHeredoc,    // heredoc 方式
    ShellCommandViaHeredoc,  // shell_command 工具
}
```

**ApplyPatchAction**:
```rust
pub struct ApplyPatchAction {
    pub cwd: PathBuf,
    // changes: BTreeMap<PathBuf, ApplyPatchFileChange>
}

pub enum ApplyPatchFileChange {
    Add { content: String },
    Update { move_path: Option<PathBuf>, hunks: Vec<Hunk> },
    Delete,
}
```

**Hunk 结构**:
```rust
pub struct Hunk {
    pub context_before: Vec<String>,  // 前置上下文行
    pub removals: Vec<String>,        // 删除行（以 - 开头）
    pub additions: Vec<String>,       // 添加行（以 + 开头）
    pub context_after: Vec<String>,  // 后置上下文行
}
```

### 测试辅助函数

**apply_patch_harness**:
```rust
pub async fn apply_patch_harness() -> Result<TestCodexHarness> {
    apply_patch_harness_with(|builder| builder).await
}
```

**mount_apply_patch**:
```rust
pub async fn mount_apply_patch(
    harness: &TestCodexHarness,
    call_id: &str,
    patch: &str,
    assistant_msg: &str,
    output_type: ApplyPatchModelOutput,
)
```

**apply_patch_responses**:
```rust
fn apply_patch_responses(
    call_id: &str,
    patch: &str,
    assistant_msg: &str,
    output_type: ApplyPatchModelOutput,
) -> Vec<String>
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/apply_patch_cli.rs` - 本测试文件（1436 行）

### 被测试的核心代码
- `codex-rs/core/src/tools/handlers/apply_patch.rs` - 工具处理器
- `codex-rs/core/src/apply_patch.rs` - 补丁应用逻辑
- `codex-rs/apply_patch/src/lib.rs` - 补丁解析 crate
- `codex-rs/core/src/tools/runtimes/apply_patch.rs` - 运行时实现

### 补丁解析 crate
- `codex-rs/apply_patch/` - 独立的补丁解析库
  - 解析 `maybe_parse_apply_patch_verified()`
  - 验证上下文匹配
  - 生成文件系统操作列表

### 测试支持代码
- `codex-rs/core/tests/common/responses.rs`:
  - `ev_apply_patch_call()` - 根据输出类型构造事件
  - `ev_apply_patch_custom_tool_call()` - Freeform 格式
  - `ev_apply_patch_function_call()` - Function 格式
  - `ev_apply_patch_shell_call()` - Shell 格式

- `codex-rs/core/tests/common/test_codex.rs`:
  - `TestCodexHarness::apply_patch_output()` - 获取补丁输出

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|------|------|
| `test_case` | 参数化测试 |
| `codex_test_macros::large_stack_test` | 大栈测试属性 |
| `pretty_assertions` | 美观的断言输出 |
| `base64` | PowerShell 编码 |

### 参数化测试模式
```rust
#[large_stack_test]
#[test_case(ApplyPatchModelOutput::Freeform)]
#[test_case(ApplyPatchModelOutput::Function)]
#[test_case(ApplyPatchModelOutput::Shell)]
#[test_case(ApplyPatchModelOutput::ShellViaHeredoc)]
#[test_case(ApplyPatchModelOutput::ShellCommandViaHeredoc)]
async fn apply_patch_cli_multiple_operations_integration(
    output_type: ApplyPatchModelOutput,
) -> Result<()>
```

### 动态响应器
测试实现了 `DynamicApplyFromRead` 响应器，模拟真实的多轮交互：
1. 第一轮：读取源文件内容
2. 第二轮：基于读取内容动态生成补丁
3. 第三轮：确认完成

```rust
struct DynamicApplyFromRead {
    num_calls: AtomicI32,
    read_call_id: String,
    apply_call_id: String,
}

impl Respond for DynamicApplyFromRead {
    fn respond(&self, request: &wiremock::Request) -> ResponseTemplate {
        let call_num = self.num_calls.fetch_add(1, Ordering::SeqCst);
        match call_num {
            0 => { /* 返回 shell_command 调用 */ }
            1 => { /* 解析输出，生成 apply_patch 调用 */ }
            2 => { /* 返回完成消息 */ }
            _ => panic!("no response for call {call_num}"),
        }
    }
}
```

## 风险、边界与改进建议

### 当前风险点

1. **大栈测试依赖**
   - 所有测试使用 `#[large_stack_test]`，表明 apply_patch 处理可能消耗大量栈空间
   - 在资源受限环境中可能失败

2. **平台特定代码**
   - Windows 测试使用 PowerShell 编码脚本
   ```rust
   let script = "$ProgressPreference = 'SilentlyContinue'; ...";
   let encoded = BASE64_STANDARD.encode(
       script.encode_utf16().flat_map(u16::to_le_bytes).collect::<Vec<u8>>()
   );
   ```
   - 增加了维护复杂度

3. **网络依赖**
   - 所有测试使用 `skip_if_no_network!`，需要实际网络连接
   - 无法作为纯单元测试运行

4. **时间依赖**
   - 部分测试使用 `timeout_ms: 5_000`，在慢速环境中可能超时

### 边界情况

1. **二进制文件**
   - 测试未覆盖二进制文件的补丁应用

2. **超大文件**
   - 未测试 GB 级文件的补丁处理

3. **并发修改**
   - 未测试多线程同时修改同一文件的场景

4. **特殊字符**
   - 虽然测试了 Unicode（`naïve café`），但未覆盖所有 Unicode 边界情况

5. **符号链接**
   - 未测试对符号链接的补丁操作

### 改进建议

1. **减少网络依赖**
   - 将 Mock 服务器扩展为支持 apply_patch 的完整模拟
   - 允许在无网络环境下运行基础测试

2. **增加压力测试**
   ```rust
   // 建议添加：
   #[large_stack_test]
   async fn apply_patch_very_large_file() { ... }
   
   #[large_stack_test]
   async fn apply_patch_many_files() { ... }
   ```

3. **并发安全测试**
   ```rust
   #[tokio::test]
   async fn apply_patch_concurrent_modifications() { ... }
   ```

4. **错误恢复测试**
   - 测试磁盘满时的优雅降级
   - 测试权限拒绝时的错误信息

5. **性能基准**
   - 添加基准测试测量补丁应用速度
   - 监控大补丁的内存使用

6. **模糊测试**
   - 对补丁解析器进行模糊测试
   - 发现潜在的解析漏洞

7. **简化 Windows 测试**
   - 考虑使用跨平台的测试数据
   - 或者将平台特定逻辑提取到单独的测试文件

8. **差异格式验证**
   - 当前测试只检查 diff 包含特定字符串
   - 建议验证完整的统一差异格式合规性
