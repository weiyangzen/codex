# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 场景关键词：`Update File`、末尾换行收敛（trailing newline normalization）

## 场景与职责

该目录是 `apply_patch` 端到端 fixtures 场景之一，用于锁定以下行为：

1. 对已存在文件执行 `*** Update File` 后，结果文件应带有末尾换行（newline-terminated text file）。
2. 场景只验证最终文件系统状态，不验证进程退出码与 stderr 文案。
3. 场景作为数据驱动回归样例，被 `tests/suite/scenarios.rs` 自动遍历执行。

目录内文件构成：

1. `patch.txt`：定义一次更新操作（`codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/patch.txt:1-7`）。
2. `input/no_newline.txt`：初始文件。
3. `expected/no_newline.txt`：期望输出文件（两行文本，末尾有 `\n`）。

在场景集中的职责分层：

1. 与 `016_pure_addition_update_chunk` 共同覆盖 update chunk 的正向路径。
2. 与 `021_update_file_deletion_only` 共同覆盖 update 的替换/删除细分语义。
3. 与 `022_update_file_end_of_file_marker` 共同覆盖“文件尾部处理”语义，其中 `014` 验证默认换行补齐，`022` 验证显式 `*** End of File` 标记路径。

## 功能点目的

该场景要保护的核心契约是：

1. `apply_patch` 对 `UpdateFile` 的输出应保持“文本文件标准化”策略，即结果始终以换行结束。
2. 即使补丁内容是普通替换（无 `*** End of File`），仍要保证末尾换行一致性。
3. 该契约必须在 CLI 集成层可观测，且与 fixture 回放结果一致。

对应代码内的直接目的：

1. `derive_new_contents_from_chunks` 在拼接 `new_lines` 后会强制补一个空字符串行并 `join("\n")`，从而得到尾部 `\n`（`codex-rs/apply-patch/src/lib.rs:372-377`）。
2. `compute_replacements` 在 EOF 邻域处理时会去除 trailing empty sentinel 再尝试匹配，降低“末行替换”失败概率（`codex-rs/apply-patch/src/lib.rs:428-457`）。
3. `seek_sequence` 通过多级宽松匹配，保证 update chunk 可以稳定定位到目标行（`codex-rs/apply-patch/src/seek_sequence.rs:34-109`）。

与代码测试的对应关系：

1. `tests/suite/tool.rs` 有等价行为测试 `test_apply_patch_cli_updates_file_appends_trailing_newline`，直接断言 `ends_with('\n')`（`codex-rs/apply-patch/tests/suite/tool.rs:223-237`）。
2. fixture 场景与该测试互补：前者验证目录快照一致性，后者验证 stdout 与换行语义。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与输入

本场景 patch 为：

```patch
*** Begin Patch
*** Update File: no_newline.txt
@@
-no newline at end
+first line
+second line
*** End Patch
```

来源：`codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/patch.txt:1-7`。

协议层约束来自：

1. `tests/fixtures/scenarios/README.md` 规定每个场景由 `input/ + patch.txt + expected/` 组成（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。
2. parser grammar 定义 `update_hunk` + `change_line`，并允许可选 `*** End of File`（`codex-rs/apply-patch/src/parser.rs:6-21`）。

### 2) 调用方链路（谁执行该场景）

`test_apply_patch_scenarios` 的关键流程：

1. 遍历 `tests/fixtures/scenarios/*` 目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 把当前场景 `input/` 拷贝到 `tempdir()`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`）。
3. 读取 `patch.txt` 并调用 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. 比较 `expected` 与实际目录快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

快照数据结构：

1. `Entry::File(Vec<u8>) | Entry::Dir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`）。
2. `BTreeMap<PathBuf, Entry>` 保证比较稳定性（`codex-rs/apply-patch/tests/suite/scenarios.rs:71-77`）。

### 3) 被调用方链路（apply_patch 内核如何落地）

1. CLI 入口：`run_main` 读取参数或 stdin，调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. 解析：`parse_patch` 产出 `ApplyPatchArgs` 与 `Hunk` 列表（`codex-rs/apply-patch/src/parser.rs:106-183`）。
3. 执行：`apply_hunks_to_files` 处理 `Hunk::UpdateFile` 分支（`codex-rs/apply-patch/src/lib.rs:306-331`）。
4. 更新内容推导：`derive_new_contents_from_chunks` -> `compute_replacements` -> `apply_replacements`（`codex-rs/apply-patch/src/lib.rs:348-490`）。
5. 末尾换行关键语句：
   - 若最后一行不是空字符串，则 `push(String::new())`（`codex-rs/apply-patch/src/lib.rs:373-375`）。
   - `join("\n")` 后形成以换行结尾的文本（`codex-rs/apply-patch/src/lib.rs:376`）。

### 4) 配置、构建与命令上下文

1. crate 声明：`codex-apply-patch`，bin 名称 `apply_patch`（`codex-rs/apply-patch/Cargo.toml:1-13`）。
2. 关键依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter(-bash)`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
3. Bazel：`apply_patch_tool_instructions.md` 通过 `compile_data` 进入构建产物（`codex-rs/apply-patch/BUILD.bazel:3-10`）。
4. 场景 fixture 的 EOL 策略：`** text eol=lf`（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。

