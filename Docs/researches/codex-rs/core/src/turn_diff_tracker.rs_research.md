# turn_diff_tracker.rs 研究文档

## 场景与职责

`turn_diff_tracker.rs` 是 Codex 核心 crate 的**回合级文件变更追踪模块**，负责在单个用户回合内聚合文件修改并生成统一差异（unified diff）：

1. **基线快照管理**：在文件首次被修改前捕获其原始内容
2. **重命名追踪**：通过内部 UUID 映射处理文件移动/重命名
3. **统一差异生成**：使用 `similar` crate 生成 git 风格的 unified diff
4. **Git 集成**：计算 blob SHA-1，支持 git 风格的路径显示
5. **二进制文件处理**：检测非文本内容并生成二进制差异标记

该模块是代码审查和变更展示的核心组件，为 Agent 的代码修改提供人类可读的差异视图。

## 功能点目的

### 1. TurnDiffTracker 结构体

```rust
#[derive(Default)]
pub struct TurnDiffTracker {
    external_to_temp_name: HashMap<PathBuf, String>,  // 外部路径 -> UUID
    baseline_file_info: HashMap<String, BaselineFileInfo>,  // UUID -> 基线信息
    temp_name_to_current_path: HashMap<String, PathBuf>,  // UUID -> 当前路径
    git_root_cache: Vec<PathBuf>,  // Git 根目录缓存
}
```

### 2. 基线信息结构

```rust
struct BaselineFileInfo {
    path: PathBuf,
    content: Vec<u8>,
    mode: FileMode,  // Regular/Executable/Symlink
    oid: String,     // Git blob SHA-1
}
```

### 3. 文件模式枚举

```rust
enum FileMode {
    Regular,      // 100644
    #[cfg(unix)]
    Executable,   // 100755
    Symlink,      // 120000
}
```

### 4. 核心方法

| 方法 | 用途 |
|------|------|
| `on_patch_begin` | 在应用补丁前捕获基线快照 |
| `get_unified_diff` | 生成聚合的统一差异 |
| `get_file_diff` | 生成单个文件的差异 |

## 具体技术实现

### 基线捕获流程

```rust
pub fn on_patch_begin(&mut self, changes: &HashMap<PathBuf, FileChange>) {
    for (path, change) in changes.iter() {
        // 1. 确保有稳定的内部 UUID
        if !self.external_to_temp_name.contains_key(path) {
            let internal = Uuid::new_v4().to_string();
            self.external_to_temp_name.insert(path.clone(), internal.clone());
            self.temp_name_to_current_path.insert(internal.clone(), path.clone());

            // 2. 捕获基线快照
            let baseline_file_info = if path.exists() {
                let mode = file_mode_for_path(path);
                let content = blob_bytes(path, mode)?;
                let oid = self.git_blob_oid_for_path(path)
                    .unwrap_or_else(|| compute_sha1(&content));
                Some(BaselineFileInfo { path: path.clone(), content, mode, oid })
            } else {
                // 新文件：使用 ZERO_OID
                Some(BaselineFileInfo { 
                    path: path.clone(), 
                    content: vec![], 
                    mode: FileMode::Regular, 
                    oid: ZERO_OID.to_string() 
                })
            };
            
            if let Some(info) = baseline_file_info {
                self.baseline_file_info.insert(internal.clone(), info);
            }
        }

        // 3. 处理重命名
        if let FileChange::Update { move_path: Some(dest), .. } = change {
            let uuid_filename = self.external_to_temp_name.get(path).cloned()
                .unwrap_or_else(|| Uuid::new_v4().to_string());
            self.temp_name_to_current_path.insert(uuid_filename.clone(), dest.clone());
            self.external_to_temp_name.remove(path);
            self.external_to_temp_name.insert(dest.clone(), uuid_filename);
        }
    }
}
```

### 统一差异生成

```rust
pub fn get_unified_diff(&mut self) -> Result<Option<String>> {
    let mut aggregated = String::new();

    // 按路径排序以稳定输出
    let mut baseline_file_names: Vec<String> = self.baseline_file_info.keys().cloned().collect();
    baseline_file_names.sort_by_key(|internal| {
        self.get_path_for_internal(internal)
            .map(|p| self.relative_to_git_root_str(&p))
            .unwrap_or_default()
    });

    for internal in baseline_file_names {
        aggregated.push_str(self.get_file_diff(&internal).as_str());
    }

    if aggregated.trim().is_empty() {
        Ok(None)
    } else {
        Ok(Some(aggregated))
    }
}
```

### 单文件差异生成

```rust
fn get_file_diff(&mut self, internal_file_name: &str) -> String {
    // 1. 获取基线和当前状态
    let (baseline_path, baseline_mode, left_oid) = ...;
    let current_path = self.get_path_for_internal(internal_file_name)?;
    let current_mode = file_mode_for_path(&current_path)?;
    let right_bytes = blob_bytes(&current_path, current_mode);

    // 2. 快速路径：无变化
    if left_bytes == right_bytes.as_deref() {
        return String::new();
    }

    // 3. 生成 git diff 头部
    aggregated.push_str(&format!("diff --git a/{left_display} b/{right_display}\n"));
    
    if is_add {
        aggregated.push_str(&format!("new file mode {current_mode}\n"));
    } else if is_delete {
        aggregated.push_str(&format!("deleted file mode {baseline_mode}\n"));
    } else if baseline_mode != current_mode {
        aggregated.push_str(&format!("old mode {baseline_mode}\n"));
        aggregated.push_str(&format!("new mode {current_mode}\n"));
    }

    // 4. 文本差异或二进制标记
    if can_text_diff {
        let diff = similar::TextDiff::from_lines(left_text.unwrap_or(""), right_text.unwrap_or(""));
        let unified = diff.unified_diff().context_radius(3).header(&old_header, &new_header).to_string();
        aggregated.push_str(&unified);
    } else {
        aggregated.push_str("Binary files differ\n");
    }
    
    aggregated
}
```

