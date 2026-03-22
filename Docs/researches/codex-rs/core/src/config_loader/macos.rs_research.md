# codex-rs/core/src/config_loader/macos.rs 研究文档

## 场景与职责

`macos.rs` 是配置加载器的 macOS 平台特定模块，负责与 Apple 的移动设备管理（MDM）系统集成。它通过 macOS 的 CoreFoundation 框架读取托管偏好设置（Managed Preferences），允许企业 IT 管理员通过 MDM 解决方案（如 Jamf、Kandji 等）远程配置 Codex 的行为。

主要使用场景：
- **企业部署**：IT 管理员通过 MDM 强制实施安全策略
- **合规要求**：确保所有员工设备使用统一的配置
- **安全加固**：限制可用的沙箱模式、审批策略等

该模块仅在 macOS 目标平台上编译（`#[cfg(target_os = "macos")]`），其他平台使用空实现。

## 功能点目的

### 1. MDM 配置键

模块定义了两个托管偏好设置键：

```rust
const MANAGED_PREFERENCES_APPLICATION_ID: &str = "com.openai.codex";
const MANAGED_PREFERENCES_CONFIG_KEY: &str = "config_toml_base64";
const MANAGED_PREFERENCES_REQUIREMENTS_KEY: &str = "requirements_toml_base64";
```

| 键名 | 用途 | 格式 |
|------|------|------|
| `config_toml_base64` | 托管配置（与 `config.toml` 相同结构）| Base64 编码的 TOML |
| `requirements_toml_base64` | 配置约束要求 | Base64 编码的 TOML |

### 2. 核心数据结构

```rust
#[derive(Debug, Clone)]
pub(super) struct ManagedAdminConfigLayer {
    pub config: TomlValue,      // 解析后的配置
    pub raw_toml: String,       // 原始 TOML（用于审计和调试）
}
```

### 3. 主要功能

1. **加载托管配置** (`load_managed_admin_config_layer`)
   - 支持测试覆盖（通过 base64 字符串）
   - 实际环境通过 CoreFoundation 读取 MDM 配置

2. **加载托管要求** (`load_managed_admin_requirements_toml`)
   - 将 MDM 要求合并到 `ConfigRequirementsWithSources`
   - 支持增量更新（只填充未设置的字段）

3. **来源标识** (`managed_preferences_requirements_source`)
   - 生成 `RequirementSource::MdmManagedPreferences` 用于追踪配置来源

## 具体技术实现

### CoreFoundation FFI 调用

```rust
#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFPreferencesCopyAppValue(
        key: CFStringRef, 
        application_id: CFStringRef
    ) -> *mut c_void;
}
```

这是与 macOS 系统交互的核心，通过 `CFPreferencesCopyAppValue` 读取指定应用 ID 和键的托管值。

### 配置加载流程

```rust
pub(crate) async fn load_managed_admin_config_layer(
    override_base64: Option<&str>,
) -> io::Result<Option<ManagedAdminConfigLayer>> {
    // 1. 检查是否有测试覆盖
    if let Some(encoded) = override_base64 {
        let trimmed = encoded.trim();
        return if trimmed.is_empty() {
            Ok(None)
        } else {
            parse_managed_config_base64(trimmed).map(Some)
        };
    }

    // 2. 在阻塞线程池中执行 CoreFoundation 调用
    match task::spawn_blocking(load_managed_admin_config).await {
        Ok(result) => result,
        Err(join_err) => {
            // 处理任务取消或失败
            tracing::error!("Managed config load task failed: {join_err}");
            Err(io::Error::other("Failed to load managed config"))
        }
    }
}
```

### 同步配置加载

```rust
fn load_managed_admin_config() -> io::Result<Option<ManagedAdminConfigLayer>> {
    load_managed_preference(MANAGED_PREFERENCES_CONFIG_KEY)?
        .as_deref()
        .map(str::trim)
        .map(parse_managed_config_base64)
        .transpose()
}
```

### CoreFoundation 值读取

```rust
fn load_managed_preference(key_name: &str) -> io::Result<Option<String>> {
    // 构建 CFString
    let value_ref = unsafe {
        CFPreferencesCopyAppValue(
            CFString::new(key_name).as_concrete_TypeRef(),
            CFString::new(MANAGED_PREFERENCES_APPLICATION_ID).as_concrete_TypeRef(),
        )
    };

    if value_ref.is_null() {
        tracing::debug!("Managed preferences for {key_name} not found");
        return Ok(None);
    }

    // 安全地包装 CFString 并转换为 Rust String
    let value = unsafe { CFString::wrap_under_create_rule(value_ref as _) }.to_string();
    Ok(Some(value))
}
```

