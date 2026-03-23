# apply_patch_tests.rs 深度研究文档

## 场景与职责

`apply_patch_tests.rs` 是 `apply_patch.rs` 的单元测试模块，负责验证 patch 处理相关的核心函数，特别是文件路径提取逻辑。该测试文件作为内联测试模块被包含在 `apply_patch.rs` 中。

## 功能点目的

### 测试覆盖范围

1. **Move 操作路径提取** - 验证文件移动时源路径和目标路径都被正确识别

## 具体技术实现

### 测试用例详情

#### 1. `approval_keys_include_move_destination`

```rust
#[test]
fn approval_keys_include_move_destination() {
    let tmp = TempDir::new().expect("tmp");
    let cwd = tmp.path();
    std::fs::create_dir_all(cwd.join("old")).expect("create old dir");
    std::fs::create_dir_all(cwd.join("renamed/dir")).expect("create dest dir");
    std::fs::write(cwd.join("old/name.txt"), "old content\n").expect("write old file");
    let patch = r#"*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content
*** End Patch"#;
    let argv = vec!["apply_patch".to_string(), patch.to_string()];
    let action = match codex_apply_patch::maybe_parse_apply_patch_verified(&argv, cwd) {
        MaybeApplyPatchVerified::Body(action) => action,
        other => panic!("expected patch body, got: {other:?}"),
    };

    let keys = file_paths_for_action(&action);
    assert_eq!(keys.len(), 2);
}
```

**测试目的：**
- 验证 `file_paths_for_action` 函数在文件移动场景下正确提取两个路径
- 源文件：`old/name.txt`
- 目标文件：`renamed/dir/name.txt`

**测试步骤：**
1. 创建临时目录结构
2. 创建源文件
3. 构造包含 Move 操作的 patch
4. 解析 patch 获取 `ApplyPatchAction`
5. 调用 `file_paths_for_action` 提取路径
6. 验证返回 2 个路径

## 关键代码路径与文件引用

| 测试函数 | 被测函数 | 所在文件 |
|---------|---------|---------|
| `approval_keys_include_move_destination` | `file_paths_for_action` | apply_patch.rs:46 |

## 依赖与外部交互

### 测试依赖

```rust
use super::*;  // 引入 apply_patch.rs 的所有私有函数
use codex_apply_patch::MaybeApplyPatchVerified;  // Patch 解析结果枚举
use pretty_assertions::assert_eq;  // 更好的差异输出
use tempfile::TempDir;  // 临时目录
```

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_apply_patch` | Patch 解析验证 |
| `tempfile` | 临时目录创建 |
| `pretty_assertions` | 测试断言美化 |

## 风险、边界与改进建议

### 测试覆盖缺口

当前测试文件仅 28 行，覆盖非常有限：

1. **缺少基础功能测试**
   - `ApplyPatchHandler::handle` 主流程
   - `effective_patch_permissions` 权限计算
   - `write_permissions_for_paths` 权限生成

2. **缺少边界测试**
   - 空 patch 处理
   - 语法错误处理
   - 无效路径处理
   - 权限不足场景

3. **缺少集成测试**
   - 与 `ApplyPatchRuntime` 集成
   - 与 `ToolOrchestrator` 集成
   - 事件发射验证

4. **缺少工具规格测试**
   - `create_apply_patch_freeform_tool` 输出验证
   - `create_apply_patch_json_tool` 输出验证

### 改进建议

1. **添加基础单元测试**
   ```rust
   #[test]
   fn file_paths_for_action_add_file() {
       // 测试 Add File 场景的路径提取
   }
   
   #[test]
   fn file_paths_for_action_delete_file() {
       // 测试 Delete File 场景的路径提取
   }
   
   #[test]
   fn write_permissions_for_paths_basic() {
       // 测试权限生成逻辑
   }
   ```

2. **添加错误场景测试**
   ```rust
   #[test]
   fn handle_invalid_patch_syntax() {
       // 测试无效 patch 语法处理
   }
   
   #[test]
   fn handle_path_traversal_attempt() {
       // 测试路径遍历攻击防护
   }
   ```

3. **添加集成测试**
   ```rust
   #[tokio::test]
   async fn test_apply_patch_full_flow() {
       // 使用 Mock 测试完整流程
   }
   ```

4. **测试组织建议**
   - 当前测试文件较小（28 行），可保持内联
   - 如测试增长超过 100 行，建议拆分为独立文件
