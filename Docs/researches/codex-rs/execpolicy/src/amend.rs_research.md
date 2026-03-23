# amend.rs 研究文档

## 场景与职责

`amend.rs` 是 `codex-execpolicy` crate 的核心模块之一，负责**运行时动态修改策略文件**。它提供了在策略文件中追加新规则的能力，主要用于以下场景：

1. **交互式策略学习**：当用户批准某个命令执行时，系统可以自动将该命令添加到允许列表中
2. **网络访问规则管理**：允许动态添加网络访问规则（如允许访问特定域名）
3. **策略持久化**：将内存中的策略变更持久化到磁盘文件

该模块的设计考虑了**并发安全性**（通过文件锁）和**幂等性**（避免重复添加相同规则）。

## 功能点目的

### 1. `blocking_append_allow_prefix_rule` - 追加前缀允许规则

允许向策略文件追加一个 `prefix_rule`，决策固定为 `"allow"`。这是最常见的用例——当用户确认某个命令是安全的，系统将其添加到白名单。

### 2. `blocking_append_network_rule` - 追加网络访问规则

支持添加网络访问规则，可指定：
- 目标主机（host）
- 协议（http/https/socks5_tcp/socks5_udp）
- 决策（allow/prompt/forbidden）
- 可选的说明理由（justification）

### 3. 文件级操作保障

- **自动创建目录**：如果策略文件的父目录不存在，自动创建
- **文件锁**：使用 `file.lock()` 确保并发安全
- **重复检测**：读取现有内容，避免追加重复规则
- **格式处理**：自动处理换行符，确保文件格式正确

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Error)]
pub enum AmendError {
    #[error("prefix rule requires at least one token")]
    EmptyPrefix,
    #[error("invalid network rule: {0}")]
    InvalidNetworkRule(String),
    #[error("policy path has no parent: {path}")]
    MissingParent { path: PathBuf },
    // ... 其他错误变体
}
```

错误类型使用 `thiserror` 派生，提供详细的错误上下文。

### 核心流程

#### 追加前缀规则流程

```
blocking_append_allow_prefix_rule(policy_path, prefix)
  ├── 检查 prefix 非空
  ├── 将 prefix 序列化为 JSON 数组格式
  ├── 构造 rule 字符串: prefix_rule(pattern=[...], decision="allow")
  └── append_rule_line(policy_path, rule)
       ├── 确保父目录存在
       └── append_locked_line(policy_path, line)
            ├── 打开文件（创建/追加/读取模式）
            ├── 获取文件锁
            ├── 读取全部内容
            ├── 检查是否已存在相同规则
            ├── 必要时添加换行符
            └── 写入新规则
```

#### 追加网络规则流程

```
blocking_append_network_rule(policy_path, host, protocol, decision, justification)
  ├── 规范化主机名（normalize_network_rule_host）
  ├── 验证 justification 非空（如果提供）
  ├── 序列化各字段为 JSON 字符串
  ├── 构造 rule 字符串: network_rule(host=..., protocol=..., decision=...)
  └── append_rule_line(policy_path, rule)
```

### 关键代码路径

#### 文件锁实现

```rust
fn append_locked_line(policy_path: &Path, line: &str) -> Result<(), AmendError> {
    let mut file = OpenOptions::new()
        .create(true)
        .read(true)
        .append(true)
        .open(policy_path)?;
    
    // 获取独占锁
    file.lock()?;
    
    // 读取检查重复
    file.seek(SeekFrom::Start(0))?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)?;
    
    if contents.lines().any(|existing| existing == line) {
        return Ok(());  // 已存在，幂等返回
    }
    
    // 追加写入
    // ...
}
```

#### 规则序列化

前缀规则的 pattern 使用 JSON 数组格式序列化：

```rust
let tokens = prefix
    .iter()
    .map(serde_json::to_string)
    .collect::<Result<Vec<_>, _>>()?;
let pattern = format!("[{}]", tokens.join(", "));
let rule = format!(r#"prefix_rule(pattern={pattern}, decision="allow")"#);
```

生成的规则格式示例：
```
prefix_rule(pattern=["echo", "Hello, world!"], decision="allow")
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::decision::Decision` | 决策枚举（Allow/Prompt/Forbidden）|
| `crate::rule::NetworkRuleProtocol` | 网络协议类型 |
| `crate::rule::normalize_network_rule_host` | 主机名规范化 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `serde_json` | 将规则字段序列化为 JSON 字符串 |
| `thiserror` | 错误类型派生 |
| `fs2::FileExt` (via `file.lock()`) | 跨平台文件锁 |

### 调用方

- `codex-cli` 或其他上层工具：当用户批准命令执行时调用
- 网络访问控制模块：当用户批准网络访问时调用

## 风险、边界与改进建议

### 风险点

1. **阻塞 I/O**：函数名中的 `blocking_` 明确标识这是阻塞操作，调用方必须在 `tokio::task::spawn_blocking` 中运行
2. **文件锁限制**：使用 advisory locking，如果其他进程不遵守锁协议，仍可能导致数据损坏
3. **全文件读取**：每次追加都读取整个文件来检查重复，大文件时性能较差
4. **并发竞争**：虽然文件锁防止了数据损坏，但多个进程同时尝试添加不同规则时，顺序不确定

### 边界条件

1. **空 prefix**：拒绝空前缀规则（返回 `AmendError::EmptyPrefix`）
2. **空 justification**：拒绝仅包含空白字符的 justification
3. **通配符主机**：网络规则拒绝通配符主机名（如 `*.example.com`）
4. **重复规则**：幂等处理，已存在的规则不会重复追加
5. **换行符处理**：智能处理文件末尾换行符，确保格式正确

### 改进建议

1. **增量检查优化**：对于大文件，可以考虑使用布隆过滤器或哈希索引来加速重复检查
2. **批量追加**：提供批量追加接口，减少多次文件打开/关闭的开销
3. **异步接口**：封装 `spawn_blocking` 调用，提供原生异步接口
4. **备份机制**：修改前创建备份，防止意外损坏
5. **规则排序**：考虑对规则进行排序，便于人工阅读
6. **压缩存储**：对于大量规则，考虑使用更紧凑的二进制格式

### 测试覆盖

模块包含完整的单元测试，覆盖：
- 基本追加功能
- 目录自动创建
- 重复规则检测
- 换行符处理
- 网络规则追加
- 混合规则追加
- 通配符拒绝

测试使用 `tempfile` crate 创建临时目录，确保测试隔离性。
