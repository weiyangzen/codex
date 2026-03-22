# codex-rs/artifacts/src/tests.rs 研究文档

## 场景与职责

`tests.rs` 是 `codex-artifacts` crate 的集成测试模块，负责验证 artifact 运行时管理和构建执行的完整流程。测试覆盖了从发布定位、运行时下载、缓存加载到实际构建执行的端到端场景。

主要测试场景：
- 发布定位器 URL 构建逻辑
- 缓存运行时加载和验证
- 运行时下载和提取（ZIP/TAR.GZ 格式）
- Artifact 客户端构建执行

## 功能点目的

### 1. 发布定位器测试

验证 `ArtifactRuntimeReleaseLocator` 的 URL 构建逻辑：
- `release_locator_builds_manifest_url`: 自定义基础 URL
- `default_release_locator_uses_openai_codex_github_releases`: 默认 GitHub 发布位置

### 2. 缓存运行时加载测试

验证 `load_cached_runtime` 的各种场景：
- `load_cached_runtime_reads_installed_runtime`: 正常加载
- `load_cached_runtime_requires_build_entrypoint`: 缺少入口点文件时失败
- `load_cached_runtime_requires_package_export`: 无效 package.json 导出时失败
- `load_cached_runtime_uses_custom_cache_root`: 自定义缓存根目录

### 3. 运行时下载安装测试

验证 `ArtifactRuntimeManager::ensure_installed` 的下载流程：
- `ensure_installed_downloads_and_extracts_zip_runtime`: ZIP 格式
- `ensure_installed_downloads_and_extracts_tar_gz_runtime`: TAR.GZ 格式

### 4. 构建执行测试

验证 `ArtifactsClient::execute_build`：
- `artifacts_client_execute_build_writes_wrapped_script_and_env`: 完整构建流程（Unix only）

## 具体技术实现

### 测试基础设施

#### Mock HTTP 服务器 (wiremock)

```rust
let server = MockServer::start().await;

// 配置 manifest 响应
Mock::given(method("GET"))
    .and(path("/artifact-runtime-v{version}/...-manifest.json"))
    .respond_with(ResponseTemplate::new(200).set_body_json(&manifest))
    .mount(&server)
    .await;

// 配置 archive 下载响应
Mock::given(method("GET"))
    .and(path("/artifact-runtime-v{version}/{archive_name}"))
    .respond_with(ResponseTemplate::new(200).set_body_bytes(archive_bytes))
    .mount(&server)
    .await;
```

#### 测试辅助函数

**`write_installed_runtime`**: 创建模拟的运行时安装目录
```rust
fn write_installed_runtime(install_dir: &Path, runtime_version: &str) {
    // 创建目录结构
    // 写入 package.json（包含 name, version, type, exports）
    // 写入 dist/artifact_tool.mjs（模拟工具代码）
}
```

**`build_zip_archive`**: 构建 ZIP 格式的测试归档
```rust
fn build_zip_archive(runtime_version: &str) -> Vec<u8> {
    // 使用 zip crate 创建归档
    // 包含: artifact-runtime/package.json
    //       artifact-runtime/dist/artifact_tool.mjs
}
```

**`build_tar_gz_archive`**: 构建 TAR.GZ 格式的测试归档
```rust
fn build_tar_gz_archive(runtime_version: &str) -> Vec<u8> {
    // 使用 flate2 + tar crate 创建归档
    // 包含: package/package.json
    //       package/dist/artifact_tool.mjs
}
```

**`assert_success`**: 验证命令成功执行
```rust
fn assert_success(output: &ArtifactCommandOutput) {
    assert!(output.success());
    assert_eq!(output.exit_code, Some(0));
}
```

### 关键测试用例详解

#### 1. URL 构建测试

