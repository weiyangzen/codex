# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/input`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属 crate：`codex-apply-patch`
- 目录实体：`foo.txt`

## 场景与职责

该目录是场景 `017_whitespace_padded_hunk_header` 的“初始文件系统基线”，只负责提供 patch 执行前状态，不负责定义 patch 语法或断言结果。

本目录在场景三段式契约中的位置：

1. `input/foo.txt` 提供初始内容 `old`（`codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/input/foo.txt:1`）。
2. 同级 `patch.txt` 定义一次 `Update File` 操作，关键点是 hunk 头前有前导空白：`  *** Update File: foo.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/patch.txt:2`）。
3. 同级 `expected/foo.txt` 期望结果为 `new`（`codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/expected/foo.txt:1`）。

目录职责的直接调用方是场景回放测试器：

1. `test_apply_patch_scenarios()` 扫描 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 把当前场景 `input/` 复制到临时目录后执行 `apply_patch` 二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`）。
3. 回放器对比临时目录与 `expected/` 的全量快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

该目录本质上是“语法宽容性”回归场景的一部分，验证的是 parser 对 hunk 头行前导空格的容忍行为，而不是文本匹配算法本身的复杂路径。

## 功能点目的

围绕本目录的核心功能目标：

1. 验证 `*** Update File:` 头行即使带前导空白，也能被识别成合法 hunk。
2. 确保该语法宽容不会影响实际更新语义：`old -> new` 仍正确落盘。
3. 与相邻场景形成分工边界：
- `018_whitespace_padded_patch_markers` 验证 `*** Begin Patch` / `*** End Patch` 行 padding（`codex-rs/apply-patch/tests/fixtures/scenarios/018_whitespace_padded_patch_markers/patch.txt:1-6`）。
- `020_whitespace_padded_patch_marker_lines` 验证 marker 行整体 padding 变体（`codex-rs/apply-patch/tests/fixtures/scenarios/020_whitespace_padded_patch_marker_lines/patch.txt:1-6`）。

该场景的“目的不是多覆盖”，而是用最小输入隔离一个语法容错点：hunk header 的前导空白。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

从 fixture 到真实写文件的执行链如下：

1. `tests/suite/scenarios.rs` 读取场景目录并复制 `input/`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`）。
2. 读取 `patch.txt`，以单参数调用 `apply_patch`（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
3. `standalone_executable::run_main()` 接收 PATCH 文本并调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
4. `lib::apply_patch()` 先 `parse_patch()`，再 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
5. parser 在 `parse_one_hunk()` 对首行执行 `trim()`，因此可识别 `  *** Update File: foo.txt`（`codex-rs/apply-patch/src/parser.rs:248-280`）。
6. `apply_hunks_to_files()` 进入 `UpdateFile` 分支，`derive_new_contents_from_chunks()` 算出新文本并写回（`codex-rs/apply-patch/src/lib.rs:279-339`）。
7. 回放器最终以目录快照断言收敛到 `expected/`（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`）。

### 2) 关键数据结构

1. `Hunk`：`AddFile | DeleteFile | UpdateFile`，场景 017 命中 `UpdateFile`（`codex-rs/apply-patch/src/parser.rs:58-76`）。
2. `UpdateFileChunk`：保存 `change_context / old_lines / new_lines / is_end_of_file`（`codex-rs/apply-patch/src/parser.rs:90-104`）。
3. 场景快照结构 `BTreeMap<PathBuf, Entry>`，`Entry = File(Vec<u8>) | Dir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-77`）。

### 3) 协议与语法

协议来源与实现关系：

1. fixtures 协议：每个场景是 `input/ + patch.txt + expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`）。
2. parser grammar：`UpdateFile` 头、`@@` chunk、`+/-/ ` 行等（`codex-rs/apply-patch/src/parser.rs:6-21`）。
3. 工具使用文档：`apply_patch_tool_instructions.md` 定义命令语法与调用示例（`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`）。

本场景 patch（关键在第 2 行前导空白）：

```patch
*** Begin Patch
  *** Update File: foo.txt
@@
-old
+new
*** End Patch
```

来源：`codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/patch.txt:1-6`。

### 4) 关键命令/脚本

1. 场景测试聚合入口：`codex-rs/apply-patch/tests/all.rs:1-3`。
2. 场景执行器：`codex-rs/apply-patch/tests/suite/scenarios.rs:11-126`。
3. 研究流水线 todo 生成脚本：`.ops/generate_daily_research_todo.sh:1-42`。

## 关键代码路径与文件引用

### A. 目标对象与场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/input/foo.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/patch.txt:1-6`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/017_whitespace_padded_hunk_header/expected/foo.txt:1`

### B. 直接调用方（消费 input 的测试框架）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:50-60`
4. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
5. `codex-rs/apply-patch/tests/all.rs:1-3`

