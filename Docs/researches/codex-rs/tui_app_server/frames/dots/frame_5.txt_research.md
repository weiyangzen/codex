# frame_5.txt 研究文档

## 场景与职责

`frame_5.txt` 是 Codex TUI 应用服务器的 ASCII 艺术动画帧文件，属于 `dots` 动画变体系列中的第五帧。该文件是 36 帧循环动画序列的重要组成部分，通过点阵图案的渐进变化提供流畅的视觉体验。

## 功能点目的

1. **动画中间帧**：作为第 5 帧，处于动画序列的早期阶段，建立视觉基调
2. **图案演变**：展示点阵从初始状态向中间状态的过渡
3. **视觉一致性**：确保整个 2.88 秒动画周期的视觉连贯性

## 具体技术实现

### 技术规格
- **帧索引**：4（从 0 开始计数）
- **显示时段**：320ms ~ 400ms（80ms × 4）
- **文件大小**：约 1.1KB

### 字符分布分析

frame_5 的字符使用模式：
```
○ (白色圆圈): ~40% - 背景填充
● (黑色圆圈): ~35% - 主要图案
◉ (靶心圆圈): ~15% - 视觉焦点
· (中间点):   ~10% - 过渡/细节
```

### 图案结构

```
第 1 行: 空白边距
第 2 行: ○◉○◉◉●○○○●●○  (顶部装饰)
第 3-6 行: 上部点阵，密度逐渐增加
第 7-12 行: 中部主体，不规则分布
第 13-16 行: 底部图案，右侧聚集
第 17 行: 空白边距
```

## 关键代码路径与文件引用

### 核心代码位置

```rust
// codex-rs/tui_app_server/src/frames.rs
pub(crate) const FRAMES_DOTS: [&str; 36] = frames_for!("dots");
// frame_5 对应数组索引 4
```

### 访问路径详解

```
应用启动
    ↓
frames.rs 编译时嵌入 frame_5.txt
    ↓
FRAMES_DOTS 常量初始化
    ↓
AsciiAnimation 实例化（可选变体）
    ↓
current_frame() 根据时间计算索引
    ↓
索引 4 → 返回 FRAMES_DOTS[4]（frame_5 内容）
    ↓
渲染到终端
```

### 相关代码文件

| 文件 | 行号 | 作用 |
|------|------|------|
| frames.rs | 11 | include_str! 嵌入 frame_5.txt |
| ascii_animation.rs | 65-76 | current_frame() 方法 |
| welcome.rs | 82 | 欢迎界面渲染调用 |

## 依赖与外部交互

### 编译依赖
- Rust 编译器的 `include_str!` 宏
- 文件系统路径：`frames/dots/frame_5.txt`

### 运行时依赖
- `std::time::{Duration, Instant}`
- `ratatui` 渲染库

### 数据流
```
frame_5.txt (源文件)
    ↓ 编译时
FRAMES_DOTS[4] (&str)
    ↓ 运行时引用
AsciiAnimation::current_frame() → &str
    ↓ 渲染
ratatui::text::Text → Terminal
```

## 风险、边界与改进建议

### 风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| 文件损坏 | 低 | 高 | 版本控制 + CI 检查 |
| 编码错误 | 低 | 中 | 强制 UTF-8 |
| 尺寸不一致 | 中 | 高 | 自动化验证 |

### 边界条件

1. **时间计算溢出**：
   ```rust
   // ascii_animation.rs 中的保护
   let elapsed_ms = self.start.elapsed().as_millis();
   // u128 类型，可表示数百万年的毫秒数，不会溢出
   ```

2. **空帧保护**：
   ```rust
   if frames.is_empty() {
       return "";
   }
   ```

3. **零帧率保护**：
   ```rust
   if tick_ms == 0 {
       return frames[0];
   }
   ```

### 改进建议

1. **自动化测试**：
   ```rust
   #[test]
   fn all_dot_frames_valid() {
       for (i, frame) in FRAMES_DOTS.iter().enumerate() {
           let line_count = frame.lines().count();
           assert_eq!(line_count, 17, "Frame {} has wrong line count", i + 1);
       }
   }
   ```

2. **文档生成**：
   - 自动生成帧预览图（文本格式）
   - 创建动画预览工具

3. **用户自定义**：
   - 考虑支持用户自定义动画帧
   - 运行时加载自定义帧目录

### 维护清单

- [ ] 文件编码：UTF-8
- [ ] 换行符：LF (Unix)
- [ ] 行数：17
- [ ] 字符集：仅 ○ ● ◉ · 和空格
- [ ] 编译通过：`cargo check -p codex-tui-app-server`
