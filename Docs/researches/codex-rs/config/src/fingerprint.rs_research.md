# fingerprint.rs 研究文档

## 场景与职责

`fingerprint.rs` 是 Codex 配置系统的**配置指纹与溯源模块**，负责：

1. **配置版本计算**：为 TOML 配置计算内容寻址的指纹（SHA-256）
2. **配置来源追踪**：记录每个配置项的来源（哪个配置文件、哪一层）
3. **配置层元数据管理**：支持配置层的版本控制和变更检测

### 使用场景
- 配置变更检测：比较指纹判断配置是否变化
- 配置同步：在客户端和服务器之间同步配置状态
- 调试和审计：追踪配置项的来源

## 功能点目的

### 1. 配置指纹计算 (`version_for_toml`)
```rust
pub fn version_for_toml(value: &TomlValue) -> String {
    // 1. TOML -> JSON
    // 2. JSON 规范化（排序键）
    // 3. SHA-256 哈希
    // 4. 返回 "sha256:..." 格式
}
```

**目的**：
- 提供内容寻址的标识符
- 忽略格式差异（空格、键顺序）
- 支持配置缓存和变更检测

### 2. 配置来源记录 (`record_origins`)
```rust
pub(super) fn record_origins(
    value: &TomlValue,
    meta: &ConfigLayerMetadata,
    path: &mut Vec<String>,
    origins: &mut HashMap<String, ConfigLayerMetadata>,
)
```

**目的**：
- 递归遍历 TOML 结构
- 为每个叶节点记录来源配置层
- 支持嵌套表和数组

### 3. JSON 规范化 (`canonical_json`)
```rust
fn canonical_json(value: &JsonValue) -> JsonValue {
    // 对象键按字母顺序排序
    // 数组元素递归规范化
    // 标量值保持不变
}
```

**目的**：
- 确保语义相同的配置产生相同的指纹
- 消除序列化顺序的影响

## 具体技术实现

### 指纹计算流程

```
TomlValue
    │
    ▼
serde_json::to_value() ──> JsonValue
    │
    ▼
canonical_json() ──> 规范化 JsonValue（排序键）
    │
    ▼
serde_json::to_vec() ──> 字节序列
    │
    ▼
Sha256::digest() ──> 32 字节哈希
    │
    ▼
hex encode ──> "sha256:..." 字符串
```

### 来源记录递归逻辑

```rust
pub(super) fn record_origins(
    value: &TomlValue,
    meta: &ConfigLayerMetadata,
    path: &mut Vec<String>,
    origins: &mut HashMap<String, ConfigLayerMetadata>,
) {
    match value {
        TomlValue::Table(table) => {
            for (key, val) in table {
                path.push(key.clone());
                record_origins(val, meta, path, origins);
                path.pop();
            }
        }
        TomlValue::Array(items) => {
            for (idx, item) in (0_i32..).zip(items.iter()) {
                path.push(idx.to_string());
                record_origins(item, meta, path, origins);
                path.pop();
            }
        }
        _ => {
            if !path.is_empty() {
                origins.insert(path.join("."), meta.clone());
            }
        }
    }
}
```

### 关键设计决策

1. **使用 JSON 作为中间格式**：
   - TOML 和 JSON 的数据模型兼容
   - `serde_json` 提供稳定的序列化

2. **规范化规则**：
   - 对象键按字母顺序排序
   - 数组顺序保持不变（语义相关）
   - 浮点数使用默认序列化（可能有精度问题）

3. **路径格式**：
   - 使用 `.` 连接的路径（如 `server.host`）
   - 数组索引使用数字（如 `servers.0.port`）

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/config/src/fingerprint.rs` (67 行)

### 直接依赖
| 依赖 | 路径 | 用途 |
|------|------|------|
| `ConfigLayerMetadata` | `codex-rs/app-server-protocol` | 配置层元数据 |
| `sha2::Sha256` | Cargo.toml | SHA-256 哈希 |
| `serde_json` | Cargo.toml | JSON 序列化 |
| `toml::Value` | Cargo.toml | TOML 类型 |

### 调用方
- `codex-rs/config/src/state.rs` - 配置层状态管理
- `codex-rs/core/src/config/mod.rs` - 核心配置

### 使用示例（来自 state.rs）

```rust
// ConfigLayerEntry::new 中使用
pub fn new(name: ConfigLayerSource, config: TomlValue) -> Self {
    let version = version_for_toml(&config);  // 计算指纹
    Self {
        name,
        config,
        raw_toml: None,
        version,
        disabled_reason: None,
    }
}

