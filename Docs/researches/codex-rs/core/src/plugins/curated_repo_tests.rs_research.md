# curated_repo_tests.rs 研究文档

## 场景与职责

`curated_repo_tests.rs` 是 `curated_repo.rs` 的单元测试模块，负责验证精选插件仓库同步功能的正确性。测试使用 `wiremock` 库模拟 GitHub API 响应，确保在无外部网络依赖的情况下验证同步逻辑。

### 测试范围
1. **路径管理**：验证插件仓库路径拼接逻辑
2. **版本读取**：验证 SHA 文件读取与解析
3. **完整同步流程**：验证从 API 调用到本地存储的全流程
4. **增量同步优化**：验证 SHA 匹配时跳过下载的优化逻辑

---

## 功能点目的

### 1. 路径管理测试
- **测试函数**：`curated_plugins_repo_path_uses_codex_home_tmp_dir`
- **目的**：验证 `curated_plugins_repo_path()` 函数正确将 codex_home 与 `.tmp/plugins` 拼接

### 2. SHA 文件读取测试
- **测试函数**：`read_curated_plugins_sha_reads_trimmed_sha_file`
- **目的**：验证 SHA 文件读取时会去除首尾空白字符（包括换行符）

### 3. 完整同步流程测试
- **测试函数**：`sync_openai_plugins_repo_downloads_zipball_and_records_sha`
- **目的**：验证完整的同步流程
  - 模拟 GitHub API 的三个端点响应
  - 构造包含 marketplace.json 和插件的 ZIP 包
  - 验证同步后文件正确写入
  - 验证 SHA 文件被正确记录

### 4. 增量同步测试
- **测试函数**：`sync_openai_plugins_repo_skips_archive_download_when_sha_matches`
- **目的**：验证当本地 SHA 与远程一致时，跳过 ZIP 下载
  - 预先创建本地插件目录和 SHA 文件
  - 仅模拟两个 API 端点（不模拟 ZIP 下载）
  - 验证同步成功且未触发 ZIP 下载

---

## 具体技术实现

### 测试架构

```
测试用例
├── 创建临时目录 (tempfile::tempdir)
├── 启动 MockServer (wiremock)
├── 配置 Mock 响应
│   ├── GET /repos/openai/plugins → 仓库信息
│   ├── GET /repos/openai/plugins/git/ref/heads/main → SHA
│   └── GET /repos/openai/plugins/zipball/{sha} → ZIP 包（可选）
├── 执行被测函数
├── 验证结果
└── 清理（自动）
```

### 关键辅助函数

```rust
/// 构造测试用的 ZIP 包字节流
fn curated_repo_zipball_bytes(sha: &str) -> Vec<u8> {
    let cursor = Cursor::new(Vec::new());
    let mut writer = ZipWriter::new(cursor);
    let options = SimpleFileOptions::default();
    let root = format!("openai-plugins-{sha}");
    
    // 写入 marketplace.json
    writer.start_file(format!("{root}/.agents/plugins/marketplace.json"), options)?;
    writer.write_all(br#"{ "name": "openai-curated", "plugins": [...] }"#)?;
    
    // 写入插件 manifest
    writer.start_file(format!("{root}/plugins/gmail/.codex-plugin/plugin.json"), options)?;
    writer.write_all(br#"{"name":"gmail"}"#)?;
    
    writer.finish()?.into_inner()
}
```

### Mock 配置详解

```rust
// 1. 模拟仓库信息端点
Mock::given(method("GET"))
    .and(path("/repos/openai/plugins"))
    .respond_with(ResponseTemplate::new(200)
        .set_body_string(r#"{"default_branch":"main"}"#))
    .mount(&server)
    .await;

// 2. 模拟 Git Ref 端点
Mock::given(method("GET"))
    .and(path("/repos/openai/plugins/git/ref/heads/main"))
    .respond_with(ResponseTemplate::new(200)
        .set_body_string(format!(r#"{{"object":{{"sha":"{sha}"}}}}"#)))
    .mount(&server)
    .await;

// 3. 模拟 ZIP 下载端点（仅完整流程测试需要）
Mock::given(method("GET"))
    .and(path(format!("/repos/openai/plugins/zipball/{sha}")))
    .respond_with(ResponseTemplate::new(200)
        .insert_header("content-type", "application/zip")
        .set_body_bytes(curated_repo_zipball_bytes(sha)))
    .mount(&server)
    .await;
```

### 异步与同步的桥接

由于 `sync_openai_plugins_repo_with_api_base_url` 是同步函数（内部创建 tokio runtime），测试中使用 `tokio::task::spawn_blocking` 在阻塞线程中执行：