### C. 被调用方（patch 解析与应用）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/parser.rs:154-183`
4. `codex-rs/apply-patch/src/parser.rs:248-340`
5. `codex-rs/apply-patch/src/lib.rs:279-339`
6. `codex-rs/apply-patch/src/lib.rs:386-474`
7. `codex-rs/apply-patch/src/seek_sequence.rs:12-109`

### D. 跨 crate 上下文依赖（工具注册与运行时）

1. 工具注册：`apply_patch` 在 core 中按配置启用并绑定 handler（`codex-rs/core/src/tools/spec.rs:2784-2804`）。
2. handler 二次校验：`maybe_parse_apply_patch_verified` 用于先解析再决定审批/执行路径（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-257`，`codex-rs/apply-patch/src/invocation.rs:132-217`）。
3. runtime 命令构建：最终执行 `codex --codex-run-as-apply-patch <patch>`（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`）。
4. arg0 分发：遇到 `apply_patch` 别名或 `--codex-run-as-apply-patch` 时进入 `codex_apply_patch`（`codex-rs/arg0/src/lib.rs:85-107`）。
5. 平台约定文档：`codex-core` 依赖该虚拟 CLI 合约（`codex-rs/core/README.md:94`）。

### E. 相关测试与文档

1. CLI 正向/反向用例集合：`codex-rs/apply-patch/tests/suite/tool.rs:19-257`。
2. 参数与 stdin 入口验证：`codex-rs/apply-patch/tests/suite/cli.rs:11-90`。
3. parser 单元测试中也包含“头部有空白”的变体（`codex-rs/apply-patch/src/parser.rs:470-584`）。
4. `exec` 侧验证 `CODEX_CORE_APPLY_PATCH_ARG1` 调用链（`codex-rs/exec/tests/suite/apply_patch.rs:20-46`）。

## 依赖与外部交互

### 1) 依赖关系

`codex-apply-patch` crate 依赖：

1. `anyhow`、`thiserror`：错误传播和建模（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. `similar`：生成 unified diff（`codex-rs/apply-patch/src/lib.rs:527-533`，`codex-rs/apply-patch/Cargo.toml:20`）。
3. `tree-sitter`、`tree-sitter-bash`：shell/heredoc 解析（`codex-rs/apply-patch/src/invocation.rs:1-9`，`codex-rs/apply-patch/Cargo.toml:22-23`）。

测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 外部交互

1. 文件系统读写：`apply_hunks_to_files()` 对目标文件做创建/删除/覆盖写（`codex-rs/apply-patch/src/lib.rs:279-339`）。
2. 子进程调用：fixture 回放器通过 `Command::new(...cargo_bin("apply_patch"))` 执行二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准输出/错误流：CLI 通过 stdout 输出 summary，错误经 stderr 返回（`codex-rs/apply-patch/src/standalone_executable.rs:49-58`，`codex-rs/apply-patch/src/lib.rs:191-206`）。

### 3) 配置与构建

1. crate/bin 定义：`codex-rs/apply-patch/Cargo.toml:1-13`。
2. Bazel 把 `apply_patch_tool_instructions.md` 作为 `compile_data`（`codex-rs/apply-patch/BUILD.bazel:3-10`）。
3. 研究任务来源于 checklist，daily todo 由脚本按正则抽取 pending（`.ops/generate_daily_research_todo.sh:15-39`）。

## 风险、边界与改进建议

### 风险

1. 场景回放器不校验 `apply_patch` 退出码，只看最终文件树；若未来出现“非 0 退出但文件偶然收敛”的情况，可能漏报（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。
2. `parse_one_hunk` 注释写了“tolerant of case mismatches”，但代码只做 `trim()` 不做大小写归一，注释与实现存在偏差风险（`codex-rs/apply-patch/src/parser.rs:249-250`）。
3. 当前场景仅覆盖前导空格，不覆盖前导制表符、`Move to` 行 padding、多 hunk 组合下的同类容错。

### 边界

1. 本目录只覆盖单文件文本更新，不覆盖目录层级重命名、删除目录失败、部分成功后失败等语义（这些由其他编号场景覆盖）。
2. 不覆盖 `@@` 复杂上下文定位和 `*** End of File` 语义细节（分别由其它场景与单元测试覆盖）。
3. 场景 fixture 断言是“结果态一致”，不是“执行轨迹一致”（不关心 stderr 内容和具体错误码）。

### 改进建议

1. 为 `017` 增加配套 parser 单测，显式断言 `"\t*** Update File: ..."` 与 `"  *** Move to: ..."` 的行为，减少仅靠 fixture 间接覆盖的盲区。
2. 在 `tests/suite/scenarios.rs` 增加可选元数据断言（例如 `exit_code`/`stderr_contains`），保持现有快照机制同时补上执行语义验证。
3. 修正文档注释“case mismatches”表述，或者实现真正 case-insensitive 解析并新增反例测试，避免注释误导维护者。
4. 为 whitespace 容错场景（017/018/020）补一页聚合 README，明确各场景分工，降低未来重复新增类似用例的概率。
