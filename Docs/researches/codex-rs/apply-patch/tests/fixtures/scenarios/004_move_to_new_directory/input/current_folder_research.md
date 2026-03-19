# DIR 研究：codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input

## 场景与职责

目标目录 `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input` 是 `apply_patch` 场景测试的输入快照目录，职责是提供“重命名并改写文件”的初始文件系统状态。

该目录当前包含：

- `old/name.txt`：待更新并搬迁的源文件，初始内容为 `old content`（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt:1`）。
- `old/other.txt`：同目录下不应被误改动的旁路文件，内容为 `unrelated file`（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/other.txt:1`）。

与之配套的补丁声明：

- `*** Update File: old/name.txt`
- `*** Move to: renamed/dir/name.txt`
- 把 `old content` 改为 `new content`
（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt:1-7`）

预期最终状态是：

- `renamed/dir/name.txt` 内容为 `new content`（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt:1`）
- `old/other.txt` 仍存在且内容不变（`codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old/other.txt:1`）

## 功能点目的

该输入目录对应的功能点是验证 `Update + Move to` 组合行为，具体覆盖三件事：

1. 能在更新文本内容的同时完成路径迁移（rename 到新目录）。
2. 目标目录不存在时可自动创建父目录。
3. 同级无关文件不会被误删或误改。

该能力在单元/集成层均有对齐：

