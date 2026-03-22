# notify_capture.rs 研究文档

## 场景与职责

`notify_capture.rs` 是 `codex-app-server` crate 中的一个辅助二进制程序，专门用于**集成测试环境中捕获和持久化通知 payload**。该程序被注册为 `codex-app-server-test-notify-capture`，是 app-server v2 初始化与 turn 测试流程中的关键验证工具。

主要使用场景：
- **测试验证**：在 `turn_start_notify_payload_includes_initialize_client_name` 等测试中，验证 `initialize.clientInfo.name` 是否能正确贯通到 turn 完成的通知 payload 中
- **通知捕获**：作为 `notify` hook 的执行目标，接收 JSON payload 并原子性地写入指定文件
- **CI/自动化测试**：支持无人值守的自动化测试流程，通过文件系统轮询验证通知内容

## 功能点目的

### 1. 命令行参数解析
接收两个必需参数：
- `output_path`: 目标文件路径，用于存储捕获的通知 payload
- `payload`: JSON 格式的通知内容（作为最后一个参数接收）

参数校验严格：
- 拒绝多余参数（第 23-25 行）
- 使用 `anyhow` 提供清晰的错误上下文

### 2. 原子性文件写入
采用 **write-to-temp-then-rename** 模式确保数据完整性：
1. 创建临时文件 `{output_path}.tmp`
2. 写入 payload 内容
3. 调用 `sync_all()` 强制刷盘
4. 原子性 `rename` 到目标路径

此设计避免测试进程读取到半写入状态的数据。

### 3. 容错处理
- 使用 `to_string_lossy()` 处理可能的非 UTF-8 输入，提高鲁棒性
- 每个 IO 操作都附带 `with_context` 错误信息

## 具体技术实现

### 关键流程

```
main()
  ├── 解析命令行参数 (args_os)
  │     ├── 验证参数数量（严格2个）
  │     └── 提取 output_path 和 payload
  ├── 构建临时文件路径: "{output_path}.tmp"
  ├── 原子写入流程
  │     ├── File::create(&temp_path)
  │     ├── write_all(payload)
  │     ├── sync_all()          // 强制刷盘
  │     └── fs::rename(temp → target)
  └── 返回 Ok(())
```

### 数据结构

**输入**: 命令行参数（OsString 类型）
- `output_path`: 目标文件路径
- `payload`: JSON 字符串（最后一个参数）

**中间状态**: 
- `temp_path`: `PathBuf` 类型，格式为 `{output_path}.tmp`

**输出**: 持久化到文件系统的 JSON 文件

### 协议与命令

该程序遵循 **legacy notify hook 协议**：
- 通过 `argv` 接收命令行调用
- 最后一个参数为 JSON payload
- 标准输入/输出被忽略（fire-and-forget 模式）

调用示例（由 hooks 层触发）：
```bash
codex-app-server-test-notify-capture /path/to/notify.json '{"type":"agent-turn-complete",...}'
```

## 关键代码路径与文件引用

### 本文件
- `codex-rs/app-server/src/bin/notify_capture.rs:1-44`

### 配置声明
- `codex-rs/app-server/Cargo.toml:11-13`
  ```toml
  [[bin]]
  name = "codex-app-server-test-notify-capture"
  path = "src/bin/notify_capture.rs"
  ```

### 测试调用方
- `codex-rs/app-server/tests/suite/v2/initialize.rs:199-221`
  - 测试用例：`turn_start_notify_payload_includes_initialize_client_name`
  - 使用 `cargo_bin("codex-app-server-test-notify-capture")` 获取二进制路径
  - 配置 `notify = [<capture_bin>, <notify_file>]`

### 上游 Hook 链路
1. **配置解析**: `codex-rs/core/src/config.rs` - 解析 `notify` 配置项
2. **Hook 注册**: `codex-rs/hooks/src/registry.rs:40-46` - 创建 notify_hook
3. **Payload 构造**: `codex-rs/hooks/src/legacy_notify.rs:28-44` - 生成 JSON payload
4. **命令执行**: `codex-rs/hooks/src/legacy_notify.rs:46-73` - 调用本程序

### 相关数据结构
- `UserNotification::AgentTurnComplete` (`legacy_notify.rs:15-26`)
  - `thread_id`, `turn_id`, `cwd`, `client`, `input_messages`, `last_assistant_message`

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `std::env` | 命令行参数获取 |
| `std::fs::{File, rename}` | 文件操作 |
| `std::io::Write` | 文件写入 trait |
| `std::path::PathBuf` | 路径处理 |
| `anyhow` | 错误处理与上下文 |

### 外部交互
- **文件系统**: 写入临时文件后原子重命名
- **调用方**: 由 `tokio::process::Command` 通过 hooks 层触发
- **测试框架**: 测试通过 `fs_wait::wait_for_path_exists` 轮询文件存在性

### 环境变量
本程序本身不直接消费环境变量，运行上下文由调用方（app-server/hooks）提供。

## 风险、边界与改进建议

### 风险

1. **双实现漂移风险（中）**
   - 与 `test_notify_capture.rs` 存在语义不一致：
     - UTF-8 处理：`to_string_lossy()` vs `into_string()`
     - 参数校验：严格拒绝多余参数 vs 宽松处理
     - 落盘策略：显式 `sync_all()` vs 依赖系统缓冲
     - 临时文件命名：`.tmp` vs `.json.tmp`
   - 维护时容易误用或误判

2. **隐式构建目标风险（低）**
   - 虽在 `Cargo.toml` 显式声明，但属于测试专用二进制
   - 生产环境不应依赖此工具

3. **测试链路可观测性边界（低）**
   - hooks 为 fire-and-forget 模式
   - 若通知进程启动失败仅体现为 `HookResult::FailedContinue`
   - 测试层需依赖轮询文件存在来观测，延迟较大

### 边界条件

| 场景 | 行为 |
|------|------|
| 参数不足 | 返回 `anyhow!("expected output path as first argument")` |
| 参数过多 | 返回 `bail!("expected payload as final argument")` |
| 临时文件已存在 | 覆盖（`File::create` 行为） |
| 目标目录不存在 | 返回 IO 错误（`with_context` 包装） |
| 非 UTF-8 payload | 使用 `to_string_lossy()` 转换，可能丢失信息 |
| 磁盘满/权限不足 | 返回 IO 错误 |

### 改进建议

1. **收敛重复实现**
   - 建议保留 `notify_capture.rs` 作为唯一实现
   - 删除或合并 `test_notify_capture.rs`，或明确标注其废弃状态

2. **增强测试覆盖**
   - 为 capture bin 增加独立单元测试：
     - 参数数量边界
     - 非法 UTF-8 处理
     - 原子写行为验证
   - 当前仅被上层间接覆盖，风险前移不足

3. **文档化测试契约**
   - 在 `app-server/tests` 或 README 中增加说明：
     - 该 bin 是测试专用
     - 不应被外部集成依赖
     - 使用方式与协议规范

4. **考虑添加版本/标识**
   - 添加 `--version` 或 `--help` 支持，便于调试
   - 在输出文件中添加元数据（如捕获时间戳）

5. **错误输出改进**
   - 当前错误仅通过返回码体现
   - 可考虑向 stderr 输出结构化错误信息，便于测试诊断
