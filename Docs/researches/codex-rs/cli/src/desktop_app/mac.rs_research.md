# mac.rs 研究文档

## 场景与职责

`mac.rs` 是 Codex CLI 中负责 macOS 桌面应用（Codex Desktop）自动安装和启动的模块。它实现了 `codex app` 子命令的核心逻辑，主要解决以下场景：

1. **首次使用场景**：用户首次运行 `codex app` 命令时，系统未安装 Codex Desktop，需要自动下载并安装
2. **日常使用场景**：用户已安装 Codex Desktop，直接打开应用并加载指定工作区
3. **跨版本兼容**：支持检测不同位置的 Codex.app 安装（系统级 `/Applications` 和用户级 `~/Applications`）

该模块仅针对 macOS 平台（通过 `#[cfg(target_os = "macos")]` 条件编译），是 Codex CLI 与桌面应用生态集成的关键桥梁。

## 功能点目的

### 1. 应用发现与启动 (`run_mac_app_open_or_install`)
- **目的**：智能判断应用状态，优先使用现有安装，否则执行下载安装流程
- **决策逻辑**：
  ```
  检查现有安装 → 存在 → 直接打开工作区
       ↓
  不存在 → 下载 DMG → 挂载 → 复制 → 卸载 → 启动
  ```

### 2. 多路径应用查找 (`find_existing_codex_app_path` / `candidate_codex_app_paths`)
- **目的**：支持灵活的安装位置检测
- **搜索顺序**：
  1. `/Applications/Codex.app`（系统级安装）
  2. `$HOME/Applications/Codex.app`（用户级安装）

### 3. DMG 下载与安装 (`download_and_install_codex_to_user_applications`)
- **目的**：自动化 Codex Desktop 的获取和安装
- **关键步骤**：
  1. 创建临时目录（`tempfile::Builder`）
  2. 使用 `curl` 下载 DMG（支持重试机制）
  3. 使用 `hdiutil attach` 挂载镜像
  4. 查找 `.app`  bundle
  5. 使用 `ditto` 复制到 Applications 目录
  6. 使用 `hdiutil detach` 卸载镜像

### 4. 工作区启动 (`open_codex_app`)
- **目的**：通过 macOS `open` 命令启动应用并加载指定工作区
- **命令格式**：`open -a <app_path> <workspace>`

## 具体技术实现

### 关键流程

#### 主流程：`run_mac_app_open_or_install`
```rust
pub async fn run_mac_app_open_or_install(
    workspace: PathBuf,
    download_url: String,
) -> anyhow::Result<()>
```

流程图：
```
┌─────────────────────────────────────┐
│  run_mac_app_open_or_install        │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│ find_existing_codex_app_path()      │
│  - 检查 /Applications/Codex.app     │
│  - 检查 ~/Applications/Codex.app    │
└─────────────┬───────────────────────┘
              │
       ┌──────┴──────┐
       ▼             ▼
   找到应用      未找到应用
       │             │
       ▼             ▼
┌─────────────┐  ┌─────────────────────────────┐
│ open_codex  │  │ download_and_install_*      │
│ _app()      │  │  - download_dmg()           │
│             │  │  - mount_dmg()              │
└─────────────┘  │  - find_codex_app_in_mount()│
                 │  - install_codex_app_bundle()│
                 │  - detach_dmg()             │
                 └─────────────┬───────────────┘
                               │
                               ▼
                         ┌─────────────┐
                         │ open_codex  │
                         │ _app()      │
                         └─────────────┘
```

#### DMG 安装流程
```rust
async fn download_and_install_codex_to_user_applications(
    dmg_url: &str
) -> anyhow::Result<PathBuf>
```

1. **临时目录创建**：
   ```rust
   let temp_dir = Builder::new()
       .prefix("codex-app-installer-")
       .tempdir()
       .context("failed to create temp dir")?;
   ```
   - 使用 `tempfile` crate 创建自动清理的临时目录
   - 前缀便于调试识别

