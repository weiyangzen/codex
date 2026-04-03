# sed_command.rs 研究文档

## 场景与职责

`sed_command.rs` 实现了 sed 命令的安全解析器。由于 GNU sed 支持 `e` 标志（允许执行任意 shell 命令），直接允许任意 sed 命令存在严重的命令注入风险。该模块通过严格限制支持的 sed 命令格式，确保只有"可证明安全"的 sed 命令才能通过验证。

该模块的核心职责：
- 解析 sed 命令字符串
- 验证命令是否符合安全白名单
- 拒绝可能包含代码执行的命令模式

## 功能点目的

### 1. 安全背景

GNU sed 的 `e` 标志允许在替换时执行 shell 命令：
```bash
# 危险：每次匹配 y 时执行 echo hi
$ sed 's/y/echo hi/e' /tmp/yes.txt
hi
hi
hi
hi
```

这种功能在自动化工具中极其危险，因为恶意输入可能通过 sed 命令执行任意代码。

### 2. 支持的命令格式

当前仅支持一种格式：**行范围打印**
```
122,202p
```
- 两个正整数（行号范围）
- 以 `p` 结尾（打印命令）

### 3. 验证函数

```rust
pub fn parse_sed_command(sed_command: &str) -> Result<()>
```

返回：
- `Ok(())`: 命令安全
- `Err(Error::SedCommandNotProvablySafe)`: 命令不安全或格式不支持

## 具体技术实现

### 完整代码

```rust
use crate::error::Error;
use crate::error::Result;

pub fn parse_sed_command(sed_command: &str) -> Result<()> {
    // 目前仅解析形如 `122,202p` 的命令
    if let Some(stripped) = sed_command.strip_suffix("p")
        && let Some((first, rest)) = stripped.split_once(",")
        && first.parse::<u64>().is_ok()
        && rest.parse::<u64>().is_ok()
    {
        return Ok(());
    }

    Err(Error::SedCommandNotProvablySafe {
        command: sed_command.to_string(),
    })
}
```

### 解析逻辑

1. **检查后缀**: 必须以 `p` 结尾（打印命令）
2. **去除后缀**: 获取 `122,202`
3. **分割范围**: 以 `,` 分割为两部分
4. **验证数字**: 两部分都必须是有效的 `u64`

### 错误处理

使用 `let else` 链式条件，任何条件不满足都返回错误。

## 关键代码路径与文件引用

### 当前文件关键位置
- 行 4-17: `parse_sed_command` 函数完整实现

### 调用关系

**被调用方**:
- `arg_type.rs:68`: `ArgType::SedCommand` 验证时调用

**调用链**:
```
Policy::check()
  -> ProgramSpec::check()
    -> MatchedArg::new()
      -> ArgType::SedCommand.validate()
        -> parse_sed_command()
```

### 策略文件中的使用

```python
# default.policy
define_program(
    program="sed",
    options=common_sed_flags,
    args=[ARG_SED_COMMAND, ARG_RFILES],
    system_path=sed_system_path,
)
```

## 依赖与外部交互

### 外部 crate 依赖
- 无直接依赖

### 内部模块依赖
- `error.rs`: `Error`, `Result`

## 风险、边界与改进建议

### 当前限制与风险

1. **过度严格的限制**
   - 不支持常见的 `s/old/new/` 替换，即使它是安全的
   - 不支持 `d`（删除）、`q`（退出）等安全命令
   - 用户可能因策略限制而无法执行合理的 sed 操作

2. **行号范围验证不完整**
   - 不验证 `first <= rest`（`202,122p` 是有效的但无意义）
   - 不验证行号是否合理（如 `0` 作为起始行在某些 sed 实现中有效）

3. **实现过于简单**
   - 使用字符串操作而非正式解析
   - 容易绕过或误报
   - 例如：`"122,202p "`（尾部空格）会失败

4. **不支持地址变体**
   - 单行地址：`10p`
   - 正则地址：`/pattern/p`
   - 步长地址：`1~2p`（奇数行）

5. **GNU sed 扩展**
   - 不支持 `I`（忽略大小写）标志
   - 不支持 `M`（多行模式）标志

### 边界情况

| 场景 | 当前行为 | 说明 |
|------|----------|------|
| `"122,202p"` | 通过 | 标准格式 |
| `"1,10p"` | 通过 | 有效格式 |
| `"s/a/b/"` | 拒绝 | 不支持 |
| `"122,202p "` | 拒绝 | 尾部空格 |
| `" 122,202p"` | 拒绝 | 前导空格 |
| `"122,202P"` | 拒绝 | 大写 P |
| `"0,100p"` | 通过 | 0 作为起始行 |
| `"202,122p"` | 通过 | 逆序范围 |

### 改进建议

1. **支持安全的替换命令**
   ```rust
   pub fn parse_sed_command(sed_command: &str) -> Result<()> {
       // 现有格式
       if is_print_range(sed_command)? {
           return Ok(());
       }
       
       // 安全的替换：s/pattern/replacement/flags
       if is_safe_substitution(sed_command)? {
           return Ok(());
       }
       
       Err(Error::SedCommandNotProvablySafe { ... })
   }
   
   fn is_safe_substitution(cmd: &str) -> Result<bool> {
       // 确保 flags 不包含 e（执行）、r（读取文件）等危险标志
       // 确保 replacement 不包含 \n（换行）等可能导致注入的序列
   }
   ```

2. **使用正式解析器**
   ```rust
   use nom::IResult;
   
   fn parse_sed_command(input: &str) -> IResult<&str, SedCommand> {
       // 使用 nom 解析器组合子
   }
   ```

3. **支持更多安全命令**
   ```rust
   enum SedCommand {
       PrintRange(LineRange),
       DeleteRange(LineRange),
       Quit(LineNumber),
       SafeSubstitution { pattern: String, replacement: String, flags: SafeFlags },
   }
   ```

4. **添加命令规范化**
   ```rust
   fn normalize(cmd: &str) -> String {
       cmd.trim().to_lowercase()
   }
   ```

5. **支持注释和文档**
   ```rust
   // 在策略文件中
   define_program(
       program="sed",
       args=[ARG_SED_COMMAND_WITH_COMMENT, ARG_RFILES],
       # ARG_SED_COMMAND_WITH_COMMENT 支持：
       # - 122,202p (打印范围)
       # - s/pattern/replacement/ (安全替换)
   )
   ```

6. **考虑使用白名单而非黑名单**
   ```rust
   static ALLOWED_COMMANDS: &[&str] = &[
       r"^\d+,\d+p$",           // 范围打印
       r"^\d+p$",               // 单行打印
       r"^s/[^/]+/[^/]*/g?$",   // 简单替换
   ];
   ```

7. **添加测试覆盖**
   ```rust
   #[test]
   fn test_edge_cases() {
       assert!(parse_sed_command("1,10p").is_ok());
       assert!(parse_sed_command("s/a/b/").is_err());
       assert!(parse_sed_command("s/a/b/e").is_err());  // 危险！
       assert!(parse_sed_command("122,202p ").is_err());  // 可能需要支持
   }
   ```