```rust
#[test]
fn release_locator_builds_manifest_url() {
    let locator = ArtifactRuntimeReleaseLocator::new(
        url::Url::parse("https://example.test/releases/").unwrap(),
        "0.1.0",
    );
    let url = locator.manifest_url().unwrap();
    // 验证: https://example.test/releases/artifact-runtime-v0.1.0/artifact-runtime-v0.1.0-manifest.json
}
```

#### 2. 缓存加载测试

```rust
#[test]
fn load_cached_runtime_reads_installed_runtime() {
    // 1. 创建临时目录作为 codex_home
    // 2. 使用 write_installed_runtime 创建模拟运行时
    // 3. 调用 load_cached_runtime
    // 4. 验证: runtime_version, platform, build_js_path
}
```

#### 3. 下载安装测试（异步）

```rust
#[tokio::test]
async fn ensure_installed_downloads_and_extracts_zip_runtime() {
    // 1. 启动 mock HTTP 服务器
    // 2. 构建测试归档和 manifest
    // 3. 配置 mock 响应
    // 4. 创建 ArtifactRuntimeManager
    // 5. 调用 ensure_installed().await
    // 6. 验证返回的运行时信息
}
```

#### 4. 构建执行测试

```rust
#[tokio::test]
#[cfg(unix)]
async fn artifacts_client_execute_build_writes_wrapped_script_and_env() {
    // 1. 创建临时运行时环境
    // 2. 使用已安装运行时创建 ArtifactsClient
    // 3. 执行构建请求（测试全局变量注入）
    // 4. 验证输出包含预期的 stdout/stderr
}
```

测试代码验证的全局变量注入：
```javascript
console.log(typeof artifacts);        // "undefined" - 未定义
console.log(typeof codexArtifacts);   // "undefined" - 未定义  
console.log(artifactTool.ok);         // "true" - 从导入模块
console.log(ok);                      // "true" - 全局注入
```

## 关键代码路径与文件引用

### 测试依赖的模块

| 被测模块 | 文件路径 | 测试覆盖功能 |
|----------|----------|--------------|
| `ArtifactRuntimeReleaseLocator` | `runtime/manager.rs` | URL 构建 |
| `load_cached_runtime` | `runtime/installed.rs` | 缓存加载 |
| `ArtifactRuntimeManager` | `runtime/manager.rs` | 下载安装 |
| `ArtifactsClient` | `client.rs` | 构建执行 |

### 关键测试函数行号

- **行 34-47**: `release_locator_builds_manifest_url`
- **行 49-60**: `default_release_locator_uses_openai_codex_github_releases`
- **行 62-88**: `load_cached_runtime_reads_installed_runtime`
- **行 90-118**: `load_cached_runtime_requires_build_entrypoint`
- **行 120-184**: `ensure_installed_downloads_and_extracts_zip_runtime`
- **行 186-222**: `load_cached_runtime_requires_package_export`
- **行 224-288**: `ensure_installed_downloads_and_extracts_tar_gz_runtime`
- **行 290-313**: `load_cached_runtime_uses_custom_cache_root`
- **行 315-352**: `artifacts_client_execute_build_writes_wrapped_script_and_env`
- **行 354-357**: `assert_success`
- **行 359-379**: `write_installed_runtime`
- **行 381-407**: `build_zip_archive`
- **行 409-453**: `build_tar_gz_archive`

### 测试数据

**模拟 package.json**:
```json
{
    "name": "@oai/artifact-tool",
    "version": "{runtime_version}",
    "type": "module",
    "exports": {
        ".": "./dist/artifact_tool.mjs"
    }
}
```

**模拟 artifact_tool.mjs**:
```javascript
export const ok = true;
```

## 依赖与外部交互

### 测试依赖的 crates

| Crate | 用途 |
|-------|------|
| `wiremock` | HTTP mock 服务器，模拟发布服务器 |
| `tempfile` | 临时目录创建 |
| `pretty_assertions` | 更好的断言失败输出 |
| `sha2` | SHA256 校验和计算 |
| `flate2` | Gzip 压缩 |
| `tar` | TAR 归档创建 |
| `zip` | ZIP 归档创建 |
| `tokio` | 异步运行时（测试用） |

