# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old`
- 对象类型：`apply_patch` 场景 fixture 输入目录（DIR）
- 目录内文件：
  - `name.txt`：`old content`（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt:1`）
  - `other.txt`：`unrelated file`（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/other.txt:1`）

## 场景与职责

该目录是场景 `004_move_to_new_directory` 的初始状态快照，承担两类输入职责：

1. 提供“被更新并迁移”的源文件：`old/name.txt`。
2. 提供“同级不应受影响”的旁路文件：`old/other.txt`。

与它配套的补丁定义在 `patch.txt`，执行语义是：

- `*** Update File: old/name.txt`
- `*** Move to: renamed/dir/name.txt`
- 将 `old content` 改为 `new content`

（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt:1-7`）

因此，本目录本质上是 `apply_patch` 端到端场景中的“迁移前输入基线”，用于证明引擎既能移动并改写目标文件，又不会误动同目录无关文件。

## 功能点目的

该目录对应并支撑以下功能点验证：

1. `Update File` 与 `Move to` 的组合语义：更新内容与路径迁移在同一 hunk 内生效。
2. 自动创建新目标目录：目标 `renamed/dir/` 在输入中不存在，执行阶段必须补齐父目录。
3. 非目标文件隔离：`old/other.txt` 在迁移后仍保留且内容不变。
4. 以“最终文件树”而非“命令返回码”作为主断言，保证跨实现可移植性（场景规范强调 input/patch/expected 三段式）。

场景规范来源：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 执行流程（从本目录到断言）

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*` 并运行每个目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`）。
2. `run_apply_patch_scenario()` 把场景 `input/` 递归复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37,107-125`）。
3. 读取 `patch.txt` 后调用 `apply_patch` 二进制执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. 对临时目录与 `expected/` 进行目录快照比较，快照结构为 `BTreeMap<PathBuf, Entry>`（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-58,65-105`）。

### 2) 解析协议与数据结构

`apply_patch` parser 在 `Update File` hunk 中允许可选 `Move to`：

- 语法层：`update_hunk ... change_move?`（`codex-rs/apply-patch/src/parser.rs:13,17`）。
- 常量：`MOVE_TO_MARKER = "*** Move to: "`（`codex-rs/apply-patch/src/parser.rs:36`）。
- 结构体：`Hunk::UpdateFile { path, move_path: Option<PathBuf>, chunks }`（`codex-rs/apply-patch/src/parser.rs:68-75`）。
- 解析实现：读取 `Move to` 后写入 `move_path`（`codex-rs/apply-patch/src/parser.rs:279-333`）。

该场景 patch 与协议定义完全对应：

```text
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content
*** End Patch
```

（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt:1-7`）

### 3) 文件系统应用逻辑

`lib.rs::apply_hunks_to_files()` 的 `UpdateFile + move_path` 分支执行顺序为：

1. 基于 chunks 计算 `new_contents`（`derive_new_contents_from_chunks`）
2. `create_dir_all(dest.parent())` 创建目标父目录
3. `write(dest, new_contents)` 写入目标文件
4. `remove_file(path)` 删除源文件
5. 在 summary 中记为 `M <dest>`

关键实现：`codex-rs/apply-patch/src/lib.rs:306-331`。

这与本目录语义直接绑定：源 `old/name.txt` 从输入态消费，目标落到 `expected/renamed/dir/name.txt`，而 `old/other.txt` 应保持存在。

### 4) 命令与入口协议

- 独立二进制入口：`apply_patch`（`codex-rs/apply-patch/Cargo.toml:11-13`、`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
- 支持参数或 stdin patch 文本（`codex-rs/apply-patch/src/standalone_executable.rs:16-41`）。
- 文档协议强调 `Update File` 后可跟 `Move to`，且路径必须相对路径（`codex-rs/apply-patch/apply_patch_tool_instructions.md:16-19,47-49,69`）。

## 关键代码路径与文件引用

### 直接场景文件（本目录及同级）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/other.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt:1-7`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt:1`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old/other.txt:1`

