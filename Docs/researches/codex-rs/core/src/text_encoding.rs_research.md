# text_encoding.rs 研究文档

## 场景与职责

`text_encoding.rs` 是 Codex Core 模块中负责 Shell 输出文本编码检测与转换的工具模块。它解决 Windows 用户在 VS Code 等环境中遇到的非 UTF-8 编码问题（如 CP1251、CP866 等代码页）。

**背景问题：**
- Windows 命令行经常使用遗留代码页（如 CP1251 俄语、CP866 俄语 DOS）
- 这些字节在 UTF-8 中显示为无效字符，被替换为 Unicode 替换字符（�）
- 用户无法正确查看 shell 输出

**解决方案：**
- 使用 `chardetng` 进行编码检测
- 使用 `encoding_rs` 进行解码
- 针对 Windows-1252 智能标点的特殊启发式处理

## 功能点目的

### 1. 智能字节到字符串转换

```rust
pub fn bytes_to_string_smart(bytes: &[u8]) -> String
```

**核心流程：**
1. **空输入快速返回** - 空字节返回空字符串
2. **UTF-8 快速路径** - 有效 UTF-8 直接返回，避免额外处理
3. **编码检测** - 使用 `chardetng` 检测编码
4. **解码** - 使用检测到的编码解码字节
5. **错误回退** - 解码失败时回退到 lossy UTF-8

### 2. 编码检测与启发式修正

```rust
fn detect_encoding(bytes: &[u8]) -> &'static Encoding
```

**chardetng 检测：**
- 使用 `EncodingDetector` 分析字节序列
- 返回检测到的编码和置信度

**IBM866 → Windows-1252 启发式：**

问题背景：
- Windows-1252 在 0x80-0x9F 范围使用智能标点（弯引号、破折号、™）
- IBM866 在相同字节范围使用西里尔字母大写
- chardetng 对短字符串可能误判为 IBM866

解决方案：
```rust
if encoding == IBM866 && looks_like_windows_1252_punctuation(bytes) {
    return WINDOWS_1252;
}
```

### 3. Windows-1252 标点启发式

```rust
fn looks_like_windows_1252_punctuation(bytes: &[u8]) -> bool
```

**判定条件：**
1. 所有高字节（0x80-0x9F）必须是 Windows-1252 标点
2. 必须包含 ASCII 字母（证明是文本而非二进制）
3. 不包含 0xA0 以上字节（避免其他 Unicode 范围）

**Windows-1252 标点字节：**
```rust
const WINDOWS_1252_PUNCT_BYTES: [u8; 8] = [
    0x91, // ' 左单引号
    0x92, // ' 右单引号
    0x93, // " 左双引号
    0x94, // " 右双引号
    0x95, // • 项目符号
    0x96, // – 短破折号
    0x97, // — 长破折号
    0x99, // ™ 商标符号
];
```

### 4. 字节解码

```rust
fn decode_bytes(bytes: &[u8], encoding: &'static Encoding) -> String
```

**处理流程：**
1. 使用 `encoding.decode()` 解码
2. 如果有错误，回退到 `String::from_utf8_lossy()`
3. 成功则返回解码后的字符串

## 具体技术实现

### 关键数据结构

```rust
// Windows-1252 智能标点字节表
const WINDOWS_1252_PUNCT_BYTES: [u8; 8] = [...];
```

### 编码检测流程

```
bytes_to_string_smart(bytes)
    ├── bytes.is_empty() → return ""
    ├── std::str::from_utf8(bytes).ok() → return utf8_str
    ├── detect_encoding(bytes)
    │   ├── EncodingDetector::new()
    │   ├── detector.feed(bytes, true)
    │   ├── detector.guess_assess(None, true)
    │   ├── if encoding == IBM866 && looks_like_windows_1252_punctuation(bytes)
    │   │   └── return WINDOWS_1252
    │   └── return encoding
    └── decode_bytes(bytes, encoding)
        ├── encoding.decode(bytes)
        ├── if had_errors → String::from_utf8_lossy(bytes)
        └── return decoded
```

### 启发式算法详解

```rust
fn looks_like_windows_1252_punctuation(bytes: &[u8]) -> bool {
    let mut saw_extended_punctuation = false;
    let mut saw_ascii_word = false;

    for &byte in bytes {
        // 排除 0xA0 以上字节
        if byte >= 0xA0 {
            return false;
        }
        // 检查 0x80-0x9F 范围
        if (0x80..=0x9F).contains(&byte) {
            if !is_windows_1252_punct(byte) {
                return false;  // 非标点字节，可能是西里尔字母
            }
            saw_extended_punctuation = true;
        }
        // 检查 ASCII 字母
        if byte.is_ascii_alphabetic() {
            saw_ascii_word = true;
        }
    }

    saw_extended_punctuation && saw_ascii_word
}
```

**设计权衡：**
- 不限制标点字节数量：VS Code 常输出多个引用短语（如 `"foo" – "bar"`）
- 必须同时满足：有标点字节 + 有 ASCII 字母
- 避免误伤：合法的 IBM866 西里尔文本（如 `ПРИ test`）会通过 ASCII 字母检测

