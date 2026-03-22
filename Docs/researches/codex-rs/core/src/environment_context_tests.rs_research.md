# environment_context_tests.rs 研究文档

## 场景与职责

`environment_context_tests.rs` 是 `environment_context.rs` 的配套测试模块，负责验证环境上下文的序列化、构造和比较逻辑。测试覆盖了各种环境配置组合的 XML 输出格式验证。

**测试覆盖范围：**
1. 基本环境上下文序列化（工作目录、Shell、日期、时区）
2. 网络策略序列化（允许/拒绝域名列表）
3. 只读环境（无工作目录）
4. 外部沙箱环境
5. 受限网络环境
6. 完全访问环境
7. 环境差异比较（忽略 Shell）
8. 子代理信息序列化

---

## 功能点目的

### 测试用例清单

| 测试函数 | 目的 | 关键验证点 |
|---------|------|-----------|
| `serialize_workspace_write_environment_context` | 基本序列化 | cwd, shell, date, timezone |
| `serialize_environment_context_with_network` | 网络策略序列化 | allowed_domains, denied_domains |
| `serialize_read_only_environment_context` | 只读环境 | 无 cwd，其他字段正常 |
| `serialize_external_sandbox_environment_context` | 外部沙箱 | 与只读环境相同格式 |
| `serialize_external_sandbox_with_restricted_network` | 受限网络 | 与只读环境相同格式 |
| `serialize_full_access_environment_context` | 完全访问 | 与只读环境相同格式 |
| `equals_except_shell_compares_cwd` | 比较逻辑 | cwd 变化检测 |
| `equals_except_shell_ignores_sandbox_policy` | 比较逻辑 | sandbox 策略忽略（注：实际代码中 sandbox 字段已移除）|
| `equals_except_shell_compares_cwd_differences` | 比较逻辑 | 不同 cwd 返回 false |
| `equals_except_shell_ignores_shell` | 比较逻辑 | shell 差异被忽略 |
| `serialize_environment_context_with_subagents` | 子代理序列化 | subagents YAML 列表 |

---

## 具体技术实现

### 测试基础设施

**假 Shell 创建：**
```rust
fn fake_shell() -> Shell {
    Shell {
        shell_type: ShellType::Bash,
        shell_path: PathBuf::from("/bin/bash"),
        shell_snapshot: crate::shell::empty_shell_snapshot_receiver(),
    }
}
```
- 使用固定的 Bash shell 配置
- 使用空的 shell snapshot receiver

**测试路径：**
```rust
use core_test_support::test_path_buf;
let cwd = test_path_buf("/repo");
```
- 使用测试辅助函数创建跨平台兼容的路径

### 关键测试场景

**1. 网络策略测试**
```rust
#[test]
fn serialize_environment_context_with_network() {
    let network = NetworkContext {
        allowed_domains: vec!["api.example.com".to_string(), "*.openai.com".to_string()],
        denied_domains: vec!["blocked.example.com".to_string()],
    };
    // 验证 XML 输出包含：
    // <network enabled="true">
    //   <allowed>api.example.com</allowed>
    //   <allowed>*.openai.com</allowed>
    //   <denied>blocked.example.com</denied>
    // </network>
}
```
- 验证网络策略正确序列化为嵌套 XML
- 验证通配符域名（`*.openai.com`）保留

**2. 环境差异比较测试**
```rust
#[test]
fn equals_except_shell_ignores_shell() {
    let context1 = EnvironmentContext::new(..., Shell { shell_type: ShellType::Bash, ... });
    let context2 = EnvironmentContext::new(..., Shell { shell_type: ShellType::Zsh, ... });
    assert!(context1.equals_except_shell(&context2));  // 应返回 true
}
```
- 验证 Shell 类型差异被忽略
- 用于 turn 之间环境变化检测

