# apply_patch_tests.rs 深度研究文档

## 场景与职责

`apply_patch_tests.rs` 是 `apply_patch.rs` 的配套单元测试模块。当前测试覆盖非常有限，仅包含一个基础测试用例验证协议转换功能。

### 当前测试状态
- **测试数量**：1 个测试函数
- **代码行数**：21 行（含空行和导入）
- **覆盖范围**：仅测试 `convert_apply_patch_to_protocol` 函数的 Add 变体

---

## 功能点目的

### 唯一测试：Add 变体映射

```rust
#[test]
fn convert_apply_patch_maps_add_variant() {
    let tmp = tempdir().expect("tmp");
    let p = tmp.path().join("a.txt");
    
    // 创建 Add 类型的补丁操作
    let action = ApplyPatchAction::new_add_for_test(&p, "hello".to_string());
    
    // 转换为协议格式
    let got = convert_apply_patch_to_protocol(&action);
    
    // 验证结果
    assert_eq!(
        got.get(&p),
        Some(&FileChange::Add { content: "hello".to_string() })
    );
}
```

---

## 具体技术实现

### 测试依赖

```rust
use super::*;  // apply_patch 模块的所有内容
use pretty_assertions::assert_eq;
use tempfile::tempdir;  // 临时目录创建
```

### 测试辅助方法
测试使用了 `ApplyPatchAction::new_add_for_test()` 这个测试专用构造方法：

```rust
// 来自 codex_apply_patch crate
impl ApplyPatchAction {
    #[cfg(test)]
    pub fn new_add_for_test(path: &Path, content: String) -> Self {
        // 创建仅包含 Add 变更的补丁操作
    }
}
```

---

## 关键代码路径与文件引用

### 被测函数
- `convert_apply_patch_to_protocol()` - 补丁操作到协议格式的转换

### 测试数据流
```
tempdir() ──▶ ApplyPatchAction::new_add_for_test() ──▶ convert_apply_patch_to_protocol() ──▶ HashMap<PathBuf, FileChange>
```

---

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `tempfile::tempdir` | 创建临时目录和文件路径 |
| `pretty_assertions::assert_eq` | 测试失败时提供 diff |

---

## 风险、边界与改进建议

### 严重测试缺口

1. **未测试的变更类型**
   - `ApplyPatchFileChange::Delete` - 文件删除
   - `ApplyPatchFileChange::Update` - 文件更新（含 unified_diff）
   - `ApplyPatchFileChange::Update` with `move_path` - 文件移动

2. **未测试的核心逻辑**
   - `apply_patch()` 函数 - 模块的核心功能
   - `InternalApplyPatchInvocation` 的两种结果类型
   - 安全评估结果的映射
   - `ApplyPatchExec` 结构构造

3. **未测试的边界情况**
   - 空补丁操作
   - 多文件补丁
   - 无效路径
   - 权限不足场景

### 建议添加的测试

1. **协议转换完整测试**
   ```rust
   #[test]
   fn convert_apply_patch_maps_delete_variant() {
       let tmp = tempdir().expect("tmp");
       let p = tmp.path().join("delete.txt");
       let action = ApplyPatchAction::new_delete_for_test(&p, "old content".to_string());
       
       let got = convert_apply_patch_to_protocol(&action);
       
       assert_eq!(
           got.get(&p),
           Some(&FileChange::Delete { content: "old content".to_string() })
       );
   }

   #[test]
   fn convert_apply_patch_maps_update_variant() {
       let tmp = tempdir().expect("tmp");
       let p = tmp.path().join("update.txt");
       let action = ApplyPatchAction::new_update_for_test(
           &p,
           "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new".to_string(),
           None,
       );
       
       let got = convert_apply_patch_to_protocol(&action);
       
       assert!(matches!(
           got.get(&p),
           Some(FileChange::Update { unified_diff, move_path: None })
           if unified_diff == "--- a\n+++ b\n..."
       ));
   }

   #[test]
   fn convert_apply_patch_maps_move_variant() {
       let tmp = tempdir().expect("tmp");
       let src = tmp.path().join("old.txt");
       let dst = tmp.path().join("new.txt");
       let action = ApplyPatchAction::new_move_for_test(&src, &dst, "content".to_string());
       
       let got = convert_apply_patch_to_protocol(&action);
       
       assert!(matches!(
           got.get(&src),
           Some(FileChange::Update { move_path: Some(d), .. })
           if d == &dst
       ));
   }
   ```

2. **apply_patch 核心逻辑测试（需 mock）**
   ```rust
   #[tokio::test]
   async fn apply_patch_auto_approves_constrained_paths() {
       // 设置 TurnContext 和策略
       // 验证返回 DelegateToExec(auto_approved=true)
   }

   #[tokio::test]
   async fn apply_patch_asks_user_for_untrusted() {
       // 设置 UnlessTrusted 策略
       // 验证返回 DelegateToExec 且需要审批
   }

   #[tokio::test]
   async fn apply_patch_rejects_empty_patch() {
       // 验证空补丁返回 Output(Err)
   }
   ```

3. **集成测试建议**
   - 与 safety.rs 的集成测试
   - 与 tools/sandboxing.rs 的集成测试
   - 端到端的补丁应用测试（使用临时文件系统）

### 测试基础设施建议

1. **创建测试辅助库**
   ```rust
   // test_support.rs
   pub fn create_test_turn_context(policy: AskForApproval) -> TurnContext { ... }
   pub fn create_test_sandbox_policy() -> FileSystemSandboxPolicy { ... }
   ```

2. **使用 insta 快照测试**
   ```rust
   #[test]
   fn apply_patch_result_snapshot() {
       let result = apply_patch(...);
       insta::assert_debug_snapshot!(result);
   }
   ```

3. **参数化测试**
   ```rust
   #[test_case(AskForApproval::Never, Expected::AutoApprove)]
   #[test_case(AskForApproval::UnlessTrusted, Expected::AskUser)]
   #[test_case(AskForApproval::OnFailure, Expected::AutoApprove)]
   fn test_approval_policy(policy: AskForApproval, expected: Expected) { ... }
   ```