```rust
let server_uri = server.uri();
let tmp_path = tmp.path().to_path_buf();
tokio::task::spawn_blocking(move || {
    sync_openai_plugins_repo_with_api_base_url(tmp_path.as_path(), &server_uri)
})
.await  // 等待阻塞任务完成
.expect("sync task should join")
.expect("sync should succeed");
```

---

## 关键代码路径与文件引用

### 被测函数

| 被测函数 | 所在文件 | 测试函数 |
|---------|---------|---------|
| `curated_plugins_repo_path()` | `curated_repo.rs` | `curated_plugins_repo_path_uses_codex_home_tmp_dir` |
| `read_curated_plugins_sha()` | `curated_repo.rs` | `read_curated_plugins_sha_reads_trimmed_sha_file` |
| `sync_openai_plugins_repo_with_api_base_url()` | `curated_repo.rs` | `sync_openai_plugins_repo_downloads_zipball_and_records_sha` |
| `sync_openai_plugins_repo_with_api_base_url()` | `curated_repo.rs` | `sync_openai_plugins_repo_skips_archive_download_when_sha_matches` |

### 依赖库

| 库 | 用途 |
|----|------|
| `wiremock` | HTTP 服务模拟 |
| `tempfile` | 临时目录管理 |
| `zip` | ZIP 包构造 |
| `pretty_assertions` | 美观的断言输出 |

### 测试数据

| 数据 | 说明 |
|------|------|
| `sha = "0123456789abcdef0123456789abcdef01234567"` | 40位十六进制 SHA |
| `marketplace.json` | 包含 name 和 plugins 数组 |
| `plugin.json` | 插件 manifest，包含 name 字段 |

---

## 依赖与外部交互

### 测试隔离性

测试完全隔离，无外部依赖：
- 使用 `tempfile::tempdir()` 创建独立临时目录
- 使用 `wiremock::MockServer` 模拟所有 HTTP 请求
- 测试结束后临时目录自动清理

### 模块结构

```rust
// curated_repo.rs 中的测试模块声明
#[cfg(test)]
#[path = "curated_repo_tests.rs"]
mod tests;
```

### 导入关系

```rust
use super::*;  // 导入 curated_repo.rs 的所有公有项
use pretty_assertions::assert_eq;
use std::io::Write;
use tempfile::tempdir;
use wiremock::{Mock, MockServer, ResponseTemplate};
use wiremock::matchers::{method, path};
use zip::{ZipWriter, write::SimpleFileOptions};
```

---

## 风险、边界与改进建议

### 当前测试覆盖

| 场景 | 覆盖状态 |
|------|---------|
| 正常同步流程 | ✅ 已覆盖 |
| SHA 匹配跳过下载 | ✅ 已覆盖 |
| 路径拼接 | ✅ 已覆盖 |
| SHA 文件读取 | ✅ 已覆盖 |
| 网络超时 | ❌ 未覆盖 |
| API 错误响应 | ❌ 未覆盖 |
| ZIP 解压失败 | ❌ 未覆盖 |
| 磁盘满 | ❌ 未覆盖 |
| 并发同步 | ❌ 未覆盖 |

### 边界条件

| 边界 | 当前测试 |
|------|---------|
| SHA 文件带换行符 | ✅ `write "abc123\n"` |
| ZIP 包含多层目录 | ✅ `openai-plugins-{sha}/.agents/plugins/...` |
| 空插件列表 | ✅ `{"plugins":[]}` |

### 改进建议

1. **错误场景覆盖**
   ```rust
   // 建议添加：API 返回 404
   #[tokio::test]
   async fn sync_fails_gracefully_on_api_404() { ... }
   
   // 建议添加：ZIP 包损坏
   #[tokio::test]
   async fn sync_fails_on_corrupted_zip() { ... }
   ```

2. **并发测试**
   ```rust
   // 建议添加：并发同步请求
   #[tokio::test]
   async fn concurrent_sync_is_serialized() { ... }
   ```

3. **性能测试**
   ```rust
   // 建议添加：大 ZIP 包处理
   #[tokio::test]
   async fn handles_large_zip_efficiently() { ... }
   ```

4. **测试辅助函数增强**
   - 当前 `curated_repo_zipball_bytes` 硬编码插件结构
   - 建议参数化：支持自定义插件列表、文件内容

### 代码质量建议

1. **常量提取**：测试中的字符串常量（如 `"openai-curated"`）可提取为常量
2. **辅助宏**：构造 marketplace.json 的代码可提取为宏或 builder
3. **快照测试**：考虑使用 `insta` 进行 JSON 响应的快照测试