## 关键代码路径与文件引用

### 核心函数

| 函数 | 行号 | 用途 |
|------|------|------|
| `bytes_to_string_smart` | 15-26 | 公共 API，智能转换 |
| `detect_encoding` | 49-68 | 编码检测 + 启发式修正 |
| `looks_like_windows_1252_punctuation` | 93-113 | Windows-1252 启发式 |
| `is_windows_1252_punct` | 115-117 | 标点字节检查 |
| `decode_bytes` | 70-78 | 字节解码 |

### 依赖关系

**被调用方（上游）：**
- `crate::shell` - Shell 输出处理
- `crate::process` - 进程输出解码
- 任何需要解码外部命令输出的模块

**调用方（下游）：**
- `chardetng::EncodingDetector` - 编码检测
- `encoding_rs` - 编码解码

### 外部 Crate 依赖

```rust
use chardetng::EncodingDetector;
use encoding_rs::Encoding;
use encoding_rs::IBM866;
use encoding_rs::WINDOWS_1252;
```

| Crate | 用途 |
|-------|------|
| `chardetng` | Mozilla 的编码检测库，基于统计机器学习 |
| `encoding_rs` | 高性能编码转换，支持 40+ 编码 |

## 依赖与外部交互

### 编码支持

通过 `encoding_rs` 支持的编码：
- UTF-8（快速路径）
- Windows 系列：Windows-1250 到 Windows-1258、Windows-874
- ISO-8859 系列：ISO-8859-1 到 ISO-8859-10、ISO-8859-13
- 东亚编码：Shift_JIS、GBK、EUC-KR、Big5
- 遗留编码：IBM866、KOI8-R 等

### 性能特性

1. **UTF-8 快速路径**
   - 大多数现代工具输出 UTF-8
   - 避免编码检测开销

2. **零拷贝优化**
   - `encoding_rs` 在可能时使用零拷贝解码
   - 仅在编码转换时需要分配

3. **启发式短路**
   - IBM866 检测后才执行启发式检查
   - 常见编码（UTF-8、Windows-1252）无额外开销

## 风险、边界与改进建议

### 已知风险

1. **编码检测误判**
   - chardetng 对短字符串（<100 字节）置信度较低
   - 启发式可能错误地将西里尔文本识别为 Windows-1252
   - 缓解：启发式要求同时存在 ASCII 字母

2. **性能开销**
   - 编码检测需要遍历字节序列
   - 大输出（如 `cat large.log`）可能有明显延迟
   - 缓解：UTF-8 快速路径避免检测

3. **编码覆盖不全**
   - 某些遗留编码（如 EBCDIC）不支持
   - 某些地区特定编码可能检测失败

### 边界情况

1. **混合编码**
   - 单字节流中包含多种编码的字节
   - 检测结果不确定，可能产生乱码

2. **二进制数据**
   - 非文本字节流（如图片、可执行文件）
   - 可能误判为某种编码，产生无意义输出
   - 当前无二进制检测机制

3. **空输入**
   - 空字节数组快速返回空字符串
   - 无编码检测开销

4. **纯标点输入**
   - `"test"`（仅引号 + ASCII）
   - 启发式通过，正确识别为 Windows-1252

5. **纯西里尔输入**
   - `ПРИ`（仅 IBM866 西里尔字母）
   - 无 ASCII 字母，启发式失败，保留 IBM866

### 改进建议

1. **置信度阈值**
   ```rust
   fn detect_encoding(bytes: &[u8]) -> Option<&'static Encoding> {
       let (encoding, confidence) = detector.guess_assess(None, true);
       if confidence < 0.5 {
           return None;  // 不确定时返回 None，调用方决定回退
       }
       Some(encoding)
   }
   ```

2. **二进制检测**
   ```rust
   fn is_likely_binary(bytes: &[u8]) -> bool {
       // 检查空字节比例、控制字符等
       bytes.iter().filter(|&&b| b == 0).count() > bytes.len() / 10
   }
   ```

3. **缓存编码结果**
   ```rust
   // 对同一来源的连续输出使用相同编码
   struct EncodingCache {
       source_hash: u64,
       encoding: &'static Encoding,
   }
   ```

4. **用户覆盖**
   ```rust
   // 允许用户强制指定编码
   if let Ok(forced) = env::var("CODEX_SHELL_ENCODING") {
       return decode_with_encoding(bytes, &forced);
   }
   ```

5. **更多启发式**
   ```rust
   // 针对其他编码碰撞的启发式
   fn looks_like_shift_jis(bytes: &[u8]) -> bool { ... }
   fn looks_like_gbk(bytes: &[u8]) -> bool { ... }
   ```

6. **性能优化**
   ```rust
   // 大输出分块处理
   const CHUNK_SIZE: usize = 8192;
   for chunk in bytes.chunks(CHUNK_SIZE) {
       // 检测并解码分块
   }
   ```

### 测试文件

- `src/text_encoding_tests.rs` - 全面覆盖 30+ 编码的测试
