# merge.rs 研究文档

## 场景与职责

`merge.rs` 是 Codex 配置系统的**TOML 值合并模块**，提供了一个简单的递归合并算法：

1. **配置层合并**：将多个配置源（系统、用户、项目）的 TOML 值合并为单一配置
2. **优先级处理**：后传入的配置（overlay）覆盖先传入的配置（base）
3. **递归表合并**：对于嵌套表结构，递归合并而非简单替换

### 使用场景
- 多层配置合并（系统默认 + 用户配置 + 项目配置）
- CLI 覆盖合并（命令行参数覆盖配置文件）
- 动态配置更新（新配置覆盖旧配置）

## 功能点目的

### 1. TOML 值合并 (`merge_toml_values`)
```rust
pub fn merge_toml_values(base: &mut TomlValue, overlay: &TomlValue) {
    if let TomlValue::Table(overlay_table) = overlay
        && let TomlValue::Table(base_table) = base
    {
        for (key, value) in overlay_table {
            if let Some(existing) = base_table.get_mut(key) {
                merge_toml_values(existing, value);  // 递归合并
            } else {
                base_table.insert(key.clone(), value.clone());  // 插入新键
            }
        }
    } else {
        *base = overlay.clone();  // 非表类型，直接替换
    }
}
```

**目的**：
- 实现深度合并，保留 base 中 overlay 未指定的部分
- 对于表类型，递归合并嵌套结构
- 对于非表类型（字符串、数字、数组等），overlay 完全替换 base

## 具体技术实现

### 合并算法

```
merge_toml_values(base, overlay):
    if base 是表 AND overlay 是表:
        for (key, value) in overlay:
            if key 存在于 base:
                merge_toml_values(base[key], value)  // 递归
            else:
                base[key] = value.clone()  // 插入
    else:
        base = overlay.clone()  // 替换
```

### 行为示例

```toml
# base.toml
[server]
host = "localhost"
port = 8080

[logging]
level = "info"
```

```toml
# overlay.toml
[server]
port = 3000  # 覆盖 base 的 port

[database]  # 新增表
url = "postgres://localhost"
```

```toml
# 合并结果
[server]
host = "localhost"  # 保留自 base
port = 3000         # 来自 overlay

[logging]
level = "info"      # 保留自 base

[database]
url = "postgres://localhost"  # 来自 overlay
```

### 数组处理

**注意**：数组被视为原子值，会被完全替换而非合并：

```toml
# base.toml
items = [1, 2, 3]
```

```toml
# overlay.toml
items = [4, 5]
```

```toml
# 合并结果（base 的数组被完全替换）
items = [4, 5]
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/config/src/merge.rs` (18 行)

### 直接依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `TomlValue` | `toml` crate | TOML 值类型 |

### 调用方
- `codex-rs/config/src/state.rs` - 配置层状态管理
- `codex-rs/core/src/config/mod.rs` - 核心配置服务

### 使用示例（来自 state.rs）

```rust
impl ConfigLayerStack {
    pub fn effective_config(&self) -> TomlValue {
        let mut merged = TomlValue::Table(toml::map::Map::new());
        for layer in self.get_layers(...) {
            merge_toml_values(&mut merged, &layer.config);
        }
        merged
    }
}
```

## 依赖与外部交互

### 外部依赖
- `toml` crate：提供 `TomlValue` 类型

### 内部依赖
- 无直接内部依赖

### 设计特点
- **零依赖**：仅依赖标准库和 `toml` crate
- **递归实现**：简洁但可能有栈溢出风险
- **原地修改**：修改 `base` 参数而非返回新值

## 风险、边界与改进建议

### 潜在风险

1. **栈溢出**：
   ```rust
   // 风险：极深层嵌套的表可能导致栈溢出
   // 例如：a.b.c.d.e.f.g.h.i.j... （数百层）
   ```

