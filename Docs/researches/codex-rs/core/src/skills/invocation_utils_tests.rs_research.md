# invocation_utils_tests.rs 研究文档

## 场景与职责

`invocation_utils_tests.rs` 是 `invocation_utils.rs` 模块的**单元测试文件**，专注于验证隐式技能调用检测逻辑的正确性。与 `injection_tests.rs` 测试显式技能提及不同，本测试文件覆盖以下场景：

1. **脚本运行检测**：验证各种脚本执行命令的解析和匹配
2. **文档读取检测**：验证文件读取命令中技能文档的识别
3. **路径匹配**：验证绝对路径和相对路径的规范化与匹配
4. **命令令牌化**：验证命令解析的边界情况

该测试文件确保隐式调用检测在各种 shell 命令场景下的准确性。

## 功能点目的

### 测试辅助函数

#### `test_skill_metadata` - 技能元数据工厂
```rust
fn test_skill_metadata(skill_doc_path: PathBuf) -> SkillMetadata
```
创建最小化的 `SkillMetadata` 实例用于测试，填充必需的字段：
- `name`: "test-skill"
- `description`: "test"
- `scope`: `SkillScope::User`
- 其他字段使用 `None` 或默认值

### 核心测试用例

#### 1. 脚本运行检测测试

**`script_run_detection_matches_runner_plus_extension`**
- 验证标准 Python 脚本执行命令的检测
- 输入：`["python3", "-u", "scripts/fetch_comments.py"]`
- 期望：`script_run_token` 返回 `Some(...)`
- 覆盖场景：带选项的脚本执行

**`script_run_detection_excludes_python_c`**
- 验证内联代码执行不被识别为脚本运行
- 输入：`["python3", "-c", "print(1)"]`
- 期望：`script_run_token` 返回 `None`
- 覆盖场景：`-c` 选项执行内联代码，不是脚本文件

**`skill_script_run_detection_matches_relative_path_from_skill_root`**
- 验证从技能根目录执行的相对路径脚本匹配
- 设置：技能文档在 `/tmp/skill-test/SKILL.md`，脚本目录在 `/tmp/skill-test/scripts`
- 输入：`["python3", "scripts/fetch_comments.py"]`
- 工作目录：`/tmp/skill-test`
- 期望：检测到技能 "test-skill"

**`skill_script_run_detection_matches_absolute_path_from_any_workdir`**
- 验证绝对路径脚本的匹配
- 设置：同上
- 输入：`["python3", "/tmp/skill-test/scripts/fetch_comments.py"]`
- 工作目录：`/tmp/other`（非技能目录）
- 期望：仍能检测到技能

#### 2. 文档读取检测测试

**`skill_doc_read_detection_matches_absolute_path`**
- 验证直接读取 SKILL.md 文件的检测
- 设置：技能文档在 `/tmp/skill-test/SKILL.md`
- 输入：`["cat", "/tmp/skill-test/SKILL.md", "|", "head"]`
- 工作目录：`/tmp`
- 期望：检测到技能 "test-skill"
- 覆盖场景：管道命令中的文件读取

## 具体技术实现

### 测试结构模式
```rust
#[test]
fn test_name() {
    // 1. 准备测试数据
    let skill_doc_path = PathBuf::from("/tmp/skill-test/SKILL.md");
    let skill = test_skill_metadata(skill_doc_path);
    
    // 2. 构建 SkillLoadOutcome 和索引
    let outcome = SkillLoadOutcome {
        implicit_skills_by_scripts_dir: Arc::new(HashMap::from([(scripts_dir, skill)])),
        implicit_skills_by_doc_path: Arc::new(HashMap::new()),
        ..Default::default()
    };
    
    // 3. 执行被测函数
    let tokens = vec![...];
    let found = detect_skill_script_run(&outcome, &tokens, Path::new(...));
    
    // 4. 断言结果
    assert_eq!(found.map(|v| v.name), Some("test-skill".to_string()));
}
```

