# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`016_pure_addition_update_chunk`

## 场景与职责

该目录在场景 `016_pure_addition_update_chunk` 中承担“初始文件状态（before state）”职责，目录内仅有一个基线文件：`input.txt`，内容为两行：`line1`、`line2`（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/input/input.txt:1-2`）。

它不是业务逻辑代码目录，而是 `apply_patch` 规范测试的输入夹具（fixture input）。在执行链路中：

1. `tests/suite/scenarios.rs` 会把该目录内容复制到临时目录作为执行起点（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37,107-123`）。
2. 随后读取同场景 `patch.txt` 并调用 `apply_patch` 二进制执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
3. 最终把临时目录与 `expected/` 做整树快照比对（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60,71-105`）。

对本目录而言，核心职责是给“纯新增 update chunk（只有 `+` 行）”提供非空文件基线，验证实现会把新增行追加到文件尾部，而不是覆盖/插入到错误位置。

## 功能点目的

`016` 场景的功能目的，是验证 `*** Update File` 下的 `@@` 块即便没有 `-` 或空格上下文行（即 `old_lines` 为空），仍应被解释为“追加新增内容”。

具体由三段数据配合表达：

1. 输入基线：`input/input.txt` 为两行（`.../input/input.txt:1-2`）。
2. 补丁定义：`patch.txt` 使用
   - `*** Update File: input.txt`
   - `@@`
   - `+added line 1`
   - `+added line 2`
   （`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/patch.txt:1-6`）。
3. 期望结果：`expected/input.txt` 为原两行 + 两行新增（`codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected/input.txt:1-4`）。

该功能点覆盖的实现边界是：`Update File` 并非总是“替换旧行”；在 `old_lines.is_empty()` 时应按插入逻辑处理。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（从本目录到断言通过）

1. 场景发现：`test_apply_patch_scenarios()` 遍历 `fixtures/scenarios` 下所有目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 输入复制：`copy_dir_recursive(input/, tmp/)` 将本目录下 `input.txt` 复制到临时工作目录（`.../scenarios.rs:34-37,107-123`）。
3. 执行补丁：子进程调用 `apply_patch <patch_text>`（`.../scenarios.rs:45-48`）。
4. 比对快照：字节级比较 `tmp/` 与 `expected/`（`.../scenarios.rs:50-60,99-102`）。

### 2) 数据结构与解析映射

场景中的 `@@` + 两条 `+` 行，会被 parser 映射为 `UpdateFileChunk`：

1. `change_context = None`（因为是 `@@` 空上下文头，`codex-rs/apply-patch/src/parser.rs:356-358`）。
2. `old_lines = []`（无 `-` 或空格前缀行，`parser.rs:405-414`）。
3. `new_lines = ["added line 1", "added line 2"]`（`parser.rs:409-411`）。

关键类型：

1. `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:68-75`）。
2. `UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`（`codex-rs/apply-patch/src/parser.rs:90-104`）。

### 3) 应用算法如何处理“纯新增 chunk”

在 `compute_replacements()` 中，当 `chunk.old_lines.is_empty()` 命中时，走专门分支：

1. 计算 `insertion_idx`：追加到文件尾（若末尾有空哨兵则插入到哨兵前）（`codex-rs/apply-patch/src/lib.rs:414-423`）。
2. 记录替换项 `(insertion_idx, 0, chunk.new_lines.clone())`，即“删除 0 行，插入新行”。

随后 `apply_replacements()` 倒序应用替换，插入新增行（`codex-rs/apply-patch/src/lib.rs:478-501`）；`derive_new_contents_from_chunks()` 最后确保文件有 trailing newline（`codex-rs/apply-patch/src/lib.rs:373-377`）。

因此该场景得到 `line1\nline2\nadded line 1\nadded line 2\n`，与 expected 一致。

### 4) 协议与命令

1. fixture 协议：`input/ + patch.txt + expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。
2. patch 协议语法：`Begin/End`、`Update File`、`@@`、`+/-/ ` 前缀行（`codex-rs/apply-patch/src/parser.rs:6-21`，`codex-rs/apply-patch/apply_patch_tool_instructions.md:27-50`）。
3. CLI 命令模型：`apply_patch '<PATCH>'` 或 stdin（`codex-rs/apply-patch/src/standalone_executable.rs:12-47`）。

### 5) 相关测试覆盖

1. 场景级（数据驱动）：`test_apply_patch_scenarios` 自动覆盖本目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 代码级（行为补强）：`test_pure_addition_chunk_followed_by_removal` 覆盖“纯新增块 + 后续替换块”组合，防止替换顺序或索引处理回归（`codex-rs/apply-patch/src/lib.rs:764-789`）。