2. **下载阶段** (`download_dmg`)：
   ```rust
   Command::new("curl")
       .arg("-fL")           // 跟随重定向，失败时返回非零
       .arg("--retry").arg("3")
       .arg("--retry-delay").arg("1")
       .arg("-o").arg(dest)
       .arg(url)
   ```
   - 使用系统 `curl` 命令
   - 内置重试机制（3次，间隔1秒）

3. **挂载阶段** (`mount_dmg`)：
   ```rust
   Command::new("hdiutil")
       .arg("attach")
       .arg("-nobrowse")     // 不在 Finder 中显示
       .arg("-readonly")     // 只读挂载
       .arg(dmg_path)
   ```
   - 解析 `hdiutil attach` 输出获取挂载点
   - 支持制表符分隔和空格分隔的格式

4. **应用定位** (`find_codex_app_in_mount`)：
   - 优先检查直接子目录 `Codex.app`
   - 遍历挂载点查找任意 `.app` 目录

5. **安装阶段** (`install_codex_app_bundle`)：
   - 尝试两个目标目录：`/Applications` 和 `~/Applications`
   - 使用 `ditto` 命令复制（保留资源分支和权限）
   - 幂等性检查：如果目标已存在则直接返回

6. **卸载阶段** (`detach_dmg`)：
   ```rust
   Command::new("hdiutil")
       .arg("detach")
       .arg(mount_point)
   ```
   - 失败时仅打印警告，不阻断主流程

### 数据结构

#### 路径类型
- `PathBuf`：标准 Rust 路径类型
- 候选路径通过 `Vec<PathBuf>` 管理优先级

#### 命令输出解析
```rust
fn parse_hdiutil_attach_mount_point(output: &str) -> Option<String>
```
- 输入：`hdiutil attach` 的标准输出
- 输出：挂载点路径（如 `/Volumes/Codex`）
- 解析策略：
  1. 查找包含 `/Volumes/` 的行
  2. 优先使用最后一个制表符后的字段
  3. 回退到查找以 `/Volumes/` 开头的任意字段

### 外部命令协议

| 命令 | 用途 | 关键参数 |
|------|------|----------|
| `open` | 启动应用 | `-a <app>` 指定应用，`<path>` 指定工作区 |
| `curl` | 下载 DMG | `-fL` 失败处理+重定向，`--retry 3` 重试 |
| `hdiutil attach` | 挂载镜像 | `-nobrowse` 隐藏，`-readonly` 只读 |
| `hdiutil detach` | 卸载镜像 | `<mount_point>` 挂载点路径 |
| `ditto` | 复制应用 | 保留 macOS 扩展属性和资源分支 |

## 关键代码路径与文件引用

### 当前文件结构
```
codex-rs/cli/src/desktop_app/
├── mod.rs          # 模块入口，平台分发
└── mac.rs          # macOS 实现（本文件）
```

### 调用链
```
main.rs (Subcommand::App)
    └── app_cmd.rs (run_app)
            └── desktop_app/mod.rs (run_app_open_or_install)
                    └── desktop_app/mac.rs (run_mac_app_open_or_install)
```

### 关键函数引用

| 函数 | 行号 | 职责 |
|------|------|------|
| `run_mac_app_open_or_install` | 7-29 | 主入口，协调发现/安装/启动 |
| `find_existing_codex_app_path` | 31-35 | 查找现有安装 |
| `candidate_codex_app_paths` | 37-43 | 生成候选路径列表 |
| `open_codex_app` | 45-67 | 使用 `open` 命令启动应用 |
| `download_and_install_*` | 69-102 | 完整安装流程协调 |
| `install_codex_app_bundle` | 104-134 | 复制应用到 Applications |
| `download_dmg` | 142-161 | curl 下载 |
| `mount_dmg` | 163-185 | hdiutil 挂载 |
| `detach_dmg` | 187-199 | hdiutil 卸载 |
| `find_codex_app_in_mount` | 201-224 | 在挂载点定位 .app |
| `copy_app_bundle` | 226-238 | ditto 复制 |
| `parse_hdiutil_attach_mount_point` | 245-257 | 解析挂载输出 |