### 被测 crate 的依赖

| Crate | 被测功能 |
|-------|----------|
| `codex-package-manager` | `PackageReleaseArchive`, `ArchiveFormat` |
| `serde_json` | Manifest JSON 序列化 |

### 外部命令依赖

- **Node.js/Electron**: `artifacts_client_execute_build_writes_wrapped_script_and_env` 需要系统安装 Node.js 或 Electron

## 风险、边界与改进建议

### 已知风险

1. **平台限制**
   - `#[cfg(all(test, not(windows)))]` 排除 Windows 测试
   - `#[cfg(unix)]` 限制构建执行测试仅在 Unix 运行
   - Windows 测试覆盖不足

2. **外部依赖**
   - 构建执行测试依赖系统安装的 Node.js/Electron
   - 测试环境不一致可能导致测试失败

3. **Mock 数据同步**
   - 测试中的归档结构与真实发布可能不同步
   - 如果真实 artifact-runtime 包结构变化，测试可能通过但实际失败

4. **网络模拟局限**
   - wiremock 仅模拟成功路径
   - 缺少网络失败、超时、部分下载等错误场景测试

### 边界情况

1. **归档格式差异**
   - ZIP 测试使用 `artifact-runtime/` 前缀
   - TAR.GZ 测试使用 `package/` 前缀
   - 这反映了真实发布的差异，但测试未验证自动检测逻辑

2. **并发安装**
   - 测试未覆盖多进程并发安装场景
   - `PackageManager` 有文件锁逻辑，但测试未验证

3. **缓存失效**
   - 测试未覆盖版本不匹配时的缓存失效
   - 未测试损坏缓存的恢复

### 改进建议

1. **增强平台覆盖**
   ```rust
   // 建议：添加 Windows 特定测试或模拟
   #[cfg(windows)]
   mod windows_tests {
       // Windows 特定的路径和运行时检测测试
   }
   ```

2. **添加错误场景测试**
   ```rust
   #[tokio::test]
   async fn ensure_installed_handles_network_failure() {
       // 模拟 404/500 响应
   }
   
   #[tokio::test]
   async fn ensure_installed_handles_invalid_checksum() {
       // 提供错误的 SHA256
   }
   ```

3. **隔离外部依赖**
   ```rust
   // 建议：使用 mock JS 运行时，而非依赖系统 Node.js
   fn create_mock_js_runtime() -> JsRuntime {
       // 创建一个简单的可执行文件作为 mock
   }
   ```

4. **并发测试**
   ```rust
   #[tokio::test]
   async fn concurrent_install_is_safe() {
       // 同时启动多个 ensure_installed 调用
       // 验证文件锁正确工作
   }
   ```

5. **测试数据生成**
   ```rust
   // 建议：使用 proptest 或类似工具生成随机版本号
   // 验证版本解析的鲁棒性
   ```

6. **文档测试**
   ```rust
   /// ```
   /// let locator = ArtifactRuntimeReleaseLocator::default("1.0.0");
   /// assert!(locator.manifest_url().is_ok());
   /// ```
   pub fn default(...) { ... }
   ```

7. **性能基准**
   ```rust
   // 建议：添加下载和提取的性能基准测试
   #[bench]
   fn bench_archive_extraction(b: &mut Bencher) {
       // 测量大归档的提取性能
   }
   ```

8. **测试辅助函数改进**
   ```rust
   // 建议：使用 builder 模式创建测试数据
   struct TestRuntimeBuilder { ... }
   impl TestRuntimeBuilder {
       fn with_version(mut self, version: &str) -> Self { ... }
       fn with_corrupted_package(mut self) -> Self { ... }
       fn build(self) -> TempDir { ... }
   }
   ```