### 调用方（测试执行与断言）

1. 场景遍历：`codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`
2. 输入复制与命令执行：`codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`
3. 快照比对：`codex-rs/apply-patch/tests/suite/scenarios.rs:50-58,71-105`
4. 并行 CLI 覆盖：
   - `test_apply_patch_cli_moves_file_to_new_directory`（`codex-rs/apply-patch/tests/suite/tool.rs:65-82`）
   - 目的地覆盖场景（`codex-rs/apply-patch/tests/suite/tool.rs:155-175`）

### 被调用方（解析与执行）

1. 语法与 hunk 结构：`codex-rs/apply-patch/src/parser.rs:13-21,58-75`
2. `Move to` 解析：`codex-rs/apply-patch/src/parser.rs:284-329`
3. 文件系统应用：`codex-rs/apply-patch/src/lib.rs:279-339`
4. CLI 入口：`codex-rs/apply-patch/src/standalone_executable.rs:11-58`

### 上下文依赖（跨 crate）

1. tool handler 侧验证 patch 并组装 runtime 请求：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-238`
2. runtime 侧通过 `codex --codex-run-as-apply-patch <patch>` 执行：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102,200-215`
3. arg0 分发入口处理 `--codex-run-as-apply-patch`：`codex-rs/arg0/src/lib.rs:89-107`
4. `maybe_parse_apply_patch_verified` 将 `move_path` 解析为绝对路径并产出 `ApplyPatchAction`：`codex-rs/apply-patch/src/invocation.rs:132-217`

## 依赖与外部交互

### 代码依赖

- crate 元数据：`codex-apply-patch` 提供库 + `apply_patch` bin（`codex-rs/apply-patch/Cargo.toml:1-13`）。
- 关键库：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
- Bazel 打包 `apply_patch_tool_instructions.md` 作为 `compile_data`（`codex-rs/apply-patch/BUILD.bazel:3-10`）。

### 外部交互

1. 文件系统交互：`copy/create_dir_all/write/remove_file/read`（`codex-rs/apply-patch/tests/suite/scenarios.rs:107-125`、`codex-rs/apply-patch/src/lib.rs:289-329`）。
2. 进程交互：测试通过 `Command::new(cargo_bin("apply_patch"))` 运行二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. shell/AST 交互：上层可从 `bash -lc` heredoc 提取 patch 并验证（`codex-rs/apply-patch/src/invocation.rs:132-217,219-239`）。
4. 审批与沙箱交互：core 在执行前后处理审批键、权限、事件流（`codex-rs/core/src/tools/handlers/apply_patch.rs:176-237`、`codex-rs/core/src/tools/runtimes/apply_patch.rs:122-215`）。

## 风险、边界与改进建议

### 风险与边界

1. 移动写删顺序非原子：当前先写目标后删源，若删除失败可能出现双副本（`codex-rs/apply-patch/src/lib.rs:321-324`）。
2. 场景 runner 不断言退出码：仅断言最终文件树，错误文案/退出码回归需依赖 `suite/tool.rs`（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
3. `Move to` 允许覆盖已存在目标：行为由专门测试确认（`codex-rs/apply-patch/tests/suite/tool.rs:155-175`），调用方若期望“冲突即失败”需要额外策略层兜底。
4. 本目录仅覆盖单文件迁移：未覆盖权限不足、目录只读、跨设备特殊语义等环境性异常。

### 改进建议

1. 增加 fixture：`move_path` 写成功但源删除失败的失败注入场景，明确预期最终状态。
2. 为 `scenarios` 套件增加可选“退出码+stderr 断言”模式，与当前快照断言并行。
3. 在场景说明文档补充 `Move to` 的覆盖语义与非原子边界，减少跨语言移植时行为误解。
4. 可在 future 场景中加入 permissions/symlink 组合样例，补齐真实文件系统边界。
