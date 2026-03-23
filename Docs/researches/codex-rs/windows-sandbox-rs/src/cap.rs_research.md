# cap.rs 研究文档

## 场景与职责

`cap.rs` 负责 Capability SID（安全标识符）的管理。Capability SID 是 Windows 沙箱安全模型的核心概念，用于：
- 标识沙箱进程的能力级别（workspace/readonly）
- 隔离不同工作区的沙箱实例
- 为文件系统 ACL 提供细粒度的访问控制目标

该模块在以下场景中使用：
- 沙箱初始化时生成或加载 Capability SID
- 为每个工作区（CWD）创建独立的 Capability SID
- 持久化 Capability 配置到磁盘

## 功能点目的

### 1. Capability SID 数据结构
- **`CapSids`**: 包含 workspace、readonly 和 workspace_by_cwd 三个字段
- 使用 JSON 格式持久化存储

### 2. SID 生成
- **`make_random_cap_sid_string`**: 生成随机 Capability SID 字符串
- 格式：`S-1-5-21-{a}-{b}-{c}-{d}`（随机 32 位整数）
- 使用 `SmallRng::from_entropy()` 获取高质量随机数

### 3. 持久化管理
- **`load_or_create_cap_sids`**: 加载或创建 Capability 配置
- **`persist_caps`**: 将配置持久化到磁盘
- 存储路径：`{codex_home}/cap_sid`

### 4. 每工作区 SID
- **`workspace_cap_sid_for_cwd`**: 为特定工作区获取或创建独立 SID
- 使用 `canonical_path_key` 确保路径拼写变体共享同一 SID
- 用于隔离不同工作区的沙箱访问权限

## 具体技术实现

### 关键数据结构

```rust
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CapSids {
    pub workspace: String,  // WorkspaceWrite 策略使用的 SID
    pub readonly: String,   // ReadOnly 策略使用的 SID
    /// Per-workspace capability SIDs keyed by canonicalized CWD string.
    #[serde(default)]
    pub workspace_by_cwd: HashMap<String, String>,
}
```

### SID 生成算法

```rust
fn make_random_cap_sid_string() -> String {
    let mut rng = SmallRng::from_entropy();
    let a = rng.next_u32();
    let b = rng.next_u32();
    let c = rng.next_u32();
    let d = rng.next_u32();
    format!("S-1-5-21-{}-{}-{}-{}", a, b, c, d)
}
```

使用 Windows 标准 SID 格式 `S-1-5-21-*`，这是非域账户的常规前缀。

### 加载/创建流程

```
load_or_create_cap_sids(codex_home)
  └─> cap_sid_file(codex_home) -> {codex_home}/cap_sid
  └─> 如果文件存在:
  │     └─> 读取内容
  │     └─> 如果内容是 JSON (以 { 开头):
  │     │     └─> 解析为 CapSids
  │     └─> 否则 (旧格式，单行 SID):
  │           └─> 创建新 CapSids（旧 SID 作为 workspace）
  │           └─> persist_caps 保存新格式
  │           └─> 返回
  └─> 如果文件不存在或解析失败:
        └─> 生成新的 workspace 和 readonly SID
        └─> persist_caps 保存
        └─> 返回
```

### 向后兼容性

```rust
if t.starts_with('{') && t.ends_with('}') {
    // JSON 格式（新）
    if let Ok(obj) = serde_json::from_str::<CapSids>(t) {
        return Ok(obj);
    }
} else if !t.is_empty() {
    // 单行 SID 格式（旧）
    let caps = CapSids {
        workspace: t.to_string(),
        readonly: make_random_cap_sid_string(),
        workspace_by_cwd: HashMap::new(),
    };
    persist_caps(&path, &caps)?;
    return Ok(caps);
}
```

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 调用函数 | 用途 |
|--------|----------|------|
| `lib.rs` (windows_impl) | `load_or_create_cap_sids`, `workspace_cap_sid_for_cwd` | 沙箱执行 |
| `elevated_impl.rs` | `load_or_create_cap_sids`, `workspace_cap_sid_for_cwd` | 提升执行路径 |
| `audit.rs` | `load_or_create_cap_sids`, `cap_sid_file`, `workspace_cap_sid_for_cwd` | 审计拒绝 ACE |