### 路径规范化
测试中使用 `normalize_path` 函数确保路径一致性：
```rust
let scripts_dir = normalize_path(Path::new("/tmp/skill-test/scripts"));
```
这模拟了生产环境中使用 `std::fs::canonicalize` 的行为。

### 使用 `pretty_assertions`
```rust
use pretty_assertions::assert_eq;
```
提供清晰的测试失败差异输出，便于调试。

## 关键代码路径与文件引用

### 被测函数
| 被测函数 | 测试覆盖 |
|---------|----------|
| `script_run_token` | `script_run_detection_*` |
| `detect_skill_script_run` | `skill_script_run_detection_*` |
| `detect_skill_doc_read` | `skill_doc_read_detection_*` |
| `normalize_path` | 所有测试（间接） |

### 依赖模块
| 模块 | 用途 |
|------|------|
| `super::*` | 被测模块的公共和 crate 私有 API |
| `pretty_assertions::assert_eq` | 增强断言输出 |
| `std::collections::HashMap` | 测试数据结构 |
| `std::path::{Path, PathBuf}` | 路径操作 |
| `std::sync::Arc` | 索引共享所有权 |

### 相关类型
| 类型 | 定义位置 | 用途 |
|------|----------|------|
| `SkillLoadOutcome` | model.rs | 包含隐式技能索引 |
| `SkillMetadata` | model.rs | 技能元数据 |
| `SkillScope` | codex_protocol | 技能作用域枚举 |

## 依赖与外部交互

### 测试框架
- 使用 Rust 内置测试框架 (`#[test]`)
- 标准库测试 runner

### 外部依赖
- `pretty_assertions`: 彩色差异输出
- `std::sync::Arc`: 共享所有权
- `std::collections::HashMap`: 索引构建

## 风险、边界与改进建议

### 测试覆盖分析

**已覆盖场景：**
- ✅ 标准脚本运行检测
- ✅ 带选项的脚本执行
- ✅ 内联代码执行排除
- ✅ 相对路径脚本匹配
- ✅ 绝对路径脚本匹配
- ✅ 文档读取检测

**未覆盖场景（潜在改进）：**

1. **更多运行器类型**
   - `node`, `deno`, `ruby`, `perl`, `pwsh` 等运行器
   - 当前仅测试 `python3`

2. **复杂命令结构**
   - 管道命令（`cat file | python script.py`）
   - 子 shell（`$(python script.py)`）
   - 命令序列（`cmd1; cmd2`）

3. **路径边界情况**
   - 符号链接路径
   - 包含空格的路径
   - 非 UTF-8 路径

4. **错误处理**
   - 无效的路径格式
   - 权限不足的文件访问

5. **并发场景**
   - 多线程环境下的去重机制

### 改进建议

1. **参数化测试**
   ```rust
   #[test_case("python3", "script.py", true)]
   #[test_case("node", "script.js", true)]
   #[test_case("ruby", "script.rb", true)]
   #[test_case("gcc", "main.c", false)]  // 不是脚本运行器
   fn test_runner_detection(runner: &str, script: &str, expected: bool) { ... }
   ```

2. **测试数据生成**
   - 使用 `proptest` 生成随机路径和命令
   - 发现边界情况和潜在 bug

3. **集成测试**
   - 添加使用真实文件系统的集成测试
   - 验证 `canonicalize` 的实际行为

4. **性能测试**
   - 测试大量技能（1000+）的索引构建性能
   - 测试复杂命令的解析性能

5. **负面测试**
   ```rust
   #[test]
   fn script_run_detection_rejects_directory() {
       // 目录不应该被识别为脚本
       let tokens = vec!["python3".to_string(), "/path/to/dir".to_string()];
       assert_eq!(script_run_token(&tokens), None);
   }
   ```

6. **文档测试**
   - 为被测函数添加文档示例
   - 示例代码即测试，提高文档准确性
