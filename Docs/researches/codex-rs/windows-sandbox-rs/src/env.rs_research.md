# env.rs 研究文档

## 场景与职责

`env.rs` 负责环境变量的准备和修改，为沙箱进程提供安全且功能完整的环境配置。该模块处理各种环境变量的规范化、继承和网络访问限制。

该模块在以下场景中使用：
- 沙箱启动前准备环境变量映射
- 网络隔离时注入代理配置阻止网络访问
- 确保分页器非交互式运行
- 处理 Windows 特定的路径和环境变量

## 功能点目的

### 1. NULL 设备规范化
- **`normalize_null_device_env`**: 将 Unix 风格的 `/dev/null` 转换为 Windows `NUL`
- 处理大小写变体和不同分隔符形式
- 避免沙箱进程因无效设备路径失败

### 2. 分页器配置
- **`ensure_non_interactive_pager`**: 确保分页器非交互式运行
- 设置 `GIT_PAGER=more.com`, `PAGER=more.com`, `LESS=""`
- 防止沙箱进程挂起等待用户输入

### 3. PATH 环境继承
- **`inherit_path_env`**: 继承父进程的 PATH 和 PATHEXT
- 确保可执行文件查找正常工作
- 仅在环境变量未设置时继承

### 4. 网络隔离配置
- **`apply_no_network_to_env`**: 应用网络隔离配置
- 设置代理指向无效地址（`127.0.0.1:9`）
- 配置各工具离线模式（pip, npm, cargo, git）
- 创建拒绝执行的虚拟工具脚本

### 5. 路径操作辅助
- **`prepend_path`**: 在 PATH 前添加目录
- **`reorder_pathext_for_stubs`**: 调整 PATHEXT 顺序优先批处理文件
- **`ensure_denybin`**: 创建拒绝执行的虚拟工具目录

## 具体技术实现

### NULL 设备规范化

```rust
pub fn normalize_null_device_env(env_map: &mut HashMap<String, String>) {
    let keys: Vec<String> = env_map.keys().cloned().collect();
    for k in keys {
        if let Some(v) = env_map.get(&k).cloned() {
            let t = v.trim().to_ascii_lowercase();
            // 处理 /dev/null 和 \\\\dev\\\\null 形式
            if t == "/dev/null" || t == "\\\\dev\\\\null" {
                env_map.insert(k, "NUL".to_string());
            }
        }
    }
}
```

### 分页器配置

```rust
pub fn ensure_non_interactive_pager(env_map: &mut HashMap<String, String>) {
    env_map.entry("GIT_PAGER".into()).or_insert_with(|| "more.com".into());
    env_map.entry("PAGER".into()).or_insert_with(|| "more.com".into());
    env_map.entry("LESS".into()).or_insert_with(|| "".into());
}
```

使用 `or_insert_with` 仅在未设置时添加，尊重用户显式配置。

### 网络隔离配置

```rust
pub fn apply_no_network_to_env(env_map: &mut HashMap<String, String>) -> Result<()> {
    // 标记网络隔离激活
    env_map.insert("SBX_NONET_ACTIVE".into(), "1".into());
    
    // 设置无效代理
    env_map.entry("HTTP_PROXY".into()).or_insert_with(|| "http://127.0.0.1:9".into());
    env_map.entry("HTTPS_PROXY".into()).or_insert_with(|| "http://127.0.0.1:9".into());
    env_map.entry("ALL_PROXY".into()).or_insert_with(|| "http://127.0.0.1:9".into());
    env_map.entry("NO_PROXY".into()).or_insert_with(|| "localhost,127.0.0.1,::1".into());
    
    // 工具特定离线配置
    env_map.entry("PIP_NO_INDEX".into()).or_insert_with(|| "1".into());
    env_map.entry("PIP_DISABLE_PIP_VERSION_CHECK".into()).or_insert_with(|| "1".into());
    env_map.entry("NPM_CONFIG_OFFLINE".into()).or_insert_with(|| "true".into());
    env_map.entry("CARGO_NET_OFFLINE".into()).or_insert_with(|| "true".into());
    
    // Git 代理和协议限制
    env_map.entry("GIT_HTTP_PROXY".into()).or_insert_with(|| "http://127.0.0.1:9".into());
    env_map.entry("GIT_HTTPS_PROXY".into()).or_insert_with(|| "http://127.0.0.1:9".into());
    env_map.entry("GIT_SSH_COMMAND".into()).or_insert_with(|| "cmd /c exit 1".into());
    env_map.entry("GIT_ALLOW_PROTOCOLS".into()).or_insert_with(|| "".into());
    
    // 创建拒绝执行的虚拟工具
    let base = ensure_denybin(&["ssh", "scp"], None)?;
    // ... 清理 curl/wget 虚拟工具 ...
    prepend_path(env_map, &base.to_string_lossy());
    reorder_pathext_for_stubs(env_map);
    Ok(())
}
```

### 虚拟拒绝工具

```rust
fn ensure_denybin(tools: &[&str], denybin_dir: Option<&Path>) -> Result<PathBuf> {
    let base = match denybin_dir {
        Some(p) => p.to_path_buf(),
        None => home_dir().ok_or_else(|| anyhow!("no home dir"))?.join(".sbx-denybin"),
    };
    fs::create_dir_all(&base)?;
    for tool in tools {
        for ext in [".bat", ".cmd"] {
            let path = base.join(format!("{}{}", tool, ext));
            if !path.exists() {
                let mut f = File::create(&path)?;
                // 退出码 1 表示失败
                f.write_all(b"@echo off\r\nexit /b 1\r\n")?;
            }
        }
    }
    Ok(base)
}
```

### PATHEXT 重排序