2. **数组替换语义**：
   - 数组被完全替换可能不符合用户预期
   - 某些场景可能需要数组追加而非替换

3. **类型不匹配**：
   ```rust
   // base: { "key": "string" }
   // overlay: { "key": { "nested": "table" } }
   // 结果："key" 变为表，原字符串丢失
   ```

4. **性能**：
   - 递归调用有函数调用开销
   - 大量克隆操作（`value.clone()`）

### 边界条件

1. **空表**：
   ```rust
   // 空表作为 overlay 不产生任何效果
   merge_toml_values(base, &TomlValue::Table(Map::new()));
   ```

2. **空值**：
   ```rust
   // 非表类型的空值会替换 base
   // 例如：base = { "key": "value" }
   // overlay = { "key": null }
   // 结果：{ "key": null }
   ```

3. **循环引用**：
   - `TomlValue` 不包含循环引用（通过所有权保证）
   - 无需处理循环引用检测

### 改进建议

1. **迭代实现**：
   ```rust
   // 建议：使用栈迭代避免栈溢出
   pub fn merge_toml_values_iter(base: &mut TomlValue, overlay: &TomlValue) {
       let mut stack = vec![(base, overlay)];
       
       while let Some((base, overlay)) = stack.pop() {
           if let (TomlValue::Table(base_table), TomlValue::Table(overlay_table)) = (base, overlay) {
               for (key, value) in overlay_table {
                   if let Some(existing) = base_table.get_mut(key) {
                       stack.push((existing, value));
                   } else {
                       base_table.insert(key.clone(), value.clone());
                   }
               }
           } else {
               *base = overlay.clone();
           }
       }
   }
   ```

2. **数组合并策略**：
   ```rust
   // 建议：支持多种数组合并策略
   pub enum ArrayMergeStrategy {
       Replace,    // 默认：完全替换
       Append,     // 追加
       Prepend,    // 前置
       Merge,      // 元素级合并（如果元素是表）
   }
   
   pub fn merge_toml_values_with_strategy(
       base: &mut TomlValue,
       overlay: &TomlValue,
       strategy: ArrayMergeStrategy,
   )
   ```

3. **合并报告**：
   ```rust
   // 建议：返回合并报告，记录哪些键被修改
   pub struct MergeReport {
       pub added: Vec<String>,
       pub modified: Vec<String>,
       pub removed: Vec<String>,  // 如果需要支持删除
   }
   
   pub fn merge_toml_values_with_report(
       base: &mut TomlValue,
       overlay: &TomlValue,
   ) -> MergeReport
   ```

4. **路径跟踪**：
   ```rust
   // 建议：在合并冲突时提供路径信息
   pub enum MergeError {
       TypeMismatch { path: String, base: String, overlay: String },
   }
   ```

5. **性能优化**：
   ```rust
   // 建议：使用 Cow 避免不必要的克隆
   use std::borrow::Cow;
   
   pub fn merge_toml_values_cow<'a>(
       base: &'a TomlValue,
       overlay: &'a TomlValue,
   ) -> Cow<'a, TomlValue> {
       // 只在必要时克隆
   }
   ```

### 测试覆盖

当前测试：
- 主要通过集成测试覆盖（`state.rs` 的测试）
- 无单元测试

建议补充：
- 基础合并场景测试
- 嵌套表合并测试
- 数组替换测试
- 大表性能测试
- 深层嵌套栈溢出测试

### 对比参考

与其他配置合并库对比：

| 特性 | 当前实现 | `serde_json::Value` 合并 | `config` crate |
|------|----------|--------------------------|----------------|
| 递归深度 | 有限（栈深度） | 类似 | 类似 |
| 数组处理 | 替换 | 通常替换 | 可配置 |
| 性能 | 中等 | 类似 | 优化 |
| 功能丰富度 | 简单 | 简单 | 丰富 |

当前实现适合 Codex 的使用场景，但如需更复杂功能可考虑专用配置管理 crate。
