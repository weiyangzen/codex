# valid_exec.rs 研究文档

## 场景与职责

`valid_exec.rs` 定义了策略验证成功后的输出类型。当 `Policy::check()` 成功匹配时，它返回描述已验证执行的详细信息，包括程序名、匹配的标志、选项和参数。

该模块的核心职责：
- 定义验证通过的执行调用表示（`ValidExec`）
- 定义匹配参数、选项和标志的类型
- 提供文件写入风险检测

## 功能点目的

### 1. ValidExec 结构体

表示已通过策略验证的执行调用：
```rust
pub struct ValidExec {
    pub program: String,              // 程序名称
    pub flags: Vec<MatchedFlag>,      // 匹配的无值选项
    pub opts: Vec<MatchedOpt>,        // 匹配的带值选项
    pub args: Vec<MatchedArg>,        // 匹配的位置参数
    pub system_path: Vec<String>,     // 可信系统路径列表
}
```

### 2. 匹配组件类型

**MatchedArg**: 位置参数匹配结果
```rust
pub struct MatchedArg {
    pub index: usize,        // 参数在原始命令行中的索引
    pub r#type: ArgType,     // 参数类型
    pub value: String,       // 参数值
}
```

**MatchedOpt**: 带值选项匹配结果
```rust
pub struct MatchedOpt {
    pub name: String,        // 选项名称
    pub value: String,       // 选项值
    pub r#type: ArgType,     // 值类型
}
```

**MatchedFlag**: 无值选项（标志）匹配结果
```rust
pub struct MatchedFlag {
    pub name: String,        // 标志名称
}
```

### 3. 文件写入风险检测

```rust
impl ValidExec {
    pub fn might_write_files(&self) -> bool {
        self.opts.iter().any(|opt| opt.r#type.might_write_file())
            || self.args.iter().any(|opt| opt.r#type.might_write_file())
    }
}
```

检查执行是否可能写入文件，用于区分 "safe" 和 "match" 输出。

## 具体技术实现

### ValidExec 结构体

```rust
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
pub struct ValidExec {
    pub program: String,
    pub flags: Vec<MatchedFlag>,
    pub opts: Vec<MatchedOpt>,
    pub args: Vec<MatchedArg>,
    pub system_path: Vec<String>,
}

impl ValidExec {
    pub fn new(program: &str, args: Vec<MatchedArg>, system_path: &[&str]) -> Self {
        Self {
            program: program.to_string(),
            flags: vec![],
            opts: vec![],
            args,
            system_path: system_path.iter().map(|&s| s.to_string()).collect(),
        }
    }

    pub fn might_write_files(&self) -> bool {
        self.opts.iter().any(|opt| opt.r#type.might_write_file())
            || self.args.iter().any(|opt| opt.r#type.might_write_file())
    }
}
```

### MatchedArg 实现

```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct MatchedArg {
    pub index: usize,
    pub r#type: ArgType,
    pub value: String,
}

impl MatchedArg {
    pub fn new(index: usize, r#type: ArgType, value: &str) -> Result<Self> {
        r#type.validate(value)?;
        Ok(Self {
            index,
            r#type,
            value: value.to_string(),
        })
    }
}
```

注意：`new()` 方法调用 `ArgType::validate()` 进行验证。

### MatchedOpt 实现

```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct MatchedOpt {
    pub name: String,
    pub value: String,
    pub r#type: ArgType,
}

impl MatchedOpt {
    pub fn new(name: &str, value: &str, r#type: ArgType) -> Result<Self> {
        r#type.validate(value)?;
        Ok(Self {
            name: name.to_string(),
            value: value.to_string(),
            r#type,
        }
    }

    pub fn name(&self) -> &str {
        &self.name
    }
}
```

### MatchedFlag 实现

```rust
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct MatchedFlag {
    pub name: String,
}

impl MatchedFlag {
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
        }
    }
}
```

## 关键代码路径与文件引用

### 当前文件关键位置
- 行 6-37: `ValidExec` 结构体和方法
- 行 39-55: `MatchedArg` 结构体和方法
- 行 57-81: `MatchedOpt` 结构体和方法
- 行 83-95: `MatchedFlag` 结构体和方法

### 调用关系

**被调用方**:
- `program.rs:181-186`: `ProgramSpec::check()` 构建 `ValidExec`
- `arg_resolver.rs`: `MatchedArg::new()` 创建匹配参数
- `main.rs`: `Output::Safe`/`Output::Match` 包含 `ValidExec`
- `execv_checker.rs`: 运行时检查使用 `ValidExec`

