# test_notify_capture.rs 研究文档

## 场景与职责

`test_notify_capture.rs` 是 `codex-app-server` crate 中的另一个辅助二进制程序，位于 `src/bin/` 目录下。与 `notify_capture.rs` 类似，它也是为了**捕获和持久化通知 payload** 而设计的，但实现风格更为精简。

**当前状态**：
- 该程序**未被任何测试或脚本显式引用**
- 由于 Cargo 的自动发现机制（`src/bin/*.rs`），它仍会被构建为名为 `test_notify_capture` 的二进制目标
- 可能是历史遗留实现或备用方案

主要潜在用途：
- 备用通知捕获工具（历史版本兼容）
- 简化版测试辅助程序（无显式 `sync_all`）

## 功能点目的

### 1. 命令行参数解析
接收两个必需参数：
- `output_path`: 目标文件路径
- `payload`: JSON 格式的通知内容（必须为有效 UTF-8）

参数处理特点：
- 使用 `skip(1)` 跳过程序名
- 仅检查前两个参数存在性，**不拒绝多余参数**
- 严格要求 payload 为有效 UTF-8（使用 `into_string()`）

### 2. 简化文件写入
采用基本的 **write-then-rename** 模式：
1. 使用 `with_extension("json.tmp")` 创建临时文件路径
2. 使用 `std::fs::write` 一次性写入
3. `std::fs::rename` 到目标路径

**与 `notify_capture.rs` 的关键差异**：
- 无显式 `sync_all()` 调用
- 临时文件扩展名固定为 `.json.tmp`
- 使用 `std::fs::write` 而非 `File::create` + `write_all`

## 具体技术实现

### 关键流程

```
main()
  ├── 解析命令行参数 (args_os().skip(1))
  │     ├── 提取 output_path（必需）
  │     └── 提取 payload（必需，严格 UTF-8）
  ├── 构建临时文件路径: output_path.with_extension("json.tmp")
  ├── 写入流程
  │     ├── std::fs::write(&temp_path, payload)
  │     └── std::fs::rename(temp → target)
  └── 返回 Ok(())
```

### 数据结构

**输入**: 命令行参数（OsString 类型）
- `output_path`: 目标文件路径
- `payload`: JSON 字符串（必须为有效 UTF-8）

**中间状态**:
- `temp_path`: `PathBuf` 类型，通过 `with_extension("json.tmp")` 生成

**输出**: 持久化到文件系统的 JSON 文件

### 协议与命令

理论上遵循与 `notify_capture.rs` 相同的 **legacy notify hook 协议**，但由于未被实际调用，协议兼容性未经验证。

预期调用方式：
```bash
test_notify_capture /path/to/notify.json '{"type":"agent-turn-complete",...}'
```

## 关键代码路径与文件引用

### 本文件
- `codex-rs/app-server/src/bin/test_notify_capture.rs:1-23`

### 构建配置
- **Cargo.toml 中无显式声明**（依赖自动发现）
- 构建目标名：`test_notify_capture`（由 Cargo 从文件名推断）

### 与 `notify_capture.rs` 的对比

| 特性 | `notify_capture.rs` | `test_notify_capture.rs` |
|------|---------------------|--------------------------|
| Cargo.toml 声明 | 显式 `[[bin]]` | 自动发现 |
| 目标名称 | `codex-app-server-test-notify-capture` | `test_notify_capture` |
| 参数校验 | 严格（拒绝多余参数） | 宽松（仅检查前两个） |
| Payload 编码 | `to_string_lossy()`（容错） | `into_string()`（严格 UTF-8） |
| 临时文件命名 | `{path}.tmp` | `{path}.json.tmp` |
| 刷盘策略 | `sync_all()` 强制刷盘 | 依赖系统缓冲 |
| 代码行数 | 44 行 | 23 行 |
| 实际使用 | 是（被 initialize.rs 引用） | 否（无调用方） |

### 相关文件（潜在关联）
- `codex-rs/app-server/src/bin/notify_capture.rs` - 主实现
- `codex-rs/hooks/src/legacy_notify.rs` - Hook payload 构造
- `codex-rs/hooks/src/registry.rs` - Hook 注册

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `std::env` | 命令行参数获取 |
| `std::fs` | 文件操作（write, rename） |
| `std::path::PathBuf` | 路径处理 |
| `anyhow` | 错误处理 |

### 外部交互
- **文件系统**: 写入临时文件后重命名
- **潜在调用方**: 理论上可由 hooks 层触发，但当前无实际调用

### 环境变量
本程序本身不消费环境变量。

## 风险、边界与改进建议

### 风险

1. **代码漂移风险（高）**
   - 与 `notify_capture.rs` 存在功能重叠但实现差异
   - 长期维护容易产生不一致
   - 开发者可能误用或混淆两个版本

2. **隐式构建目标风险（中）**
   - 虽无调用方，但仍参与构建
   - 代码退化可能影响 CI 时长或引入编译失败
   - 占用构建资源但无实际价值

3. **数据完整性风险（中）**
   - 无 `sync_all()` 调用，依赖 OS 缓冲策略
   - 在系统崩溃/断电场景下可能丢失数据
   - 对于测试场景，可能导致 flaky test（测试读取时数据未完全落盘）

4. **UTF-8 严格性风险（低）**
   - 使用 `into_string()` 要求严格 UTF-8
   - 若 payload 包含非 UTF-8 字节，直接报错
   - 与主实现 `to_string_lossy()` 的容错策略不一致

### 边界条件

| 场景 | 行为 |
|------|------|
| 参数不足 | 返回 `anyhow!("missing output path argument")` 或 payload 错误 |
| 参数过多 | **忽略多余参数，正常执行** |
| payload 非 UTF-8 | 返回 `anyhow!("payload must be valid UTF-8")` |
| 临时文件已存在 | 覆盖（`std::fs::write` 行为） |
| 目标目录不存在 | 返回 IO 错误 |

### 改进建议

1. **明确废弃或删除**
   - 建议评估后删除此文件，避免维护负担
   - 若需保留历史兼容，应添加明确注释说明其状态

2. **若保留，需对齐主实现**
   - 添加 `sync_all()` 确保数据完整性
   - 统一参数校验策略（严格拒绝多余参数）
   - 统一临时文件命名约定

3. **显式声明或排除**
   - 若有意保留，应在 `Cargo.toml` 显式声明
   - 或设置 `autobins = false` 并仅保留需要的二进制

4. **添加文档注释**
   - 在文件头部添加注释说明：
     - 该文件的用途
     - 与 `notify_capture.rs` 的关系
     - 是否被使用/维护

5. **合并到主实现（可选）**
   - 若存在特定使用场景（如简化版需求）
   - 可考虑通过命令行标志（如 `--simple`）在单一实现中支持两种模式

### 决策建议

| 选项 | 评估 | 推荐度 |
|------|------|--------|
| 直接删除 | 无调用方，功能被完全覆盖 | ⭐⭐⭐⭐⭐ |
| 保留并标注废弃 | 最小改动，但增加技术债务 | ⭐⭐⭐ |
| 合并功能 | 若确有需求，但当前未见 | ⭐⭐ |
| 保持现状 | 风险累积，不推荐 | ⭐ |

**推荐行动**：删除 `test_notify_capture.rs`，并在 `notify_capture.rs` 中添加注释说明其为唯一通知捕获实现。
