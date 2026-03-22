# 研究文档: other.txt

## 场景与职责

`other.txt` 是 `apply-patch` 测试场景 `010_move_overwrites_existing_destination` 的**对照文件（control file）**，用于验证 patch 操作的**隔离性**和**无副作用**特性。该文件位于 `input/old/other.txt`，在测试过程中应保持内容不变，确保 apply-patch 只影响 patch 中明确指定的文件。

### 测试场景定位
- **场景编号**: 010_move_overwrites_existing_destination
- **文件角色**: 对照/验证文件（非操作目标）
- **测试目的**: 验证 patch 应用不会影响未指定的文件

### 核心职责
1. **隔离性验证**: 确保 apply-patch 只修改 patch 中明确声明的文件
2. **副作用检测**: 验证文件系统操作不会意外影响其他文件
3. **目录结构保持**: 确认源文件被移动后，其所在目录中的其他文件不受影响

## 功能点目的

### 测试设计意图
```
input/old/
├── name.txt    ← Patch 操作目标（将被移动并修改）
└── other.txt   ← 本文件（对照组，应保持不变）
```

### 验证点
1. **文件保留**: 当 `name.txt` 被移动到新位置后，`old/` 目录应仍然保留 `other.txt`
2. **内容不变**: `other.txt` 的内容在 patch 应用前后应完全一致
3. **权限不变**: 文件的元数据（权限、时间戳等）不应被意外修改

### 预期行为
| 阶段 | name.txt | other.txt |
|------|----------|-----------|
| 初始状态 | 存在于 `old/name.txt` | 存在于 `old/other.txt` |
| Patch 应用 | 移动至 `renamed/dir/name.txt` | **保持不变** |
| 最终状态 | 不存在于 `old/` | 仍存在于 `old/other.txt` |

## 具体技术实现

### 文件内容分析
```
内容: "unrelated file"
大小: 15 bytes (含换行符)
```

该内容设计意图明确：
- **语义清晰**: "unrelated file" 直接表明此文件与 patch 操作无关
- **简单可验证**: 短文本内容易于在测试中断言
- **无特殊字符**: 避免编码、换行符等跨平台问题

### 测试验证逻辑

在 `scenarios.rs` 的 `run_apply_patch_scenario()` 函数中：

```rust
// 1. 复制 input 到临时目录
copy_dir_recursive(&input_dir, tmp.path())?;

// 2. 执行 patch
Command::new(cargo_bin("apply_patch")?)
    .arg(patch)
    .current_dir(tmp.path())
    .output()?;

// 3. 比较完整目录快照
let expected_snapshot = snapshot_dir(&expected_dir)?;
let actual_snapshot = snapshot_dir(tmp.path())?;
assert_eq!(actual_snapshot, expected_snapshot);
```

### 快照比对机制

`snapshot_dir()` 函数生成目录的完整快照：

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
enum Entry {
    File(Vec<u8>),  // 文件内容（二进制）
    Dir,            // 目录标记
}

// BTreeMap 确保确定性顺序
fn snapshot_dir(root: &Path) -> anyhow::Result<BTreeMap<PathBuf, Entry>> {
    // 递归遍历目录，收集所有文件和目录
}
```

### 预期目录结构对比

**Input 状态:**
```
input/
├── old/
│   ├── name.txt      (内容: "from")
│   └── other.txt     (内容: "unrelated file") ← 本文件
└── renamed/dir/name.txt  (内容: "existing")
```

**Expected 状态:**
```
expected/
├── old/
│   └── other.txt     (内容: "unrelated file") ← 必须保持不变
└── renamed/dir/name.txt  (内容: "new")
```

## 关键代码路径与文件引用

### 测试框架代码
- **文件**: `codex-rs/apply-patch/tests/suite/scenarios.rs`

关键函数：
```rust
/// 执行单个测试场景
fn run_apply_patch_scenario(dir: &Path) -> anyhow::Result<()> {
    let tmp = tempdir()?;
    
    // 复制输入文件
    let input_dir = dir.join("input");
    copy_dir_recursive(&input_dir, tmp.path())?;
    
    // 读取并执行 patch
    let patch = fs::read_to_string(dir.join("patch.txt"))?;
    Command::new(cargo_bin("apply_patch")?)
        .arg(patch)
        .current_dir(tmp.path())
        .output()?;
    
    // 完整快照比对
    let expected_dir = dir.join("expected");
    let expected_snapshot = snapshot_dir(&expected_dir)?;
    let actual_snapshot = snapshot_dir(tmp.path())?;
    assert_eq!(actual_snapshot, expected_snapshot);
    
    Ok(())
}
```

### 目录复制逻辑
```rust
fn copy_dir_recursive(src: &Path, dst: &Path) -> anyhow::Result<()> {
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let path = entry.path();
        let dest_path = dst.join(entry.file_name());
        
        let metadata = fs::metadata(&path)?;
        if metadata.is_dir() {
            fs::create_dir_all(&dest_path)?;
            copy_dir_recursive(&path, &dest_path)?;
        } else if metadata.is_file() {
            if let Some(parent) = dest_path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(&path, &dest_path)?;
        }
    }
    Ok(())
}
```

### 快照生成逻辑
```rust
fn snapshot_dir_recursive(
    base: &Path,
    dir: &Path,
    entries: &mut BTreeMap<PathBuf, Entry>,
) -> anyhow::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let Some(stripped) = path.strip_prefix(base).ok()? else {
            continue;
        };
        let rel = stripped.to_path_buf();
        
        let metadata = fs::metadata(&path)?;
        if metadata.is_dir() {
            entries.insert(rel.clone(), Entry::Dir);
            snapshot_dir_recursive(base, &path, entries)?;
        } else if metadata.is_file() {
            let contents = fs::read(&path)?;
            entries.insert(rel, Entry::File(contents));
        }
    }
    Ok(())
}
```

## 依赖与外部交互

### 文件依赖关系
```
other.txt
    ├── 与 name.txt 的关系: 同目录邻居文件
    ├── 与 patch.txt 的关系: 无直接关联（patch 只引用 name.txt）
    └── 与 expected/old/other.txt 的关系: 内容必须完全一致
