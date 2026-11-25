# 资源预算

默认路径是矢量：形状 path、色素、[design-system.md](./design-system.md) 里的材质画法、sand 图标。图标沿用 `packages/ui/src/kit/sand-icon-registry.ts` 的 SVG path，按 1 px = 1 pt 画成矢量。需要的名字：`search`、`plus`、`sliders`、`close`、`chevron-right`、`chevron-left`、`pin`、`folder`、`edit`、`copy`、`arrow-up`、`arrow-down`、`ungroup`、`sidebar`、`attach`、`stop`、`settings-gear`、`nunu-plus`、`people`。

不把 `packages/ui/src/assets/nunu/` 的 png 和 webm 放进切图，也不提交进 `ios/`。该目录合计约 9.4 MB。规格只引用矢量，不把这批原图带进包。

## 目录里的文件，以及本期是否使用

| 文件 | 体积 | 本期 |
| --- | --- | --- |
| `plush.png` | 1.7 MB | 不打包。矢量 `plush` 代替 |
| `plush-body.png` | 1.4 MB | 不打包 |
| `felt.png` | 1.4 MB | 不打包。矢量 `felt` 代替 |
| `glass.png` | 1.1 MB | 不打包。矢量 `glass` 代替 |
| `matte.png` | 1001 KB | 不打包。矢量 `matte` 代替 |
| `actions-atlas.png` | 2.0 MB | 不打包。头像状态用 [motion.md](./motion.md) 的矢量 |
| `cheer.webm` | 234 KB | 不打包 |
| `sleepy.webm` | 286 KB | 不打包 |
| `think.webm` | 266 KB | 不打包 |
| `wave.webm` | 182 KB | 不打包。即使体积较小，也不播 webm |
| `portrait-idle.png` | 65 KB | 默认不打包。矢量全身已经覆盖打招呼 |

## 如果某一屏必须用位图

只允许一张 webp，小于 200 KB，并且只能替代 `portrait-idle.png`：

- 源：`packages/ui/src/assets/nunu/portrait-idle.png`（65 KB）
- 用途：资料页印章里的静止半身，仅当矢量全身在 212 pt 印章内无法阅读时
- 解码宽度不超过 512 px
- 不作为开箱贴图，不作为列表头像
- 生成物若要进包，放在实现 package 的资源里，仍不要把 9.4 MB 原图提交进 `ios/`

其余九个文件都不是这张 webp 的替代对象。不要把它们转码进规格或进包。

`output/brand` 是品牌原稿，不是运行时资源，不进入 iOS 包。

托盘模板图 `apps/desktop/resources/proactive-onTemplate.png` 与 off 版本属于菜单栏。Mac 上有菜单栏常驻。iOS 不要求菜单栏常驻，这两张图不进包。