### 被调用模块

| 模块 | 函数 | 用途 |
|------|------|------|
| `path_normalization.rs` | `canonical_path_key` | 工作区路径规范化 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/cap.rs
  ├─> 依赖: path_normalization.rs (canonical_path_key)
  ├─> 被 lib.rs 公开导出:
  │     load_or_create_cap_sids, workspace_cap_sid_for_cwd
  └─> 存储: {codex_home}/cap_sid (JSON)
```

## 依赖与外部交互

### 内部依赖
- **`path_normalization.rs`**: `canonical_path_key` 用于工作区路径键生成

### 外部依赖
- **serde**: JSON 序列化/反序列化
- **rand**: 随机数生成 (`SmallRng`, `RngCore`, `SeedableRng`)
- **anyhow**: 错误处理

### 文件系统交互
- 读取/写入 `{codex_home}/cap_sid` 文件
- 使用 `fs::create_dir_all` 确保目录存在

### 存储格式

```json
{
  "workspace": "S-1-5-21-1234567890-1234567890-1234567890-1234567890",
  "readonly": "S-1-5-21-0987654321-0987654321-0987654321-0987654321",
  "workspace_by_cwd": {
    "c:/users/dev/project1": "S-1-5-21-1111111111-1111111111-1111111111-1111111111",
    "c:/users/dev/project2": "S-1-5-21-2222222222-2222222222-2222222222-2222222222"
  }
}
```

## 风险、边界与改进建议

### 安全风险

1. **SID 可预测性**
   - 使用 `SmallRng::from_entropy()`，熵源质量依赖操作系统
   - 虽然概率极低，但理论上存在 SID 碰撞可能

2. **文件权限**
   - `cap_sid` 文件存储敏感 SID 信息
   - 如果文件权限不当，可能泄露 SID 信息

3. **持久化风险**
   - SID 一旦生成永久使用（除非手动删除文件）
   - 如果 SID 被泄露，攻击者可能构造具有相同 SID 的令牌

4. **工作区隔离**
   - `workspace_by_cwd` 使用规范化路径作为键
   - 符号链接或挂载点可能导致意外共享 SID

### 边界条件

| 边界 | 处理 |
|------|------|
| 文件损坏 | 解析失败时生成新配置 |
| 旧格式 | 自动迁移到新格式 |
| 空文件 | 生成新配置 |
| 路径规范化失败 | `canonical_path_key` 回退到原始路径 |
| 并发访问 | 无显式锁，依赖文件系统原子性 |

### 改进建议

1. **文件权限设置**
   ```rust
   // 当前: 创建文件后未设置权限
   // 建议: 限制 cap_sid 文件访问权限（仅当前用户）
   #[cfg(target_os = "windows")]
   {
       use std::os::windows::fs::MetadataExt;
       // 设置仅当前用户可读写
   }
   ```

2. **SID 轮换机制**
   - 当前 SID 永久有效
   - 建议增加定期轮换或按需轮换机制

3. **并发安全**
   ```rust
   // 当前: 无文件锁
   // 建议: 使用 fs2::FileExt::lock 或类似机制
   ```

4. **元数据增强**
   ```rust
   // 当前: 仅存储 SID
   // 建议: 增加创建时间、轮换历史等元数据
   #[derive(Serialize, Deserialize)]
   pub struct CapSids {
       pub workspace: SidEntry,
       pub readonly: SidEntry,
       pub workspace_by_cwd: HashMap<String, SidEntry>,
   }
   
   pub struct SidEntry {
       pub sid: String,
       pub created_at: DateTime<Utc>,
       pub rotated_from: Option<String>,
   }
   ```

5. **路径键改进**
   - 当前使用规范化字符串路径
   - 考虑使用卷序列号+文件 ID 作为更稳定的标识

6. **备份和恢复**
   - 当前无备份机制
   - 建议：修改前创建备份，损坏时恢复

### 测试分析

现有测试：

| 测试 | 覆盖场景 |
|------|----------|
| `equivalent_cwd_spellings_share_workspace_sid_key` | 路径拼写变体共享 SID |

测试质量良好，验证了核心功能。建议补充：
- 旧格式迁移测试
- 并发访问测试
- 文件损坏恢复测试
- 大量工作区 SID 性能测试