// origins() 方法中使用
pub fn origins(&self) -> HashMap<String, ConfigLayerMetadata> {
    let mut origins = HashMap::new();
    let mut path = Vec::new();
    
    for layer in self.get_layers(...) {
        record_origins(&layer.config, &layer.metadata(), &mut path, &mut origins);
    }
    
    origins
}
```

## 依赖与外部交互

### 外部 Crate
- `sha2`：SHA-256 哈希算法
- `serde_json`：JSON 序列化
- `toml`：TOML 类型

### 内部模块
- `state.rs`：主要使用者
- `app-server-protocol`：元数据类型定义

### 数据流

```
配置加载
    │
    ▼
TomlValue (解析后的配置)
    │
    ├──> version_for_toml() ──> 指纹字符串
    │       └──> 存储在 ConfigLayerEntry.version
    │
    └──> record_origins() ──> HashMap<path, metadata>
            └──> 用于调试和 API 响应
```

## 风险、边界与改进建议

### 潜在风险

1. **浮点数规范化**：
   ```rust
   // 风险：浮点数序列化可能因平台/版本差异而不同
   // 例如：1.0 vs 1.00 vs 1e0
   ```

2. **大配置性能**：
   - 递归遍历整个 TOML 树
   - 超大配置可能导致栈溢出或性能问题

3. **哈希冲突**：
   - 虽然 SHA-256 冲突概率极低，但理论上存在
   - 用于安全场景时需要额外验证

### 边界条件

1. **空配置**：
   ```rust
   // 空表也会产生有效指纹
   TomlValue::Table(Default::default())
   ```

2. **空路径**：
   ```rust
   // 根级值不记录来源（path.is_empty()）
   if !path.is_empty() {
       origins.insert(path.join("."), meta.clone());
   }
   ```

3. **数组索引**：
   - 使用 `i32` 作为索引类型
   - 超大数组可能溢出

### 改进建议

1. **浮点数规范化**：
   ```rust
   // 建议：使用固定精度表示
   fn canonical_json(value: &JsonValue) -> JsonValue {
       match value {
           JsonValue::Number(n) => {
               // 使用固定小数位或科学计数法
               JsonValue::String(format!("{:.10}", n.as_f64().unwrap()))
           }
           // ...
       }
   }
   ```

2. **迭代器替代递归**：
   ```rust
   // 建议：使用栈迭代避免栈溢出
   pub fn record_origins_iter(value: &TomlValue, meta: &ConfigLayerMetadata) -> HashMap<String, ConfigLayerMetadata> {
       let mut stack = vec![(vec![], value)];
       let mut origins = HashMap::new();
       
       while let Some((path, value)) = stack.pop() {
           match value {
               TomlValue::Table(table) => {
                   for (key, val) in table {
                       let mut new_path = path.clone();
                       new_path.push(key.clone());
                       stack.push((new_path, val));
                   }
               }
               // ...
           }
       }
       
       origins
   }
   ```

3. **增量指纹**：
   ```rust
   // 建议：支持增量更新，避免重新计算整个配置
   pub struct IncrementalFingerprinter {
       hasher: Sha256,
   }
   
   impl IncrementalFingerprinter {
       pub fn update(&mut self, path: &str, value: &TomlValue) {
           // 只更新变更的部分
       }
   }
   ```

4. **更多哈希算法支持**：
   ```rust
   // 建议：支持 Blake3 等更快算法
   pub enum HashAlgorithm {
       Sha256,
       Blake3,
   }
   ```

5. **来源路径优化**：
   ```rust
   // 建议：使用小型字符串优化（SSO）
   pub struct Path(Vec<String>);  // 考虑使用 String 存储 "a.b.c"
   ```

### 测试覆盖

当前测试：
- 主要通过集成测试覆盖
- 依赖 `state.rs` 的测试

建议补充：
- 指纹稳定性测试（相同配置产生相同指纹）
- 规范化正确性测试（不同格式相同语义）
- 大配置性能测试
- 浮点数边界测试
- 来源记录准确性测试

### 安全考虑

1. **哈希长度扩展攻击**：
   - SHA-256 可能受长度扩展攻击影响
   - 当前使用场景不涉及 MAC，风险较低

2. **哈希碰撞**：
   - 如果用于安全决策，需要额外验证
   - 建议添加配置内容的对等比较作为后备