**调用方**:
- `arg_type.rs`: `ArgType::validate()` 和 `might_write_file()`

### 数据流
```
ProgramSpec::check()
  -> 解析选项和参数
    -> MatchedFlag::new()
    -> MatchedOpt::new() -> ArgType::validate()
    -> MatchedArg::new() -> ArgType::validate()
  -> ValidExec { program, flags, opts, args, system_path }
    -> ValidExec::might_write_files()
      -> 用于决定 Output::Safe vs Output::Match
```

## 依赖与外部交互

### 外部 crate 依赖
- `serde`: 序列化支持

### 内部模块依赖
- `arg_type.rs`: `ArgType`
- `error.rs`: `Result`

## 风险、边界与改进建议

### 当前限制与风险

1. **序列化字段名**
   - 使用 `r#type` 作为字段名（Rust 保留字转义）
   - 在 JSON 中序列化为 `type`，可能与 JSON 关键字冲突
   - 虽然 serde 处理正确，但可能令人困惑

2. **索引语义**
   - `MatchedArg.index` 是原始命令行中的索引
   - 但 `MatchedOpt` 和 `MatchedFlag` 没有索引
   - 不一致可能导致混淆

3. **缺少原始参数引用**
   - 不保存对原始 `ExecCall` 的引用
   - 无法追溯验证结果的来源

4. **system_path 的用途不明确**
   - 存储可信路径，但 `ValidExec` 本身不验证可执行性
   - 验证在 `ExecvChecker::check()` 中进行

5. **Default 实现的陷阱**
   - `ValidExec` 派生 `Default`，但空值可能无效
   - 例如 `program: ""` 不是有效的程序名

### 边界情况

| 场景 | 当前行为 | 说明 |
|------|----------|------|
| 空 `args` | 允许 | 如 `pwd` 命令 |
| 空 `flags` 和 `opts` | 允许 | 常见情况 |
| 重复 `flags` | 允许 | 存储多个相同标志 |
| 非常大的 `args` | 正常处理 | 内存使用线性增长 |

### 改进建议

1. **统一索引**
   ```rust
   pub struct MatchedFlag {
       pub index: usize,  // 添加索引
       pub name: String,
   }
   
   pub struct MatchedOpt {
       pub index: usize,  // 选项位置
       pub name: String,
       pub value_index: usize,  // 值的位置
       pub value: String,
       pub r#type: ArgType,
   }
   ```

2. **保留原始调用引用**
   ```rust
   pub struct ValidExec {
       pub original_call: ExecCall,  // 或 Arc<ExecCall>
       // ...
   }
   ```

3. **添加验证方法**
   ```rust
   impl ValidExec {
       pub fn validate(&self) -> Result<()> {
           if self.program.is_empty() {
               return Err(Error::InvalidValidExec("empty program name"));
           }
           // 验证索引连续性等
           Ok(())
       }
   }
   ```

4. **改进序列化**
   ```rust
   #[derive(Serialize)]
   pub struct ValidExec {
       pub program: String,
       #[serde(rename = "flags")]
       pub matched_flags: Vec<MatchedFlag>,
       #[serde(rename = "options")]
       pub matched_opts: Vec<MatchedOpt>,
       #[serde(rename = "arguments")]
       pub matched_args: Vec<MatchedArg>,
       #[serde(rename = "systemPaths")]
       pub system_path: Vec<String>,
   }
   ```

5. **添加便利方法**
   ```rust
   impl ValidExec {
       pub fn get_arg(&self, index: usize) -> Option<&MatchedArg> {
           self.args.iter().find(|a| a.index == index)
       }
       
       pub fn get_opt(&self, name: &str) -> Option<&MatchedOpt> {
           self.opts.iter().find(|o| o.name == name)
       }
       
       pub fn has_flag(&self, name: &str) -> bool {
           self.flags.iter().any(|f| f.name == name)
       }
   }
   ```

6. **不可变构建器模式**
   ```rust
   pub struct ValidExecBuilder {
       program: String,
       flags: Vec<MatchedFlag>,
       // ...
   }
   
   impl ValidExecBuilder {
       pub fn with_flag(mut self, flag: MatchedFlag) -> Self {
           self.flags.push(flag);
           self
       }
       
       pub fn build(self) -> Result<ValidExec> {
           // 验证并构建
       }
   }
   ```

7. **添加统计信息**
   ```rust
   pub struct ValidExecStats {
       pub total_args: usize,
       pub file_args: usize,
       pub writeable_file_args: usize,
   }
   
   impl ValidExec {
       pub fn stats(&self) -> ValidExecStats { ... }
   }
   ```
