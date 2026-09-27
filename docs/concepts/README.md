# 池塘视觉素材

- `pond-approved.png`：用户于 2026-09-27 确认的写实俯视池塘效果图，使用内置 imagegen 生成，仅作视觉基准。
- `../../Resources/PondEnvironment.png`：基于确认图编辑的环境底图，用于应用本地渲染。鱼群、涟漪与漂浮落叶由程序独立绘制。

生成提示摘要：严格垂直俯视、16:10 横屏、不规则自然池岸、苔石与局部树冠、清澈深浅绿色池水、约30条锦鲤、轻雨涟漪与少量落叶；自然摄影质感，无文字和界面。

环境编辑提示：保持确认图的相机、岸线、树冠、石头和水底位置；去除水中的全部鱼、松散落叶、雨滴和圆形涟漪；保留自然水深、池底纹理与柔和树影，供实时内容合成。随后清除右侧水面的残余黄色落叶。

来源：内置 imagegen 工具；无运行时生成或联网。程序输出以 `.build/render-validation/` 中的实际 Metal 帧为准，不能将本目录概念图当作运行截图。

## 2026-09-27 浓绿雨景修订

用户随后指定《言叶之庭》公园的浓绿树木、池水与雨景氛围，替换原来的偏橄榄色调。当前 `Resources/PondEnvironment.png` 已用内置 imagegen 编辑为翠绿树冠、碧绿池水与冷灰湿石，保持原岸线和物体位置；鱼、落叶、雨丝和涟漪仍由实时渲染提供。

最终编辑提示：Edit the supplied overhead pond environment image into the verdant rainy Japanese park atmosphere of The Garden of Words: luminous jade and emerald greens, lush rain-soaked trees, cool diffuse cloud light, detailed painterly animation-background realism. Transform muted olive/yellow-brown foliage into emerald, malachite, forest green and restrained chartreuse highlights; damp cool gray rocks and luxuriant green moss; clear jade water with teal shadows and silver-green reflections. Preserve exact overhead camera, aspect ratio, shoreline, rocks, canopies and water/land boundary. No fish, floating leaves, rain streaks, droplets, ripple circles, text, UI, borders or watermark. Full bleed through the top edge for the menu-bar backdrop.

动态参考：[用户提供的抖音视频](https://www.douyin.com/video/7690052489864891674)，已在浏览器观察其细斜雨丝、浅色池底和轻柔鱼群；仅参考动态节奏，未提取或使用视频素材。