### Base64 解码和 TOML 解析

```rust
fn parse_managed_config_base64(encoded: &str) -> io::Result<ManagedAdminConfigLayer> {
    let raw_toml = decode_managed_preferences_base64(encoded)?;
    match toml::from_str::<TomlValue>(&raw_toml) {
        Ok(TomlValue::Table(parsed)) => Ok(ManagedAdminConfigLayer {
            config: TomlValue::Table(parsed),
            raw_toml,
        }),
        Ok(other) => {
            // 要求根必须是表类型
            Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "managed config root must be a table",
            ))
        }
        Err(err) => Err(io::Error::new(io::ErrorKind::InvalidData, err)),
    }
}

fn decode_managed_preferences_base64(encoded: &str) -> io::Result<String> {
    String::from_utf8(BASE64_STANDARD.decode(encoded.as_bytes()).map_err(|err| {
        io::Error::new(io::ErrorKind::InvalidData, err)
    })?)
    .map_err(|err| {
        io::Error::new(io::ErrorKind::InvalidData, err)
    })
}
```

### 要求加载的特殊处理

```rust
pub(crate) async fn load_managed_admin_requirements_toml(
    target: &mut ConfigRequirementsWithSources,
    override_base64: Option<&str>,
) -> io::Result<()> {
    if let Some(encoded) = override_base64 {
        // 测试覆盖路径
        let trimmed = encoded.trim();
        if trimmed.is_empty() {
            return Ok(());
        }
        target.merge_unset_fields(
            managed_preferences_requirements_source(),
            parse_managed_requirements_base64(trimmed)?,
        );
        return Ok(());
    }

    // 异步加载并合并
    match task::spawn_blocking(load_managed_admin_requirements).await {
        Ok(result) => {
            if let Some(requirements) = result? {
                target.merge_unset_fields(managed_preferences_requirements_source(), requirements);
            }
            Ok(())
        }
        Err(join_err) => { /* ... */ }
    }
}
```

## 关键代码路径与文件引用

### 模块内部结构

```
macos.rs
├── 常量定义（APPLICATION_ID, CONFIG_KEY, REQUIREMENTS_KEY）
├── ManagedAdminConfigLayer 结构体
├── managed_preferences_requirements_source()
├── load_managed_admin_config_layer() [async]
│   ├── parse_managed_config_base64()
│   │   └── decode_managed_preferences_base64()
│   └── load_managed_admin_config()
│       └── load_managed_preference() [FFI]
├── load_managed_admin_requirements_toml() [async]
│   ├── parse_managed_requirements_base64()
│   └── load_managed_admin_requirements()
│       └── load_managed_preference() [FFI]
└── 辅助函数（decode, parse）
```

### 依赖关系

| 依赖 | 路径 | 用途 |
|------|------|------|
| `core_foundation` | crates.io | CoreFoundation 类型的 Rust 绑定 |
| `base64` | crates.io | Base64 解码 |
| `tokio::task` | tokio | 阻塞操作包装 |
| `ConfigRequirementsWithSources` | `codex-config/src/config_requirements.rs` | 要求合并目标 |
| `RequirementSource` | `codex-config/src/config_requirements.rs` | 来源标识 |

### 调用方

1. **layer_io.rs**
   ```rust
   let managed_preferences =
       load_managed_admin_config_layer(managed_preferences_base64.as_deref())
           .await?
           .map(map_managed_admin_layer);
   ```

2. **mod.rs**
   ```rust
   macos::load_managed_admin_requirements_toml(
       &mut config_requirements_toml,
       overrides.macos_managed_config_requirements_base64.as_deref(),
   ).await?;
   ```

### 类型转换映射

```
CoreFoundation (C)
    ↓ CFPreferencesCopyAppValue
*mut c_void (CFStringRef)
    ↓ wrap_under_create_rule
CFString (core_foundation crate)
    ↓ to_string()
String (Rust)
    ↓ BASE64_STANDARD.decode
Vec<u8>
    ↓ String::from_utf8
String (TOML text)
    ↓ toml::from_str
TomlValue
```

## 依赖与外部交互

### 系统框架依赖

**CoreFoundation.framework**
- `CFPreferencesCopyAppValue`: 读取应用偏好设置
- `CFString`: 字符串类型处理
- 内存管理规则：`wrap_under_create_rule` 表示获取所有权，需要释放

### MDM 系统集成