- fixture 场景总线测试会遍历所有场景目录并比较最终文件树快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:10-23,50-60`）。
- CLI 行为测试中有直接对应的 `test_apply_patch_cli_moves_file_to_new_directory`（`codex-rs/apply-patch/tests/suite/tool.rs:64-82`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（从 fixture 到断言）

1. `tests/suite/scenarios.rs` 找到 `tests/fixtures/scenarios/*` 下所有目录并逐个执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-23`）。
2. 进入单场景后，将 `input/` 递归复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37,107-125`）。
3. 读取 `patch.txt` 作为 apply_patch 参数（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-40`）。
4. 在临时目录 `current_dir` 下执行 `apply_patch <patch>`（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
5. 对临时目录与 `expected/` 做目录快照（路径+文件字节）并 `assert_eq!`（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60,71-105`）。

### 2) 解析协议（Patch 语法）

`apply_patch` 协议支持 `Update File` 后跟可选 `Move to`，由解析器写入 `Hunk::UpdateFile { move_path: Option<PathBuf>, chunks }`：

- 语法注释定义：`update_hunk: "*** Update File: " filename LF change_move? change?` 与 `change_move: "*** Move to: " filename LF`（`codex-rs/apply-patch/src/parser.rs:13,17`）。
- 解析常量：`MOVE_TO_MARKER = "*** Move to: "`（`codex-rs/apply-patch/src/parser.rs:36`）。
- 解析实现：先识别 `Update File`，再可选消费 `Move to` 行，并写入 `move_path`（`codex-rs/apply-patch/src/parser.rs:279-292,325-329`）。

文档协议也明确了该行为：

- `*** Update File: <path>` 可紧跟 `*** Move to: <new path>`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:16-19,47-49`）。

### 3) 数据结构与语义承载

- `Hunk::UpdateFile { path, move_path, chunks }`：表达“更新哪个源文件、是否搬迁、如何改行”（`codex-rs/apply-patch/src/parser.rs:68-75`）。
- `UpdateFileChunk`：承载上下文锚点、旧行、新行、EOF 标记（`codex-rs/apply-patch/src/parser.rs:91-104`）。
- `ApplyPatchFileChange::Update { unified_diff, move_path, new_content }`：验证后给上层审批/事件系统使用（`codex-rs/apply-patch/src/lib.rs:102-107`）。

### 4) 文件系统执行逻辑（移动到新目录）

真正落盘在 `apply_hunks_to_files`：

- 先根据 chunk 计算 `new_contents`（`codex-rs/apply-patch/src/lib.rs:311-312`）。
- 若存在 `move_path`：
  - `create_dir_all(dest.parent())` 保证目标目录存在（`codex-rs/apply-patch/src/lib.rs:314-320`）。
  - 写入新文件 `write(dest, new_contents)`（`codex-rs/apply-patch/src/lib.rs:321-322`）。
  - 删除源文件 `remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:323-324`）。
  - 把目标路径记为 modified（`codex-rs/apply-patch/src/lib.rs:325`）。

这正是本场景 `input/old/name.txt -> renamed/dir/name.txt` 的核心执行路径。

### 5) 命令与入口形态

- 独立二进制入口：`apply_patch`（`codex-rs/apply-patch/Cargo.toml:11-13`，`codex-rs/apply-patch/src/main.rs:1-2`）。
- CLI 支持参数或 stdin 输入 patch（`codex-rs/apply-patch/src/standalone_executable.rs:12-41`）。
- 在完整 Codex 进程里，`arg0` 也支持通过 `--codex-run-as-apply-patch` 路径内嵌调用（`codex-rs/apply-patch/src/lib.rs:35`，`codex-rs/arg0/src/lib.rs:89-107`）。

## 关键代码路径与文件引用

### 场景对象（本目录）

- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt:1`
- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/other.txt:1`
- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt:1-7`
- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt:1`
- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old/other.txt:1`

### 场景调用方（测试框架）

- 目录遍历与场景执行：`codex-rs/apply-patch/tests/suite/scenarios.rs:10-23`
- input 复制、命令执行、快照比对：`codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`
- 递归复制与快照构建：`codex-rs/apply-patch/tests/suite/scenarios.rs:71-126`

### 被调用方（apply_patch 解析与执行）

- patch grammar 与 Move-to 解析：`codex-rs/apply-patch/src/parser.rs:13-21,279-333`
- patch 应用主流程：`codex-rs/apply-patch/src/lib.rs:183-212`
- move 到新目录的文件系统写删逻辑：`codex-rs/apply-patch/src/lib.rs:306-331`
- CLI 入口：`codex-rs/apply-patch/src/standalone_executable.rs:11-58`

### 上下游集成（非本目录但直接依赖）

- core 拦截 shell/apply_patch 并做 verified parse：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-178,262-355`
- runtime 将 verified patch 转成 `codex --codex-run-as-apply-patch <patch>` 执行：`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102,200-215`
- 协议层 `FileChange::Update { move_path }`：`codex-rs/protocol/src/protocol.rs:3137-3151`

## 依赖与外部交互

### 代码依赖

- `codex-apply-patch` crate 暴露库与 `apply_patch` 二进制（`codex-rs/apply-patch/Cargo.toml:1-13`）。
- 关键依赖：`tree-sitter` / `tree-sitter-bash`（shell heredoc 解析）、`similar`（unified diff）、`anyhow`（错误聚合）（`codex-rs/apply-patch/Cargo.toml:18-23`）。
- Bazel 侧把 `apply_patch_tool_instructions.md` 作为 `compile_data` 打包，避免运行时缺资源（`codex-rs/apply-patch/BUILD.bazel:3-10`）。

### 外部交互面

1. 文件系统：
- 读 `patch.txt`、读写/删除目标文件、创建目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-40`，`codex-rs/apply-patch/src/lib.rs:289-329`）。

2. 子进程：
- 测试内通过 `Command::new(cargo_bin("apply_patch"))` 启动二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。

3. Shell AST 解析（上层工具链）：
- `maybe_parse_apply_patch_verified` 可解析 `bash -lc` heredoc 调用，提取 patch 与可选 `cd` workdir（`codex-rs/apply-patch/src/invocation.rs:132-217,219-369`）。

4. 审批与事件：
- core 层把 verified 变化映射为协议 `FileChange`，并发出 patch begin/end 事件（`codex-rs/core/src/apply_patch.rs:79-104`，`codex-rs/protocol/src/protocol.rs:2781-2814`）。

## 风险、边界与改进建议

### 主要风险/边界

1. 移动执行非原子
- 当前 move 路径是“先写目标，再删源”（`codex-rs/apply-patch/src/lib.rs:321-324`）。若删除失败，可能出现源与目标同时存在的中间态。

2. 目的地覆盖语义较强
- `Move to` 会直接覆盖已存在目标（CLI 测试已验证该行为）（`codex-rs/apply-patch/tests/suite/tool.rs:155-173`）。对调用方而言需要明确这是“覆盖式搬迁”而非“冲突报错”。

3. 场景测试只看最终文件树
- fixture 场景测试有意不校验进程退出码，仅比较最终状态（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。这对“输出诊断文案”回归不敏感。

4. 路径约束依赖上层策略
- parser/执行层以相对路径协议为主（`codex-rs/apply-patch/apply_patch_tool_instructions.md:69`），但最终路径安全边界更多由 core 的审批与沙箱策略兜底（`codex-rs/core/src/apply_patch.rs:41-76`）。

### 改进建议

1. 为 move 增加“删除源失败”专门 fixture
- 目前已有覆盖成功与覆盖目标文件场景，但缺“目标写入成功、源删除失败”的恢复策略测试。

2. 增加 move 场景的元数据断言
- 可补充权限位/mtime 等行为预期，避免未来实现替换成不同 IO 路径时出现无声退化。

3. 对失败场景补充 stderr 快照测试
- 保留“最终状态断言”同时，补一层错误输出 contract，降低回归漏检概率。

4. 在文档里显式强调覆盖语义
- 把 `Move to` 对已有目标文件的覆盖行为补充到工具说明，可减少调用侧误用。
