# text_encoding_tests.rs 研究文档

## 场景与职责

`text_encoding_tests.rs` 是 `text_encoding.rs` 的全面单元测试模块，覆盖 30+ 种字符编码的检测和解码验证。测试确保 `bytes_to_string_smart` 函数能够正确处理各种遗留编码和边缘情况。

**测试范围：**
- UTF-8 快速路径
- Windows 代码页（CP1250-CP1258、CP874、CP932、CP936、CP949、CP950）
- ISO-8859 系列（Latin-1 到 Latin-10、Latin-13）
- 遗留俄语编码（CP1251、CP866、KOI8-R）
- 东亚编码（Shift_JIS、GBK、EUC-KR、Big5）
- Windows-1252 智能标点启发式
- ANSI 转义序列保留
- 无效序列回退

## 功能点目的

### 1. UTF-8 快速路径验证

```rust
#[test]
fn test_utf8_passthrough()
```

验证当输入为有效 UTF-8 时，函数直接返回而不进行编码检测，确保性能优化有效。

**测试数据：** `"Hello, мир! 世界"`（混合 ASCII、西里尔、CJK）

### 2. 俄语编码测试

覆盖三种常见的俄语遗留编码：

| 编码 | 测试函数 | 示例文本 |
|------|---------|---------|
| Windows-1251 | `test_cp1251_russian_text` | "пример" |
| Windows-1251 | `test_cp1251_privet_word` | "Привет" |
| KOI8-R | `test_koi8_r_privet_word` | "Привет" |
| CP866 | `test_cp866_russian_text` | "пример" |
| CP866 | `test_cp866_uppercase_text` | "ПРИ" |
| CP866 | `test_cp866_uppercase_followed_by_ascii` | "ПРИ test" |

**特殊关注：** `test_cp866_uppercase_followed_by_ascii` 验证启发式不会错误地将合法的 IBM866 西里尔文本识别为 Windows-1252。

### 3. Windows-1252 智能标点测试

```rust
#[test]
fn test_windows_1252_quotes()
#[test]
fn test_windows_1252_multiple_quotes()
```

验证启发式正确识别 Windows-1252 智能标点：
- `\x93\x94test` → `""test`（弯引号）
- `"foo" – "bar"` 模式正确处理多个引用短语

### 4. ISO-8859 系列测试

| 编码 | 测试函数 | 语言/区域 |
|------|---------|----------|
| ISO-8859-1 | `test_iso8859_1_latin_text` | 西欧（与 Windows-1252 统一） |
| ISO-8859-2 | `test_iso8859_2_central_european_text` | 中欧（捷克语 "Příliš žluťoučký kůň"） |
| ISO-8859-3 | `test_iso8859_3_south_europe_text` | 南欧（马耳他语/世界语） |
| ISO-8859-4 | `test_iso8859_4_baltic_text` | 波罗的海 |
| ISO-8859-5 | `test_iso8859_5_cyrillic_text` | 西里尔（俄语 "Привет"） |
| ISO-8859-6 | `test_iso8859_6_arabic_text` | 阿拉伯语 "مرحبا" |
| ISO-8859-7 | `test_iso8859_7_greek_text` | 希腊语 "Καλημέρα" |
| ISO-8859-8 | `test_iso8859_8_hebrew_text` | 希伯来语 "שלום" |
| ISO-8859-9 | `test_iso8859_9_turkish_text` | 土耳其语 "İstanbul" |
| ISO-8859-10 | `test_iso8859_10_nordic_text` | 北欧 |
| ISO-8859-11 | `test_iso8859_11_thai_text` | 泰语（通过 Windows-874） |
| ISO-8859-13 | `test_iso8859_13_baltic_text` | 波罗的海 "Sveiki" |

**注意：** ISO-8859-12 从未标准化，ISO-8859-14 到 16 因检测不可靠被故意省略。

### 5. Windows 代码页测试