```

### 测试场景文件依赖图
```
010_move_overwrites_existing_destination/
├── input/
│   ├── old/
│   │   ├── name.txt ─────┐
│   │   └── other.txt     │    (无直接交互)
│   │                     │
│   └── renamed/dir/      │
│       └── name.txt ─────┤ (将被覆盖)
│                         │
├── patch.txt ◄───────────┘ (只操作 name.txt)
│
└── expected/
    ├── old/
    │   └── other.txt ────► (必须与 input 版本一致)
    └── renamed/dir/
        └── name.txt
```

### 外部工具依赖
- `apply_patch` 二进制: 被测试的主体程序
- `tempfile` crate: 提供临时目录隔离
- `pretty_assertions`: 提供清晰的测试失败输出

## 风险、边界与改进建议

### 当前设计的优点

1. **简单明确**: 使用 "unrelated file" 作为内容，语义自解释
2. **隔离验证**: 有效检测 apply-patch 是否意外修改未指定的文件
3. **回归防护**: 防止未来代码变更引入副作用

### 潜在风险与边界情况

#### 1. 文件名冲突风险
- **场景**: 如果 patch 错误地使用了通配符或目录操作
- **影响**: 可能意外删除或修改 `other.txt`
- **当前防护**: 快照比对会捕获任何意外的文件变化

#### 2. 目录删除风险
- **场景**: 如果实现错误地在移动文件后删除空目录
- **影响**: `old/` 目录可能被删除，导致 `other.txt` 丢失
- **当前防护**: `expected/old/other.txt` 的存在强制要求保留目录

#### 3. 编码/换行符问题
- **场景**: 跨平台测试时换行符不一致
- **影响**: 快照比对可能因 `\n` vs `\r\n` 失败
- **当前状态**: 文件使用 Unix 换行符，与项目一致

### 改进建议

#### 1. 增强对照文件多样性
当前仅使用一个简单文本文件。建议增加：
```
input/old/
├── name.txt           # 操作目标
├── other.txt          # 简单文本对照
├── binary.dat         # 二进制文件对照（验证不破坏二进制内容）
└── subdir/
    └── nested.txt     # 嵌套目录文件对照
```

#### 2. 添加元数据验证
当前仅验证文件内容，建议扩展验证：
```rust
// 验证文件权限未改变
let before_mode = fs::metadata(&src_path)?.permissions().mode();
let after_mode = fs::metadata(&dst_path)?.permissions().mode();
assert_eq!(before_mode, after_mode);
```

#### 3. 添加内容哈希验证
对于大文件或二进制文件，使用哈希比对：
```rust
use sha2::{Sha256, Digest};

fn file_hash(path: &Path) -> anyhow::Result<String> {
    let content = fs::read(path)?;
    Ok(format!("{:x}", Sha256::digest(&content)))
}
```

#### 4. 扩展测试场景
建议添加专门的"副作用检测"场景：
```
022_side_effect_check/
├── input/
│   ├── target.txt     # 操作目标
│   ├── sibling.txt    # 同级文件
│   ├── neighbor/
│   │   └── file.txt   # 邻接目录文件
│   └── unrelated/
│       └── deep.txt   # 无关目录文件
└── patch.txt          # 只操作 target.txt
```

### 相关测试场景对比

| 场景 | 对照文件策略 | 与本场景关系 |
|------|-------------|-------------|
| 001_add_file | 无（单文件操作） | 基础场景 |
| 002_multiple_operations | 多文件操作 | 扩展场景 |
| 004_move_to_new_directory | 无对照文件 | 移动基础场景 |
| **010_move_overwrites_existing** | **other.txt 作为对照** | **本场景** |
| 015_failure_after_partial_success | 复杂状态验证 | 错误处理场景 |

### 代码审查检查清单

- [ ] `other.txt` 在 `expected/` 中存在且内容与 `input/` 一致
- [ ] Patch 文本中不引用 `other.txt`
- [ ] 快照比对包含 `other.txt` 的完整内容验证
- [ ] 测试失败时输出清晰显示 `other.txt` 的差异
- [ ] 临时目录清理不影响后续测试

### 调试指南

如果本场景测试失败：

1. **检查 `other.txt` 是否被意外修改**
   ```bash
   diff input/old/other.txt expected/old/other.txt
   ```

2. **检查 `old/` 目录是否被意外删除**
   ```bash
   ls -la expected/old/
   ```

3. **查看详细测试输出**
   ```bash
   cargo test -p codex-apply-patch test_apply_patch_scenarios -- --nocapture
   ```

4. **手动复现测试步骤**
   ```bash
   cd codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination
   cp -r input /tmp/test_input
   cat patch.txt | apply_patch
   diff -r /tmp/test_input expected
   ```
