# config.rs 研究文档

## 场景与职责

`config.rs` 定义了 `codex-package-manager` crate 的配置结构 `PackageManagerConfig`，它是包管理器初始化的核心参数载体。该模块将包管理器的运行时配置与具体的包类型解耦，通过泛型参数支持不同类型的托管包。

### 核心职责
1. **配置封装**：封装包管理器所需的所有配置参数
2. **缓存根目录管理**：支持默认缓存路径和自定义缓存路径
3. **类型安全**：使用泛型参数 `P` 确保配置与具体包类型绑定

## 功能点目的

### 1. PackageManagerConfig - 配置结构体

```rust
pub struct PackageManagerConfig<P> {
    pub(crate) codex_home: PathBuf,    // Codex 主目录
    pub(crate) package: P,              // 包类型实例（ManagedPackage 实现）
    cache_root: Option<PathBuf>,        // 可选的自定义缓存根目录
}
```

**设计目的**：
- **不可变性**：配置创建后不可变，避免运行时配置漂移
- **泛型设计**：通过 `P` 类型参数与具体包实现绑定，编译期类型安全
- **可选覆盖**：`cache_root` 为 `Option`，支持默认行为和自定义行为

### 2. new - 构造函数

```rust
pub fn new(codex_home: PathBuf, package: P) -> Self
```

**设计考量**：
- 强制要求 `codex_home`，确保所有路径有统一的根基准
- 默认 `cache_root` 为 `None`，使用包类型定义的相对路径

### 3. with_cache_root - 缓存根覆盖

```rust
pub fn with_cache_root(mut self, cache_root: PathBuf) -> Self
```

**设计模式**：
- 使用消耗性构建器模式（consuming builder）
- 支持链式调用：`PackageManagerConfig::new(...).with_cache_root(...)`
- 适用于测试场景或特殊部署需求

### 4. cache_root - 有效缓存根计算

```rust
pub fn cache_root(&self) -> PathBuf
```

**计算逻辑**：
```rust
self.cache_root.clone().unwrap_or_else(|| {
    self.codex_home.join(
        self.package
            .default_cache_root_relative()
            .replace('/', std::path::MAIN_SEPARATOR_STR)
    )
})
```

**关键特性**：
- 路径分隔符转换：将 Unix 风格 `/` 转换为当前平台的分隔符
- 延迟计算：每次调用时计算，确保 `codex_home` 和包配置的最新值

## 具体技术实现

### 类型约束

```rust
impl<P: ManagedPackage> PackageManagerConfig<P>
```

`cache_root()` 方法仅在 `P: ManagedPackage` 时可用，因为需要调用 `default_cache_root_relative()`。

### 路径处理

| 功能 | 实现 | 说明 |
|------|------|------|
| 分隔符转换 | `replace('/', std::path::MAIN_SEPARATOR_STR)` | 确保跨平台兼容 |
| 路径拼接 | `PathBuf::join` | 使用标准库路径拼接 |

## 关键代码路径与文件引用

### 内部依赖
- `crate::ManagedPackage` - trait 定义（package.rs）

### 调用关系

**被调用方**（来自 manager.rs）：
- `PackageManagerConfig::new` - 创建包管理器配置
- `PackageManagerConfig::with_cache_root` - 自定义缓存路径
- `PackageManagerConfig::cache_root` - 获取有效缓存路径

**使用示例**（来自 artifacts/src/runtime/manager.rs）：
```rust
let package_manager = PackageManagerConfig::new(
    codex_home,
    ArtifactRuntimePackage::new(release.clone()),
);
```

## 依赖与外部交互

### 标准库依赖
- `std::path::PathBuf` - 路径表示
- `std::path::MAIN_SEPARATOR_STR` - 平台特定路径分隔符

### 无外部 crate 依赖

本模块仅依赖标准库，保持轻量级。

## 风险、边界与改进建议

### 已知风险

1. **路径遍历风险**
   - **缓解措施**：`default_cache_root_relative()` 应返回相对路径，不包含 `..`
   - **责任归属**：`ManagedPackage` 实现者需确保返回安全路径

2. **并发修改**
   - **缓解措施**：配置结构体不可变，创建后无法修改
   - **风险**：`cache_root()` 返回克隆的 `PathBuf`，调用者持有独立副本

### 边界条件

| 场景 | 行为 |
|------|------|
| `cache_root` 为绝对路径 | 直接使用，忽略 `codex_home` |
| `cache_root` 为相对路径 | 与 `codex_home` 拼接 |
| 空 `default_cache_root_relative` | 返回 `codex_home` 本身 |
| 包含 `..` 的相对路径 | 依赖文件系统解析，可能逃逸 |

### 改进建议

1. **路径验证**
   - 在 `with_cache_root` 中验证路径不包含 `..` 组件
   - 或规范化路径后验证仍在 `codex_home` 下

2. **缓存根规范化**
   - 使用 `std::fs::canonicalize` 或 `dunce::canonicalize` 规范化路径
   - 避免符号链接导致的路径不一致

3. **配置持久化**
   - 当前配置仅内存存在
   - 可考虑支持从配置文件加载（如 TOML/JSON）

4. **Builder 模式完善**
   - 当前仅支持 `cache_root` 覆盖
   - 可考虑添加更多可选配置（如超时、重试策略）

5. **类型安全增强**
   - 考虑使用 newtype 模式包装 `PathBuf`，区分绝对/相对路径
   - 例如：`struct AbsolutePath(PathBuf)`、`struct RelativePath(PathBuf)`

### 测试覆盖

测试文件 `tests.rs` 中相关测试：
- `resolve_cached_uses_custom_cache_root` - 验证自定义缓存根功能