### 测试覆盖
```rust
#[cfg(test)]
mod tests {
    use super::parse_hdiutil_attach_mount_point;
    
    #[test]
    fn parses_mount_point_from_tab_separated_hdiutil_output()
    #[test]
    fn parses_mount_point_with_spaces()
}
```
- 测试 `hdiutil` 输出解析的鲁棒性
- 覆盖制表符分隔和带空格的卷名场景

## 依赖与外部交互

### Rust 依赖

| Crate | 用途 |
|-------|------|
| `anyhow` | 错误处理和上下文 |
| `std::path` | 路径操作 |
| `tempfile::Builder` | 临时目录管理 |
| `tokio::process::Command` | 异步进程执行 |

### 系统依赖

| 工具 | macOS 内置 | 用途 |
|------|-----------|------|
| `open` | 是 | 启动应用程序 |
| `curl` | 是 | HTTP 下载 |
| `hdiutil` | 是 | DMG 镜像管理 |
| `ditto` | 是 | 文件复制（保留元数据）|

### 外部资源

- **下载源**：`https://persistent.oaistatic.com/codex-app-prod/Codex.dmg`
  - 定义于 `app_cmd.rs` 的 `DEFAULT_CODEX_DMG_URL`
  - 可通过 `--download-url` 参数覆盖

## 风险、边界与改进建议

### 当前风险

1. **网络依赖**：
   - 首次使用必须联网下载
   - 无离线安装包支持
   - 下载 URL 硬编码，若域名变更需更新代码

2. **权限问题**：
   - `/Applications` 需要管理员权限，失败时无 `sudo` 回退
   - 仅尝试用户目录 `~/Applications` 作为降级方案

3. **磁盘空间**：
   - 临时目录在系统临时分区，大 DMG 可能耗尽空间
   - 无下载前磁盘空间检查

4. **并发安全**：
   - 无锁机制防止并行安装冲突
   - 多个 `codex app` 实例同时运行可能导致文件竞争

5. **错误恢复**：
   - DMG 卸载失败仅打印警告，可能留下僵尸挂载
   - 下载失败重试固定为 3 次，无法配置

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 应用正在运行 | 直接调用 `open`，macOS 处理 | 可能激活现有窗口而非打开新工作区 |
| 部分安装（复制中断） | 检查目录存在即认为成功 | 可能启动损坏的应用 |
| DMG 格式非标准 | 遍历查找任意 `.app` | 可能误选错误的 bundle |
| 挂载点解析失败 | 返回错误 | 依赖 `hdiutil` 输出格式稳定性 |
| HOME 环境变量未设置 | `user_applications_dir` 失败 | 无法安装到用户目录 |

### 改进建议

1. **完整性验证**：
   - 下载后校验 DMG 签名或哈希
   - 复制后验证 `.app`  bundle 签名

2. **用户体验**：
   - 添加进度条显示下载进度
   - 提供 `--dry-run` 模式预览操作
   - 支持指定安装路径（`--install-dir`）

3. **健壮性**：
   - 添加文件锁防止并发安装
   - 实现清理逻辑处理中断的安装
   - 增加磁盘空间预检查

4. **可配置性**：
   - 支持从配置文件读取镜像 URL
   - 允许配置重试次数和超时
   - 支持代理设置透传给 curl

5. **测试覆盖**：
   - 添加集成测试（mock 外部命令）
   - 测试各种 `hdiutil` 输出格式
   - 测试权限不足场景的错误处理

6. **安全加固**：
   - 验证下载 DMG 的代码签名
   - 限制临时目录权限（当前使用默认权限）
   - 考虑使用 `quarantine` 属性处理
