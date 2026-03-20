# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`010_move_overwrites_existing_destination` 是 `apply_patch` fixtures 中的“移动更新时覆盖已存在目标文件”场景。它与 `004_move_to_new_directory` 的差异在于：`010` 不是测试目标目录创建，而是测试 `*** Move to:` 的目标文件已经存在时，执行器是否按当前实现语义覆盖目标文件内容。

该目录由三部分构成并承担明确职责：

1. `patch.txt` 声明一次 `Update File + Move to` 操作（`codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`）。
2. `input/` 声明执行前状态：
   - `old/name.txt` 为源文件，内容 `from`（`.../input/old/name.txt:1`）。
   - `renamed/dir/name.txt` 为已存在目标文件，内容 `existing`（`.../input/renamed/dir/name.txt:1`）。
   - `old/other.txt` 为旁路文件，内容 `unrelated file`（`.../input/old/other.txt:1`）。
3. `expected/` 声明执行后状态：
   - `renamed/dir/name.txt` 被改为 `new`（`.../expected/renamed/dir/name.txt:1`）。
   - `old/other.txt` 保持不变（`.../expected/old/other.txt:1`）。
   - `old/name.txt` 不再存在（通过 expected 快照间接约束）。

在职责上，这个目录是 move 语义的“覆盖边界”契约样例：

1. 验证 destination existing file 覆盖行为。
2. 验证 source 删除行为。
3. 验证同目录无关文件不受影响。

## 功能点目的

该场景的功能目的不是验证 patch 能否解析，而是锁定“解析后执行阶段”的文件系统语义，重点如下：

1. `*** Move to:` 与 `Update File` 同时存在时，更新结果写入目的路径，而不是保留在源路径。
2. 当目的文件已存在时，按当前实现以 `std::fs::write` 直接覆写，不报冲突错误。
3. 覆写发生后，源文件会被删除，形成“逻辑移动 + 内容更新”的最终状态。
4. 无关文件 (`old/other.txt`) 不应被误删或误改，防止路径匹配范围泄漏。

对测试体系的意义：

1. 补足 `004_move_to_new_directory` 没覆盖到的“目的文件已存在”分支。
2. 与 `test_apply_patch_cli_move_overwrites_existing_destination` 形成 fixture 驱动 + 代码驱动的双重回归。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键协议输入

本场景 patch：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

对应 grammar 中的 `update_hunk + change_move`（`codex-rs/apply-patch/src/parser.rs:13-21`，`codex-rs/apply-patch/apply_patch_tool_instructions.md:47-50`）。

### 2) 解析流程

1. `apply_patch()` 先调用 `parse_patch()`（`codex-rs/apply-patch/src/lib.rs:183-210`）。
2. `parse_one_hunk()` 命中 `*** Update File: ` 分支，并读取可选 `*** Move to: ` 到 `move_path`（`codex-rs/apply-patch/src/parser.rs:279-329`）。
3. 解析结果落在数据结构：
   - `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:68-75`）。

### 3) 执行流程（覆盖语义的核心）

1. `apply_hunks_to_files()` 处理 `Hunk::UpdateFile`（`codex-rs/apply-patch/src/lib.rs:279-333`）。
2. 先通过 `derive_new_contents_from_chunks()` 读取源文件并计算 `new_contents`（`codex-rs/apply-patch/src/lib.rs:311-313`, `348-360`）。
3. `move_path` 存在时执行：
   - `create_dir_all(dest.parent())`（必要时建目录）。
   - `std::fs::write(dest, new_contents)`：这是覆盖已存在目标文件的关键行为。
   - `std::fs::remove_file(path)`：删除原始源文件。
   - 将 `dest` 记录到 `modified`（`codex-rs/apply-patch/src/lib.rs:313-326`）。
4. 成功后 `print_summary()` 输出 `M <dest>`（`codex-rs/apply-patch/src/lib.rs:247-251`, `543-551`）。

结论：当前实现语义是“写目标（可覆盖）+删源”，而不是 `rename`，因此 `010` 场景的 expected 是实现自然结果。

### 4) 测试回放与断言机制

1. fixture 驱动：`test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 把 `input/` 复制到临时目录，执行 `apply_patch <patch>`，再按目录快照全量比对 `expected` 与实际（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`）。
3. 快照包含目录与文件字节内容 (`Entry::Dir | Entry::File(Vec<u8>)`)（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-105`）。

### 5) 同语义代码驱动测试

`test_apply_patch_cli_move_overwrites_existing_destination()` 明确构造“destination 已存在”并断言：

1. 命令成功且 stdout 为 `M renamed/dir/name.txt`。
2. `original_path` 不存在。
3. `destination` 内容为 `new\n`。

见 `codex-rs/apply-patch/tests/suite/tool.rs:155-173`。

### 6) 上层调用与命令通路

1. 独立二进制入口：`standalone_executable::run_main()` 读取参数或 stdin，调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. `arg0` 支持通过 argv0 或 `--codex-run-as-apply-patch` 分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:85-107`）。
3. `core` 的 apply_patch handler 会先 `maybe_parse_apply_patch_verified`，再委派 runtime 以 `codex --codex-run-as-apply-patch <patch>` 执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-179`, `197-205`; `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`）。

### 7) 与本目录相关的可复现实验命令

1. 场景回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 定向语义：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_move_overwrites_existing_destination`

