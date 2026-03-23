# shapes/frame_4.txt 研究文档

## 场景与职责

`shapes/frame_4.txt` 是 Codex TUI 应用程序服务器的 ASCII 艺术动画帧文件，属于 `shapes`（形状）动画变体的第 4 帧。作为 36 帧循环动画序列的一部分，它在 240-319ms 时间窗口内显示。

**使用场景：**
- TUI 欢迎界面动画的第 4 个时间片
- shapes 变体动画循环的延续

## 功能点目的

1. **视觉连续性**：保持从 frame_1 到 frame_36 的流畅过渡
2. **形状动态**：展示几何形状的持续演变，创造"呼吸"或"脉动"效果
3. **用户参与**：通过持续的视觉变化保持用户对加载过程的关注

## 具体技术实现

### 帧内容特征
```
帧 4 特征分析：
- 图案演变：中心聚集趋势继续，开始出现"核心-外围"分层结构
- 形状分布：
  - 核心区域（中心）：高密度 ■、◆、●
  - 过渡区域：中等密度的 ▲、△、◇
  - 外围区域：稀疏的 ○、□
```

### 动画系统接口
```rust
// 帧访问接口
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.variants[self.variant_idx];
        // frame_4 对应索引 3
        let idx = ((elapsed_ms / 80) % 36) as usize;
        frames[idx]
    }
}
```

## 关键代码路径与文件引用

### 编译时处理
```rust
// frames.rs 第 9 行
include_str!(concat!("../frames/", "shapes", "/frame_4.txt")),
```

### 运行时渲染
```rust
// welcome.rs 第 82-83 行
let frame = self.animation.current_frame();
lines.extend(frame.lines().map(Into::into));
```

## 依赖与外部交互

### 构建系统
- **Bazel**：通过 `glob` 包含所有帧文件到 `compile_data`
- **Cargo**：开发时使用，`include_str!` 宏在编译时读取文件

### 运行时环境
- **终端模拟器**：必须支持 Unicode 几何形状字符
- **字体**：需要包含几何形状字形的等宽字体

## 风险、边界与改进建议

### 兼容性风险
| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 字体缺失几何形状 | 显示为方框或空白 | 使用常见字体（如 Noto Sans Symbols） |
| 终端不支持 Unicode | 显示乱码 | 检测并回退到 ASCII 变体 |
| 双宽度字符问题 | 布局错位 | 验证 `unicode-width`  crate 的处理 |

### 改进建议
1. **自动检测**：在启动时检测终端 Unicode 支持能力
2. **优雅降级**：如果检测到显示问题，自动切换到 `default` 或 `dots` 变体
3. **用户配置**：允许用户在配置文件中指定首选动画变体
