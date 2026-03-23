# text_encoding_fix.rs 研究文档

## 场景与职责

`text_encoding_fix.rs` 是 Codex Core 的单元测试套件，专注于验证 shell 输出文本编码修复功能。该测试确保 Codex 能够正确检测和转换各种遗留编码（如 Windows CP1251、CP866）的 shell 输出，解决 issue #6178 中报告的文本乱码问题。

### 核心职责
1. **编码检测验证**：验证 `chardetng` 能够正确检测各种编码
2. **智能解码验证**：验证 `bytes_to_string_smart` 函数正确转换字节到 UTF-8
3. **边界情况处理**：验证混合 ASCII 和遗留编码、纯 Latin-1 等场景
4. **回归防护**：验证修复不会破坏原有的 `String::from_utf8_lossy` 行为

## 功能点目的

### 1. UTF-8 基线测试 (`test_utf8_shell_output`)
- **目的**：验证 UTF-8 输出能够正确通过，无需额外转换
- **测试内容**：俄语文本 "пример"（示例）
- **预期行为**：直接返回原始 UTF-8 字符串

### 2. CP1251 解码测试 (`test_cp1251_shell_output`)
- **目的**：验证 Windows CP1251 编码（西里尔字母）正确解码
- **测试内容**：`\xEF\xF0\xE8\xEC\xE5\xF2` -> "пример"
- **场景**：VS Code shell 在 Windows 上频繁使用 CP1251

### 3. CP866 解码测试 (`test_cp866_shell_output`)
- **目的**：验证 CP866 编码（俄语文本）正确解码
- **测试内容**：`\xAF\xE0\xA8\xAC\xA5\xE0` -> "пример"
- **场景**：原生 cmd.exe 默认使用 CP866

### 4. Windows-1252 智能解码 (`test_windows_1252_smart_decoding`)
- **目的**：验证 Windows-1252 "智能标点"正确解码
- **测试内容**：`\x93\x94 test \x96 dash` -> `"" test – dash`
- **场景**：智能引号和破折号转换

### 5. 智能解码优于 Lossy (`test_smart_decoding_improves_over_lossy_utf8`)
- **目的**：验证智能解码比 `String::from_utf8_lossy` 更好
- **验证点**：
  - `String::from_utf8_lossy` 产生替换字符 (`\u{FFFD}`)
  - 智能解码保留原始标点符号

### 6. 混合编码测试 (`test_mixed_ascii_and_legacy_encoding`)
- **目的**：验证 ASCII 和 Latin-1 混合内容正确解码
- **测试内容**：`"Output: caf\xE9"` -> "Output: café"
- **场景**：命令状态文本混合 Latin-1 字节

### 7. 纯 Latin-1 测试 (`test_pure_latin1_shell_output`)
- **目的**：验证纯 Latin-1 内容正确解码
- **测试内容**：`"caf\xE9"` -> "café"
- **场景**：回归覆盖旧测试

### 8. 无效字节回退 (`test_invalid_bytes_still_fall_back_to_lossy`)
- **目的**：验证检测失败时回退到 lossy 解码
- **测试内容**：`\xFF\xFE\xFD` -> 使用 `String::from_utf8_lossy`
- **场景**：完全无法识别的字节序列

## 具体技术实现

### 测试辅助函数
```rust
fn decode_shell_output(bytes: &[u8]) -> String {
    StreamOutput {
        text: bytes.to_vec(),
        truncated_after_lines: None,
    }
    .from_utf8_lossy()
    .text
}
```

### StreamOutput 结构
```rust
// codex-rs/core/src/exec.rs
pub struct StreamOutput<T: Clone> {
    pub text: T,
    pub truncated_after_lines: Option<u32>,
}

impl StreamOutput<Vec<u8>> {
    pub fn from_utf8_lossy(&self) -> StreamOutput<String> {
        StreamOutput {
            text: bytes_to_string_smart(&self.text),
            truncated_after_lines: self.truncated_after_lines,
        }
    }
}
```

### 智能解码实现 (`text_encoding.rs`)
```rust
pub fn bytes_to_string_smart(bytes: &[u8]) -> String {
    if bytes.is_empty() {
        return String::new();
    }

    // 1. 首先尝试 UTF-8
    if let Ok(utf8_str) = std::str::from_utf8(bytes) {
        return utf8_str.to_owned();
    }

    // 2. 检测编码
    let encoding = detect_encoding(bytes);
    
    // 3. 解码字节
    decode_bytes(bytes, encoding)
}

fn detect_encoding(bytes: &[u8]) -> &'static Encoding {
    let mut detector = EncodingDetector::new();
    detector.feed(bytes, true);
    let (encoding, _is_confident) = detector.guess_assess(None, true);

    // 特殊处理：IBM866 可能被误判为 Windows-1252 标点
    if encoding == IBM866 && looks_like_windows_1252_punctuation(bytes) {
        return WINDOWS_1252;
    }

    encoding
}
```

