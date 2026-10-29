# 资源预算

默认路径是矢量：形状 path、色素、§设计系统里的材质画法、sand 图标。图标沿用 `packages/ui/src/kit/sand-icon-registry.ts` 的 SVG path，按 1px = 1dp 画成 vector drawable。需要的名字：`search`、`plus`、`sliders`、`close`、`chevron-right`、`chevron-left`、`pin`、`folder`、`edit`、`copy`、`arrow-up`、`arrow-down`、`ungroup`、`sidebar`、`attach`、`stop`、`settings-gear`、`nunu-plus`、`people`。

PoC 包内不放 `packages/ui/src/assets/nunu/` 的 png 和 webm。该目录合计约 9.4MB，架构要求空闲内存与 APK 都不携带这批原图。

## 目录里的文件，以及 PoC 是否使用

| 文件 | 体积 | PoC |
| --- | --- | --- |
| `plush.png` | 1.7MB | 不打包。矢量 `plush` 代替 |
| `plush-body.png` | 1.4MB | 不打包 |
| `felt.png` | 1.4MB | 不打包。矢量 `felt` 代替 |
| `glass.png` | 1.1MB | 不打包。矢量 `glass` 代替 |
| `matte.png` | 1001KB | 不打包。矢量 `matte` 代替 |
| `actions-atlas.png` | 2.0MB | 不打包。头像状态用 [motion.md](./motion.md) 的矢量 |
| `cheer.webm` | 234KB | 不打包。视频，且超过 webp 预算的讨论范围 |
| `sleepy.webm` | 286KB | 不打包 |
| `think.webm` | 266KB | 不打包 |
| `wave.webm` | 182KB | 不打包。即使体积较小，PoC 也不播 webm |
| `portrait-idle.png` | 65KB | 默认不打包。矢量全身已经覆盖打招呼 |

## 如果某一屏必须用位图

只允许一张 webp，小于 200KB，并且只能替代 `portrait-idle.png`：

- 源：`packages/ui/src/assets/nunu/portrait-idle.png`（65KB）
- 用途：资料页印章里的静止半身，仅当矢量全身在 212dp 印章内无法阅读时
- 解码宽度不超过 512px
- 不作为开箱贴图，不作为列表头像

其余九个文件都不是这张 webp 的替代对象。不要把它们转码进规格或进 APK。

`output/brand` 是品牌原稿，不是运行时资源，不进入 Android 包。

托盘模板图 `apps/desktop/resources/proactive-onTemplate.png` 与 off 版本属于菜单栏，PoC 不使用。