## 关键代码路径与文件引用

### A. 目标目录与直接对象

1. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/input/input.txt:1-2`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/patch.txt:1-6`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/016_pure_addition_update_chunk/expected/input.txt:1-4`

### B. 调用方（消费该目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`（遍历场景）
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`（回放单场景）
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:107-126`（复制 input）
4. `codex-rs/apply-patch/tests/all.rs:1-3`、`codex-rs/apply-patch/tests/suite/mod.rs:1-4`（integration test 入口聚合）

### C. 被调用方（执行与解析）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-266`（`apply_patch` 入口）
3. `codex-rs/apply-patch/src/lib.rs:279-339`（hunk 落盘）
4. `codex-rs/apply-patch/src/lib.rs:386-474`（replacement 计算）
5. `codex-rs/apply-patch/src/parser.rs:248-333`（`Update File` hunk 解析）
6. `codex-rs/apply-patch/src/parser.rs:343-434`（chunk 解析）
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`（上下文匹配策略）

### D. 配置、上游调用、文档与脚本上下文

1. `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin 与测试依赖）
2. `codex-rs/apply-patch/BUILD.bazel:1-10`（Bazel 编译数据）
3. `codex-rs/core/src/config/mod.rs:528-531`（`include_apply_patch_tool` 配置）
4. `codex-rs/core/src/tools/spec.rs:2784-2804`（注册 `apply_patch` tool spec + handler）
5. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`（调用 `maybe_parse_apply_patch_verified` + 执行管线）
6. `codex-rs/core/src/apply_patch.rs:36-77`（安全评估后决定直返/委托 exec）
7. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102,200-215`（构造 `codex --codex-run-as-apply-patch` 并执行）
8. `codex-rs/arg0/src/lib.rs:85-107`（`arg0` 分发至 `codex_apply_patch::apply_patch`）
9. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`（fixture 文档）
10. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`（协议文档）
11. `.ops/generate_daily_research_todo.sh:1-42`（研究流程脚本，任务完成后刷新 todo）

## 依赖与外部交互

### 1) 依赖

1. 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`Cargo.toml:25-30`）。

### 2) 外部交互面

1. 文件系统：复制 `input/`、执行 patch 写盘、读取 `expected/` 与实际目录生成快照。
2. 进程：场景 runner 每个场景都会启动 `apply_patch` 子进程（`scenarios.rs:45-48`）。
3. 跨平台适配：快照和复制时使用 `metadata()` 跟随 symlink，兼容 Buck2 runfiles 行为（`scenarios.rs:92-95,113-118`）。

### 3) 与上游系统交互

1. 在 `core` 模式下，`apply_patch` 常先经 `maybe_parse_apply_patch_verified` 预检，因此错误会更早暴露（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`，`codex-rs/apply-patch/src/invocation.rs:132-217`）。
2. 预检通过后才进入 runtime 执行，runtime 通过自调用 `codex --codex-run-as-apply-patch` 落地（`codex-rs/core/src/tools/runtimes/apply_patch.rs:90-95`）。

## 风险、边界与改进建议

### 风险

1. 场景 runner 不校验 exit status/stderr，只比较最终文件树；当输出语义回归但文件结果碰巧一致时可能漏检（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
2. `compute_replacements()` 的“纯新增 = 追加尾部”策略对上下文不敏感；若未来需要“在指定上下文后插入”语义，当前场景无法约束该行为。 
3. 当前目录只有单文件基线，未覆盖“多文件同名片段 + 纯新增块”可能引发的位置歧义。

### 边界

1. 本目录只验证普通 EOF 追加，不涉及 `*** End of File` 锚点（该边界由 `022_update_file_end_of_file_marker` 负责）。
2. 不覆盖 CRLF 输入；场景仓库强制 LF（`.gitattributes`）。
3. 不覆盖权限/只读文件等 I/O 错误边界。

### 改进建议

1. 为 `scenarios` 增加可选元数据断言（`exit_code` / `stderr_contains`），补足“结果对但过程错”的检测盲区。
2. 针对“纯新增块”新增一组多 chunk fixture：第一块纯新增、第二块带上下文替换，固定替换顺序与最终插入位置（虽然 `lib.rs` 有单测覆盖，但 fixture 层还没有同等强度样例）。
3. 补充 CRLF 输入场景，明确 `split('\n')` + trailing newline 处理在混合换行下的实际契约。
4. 若产品语义要求更精确插入位置，可扩展 patch 协议在纯新增块上要求显式上下文头，并在 parser 阶段约束。