| 代码页 | 测试函数 | 语言 |
|--------|---------|------|
| Windows-1250 | `test_windows_1250_central_european_text` | 中欧 |
| Windows-1251 | `test_windows_1251_encoded_text` | 西里尔 |
| Windows-1253 | `test_windows_1253_greek_text` | 希腊 |
| Windows-1254 | `test_windows_1254_turkish_text` | 土耳其 |
| Windows-1255 | `test_windows_1255_hebrew_text` | 希伯来 |
| Windows-1256 | `test_windows_1256_arabic_text` | 阿拉伯 |
| Windows-1257 | `test_windows_1257_baltic_text` | 波罗的海 |
| Windows-1258 | `test_windows_1258_vietnamese_text` | 越南语 "Xin chào" |
| Windows-874 | `test_windows_874_thai_text` | 泰语 |

### 6. 东亚编码测试

| 编码 | 测试函数 | 语言/示例 |
|------|---------|----------|
| Shift_JIS | `test_windows_932_shift_jis_text` | 日语 "こんにちは" |
| GBK | `test_windows_936_gbk_text` | 简体中文 "你好，世界..." |
| EUC-KR | `test_windows_949_korean_text` | 韩语 "안녕하세요" |
| Big5 | `test_windows_950_big5_text` | 繁体中文 "繁體" |

### 7. 边界情况测试

```rust
#[test]
fn test_latin1_cafe()
```
验证 Latin-1 字节 `caf\xE9` → `"café"`

```rust
#[test]
fn test_preserves_ansi_sequences()
```
验证 ANSI 转义序列 `\x1b[31mred\x1b[0m` 被保留，不受编码检测影响。

```rust
#[test]
fn test_fallback_to_lossy()
```
验证完全无效序列 `[0xFF, 0xFE, 0xFD]` 回退到 `String::from_utf8_lossy`，产生替换字符。

```rust
#[test]
fn test_windows_1252_privet_gibberish_is_preserved()
```
验证当输入字面包含 Windows-1252 无法编码的字符（如 UTF-8 的 "Привет" 被错误解释为 Windows-1252 产生的乱码）时，不尝试"修复"，保留原始乱码。

## 具体技术实现

### 测试辅助

所有测试直接使用 `bytes_to_string_smart` 公共 API，无内部函数测试。

### 编码构造

使用 `encoding_rs` 的 `encode` 方法构造测试字节：

```rust
let (encoded, _, had_errors) = WINDOWS_1251.encode("Привет из Windows-1251");
assert!(!had_errors, "failed to encode Windows-1251 sample");
assert_eq!(
    bytes_to_string_smart(encoded.as_ref()),
    "Привет из Windows-1251"
);
```

### 硬编码字节

对于特定编码测试，使用硬编码字节确保测试独立性：

```rust
// "пример" encoded with Windows-1251
let bytes = b"\xEF\xF0\xE8\xEC\xE5\xF0";
assert_eq!(bytes_to_string_smart(bytes), "пример");
```

## 关键代码路径与文件引用

### 被测函数

| 函数 | 定义位置 | 测试覆盖 |
|------|---------|---------|
| `bytes_to_string_smart` | `text_encoding.rs:15-26` | 全部测试 |
| `detect_encoding` | `text_encoding.rs:49-68` | 间接测试 |
| `looks_like_windows_1252_punctuation` | `text_encoding.rs:93-113` | Windows-1252 测试 |
| `decode_bytes` | `text_encoding.rs:70-78` | 全部测试 |

### 测试依赖

```rust
use super::*;
use encoding_rs::*;  // 各种编码常量
use pretty_assertions::assert_eq;
```

### 编码常量

测试导入的 `encoding_rs` 编码：
- `BIG5`, `EUC_KR`, `GBK`, `SHIFT_JIS`
- `ISO_8859_2` 到 `ISO_8859_10`, `ISO_8859_13`
- `WINDOWS_874`, `WINDOWS_1250` 到 `WINDOWS_1258`

## 依赖与外部交互

### 测试框架