### Windows-1252 标点检测
```rust
const WINDOWS_1252_PUNCT_BYTES: [u8; 8] = [
    0x91, // ' (左单引号)
    0x92, // ' (右单引号)
    0x93, // " (左双引号)
    0x94, // " (右双引号)
    0x95, // • (项目符号)
    0x96, // – (短破折号)
    0x97, // — (长破折号)
    0x99, // ™ (商标符号)
];

fn looks_like_windows_1252_punctuation(bytes: &[u8]) -> bool {
    let mut saw_extended_punctuation = false;
    let mut saw_ascii_word = false;

    for &byte in bytes {
        if byte >= 0xA0 {
            return false;
        }
        if (0x80..=0x9F).contains(&byte) {
            if !is_windows_1252_punct(byte) {
                return false;
            }
            saw_extended_punctuation = true;
        }
        if byte.is_ascii_alphabetic() {
            saw_ascii_word = true;
        }
    }

    saw_extended_punctuation && saw_ascii_word
}
```

## 关键代码路径与文件引用

### 被测代码路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/text_encoding.rs` | 文本编码检测和转换核心实现 |
| `codex-rs/core/src/exec.rs` | `StreamOutput` 和 `from_utf8_lossy` 实现 |
| `codex-rs/core/src/text_encoding_tests.rs` | 单元测试（内部模块） |

### 外部依赖
| Crate | 用途 |
|-------|------|
| `chardetng` | 字符编码检测 |
| `encoding_rs` | 编码转换（支持 IBM866、WINDOWS_1252 等） |

### 关键类型引用
```rust
// encoding_rs
pub struct Encoding; // 编码定义
pub static IBM866: &'static Encoding; // CP866
pub static WINDOWS_1252: &'static Encoding; // CP1252

// chardetng
pub struct EncodingDetector;
impl EncodingDetector {
    pub fn new() -> Self;
    pub fn feed(&mut self, bytes: &[u8], last: bool);
    pub fn guess_assess(&self, tld: Option<&str>, allow_utf8: bool) -> (&'static Encoding, bool);
}
```

## 依赖与外部交互

### 外部依赖
1. **chardetng**: Mozilla 的字符编码检测库
2. **encoding_rs**: 高性能编码转换库
3. **pretty_assertions**: 测试断言美化

### 内部依赖
1. **codex_core**: 提供 `StreamOutput` 和 `exec` 模块

### 测试特性
- `#[test]`: 标准单元测试（非异步）
- 无网络依赖，可在任何环境运行

## 风险、边界与改进建议

### 已知风险
1. **编码检测不确定性**：`chardetng` 的检测基于启发式，可能误判
2. **短文本检测困难**：非常短的文本（如单个字符）检测准确率下降
3. **IBM866/Windows-1252 冲突**：两个编码在 0x80-0x9F 范围有重叠

### 边界情况
1. **空字节**：`bytes_to_string_smart` 正确处理空输入
2. **纯 ASCII**：快速路径直接返回，无需检测
3. **混合编码**：当前实现选择单一编码，可能无法处理一行内混合多种编码

### 改进建议
1. **更多编码覆盖**：添加 GBK、Big5、Shift_JIS 等亚洲编码测试
2. **性能基准**：添加编码检测和解码的性能基准测试
3. **置信度阈值**：考虑使用检测置信度决定是否使用检测结果
4. **逐行处理**：对于长输出，考虑逐行检测编码
5. **用户覆盖**：提供配置选项允许用户指定默认编码

### 潜在缺陷
1. **无 BOM 处理**：未测试 UTF-16 BOM 或 UTF-8 BOM 场景
2. **二进制数据**：二进制数据可能产生无意义的解码结果
3. **编码回退链**：当前只有单层回退（检测失败 -> lossy），可考虑多级回退

### 相关代码
- `codex-rs/core/src/exec.rs:682-688`: `StreamOutput::from_utf8_lossy`
- `codex-rs/core/src/text_encoding.rs:15-26`: `bytes_to_string_smart`
- `codex-rs/core/src/text_encoding.rs:49-68`: `detect_encoding`
