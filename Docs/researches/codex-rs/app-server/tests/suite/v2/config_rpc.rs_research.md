# config_rpc.rs 研究文档

## 场景与职责

`config_rpc.rs` 是 Codex App Server V2 API 的配置管理测试套件，负责验证配置读取、写入、批量写入等 RPC 方法的正确性。该测试文件确保配置系统的分层架构（Layered Configuration）能够正确工作，包括用户层、系统层、项目层和托管配置层的优先级处理。

## 功能点目的

### 1. 配置读取测试 (`config/read`)
- **目的**: 验证配置读取 RPC 能够返回有效配置、配置来源(origins)和配置层(layers)
- **关键测试**:
  - `config_read_returns_effective_and_layers`: 基础配置读取，验证模型和沙盒模式
  - `config_read_includes_tools`: 验证工具配置（web_search、view_image）的读取
  - `config_read_includes_nested_web_search_tool_config`: 验证嵌套工具配置（含位置信息）
  - `config_read_ignores_bool_web_search_tool_config`: 验证布尔值工具配置被忽略
  - `config_read_includes_apps`: 验证应用配置（apps）的读取
  - `config_read_includes_project_layers_for_cwd`: 验证基于工作目录的项目层配置
  - `config_read_includes_system_layer_and_overrides`: 验证系统层和托管配置的覆盖逻辑

### 2. 配置写入测试 (`config/value/write`)
- **目的**: 验证单值配置写入和版本冲突检测
- **关键测试**:
  - `config_value_write_replaces_value`: 验证配置值替换
  - `config_value_write_rejects_version_conflict`: 验证版本冲突时拒绝写入（乐观锁机制）

### 3. 批量配置写入测试 (`config/batchWrite`)
- **目的**: 验证多配置项原子写入
- **关键测试**:
  - `config_batch_write_applies_multiple_edits`: 验证批量编辑应用和复杂配置结构写入

## 具体技术实现

### 关键流程

```
配置读取流程:
1. 创建临时 CODEX_HOME 目录
2. 写入测试配置到 config.toml
3. 启动 MCP 进程并初始化
4. 发送 config/read 请求 (ConfigReadParams)
5. 验证 ConfigReadResponse:
   - config: 有效配置
   - origins: 每个配置项的来源映射
   - layers: 配置层列表（可选）

配置写入流程:
1. 读取当前配置获取版本号
2. 发送 config/value/write 请求 (ConfigValueWriteParams)
3. 验证 ConfigWriteResponse:
   - status: Ok 或 OkOverridden
   - version: 新版本号
   - file_path: 写入的文件路径
   - overridden_metadata: 覆盖元数据（如有）
```

### 数据结构

**ConfigReadParams**:
```rust
pub struct ConfigReadParams {
    pub include_layers: bool,  // 是否包含配置层详情
    pub cwd: Option<String>,   // 用于解析项目层的工作目录
}
```

**ConfigValueWriteParams**:
```rust
pub struct ConfigValueWriteParams {
    pub key_path: String,           // 配置键路径（如 "model"、"tools.web_search.context_size"）
    pub value: JsonValue,           // 配置值
    pub merge_strategy: MergeStrategy,  // Replace 或 Upsert
    pub file_path: Option<String>,  // 目标文件路径
    pub expected_version: Option<String>,  // 乐观锁版本
}
```

**ConfigLayerSource** (配置层来源):
```rust
pub enum ConfigLayerSource {
    Mdm { domain, key },                    // MDM 托管配置
    System { file },                        // 系统配置
    User { file },                          // 用户配置 (~/.codex/config.toml)
    Project { dot_codex_folder },           // 项目配置 (.codex/config.toml)
    SessionFlags,                           // 会话标志
    LegacyManagedConfigTomlFromFile { file },
    LegacyManagedConfigTomlFromMdm,
}
```

### 配置优先级（从高到低）

```rust
impl ConfigLayerSource {
    pub fn precedence(&self) -> i16 {
        match self {
            ConfigLayerSource::Mdm { .. } => 0,
            ConfigLayerSource::System { .. } => 10,
            ConfigLayerSource::User { .. } => 20,
            ConfigLayerSource::Project { .. } => 25,
            ConfigLayerSource::SessionFlags => 30,
            ConfigLayerSource::LegacyManagedConfigTomlFromFile { .. } => 40,
            ConfigLayerSource::LegacyManagedConfigTomlFromMdm => 50,
        }
    }
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/config_rpc.rs`: 本测试文件
- `codex-rs/app-server/tests/common/mcp_process.rs`: MCP 进程管理工具
- `codex-rs/app-server/tests/common/lib.rs`: 测试公共库

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: V2 API 协议类型定义
  - `ConfigReadParams`, `ConfigReadResponse`
  - `ConfigValueWriteParams`, `ConfigBatchWriteParams`
  - `ConfigWriteResponse`, `WriteStatus`
  - `ConfigLayer`, `ConfigLayerSource`, `ConfigLayerMetadata`
  - `MergeStrategy` (Replace/Upsert)

### 核心配置系统
- `codex-rs/core/src/config/mod.rs`: 核心配置管理
- `codex-rs/core/src/config/profile.rs`: 配置 profile 管理

### 辅助函数
- `write_config()`: 写入测试配置文件
- `assert_layers_user_then_optional_system()`: 验证用户层+系统层结构
- `assert_layers_managed_user_then_optional_system()`: 验证托管层+用户层+系统层结构

## 依赖与外部交互

### 外部依赖
- `tempfile::TempDir`: 临时目录管理
- `tokio::time::timeout`: 异步超时控制
- `serde_json`: JSON 序列化
- `pretty_assertions`: 测试断言增强

### 内部依赖
- `app_test_support`: 测试支持库
  - `McpProcess`: MCP 进程封装
  - `to_response()`: 响应解析
  - `test_path_buf_with_windows()`: 跨平台路径处理
- `codex_app_server_protocol`: 协议类型
- `codex_core::config`: 配置核心
- `codex_utils_absolute_path::AbsolutePathBuf`: 绝对路径处理

### 环境变量
- `CODEX_HOME`: 配置根目录
- `CODEX_APP_SERVER_MANAGED_CONFIG_PATH`: 托管配置路径（特定测试使用）

## 风险、边界与改进建议

### 风险点
1. **版本冲突处理**: 乐观锁机制依赖版本号，测试中使用 SHA256 哈希，实际实现可能有差异
2. **跨平台路径处理**: 使用 `test_path_buf_with_windows()` 处理 Windows 路径，但测试主要在 Unix 环境运行
3. **配置层顺序**: 测试假设层顺序固定，但 MDM 层可能存在也可能不存在

### 边界情况
1. **空配置**: 测试使用空字符串初始化配置，验证基础功能
2. **嵌套配置**: 测试 `tools.web_search.context_size` 等嵌套路径
3. **数组配置**: 测试 `tools.web_search.allowed_domains.0` 等数组索引路径
4. **项目层信任级别**: 使用 `set_project_trust_level()` 设置项目信任级别

### 改进建议
1. **并发测试**: 当前测试是顺序的，可考虑添加并发写入测试
2. **错误场景**: 可增加更多错误场景测试（如无效 key_path、无效配置值）
3. **性能测试**: 大配置文件的读写性能测试
4. **配置热重载**: 测试 `reload_user_config` 参数的热重载功能
5. **配置验证**: 增加配置值验证失败场景的测试

### 相关测试覆盖
- 配置读取: 7 个测试用例
- 配置写入: 2 个测试用例
- 批量写入: 1 个测试用例
- 总计: 10 个测试用例，覆盖主要配置操作路径