MDM 解决方案通过以下方式配置：
1. 在 MDM 控制台中配置 `com.openai.codex` 域的偏好设置
2. 设置 `config_toml_base64` 或 `requirements_toml_base64` 键
3. 值必须是 Base64 编码的有效 TOML

示例配置（解码后）：
```toml
# config_toml_base64 解码后
approval_policy = "never"
sandbox_mode = "read-only"
```

```toml
# requirements_toml_base64 解码后
allowed_approval_policies = ["never", "on-request"]
allowed_sandbox_modes = ["read-only"]
```

### 并发模型

由于 CoreFoundation API 不是异步的，使用 `tokio::task::spawn_blocking` 在专用线程池中执行：

```rust
task::spawn_blocking(load_managed_admin_config).await
```

这确保了：
- 不会阻塞主异步运行时
- 可以处理任务取消
- 可以设置超时（如果需要）

## 风险、边界与改进建议

### 潜在风险

1. **FFI 安全性**
   - 使用 `unsafe` 块调用 CoreFoundation API
   - 需要确保 `wrap_under_create_rule` 正确管理内存
   - **当前实现**：正确使用 `as_concrete_TypeRef()` 和 `wrap_under_create_rule`
   - **风险等级**：低

2. **Base64 解码失败**
   - MDM 配置可能包含无效的 Base64
   - 当前返回 `InvalidData` 错误，可能导致配置加载失败
   - **建议**：考虑更宽容的错误处理，记录警告但继续加载

3. **TOML 根类型检查**
   - 要求 TOML 根必须是表类型
   - 如果 MDM 配置了错误的类型（如数组），会报错
   - **建议**：添加更详细的错误信息，帮助 IT 管理员调试

4. **线程池耗尽**
   - 每次加载都使用 `spawn_blocking`
   - 如果频繁调用，可能耗尽 Tokio 的阻塞线程池
   - **建议**：考虑缓存 MDM 配置，避免重复读取

### 边界情况

1. **空配置处理**
   ```rust
   if trimmed.is_empty() {
       return Ok(None);  // 或 Ok(())
   }
   ```
   空字符串被视为"无配置"，而不是错误。

2. **MDM 未配置**
   - `CFPreferencesCopyAppValue` 返回 null
   - 正常返回 `Ok(None)`，不报错

3. **并发读取**
   - CoreFoundation 偏好设置 API 是线程安全的
   - 但 `spawn_blocking` 确保串行执行

4. **非 UTF-8 数据**
   - Base64 解码后必须是有效 UTF-8
   - 否则返回 `InvalidData` 错误

### 改进建议

1. **添加配置缓存**
   ```rust
   use std::sync::OnceLock;
   
   static MANAGED_CONFIG_CACHE: OnceLock<tokio::sync::RwLock<Option<ManagedAdminConfigLayer>>> 
       = OnceLock::new();
   ```
   避免重复读取 MDM 配置，提高性能。

2. **增强错误信息**
   ```rust
   Err(io::Error::new(
       io::ErrorKind::InvalidData,
       format!(
           "MDM managed config for {} must be a TOML table, got: {:?}",
           MANAGED_PREFERENCES_CONFIG_KEY,
           other
       ),
   ))
   ```

3. **添加指标和监控**
   ```rust
   tracing::info!(
       domain = MANAGED_PREFERENCES_APPLICATION_ID,
       key = MANAGED_PREFERENCES_CONFIG_KEY,
       "loaded MDM managed config"
   );
   ```

4. **支持配置验证模式**
   ```rust
   pub async fn validate_managed_config(encoded: &str) -> Result<(), ConfigValidationError> {
       let layer = parse_managed_config_base64(encoded)?;
       // 验证配置值是否在允许范围内
       Ok(())
   }
   ```

5. **添加超时处理**
   ```rust
   match tokio::time::timeout(
       Duration::from_secs(5),
       task::spawn_blocking(load_managed_admin_config)
   ).await {
       Ok(Ok(result)) => result,
       Ok(Err(join_err)) => { /* ... */ }
       Err(_) => {
           tracing::warn!("MDM config load timed out");
           Ok(None)
       }
   }
   ```

6. **文档改进**
   - 添加 MDM 配置示例文档
   - 说明如何测试 MDM 配置（使用 `override_base64`）
   - 提供常见 MDM 解决方案的配置指南

7. **测试增强**
   - 添加针对无效 Base64 的测试
   - 添加针对无效 TOML 的测试
   - 添加针对非表类型 TOML 的测试
   - 模拟 `CFPreferencesCopyAppValue` 进行单元测试