## 关键代码路径与文件引用

### A. 场景数据（本目录）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/other.txt`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt`
6. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt`

### B. 直接调用方

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
2. `codex-rs/apply-patch/tests/suite/tool.rs:155-173`
3. `codex-rs/apply-patch/tests/all.rs:1-2`
4. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`

### C. 执行与解析核心

1. `codex-rs/apply-patch/src/lib.rs:183-213` (`apply_patch`)
2. `codex-rs/apply-patch/src/lib.rs:279-339` (`apply_hunks_to_files`)
3. `codex-rs/apply-patch/src/lib.rs:348-360` (`derive_new_contents_from_chunks` 读源文件)
4. `codex-rs/apply-patch/src/parser.rs:31-39`（marker 常量）
5. `codex-rs/apply-patch/src/parser.rs:279-329`（`Move to` 解析）

### D. 上游集成/运行时

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/arg0/src/lib.rs:85-107`
3. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-179`
4. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`

### E. 配置、文档、规范

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-19`, `40-50`

## 依赖与外部交互

### 1) crate 依赖与职责

1. `anyhow` / `thiserror`：错误传播与上下文信息（`Cargo.toml:18-23`）。
2. `similar`：生成 unified diff（用于 verified 变更建模）。
3. `tree-sitter` / `tree-sitter-bash`：解析 shell/heredoc 形式的 apply_patch 调用。
4. 测试依赖 `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`（`Cargo.toml:25-30`）。

### 2) 文件系统交互

1. 读源：`read_to_string(path)`。
2. 写目标：`write(dest, new_contents)`，对已存在文件为覆盖语义。
3. 删源：`remove_file(path)`。
4. 目录：`create_dir_all(parent)`。

这些交互共同决定了 `010` 的“目标覆盖 + 源删除 + 旁路文件保留”结果。

### 3) 进程与标准流交互

1. 测试通过子进程调用 `apply_patch`（`tests/suite/scenarios.rs:45-48`）。
2. CLI 输出成功摘要到 stdout，错误到 stderr（`src/standalone_executable.rs:49-58`）。

### 4) 文档/协议交互

1. patch 三件套规范由 fixtures README 定义（`tests/fixtures/scenarios/README.md:5-7`）。
2. patch 语法及 `Move to` 协议由 `apply_patch_tool_instructions.md` 与 `parser.rs` grammar 注释共同约束（`apply_patch_tool_instructions.md:47-50`, `parser.rs:13-21`）。
3. Bazel `compile_data` 把 `apply_patch_tool_instructions.md` 打包进 crate（`BUILD.bazel:8-10`）。

### 5) 脚本维度

1. 未发现专门针对 `010_move_overwrites_existing_destination` 的独立 shell/python 回放脚本。
2. 该场景实际由 Rust 测试入口（`tests/suite/scenarios.rs`）统一驱动执行。

## 风险、边界与改进建议

### 风险与边界

1. 非原子多步写入：`write(dest)` 成功后 `remove_file(src)` 失败会出现“双文件并存”中间态风险；当前实现不提供事务回滚。
2. 目标覆盖是隐式语义：`Move to` 在文档中描述“rename”，但实现是“覆写目标 + 删除源”，调用方若预期冲突报错会误判。
3. fixture 回放默认不校验退出码/stderr，仅比较最终文件树；对错误信息文本稳定性的保护依赖 `tool.rs`。
4. 当前场景未覆盖权限错误、目标为目录、并发冲突、跨文件系统异常等 I/O 边界。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增加一句明确说明：当 `Move to` 目标文件存在时，当前实现会覆盖目标文件内容。
2. 在 fixtures 增补边界场景：
   - `move_destination_is_directory_fails`
   - `move_destination_readonly_fails`
   - `move_remove_source_fails_partial_state`
3. 为 `scenarios` 体系增加可选元数据断言（例如 `exit_code.txt`、`stderr.txt`），在保持目录驱动的同时补足行为面校验。
4. 若后续需要强一致语义，可在执行层评估“先临时文件写入+fsync+rename+校验”的更强原子策略，并单独定义覆盖策略（覆盖/拒绝）为显式配置。