**3. 子代理信息测试**
```rust
#[test]
fn serialize_environment_context_with_subagents() {
    let context = EnvironmentContext::new(
        ...,
        Some("- agent-1: atlas\n- agent-2".to_string()),
    );
    // 验证输出：
    // <subagents>
    //   - agent-1: atlas
    //   - agent-2
    // </subagents>
}
```
- 验证 YAML 格式的子代理列表正确嵌入

### 测试模式观察

**重复的测试结构：**
多个测试（`serialize_read_only`, `serialize_external_sandbox`, `serialize_full_access`）产生**完全相同的输出**，这表明：
- 这些环境类型在序列化层面没有区分
- 区分可能在其他模块（如策略执行层）处理
- 测试可能遗留自重构前的版本

---

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/environment_context_tests.rs` (274 行)

### 被测试文件
- `/home/sansha/Github/codex/codex-rs/core/src/environment_context.rs` - 主实现

### 测试依赖
- `core_test_support::test_path_buf` - 测试路径创建
- `pretty_assertions::assert_eq` - 清晰的断言输出
- `crate::shell::{Shell, ShellType}` - Shell 类型

---

## 依赖与外部交互

### 测试框架
| 依赖 | 用途 |
|------|------|
| `pretty_assertions` | 清晰的字符串比较输出 |
| `core_test_support` | 测试辅助函数 |

### 被测模块导入
```rust
use super::*;  // environment_context.rs 的所有项
use crate::shell::ShellType;
```

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **差异检测构造测试**
   - 无 `diff_from_turn_context_item` 测试
   - 无 `from_turn_context` 测试
   - 无 `from_turn_context_item` 测试

2. **边界条件测试**
   - 无空网络列表测试
   - 无特殊字符（XML 元字符）测试
   - 无超长域名列表测试
   - 无空 subagents 测试

3. **比较逻辑测试不完整**
   - 无 network 差异比较测试
   - 无 date/timezone 差异比较测试
   - 无 subagents 比较测试

4. **XML 格式验证**
   - 仅字符串比较，无 XML 解析验证
   - 可能遗漏格式错误（如未闭合标签）

5. **错误处理测试**
   - 无无效输入处理测试
   - 无 None 字段组合测试

### 改进建议

1. **添加差异检测测试**
   ```rust
   #[test]
   fn diff_detects_cwd_change() {
       let before = create_turn_context_item("/old");
       let after = create_turn_context("/new");
       let diff = EnvironmentContext::diff_from_turn_context_item(&before, &after, &shell);
       assert_eq!(diff.cwd, Some(PathBuf::from("/new")));
   }
   ```

2. **添加 XML 解析验证**
   ```rust
   #[test]
   fn serialized_xml_is_valid() {
       let xml = context.serialize_to_xml();
       let _: Element = xml.parse().expect("valid XML");
   }
   ```

3. **添加特殊字符测试**
   ```rust
   #[test]
   fn special_chars_are_escaped() {
       let context = EnvironmentContext::new(
           Some(PathBuf::from("/path/with/<special>&chars")),
           ...
       );
       let xml = context.serialize_to_xml();
       assert!(xml.contains("&lt;special&gt;&amp;chars"));
   }
   ```

4. **合并重复测试**
   - `serialize_read_only`, `serialize_external_sandbox`, `serialize_full_access` 测试相同内容
   - 建议合并或添加实际差异验证

5. **添加性能测试**
   ```rust
   #[test]
   fn large_network_list_performance() {
       let network = NetworkContext {
           allowed_domains: (0..10000).map(|i| format!("domain{i}.com")).collect(),
           ...
       };
       // 验证性能可接受
   }
   ```

### 测试代码质量

**优点：**
- 使用 `pretty_assertions` 改善多行字符串比较
- 使用 `test_path_buf` 确保跨平台路径处理
- 清晰的测试命名和结构

**可改进点：**
- 大量重复的 `fake_shell()` 调用可提取为 fixture
- 重复的 XML 字符串可使用模板或快照测试
- 可添加参数化测试减少重复代码
