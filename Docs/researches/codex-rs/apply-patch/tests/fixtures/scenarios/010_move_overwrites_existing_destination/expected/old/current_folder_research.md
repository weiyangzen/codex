# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属子系统：`codex-rs/apply-patch` 场景化 fixtures（`tests/fixtures/scenarios`）

## 场景与职责

该目录在场景 `010_move_overwrites_existing_destination` 中只包含一个文件：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt:1`，内容为 `unrelated file`。

它的职责不是“承载被修改文件”，而是做 **负向约束（non-target invariant）**：

1. 明确声明与 `old/name.txt -> renamed/dir/name.txt` 移动更新无关的同级文件 `old/other.txt` 必须保持原样。
2. 作为 `expected/` 快照的一部分，参与整个目录树比对，防止实现误删/误改旁路文件。
3. 与 `expected/renamed/dir/name.txt`（目标覆盖后的结果）共同定义“目标变、旁路不变”的最终态契约。

从测试架构看，`expected/old` 是被 `tests/suite/scenarios.rs` 的快照逻辑读取，不直接调用任何业务函数；它是执行结果断言的“数据输入端”。

## 功能点目的

`expected/old` 这个子目录要验证的功能点非常具体：

1. **移动覆盖仅影响命中路径**：`Move to` 发生后，目标文件更新，源文件删除，但 `old/other.txt` 不应受影响。
2. **回归保护粒度下沉到子目录**：即使 `expected` 根目录已覆盖整体状态，这个子目录仍将“old 目录保留项”显式化，降低误改被忽略的概率。
3. **补齐 move 场景语义闭环**：与 `patch.txt` 的 `*** Move to:` 形成对照，确保“源删 + 目的改 + 无关保留”三条件同时成立。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 协议输入到执行语义

场景补丁定义为：

- `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`
- 核心语句是 `*** Update File: old/name.txt` + `*** Move to: renamed/dir/name.txt`。

解析协议来自 apply-patch grammar：

1. `parser.rs` 将该 hunk 解析到 `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:60-75,248-330`）。
2. `MOVE_TO_MARKER` 定义为 `*** Move to: `（`codex-rs/apply-patch/src/parser.rs:36`）。

执行语义由 `apply_hunks_to_files()` 落地：

1. 先计算 `new_contents`（`codex-rs/apply-patch/src/lib.rs:311-312,348-380`）。
2. `move_path` 存在时执行 `write(dest, new_contents)`，随后 `remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:313-325`）。
3. 由于写目标是覆盖写，原先 destination 内容 `existing` 会被替换为 `new`。
4. 未命中的 `old/other.txt` 无任何写删路径，自然应保持不变；`expected/old/other.txt` 即用于锁定该行为。

### 2) 场景夹具的断言流程

`test_apply_patch_scenarios()` 逐目录执行 fixtures（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-25`）：

1. 将 `input/` 复制到临时目录（`.../scenarios.rs:33-37,107-125`）。
2. 调用 `apply_patch` 子进程执行 `patch.txt`（`.../scenarios.rs:40-48`）。
3. 对 `expected/` 与实际目录做结构+字节级快照比对（`.../scenarios.rs:51-60`）。

断言数据结构：

1. `Entry::Dir | Entry::File(Vec<u8>)`（`.../scenarios.rs:65-69`）。
2. `BTreeMap<PathBuf, Entry>` 作为稳定快照容器（`.../scenarios.rs:71-77`）。

因此，`expected/old/other.txt` 的存在与字节内容会被精确比较，不是“仅存在性检查”。

### 3) 同语义测试互证

除 fixture 场景外，`tool.rs` 中还有程序化用例：

- `test_apply_patch_cli_move_overwrites_existing_destination`（`codex-rs/apply-patch/tests/suite/tool.rs:155-175`）

其断言：

1. destination 被写成 `new\n`。
2. source 被删除。

fixture 侧再额外验证“无关文件不变”，两者组合形成互补覆盖。

### 4) 可复现实验命令

1. 仅跑场景夹具：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 仅跑 move-overwrite 定向单测：
   - `cargo test -p codex-apply-patch --test all test_apply_patch_cli_move_overwrites_existing_destination`
3. 生成研究待办：
   - `bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### A. 目标目录与场景数据

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/other.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt:1`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt:1`
6. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`