```rust
fn reorder_pathext_for_stubs(env_map: &mut HashMap<String, String>) {
    // 将 .BAT 和 .CMD 移到前面，确保虚拟批处理文件优先于真实 .EXE
    let default = ".COM;.EXE;.BAT;.CMD";
    // ... 解析、重排、重组 ...
    // 顺序: .BAT, .CMD, 其他
}
```

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `lib.rs` (windows_impl) | `normalize_null_device_env`, `ensure_non_interactive_pager`, `apply_no_network_to_env` | 沙箱执行准备 |
| `elevated_impl.rs` | `normalize_null_device_env`, `ensure_non_interactive_pager`, `inherit_path_env` | 提升路径准备 |

### 代码引用路径

```
codex-rs/windows-sandbox-rs/src/env.rs
  ├─> 被 lib.rs 使用: apply_no_network_to_env, ensure_non_interactive_pager, inherit_path_env, normalize_null_device_env
  ├─> 被 elevated_impl.rs 使用
  └─> 外部依赖: dirs_next (home_dir)
```

## 依赖与外部交互

### 内部依赖
- 无内部模块依赖

### 外部依赖
- **dirs_next**: 获取用户主目录
- **std::collections::HashMap**: 环境变量映射
- **std::env**: 读取父进程环境变量

### 环境交互
- 读取父进程环境变量（`std::env::var`）
- 修改传入的 `HashMap<String, String>`
- 文件系统操作（创建 `.sbx-denybin` 目录和脚本）

### 生成的虚拟工具

位置：`%USERPROFILE%\.sbx-denybin\`

文件：
- `ssh.bat`, `ssh.cmd`
- `scp.bat`, `scp.cmd`

内容：
```batch
@echo off
exit /b 1
```

## 风险、边界与改进建议

### 安全风险

1. **代理绕过**
   - 环境变量代理可被显式覆盖
   - 某些应用可能忽略代理设置
   - 建议：结合 Windows 防火墙规则（如 `firewall.rs`）

2. **虚拟工具绕过**
   - 如果真实工具路径在 PATH 前面，虚拟工具不生效
   - `reorder_pathext_for_stubs` 缓解但不完全
   - 建议：使用绝对路径检查或文件系统 ACL

3. **环境变量注入**
   - `apply_no_network_to_env` 使用 `or_insert_with`，不覆盖用户设置
   - 如果用户显式设置 `HTTP_PROXY`，代理绕过可能失效

4. **主目录依赖**
   - `ensure_denybin` 依赖 `home_dir()`
   - 某些环境（如某些 CI）可能没有主目录

### 边界条件

| 边界 | 处理 |
|------|------|
| 无 home 目录 | `ensure_denybin` 返回错误 |
| 目录创建失败 | 传播错误 |
| PATH 未设置 | `inherit_path_env` 从 `std::env` 读取 |
| PATHEXT 未设置 | 使用默认值 `.COM;.EXE;.BAT;.CMD` |
| 环境变量已存在 | `or_insert_with` 不覆盖 |

### 改进建议

1. **强制网络隔离**
   ```rust
   // 当前: or_insert_with 不覆盖
   // 建议: 网络隔离策略下强制设置
   if force_network_block {
       env_map.insert("HTTP_PROXY".into(), "http://127.0.0.1:9".into());
   } else {
       env_map.entry("HTTP_PROXY".into()).or_insert_with(...);
   }
   ```

2. **虚拟工具增强**
   ```rust
   // 当前: 简单批处理脚本
   // 建议: 记录尝试调用，返回特定错误码
   let script = format!(
       "@echo off\r\necho {}: Network access denied >&2\r\nexit /b 127\r\n",
       tool_name
   );
   ```

3. **配置化工具列表**
   ```rust
   // 当前: 硬编码 ["ssh", "scp"]
   // 建议: 从策略配置读取
   const DEFAULT_DENY_TOOLS: &[&str] = &["ssh", "scp", "telnet", "ftp"];
   ```

4. **清理机制**
   - 当前虚拟工具永久存在
   - 建议：沙箱退出时清理，或使用临时目录

5. **跨平台支持**
   - 当前 Windows 特定（批处理脚本）
   - 建议：为非 Windows 提供 shell 脚本版本

6. **日志记录**
   - 当前无日志输出
   - 建议：记录环境变量修改和虚拟工具创建

### 测试分析

当前模块无单元测试。建议补充：

| 测试场景 | 说明 |
|----------|------|
| NULL 设备规范化 | 验证各种 `/dev/null` 形式转换 |
| 分页器配置 | 验证默认值和保留现有值 |
| PATH 继承 | 验证继承逻辑和前置添加 |
| PATHEXT 重排序 | 验证 .BAT/.CMD 前置 |
| 网络隔离 | 验证代理设置和工具创建 |
| 边界条件 | 无 home 目录、无 PATH 等 |

### 配置参考

| 环境变量 | 用途 | 值 |
|----------|------|-----|
| `SBX_NONET_ACTIVE` | 网络隔离标记 | `1` |
| `HTTP_PROXY` | HTTP 代理 | `http://127.0.0.1:9` |
| `HTTPS_PROXY` | HTTPS 代理 | `http://127.0.0.1:9` |
| `ALL_PROXY` | 全局代理 | `http://127.0.0.1:9` |
| `NO_PROXY` | 代理例外 | `localhost,127.0.0.1,::1` |
| `PIP_NO_INDEX` | pip 离线模式 | `1` |
| `NPM_CONFIG_OFFLINE` | npm 离线模式 | `true` |
| `CARGO_NET_OFFLINE` | cargo 离线模式 | `true` |
| `GIT_SSH_COMMAND` | Git SSH 禁用 | `cmd /c exit 1` |
