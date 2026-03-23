# helper_materialization.rs 深度研究文档

## 场景与职责

`helper_materialization.rs` 是 Windows Sandbox 模块中的**辅助程序物化管理器**，负责将沙箱运行所需的辅助可执行文件（如 `codex-command-runner.exe`）从源位置复制到目标目录，并管理其生命周期。该模块解决了以下核心问题：

1. **辅助程序分发**：将命令运行器等辅助工具从安装目录复制到用户可写的沙箱目录
2. **版本一致性**：通过文件大小和修改时间检测，确保目标文件与源文件同步
3. **性能优化**：使用内存缓存避免重复的文件系统操作
4. **容错回退**：在复制失败时提供降级策略（使用原始路径）

## 功能点目的

### 1. HelperExecutable 枚举
定义支持的辅助程序类型，目前仅支持 `CommandRunner`（命令运行器）：
```rust
pub(crate) enum HelperExecutable {
    CommandRunner,
}
```

### 2. 复制结果追踪
```rust
enum CopyOutcome {
    Reused,     // 目标文件已是最新，无需复制
    ReCopied,   // 执行了复制操作
}
```

### 3. 内存缓存机制
使用 `OnceLock<Mutex<HashMap<String, PathBuf>>>` 实现线程安全的单例缓存：
- 缓存键格式：`"{file_name}|{codex_home}"`
- 避免重复的文件存在性检查和元数据比较

### 4. 核心解析函数

#### `resolve_helper_for_launch`
- **用途**：为沙箱启动解析辅助程序路径
- **逻辑**：先尝试复制，失败则回退到 `legacy_lookup`
- **调用方**：`elevated_impl.rs` 中的 `find_runner_exe`

#### `resolve_current_exe_for_launch`
- **用途**：解析当前可执行文件用于启动
- **特殊处理**：将当前 exe 复制到 `helper_bin_dir`

#### `copy_helper_if_needed`
- **用途**：条件复制辅助程序
- **流程**：
  1. 检查内存缓存
  2. 定位源文件（当前 exe 同级目录）
  3. 检查目标文件新鲜度
  4. 执行原子复制（先写临时文件再重命名）
  5. 更新缓存

## 具体技术实现

### 文件新鲜度检测 (`destination_is_fresh`)
```rust
fn destination_is_fresh(source: &Path, destination: &Path) -> Result<bool>
```
比较逻辑：
1. 源文件和目标文件大小相同
2. 目标文件修改时间 >= 源文件修改时间

### 原子复制策略 (`copy_from_source_if_needed`)
1. 创建目标目录（如果不存在）
2. 在目标目录创建临时文件（使用 `NamedTempFile`）
3. 将源文件内容复制到临时文件
4. 刷新并关闭临时文件
5. 删除旧目标文件（如果存在）
6. 原子重命名临时文件为目标文件
7. 处理重命名竞争条件（检查是否其他进程已更新）

### 源文件定位 (`sibling_source_path`)
- 从 `std::env::current_exe()` 获取当前可执行文件路径
- 在同级目录查找辅助程序

### 回退机制 (`legacy_lookup`)
当复制失败时，直接返回源路径或仅文件名，允许系统通过 PATH 解析。

## 关键代码路径与文件引用

### 内部依赖
| 函数 | 依赖模块 | 用途 |
|------|----------|------|
| `helper_bin_dir` | `setup_orchestrator.rs` | 获取辅助程序目标目录 |
| `log_note` | `logging.rs` | 记录操作日志 |
| `sandbox_dir` | `setup_orchestrator.rs` | 获取日志目录 |

### 被调用方
| 调用方 | 函数 | 场景 |
|--------|------|------|
| `elevated_impl.rs` | `resolve_helper_for_launch` | 启动命令运行器 |
| `lib.rs` | `resolve_current_exe_for_launch` | 导出给外部使用 |

### 常量定义
```rust
const HELPER_PATH_CACHE: OnceLock<Mutex<HashMap<String, PathBuf>>> = OnceLock::new();
```

## 依赖与外部交互

### 外部 Crate
- `anyhow`：错误处理
- `tempfile::NamedTempFile`：原子文件操作
- `std::fs`, `std::io`：文件系统操作
- `std::sync::{Mutex, OnceLock}`：线程安全缓存

### 文件系统交互
- 读取源文件元数据
- 创建目录结构
- 原子文件写入（临时文件 + 重命名）

### 环境依赖
- 依赖 `std::env::current_exe()` 定位源文件
- 依赖 `codex_home` 参数确定目标目录

## 风险、边界与改进建议

### 已知风险

1. **并发复制竞争**
   - 问题：多个进程同时尝试复制同一文件
   - 缓解：使用临时文件 + 原子重命名，以及重命名失败后的二次检查

2. **缓存失效**
   - 问题：内存缓存不会自动失效，如果外部修改了文件可能导致不一致
   - 缓解：缓存键包含 codex_home，进程重启后重新评估

3. **权限问题**
   - 问题：目标目录可能没有写入权限
   - 缓解：回退到 legacy_lookup，依赖系统 PATH

### 边界条件

1. **源文件不存在**：返回错误，触发回退
2. **目标目录不可写**：返回错误，触发回退
3. **文件大小为0**：仍能正确处理（大小比较逻辑适用）
4. **修改时间精度**：依赖系统时间精度，快速连续更新可能检测不到

### 改进建议

1. **哈希校验**
   - 当前使用大小+时间戳检测新鲜度
   - 建议：增加可选的哈希校验（SHA-256）用于关键场景

2. **缓存持久化**
   - 考虑将缓存状态持久化到磁盘，减少进程重启后的重复检查

3. **符号链接支持**
   - 当前处理常规文件，可考虑支持符号链接场景

4. **版本元数据**
   - 在辅助程序中嵌入版本信息，实现更精确的版本匹配

### 测试覆盖

模块包含以下单元测试：
- `copy_from_source_if_needed_copies_missing_destination`：基本复制流程
- `destination_is_fresh_uses_size_and_mtime`：新鲜度检测逻辑
- `copy_from_source_if_needed_reuses_fresh_destination`：缓存复用
- `helper_bin_dir_is_under_sandbox_bin`：目录结构验证
- `copy_runner_into_shared_bin_dir`：端到端复制测试