### B. 直接调用方（消费该目录的测试入口）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-25`（遍历 fixtures）
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`（执行单场景）
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:71-105`（expected/actual 快照）
4. `codex-rs/apply-patch/tests/all.rs:1-2`（integration 聚合入口）

### C. 被调用实现（解析、执行、输出）

1. `codex-rs/apply-patch/src/parser.rs:31-39`（patch marker 常量）
2. `codex-rs/apply-patch/src/parser.rs:248-330`（`Update File` + `Move to` 解析）
3. `codex-rs/apply-patch/src/lib.rs:183-213`（`apply_patch`）
4. `codex-rs/apply-patch/src/lib.rs:279-339`（hunk 执行）
5. `codex-rs/apply-patch/src/lib.rs:313-325`（move 覆盖 + 删除源）
6. `codex-rs/apply-patch/src/lib.rs:537-551`（stdout 成功摘要）
7. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`（CLI 入参与调用）

### D. 上游集成链路（工具调用到运行时）

1. `codex-rs/apply-patch/src/invocation.rs:132-217`（`maybe_parse_apply_patch_verified`）
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-210`（handler 内验证与 runtime 请求构造）
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:88-102`（`--codex-run-as-apply-patch` 命令构建）
4. `codex-rs/arg0/src/lib.rs:85-107`（arg0 分发到 apply_patch 执行）

### E. 配置、测试规范、脚本、文档

1. `codex-rs/apply-patch/Cargo.toml:1-30`（crate 与依赖）
2. `codex-rs/apply-patch/BUILD.bazel:1-11`（Bazel 打包与 `compile_data`）
3. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`（fixtures 文本 LF 约束）
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`（fixture 三件套规范）
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-50`（Add/Delete/Update/Move 与语法）
6. `.ops/generate_daily_research_todo.sh:4-7,15-39`（由 checklist 生成当天 todo）

## 依赖与外部交互

### 1) Rust 依赖

`codex-apply-patch` 关键依赖定义于 `Cargo.toml`（`codex-rs/apply-patch/Cargo.toml:18-30`）：

1. `anyhow` / `thiserror`：错误类型与上下文。
2. `similar`：生成 unified diff（verified 模式使用）。
3. `tree-sitter` / `tree-sitter-bash`：解析 shell/heredoc 调用。
4. `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`：测试执行与断言。

### 2) 文件系统交互

与本目录行为直接相关的外部交互都是本地文件系统：

1. `read_to_string` 读源文件。
2. `write(dest, ...)` 覆盖目标文件。
3. `remove_file(path)` 删除源文件。
4. `snapshot_dir` 递归读取 expected/actual 文件树字节内容。

### 3) 进程与命令交互

1. fixture 测试通过子进程运行 `apply_patch`（`scenarios.rs:45-48`）。
2. 在 Codex 主流程中，handler/runtime 会把 verified patch 转成 `codex --codex-run-as-apply-patch <patch>` 执行（`core/.../apply_patch.rs:170-210`; `runtimes/apply_patch.rs:90-93`）。

### 4) 文档与脚本交互

1. fixtures 规则由 `tests/fixtures/scenarios/README.md` 描述。
2. patch 协议由 `apply_patch_tool_instructions.md` 与 `parser.rs` 注释共同约束。
3. 研究流程由 `.ops/generate_daily_research_todo.sh` 读取 `Docs/researches/blueprint_checklist.md` 生成当日 TODO。

## 风险、边界与改进建议

### 风险与边界

1. **非原子 move**：当前实现是“写目标后删源”，若第二步失败会出现部分完成状态。
2. **覆盖语义隐式**：`Move to` 目标已存在时默认覆盖，若调用方期望冲突报错会出现认知偏差。
3. **fixture 场景侧重最终态**：`scenarios.rs` 不断言退出码与 stderr，错误语义主要依赖 `tool.rs` 补充测试。
4. **本目录仅覆盖旁路文件稳定性**：未覆盖权限、只读、目标为目录、并发写入等异常边界。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增补一句“`Move to` 目标文件存在时按当前实现会覆盖”。
2. 为 fixtures 增加可选行为断言元数据（如 `exit_code.txt`、`stderr.txt`），提升场景可观测性。
3. 扩展 move 失败边界场景：
   - `move_destination_is_directory_fails`
   - `move_destination_readonly_fails`
   - `move_partial_failure_after_dest_write`
4. 若未来需要强一致，可评估临时文件+原子替换方案，并将“覆盖/拒绝”做成显式策略而非隐式行为。