### Git SHA-1 计算

```rust
fn git_blob_sha1_hex_bytes(data: &[u8]) -> Output<sha1::Sha1> {
    // Git blob hash: sha1("blob <len>\0<data>")
    let header = format!("blob {}\0", data.len());
    let mut hasher = sha1::Sha1::new();
    hasher.update(header.as_bytes());
    hasher.update(data);
    hasher.finalize()
}
```

### Git 根目录查找

```rust
fn find_git_root_cached(&mut self, start: &Path) -> Option<PathBuf> {
    // 1. 检查缓存
    if let Some(root) = self.git_root_cache.iter().find(|r| dir.starts_with(r)).cloned() {
        return Some(root);
    }

    // 2. 向上遍历查找 .git
    let mut cur = dir.to_path_buf();
    loop {
        let git_marker = cur.join(".git");
        if git_marker.is_dir() || git_marker.is_file() {
            self.git_root_cache.push(cur.clone());
            return Some(cur);
        }

        #[cfg(windows)]
        if is_windows_drive_or_unc_root(&cur) {
            return None;
        }

        if let Some(parent) = cur.parent() {
            cur = parent.to_path_buf();
        } else {
            return None;
        }
    }
}
```

## 关键代码路径与文件引用

### 协议依赖

| 类型 | 路径 | 用途 |
|------|------|------|
| `FileChange` | `codex_protocol::protocol` | 文件变更类型（Add/Update/Delete） |

### FileChange 定义

```rust
pub enum FileChange {
    Add { content: String },
    Update { unified_diff: String, move_path: Option<PathBuf> },
    Delete { content: String },
}
```

### 外部 crate

| crate | 用途 |
|-------|------|
| `similar` | 文本差异计算 |
| `sha1` | Git blob SHA-1 计算 |
| `uuid` | 内部文件名生成 |
| `anyhow` | 错误处理 |

### 平台特定代码

```rust
#[cfg(unix)]
fn file_mode_for_path(path: &Path) -> Option<FileMode> {
    use std::os::unix::fs::PermissionsExt;
    let meta = fs::symlink_metadata(path).ok()?;
    let ft = meta.file_type();
    if ft.is_symlink() { return Some(FileMode::Symlink); }
    let mode = meta.permissions().mode();
    let is_exec = (mode & 0o111) != 0;
    Some(if is_exec { FileMode::Executable } else { FileMode::Regular })
}

#[cfg(not(unix))]
fn file_mode_for_path(_path: &Path) -> Option<FileMode> {
    Some(FileMode::Regular)  // 非 Unix 平台默认非可执行
}
```

## 依赖与外部交互

### 文件系统交互

- **读取**：基线捕获时读取文件内容
- **元数据**：获取文件权限和类型
- **符号链接**：Unix 平台支持符号链接

### Git 命令调用

```rust
fn git_blob_oid_for_path(&mut self, path: &Path) -> Option<String> {
    let root = self.find_git_root_cached(path)?;
    let rel = path.strip_prefix(&root).unwrap_or(path);
    let output = Command::new("git")
        .arg("-C").arg(&root)
        .arg("hash-object").arg("--").arg(rel)
        .output().ok()?;
    // ...
}
```

### 调用方

- **Agent 执行层**：在 `apply_patch` 前后调用
- **审查系统**：生成代码审查的差异视图

## 风险、边界与改进建议

### 已知风险

1. **Git 依赖**：`git_blob_oid_for_path` 依赖系统 git 命令，在无 git 环境失败
2. **内存使用**：大文件的基线快照完全驻留内存
3. **并发安全**：`TurnDiffTracker` 未实现 `Sync`，单线程使用
4. **Windows 路径**：路径分隔符统一替换为 `/`，但可能有边界情况

### 边界情况

1. **循环重命名**：A->B->A 的重命名链可能产生意外结果
2. **跨文件系统移动**：重命名检测基于路径映射，不检测 inode 变化
3. **权限变更**：仅检测内容变化，权限变更单独标记
4. **空文件**：零字节文件正确处理（ZERO_OID）

### 改进建议

1. **纯 Rust SHA-1**：
   - 当前使用 `sha1` crate 计算 blob hash
   - 可考虑完全移除 git 命令依赖，使用纯 Rust 实现

2. **流式处理**：
   - 大文件使用内存映射或流式读取
   - 避免 `Vec<u8>` 存储大文件内容

3. **增量更新**：
   - 支持增量基线更新，减少内存占用
   - 已关闭的回合可释放基线数据

4. **并发支持**：
   - 考虑使用 `RwLock` 或通道实现线程安全
   - 支持并行差异计算

5. **更多 diff 格式**：
   - 支持 side-by-side diff
   - 支持 word-level diff
   - 支持忽略空白变化

6. **性能优化**：
   - 使用 `rayon` 并行化多文件差异计算
   - 缓存相似度计算结果

### 代码统计

- 代码行数：469 行
- 结构体：2 个
- 枚举：1 个（FileMode）
- 公共方法：3 个
- 私有辅助方法：15+

### 代码质量

- 文档：详细的模块级文档和结构体注释
- 错误处理：使用 `anyhow::Result`，错误上下文丰富
- 平台兼容：Unix/Windows 条件编译
- 测试覆盖：配套 `turn_diff_tracker_tests.rs` 测试