### 5) 关联测试与文档

1. 同语义代码测试：`test_apply_patch_cli_updates_file_appends_trailing_newline`（`codex-rs/apply-patch/tests/suite/tool.rs:223-237`）。
2. 场景规范文档：`tests/fixtures/scenarios/README.md`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`）。
3. tool 协议文档：`apply_patch_tool_instructions.md`（定义 update hunk 语法）。

### 6) 研究中执行的复现实验命令

1. `cargo test -p codex-apply-patch --test all test_apply_patch_cli_updates_file_appends_trailing_newline -- --exact`
2. `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios -- --exact`

本机结果：均未进入项目断言阶段，受 Rustup 组件下载/重命名失败影响（环境问题，非该场景业务失败）。

## 关键代码路径与文件引用

### A. 目标目录（被研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/patch.txt:1-7`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/input/no_newline.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/expected/no_newline.txt`

### B. 直接调用方

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
2. `codex-rs/apply-patch/tests/all.rs:1-3`
3. `codex-rs/apply-patch/tests/suite/mod.rs:1-3`

### C. 同语义对照测试

1. `codex-rs/apply-patch/tests/suite/tool.rs:223-237`

### D. 被调用方（核心执行实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/parser.rs:6-21`
3. `codex-rs/apply-patch/src/parser.rs:90-104`
4. `codex-rs/apply-patch/src/lib.rs:306-331`
5. `codex-rs/apply-patch/src/lib.rs:348-381`
6. `codex-rs/apply-patch/src/lib.rs:386-474`
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-109`

### E. 配置/构建/文档/脚本

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. `.ops/generate_daily_research_todo.sh:1-42`
6. `Docs/researches/blueprint_checklist.md:125`

## 依赖与外部交互

### 1) 运行时/测试依赖

1. 运行时：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试时：`assert_cmd`、`codex-utils-cargo-bin`、`pretty_assertions`、`tempfile`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 文件系统与进程交互

1. 场景 runner 会复制输入目录、启动子进程、读取目录字节快照并做 map 对比（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-53`）。
2. `apply_patch` 会执行真实文件读写（读原文件、写更新结果），并输出 stdout/stderr（`codex-rs/apply-patch/src/lib.rs:297-329`, `codex-rs/apply-patch/src/standalone_executable.rs:49-58`）。

### 3) 与上层系统交互（上下文依赖）

1. `maybe_parse_apply_patch_verified` 会把 patch 先转成结构化变更，供上层审批/执行路径使用（`codex-rs/apply-patch/src/invocation.rs:132-217`）。
2. 该目录本身不直接触发 core 审批逻辑，但它验证的是 core 复用同一执行内核时的基础文本行为一致性。

### 4) 文档与脚本交互

1. 场景规范由 `scenarios/README.md` 约定。
2. 研究流程要求通过 checklist + daily todo 管理，本次更新依赖 `.ops/generate_daily_research_todo.sh`（`.ops/generate_daily_research_todo.sh:15-41`）。

## 风险、边界与改进建议

### 风险

1. 场景名为 `no_newline`，但 fixture 中提交态文件通常仍以换行结尾；名称与字节事实可能产生理解偏差。
2. `scenarios.rs` 不校验退出码/stderr，仅比最终文件树（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`），错误通路回归可能漏检。
3. 末尾换行行为是实现策略，不是显式可配置项；若未来需要保留“无末尾换行”文件，当前实现会强制标准化。

### 边界

1. 本场景只验证本地文本文件更新后的末尾换行，不覆盖：
   - 二进制文件
   - CRLF/混合换行
   - 权限只读、I/O 失败回滚
2. 本场景不验证 `*** End of File` 分支，需结合 `022_update_file_end_of_file_marker` 一起理解 EOF 语义边界。

### 改进建议

1. 在该场景目录增加说明（例如 README 或注释）明确“期望语义是结果补齐 trailing newline”，减少文件名歧义。
2. 为 fixtures 框架增加可选 `exit_code`/`stderr_contains` 元数据，使负向与边界场景可同时校验行为面与状态面。
3. 若要真正覆盖“输入无末尾换行”的字节级语义，可考虑：
   - 将目标 fixture 文件设为 `-text`（避免文本规范化干扰），或
   - 通过专门字节 fixture 与十六进制断言做补充测试。
4. 在 `apply_patch_tool_instructions.md` 或 crate 文档增加“输出文本默认补末尾换行”的显式说明，降低调用方预期偏差。