- `#[test]` - 标准测试属性
- `pretty_assertions::assert_eq` - 美观的差异输出

### 编码库

- `encoding_rs` - 测试数据编码构造
- `chardetng` - 被测代码使用（测试中不直接使用）

### 测试数据

- 多语言样本文本（俄语、希腊语、阿拉伯语、希伯来语、泰语、日语、韩语、中文）
- 硬编码字节序列（确保测试可重复）

## 风险、边界与改进建议

### 测试覆盖分析

| 功能 | 覆盖状态 | 备注 |
|------|---------|------|
| UTF-8 快速路径 | ✅ 完整 | `test_utf8_passthrough` |
| Windows 代码页 | ✅ 完整 | 1250-1258、874、932、936、949、950 |
| ISO-8859 系列 | ⚠️ 部分 | 1-10、13 覆盖，12 不存在，14-16 故意省略 |
| 遗留俄语编码 | ✅ 完整 | 1251、866、KOI8-R |
| 东亚编码 | ✅ 完整 | Shift_JIS、GBK、EUC-KR、Big5 |
| Windows-1252 启发式 | ✅ 完整 | 单/多引号测试 |
| ANSI 序列保留 | ✅ 完整 | `test_preserves_ansi_sequences` |
| 无效序列回退 | ✅ 完整 | `test_fallback_to_lossy` |
| 空输入 | ❌ 缺失 | 未显式测试 `&[]` |
| 大输入性能 | ❌ 缺失 | 无大文件测试 |
| 混合编码 | ❌ 缺失 | 无混合编码测试 |
| 二进制数据 | ❌ 缺失 | 无二进制检测测试 |

### 改进建议

1. **添加空输入测试**
   ```rust
   #[test]
   fn test_empty_input() {
       assert_eq!(bytes_to_string_smart(&[]), "");
   }
   ```

2. **添加大输入性能测试**
   ```rust
   #[test]
   fn test_large_input_performance() {
       let large = vec![b'x'; 10_000_000];  // 10MB
       let start = Instant::now();
       let _ = bytes_to_string_smart(&large);
       assert!(start.elapsed() < Duration::from_secs(1));
   }
   ```

3. **添加混合编码测试**
   ```rust
   #[test]
   fn test_mixed_encoding() {
       // UTF-8 前缀 + Windows-1251 后缀
       let mixed = b"Hello \xEF\xF0\xE8\xE2\xE5\xF2";
       // 验证行为（可能是部分解码或回退）
   }
   ```

4. **添加边界字节测试**
   ```rust
   #[test]
   fn test_boundary_bytes() {
       // 0x7F (DEL), 0x80-0x9F 边界
       let bytes = b"\x7F\x80\x9F";
       let _ = bytes_to_string_smart(bytes);
   }
   ```

5. **添加并发测试**
   ```rust
   #[test]
   fn test_concurrent_decoding() {
       // 验证线程安全
       std::thread::scope(|s| {
           for _ in 0..10 {
               s.spawn(|| {
                   bytes_to_string_smart(b"\xEF\xF0\xE8\xEC\xE5\xF0");
               });
           }
       });
   }
   ```

6. **添加模糊测试**
   ```rust
   use arbitrary::Arbitrary;
   
   #[test]
   fn test_arbitrary_bytes() {
       // 使用 fuzzing 生成随机字节序列
       // 验证不 panic，返回有效字符串
   }
   ```

### 潜在问题

1. **测试数据硬编码**
   - 字节序列如 `b"\xEF\xF0\xE8\xEC\xE5\xF0"` 无注释说明
   - 建议：添加注释说明原始文本和编码

2. **编码假设**
   - 假设 `encoding_rs` 的编码行为正确
   - 建议：添加测试验证编码库行为符合预期

3. **平台差异**
   - 某些编码在不同平台可能有差异
   - 建议：在 CI 中测试多个平台

4. **测试重复**
   - Windows-1251 和 ISO-8859-5 都测试俄语，可能冗余
   - 建议：明确每个测试的独特价值
