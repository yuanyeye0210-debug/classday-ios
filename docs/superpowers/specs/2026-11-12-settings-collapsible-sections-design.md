# 设置页改导航式分组 — 设计

批准：待叶原野批。做法已定：导航式（分组导航行 + 点进子页面），仿照他给的铁纪「自己」页布局。

## 意图和为什么

设置页（「我的」页签）现在是六个分区全部展开平铺：学期、假期与不上课时段、上课时间、提醒、数据、关于，每个分区里的所有控件（时间选择器、开关、按钮、说明卡片）一次性全显示出来，页很长，找一项设置要滑很久。用户要改成：首页只剩分组导航行，每行一个分区，点进去才是那个分区的完整内容。

布局参考是用户发的铁纪 App「自己」页截图（`workspace/user/files/A9E6591E-E5E9-4EB8-92F9-31E9B17AC44F-photo-4B07E86E-D155-43DC-82C8-298E569C942B.jpg`）：深色圆角卡片分组，每组几行，行与行之间细分隔线；每行左边图标、中间标题、右边 `>`，点进独立子页面；行上可带状态摘要（如 Apple Watch 行的「已连接」）。只借这个布局结构，不抄铁纪的内容、品牌和深色硬编码——样式沿用 Classday 自己的 Theme（自适应浅/深）。

## 目标

- 「我的」页首页只显示：顶部现有的主题/考试卡片（不动）+ 六个分区的导航行，每行带图标、标题、摘要值、`>`。
- 六个分区各有一个专属子页，点行 push 进去；子页里是现在该分区原样搬过去的控件与文案，不精简、不改行为。
- 上课时间的每节起止选择器、假期的增删、学期的保存、提醒的默认提前分钟、数据的导入导出、关于的检查更新，在子页里全部照常能用。
- 不改数据模型、不改 Core、不改 schema、不改 SideStore 分发。

## 非目标

- 不改六个分区里任何控件的行为与文案（提醒页补一个保存按钮除外，见「做法」）。
- 不动顶部主题/考试卡片（它们已经是导航式行，开 sheet 的方式不变）。
- 不改校历导入、邮件停课识别、更新日志的 sheet 流程；不改导入/导出/检查更新的逻辑。
- 不做搜索框、不做最近使用、不做分区排序或自定义隐藏。

## 反目标

- 不把 DisclosureGroup 原地展开当成做法（用户已指定仿照截图的导航式，见「已定决策」）。
- 不把铁纪的深色样式、渐变标题、个人资料卡片、会员/手表/耳机等内容搬过来。
- 不为了分组而造新的状态存储：导航式没有“展开/收起”状态需要记。
- 不动 `generate_xcodeproj.py`（D-6），不动 pbxproj 结构。

## 约束

- 本机是 Linux，没有 Swift、Xcode、模拟器和真机。UI 变化靠 GitHub Actions CI（`classday-ios-ipa.yml` 的构建 + 主题截图）与叶原野真机点验。
- 安卓版在 GitHub 上没找到（2026-11-12 已查）。本批只保证共享逻辑、数据结构和行为跨平台可用，不写安卓代码；导航重组是 App 层纯界面改动，不碰 Core。
- 分发不变：侧载，LocalDevPN + SideStore，安装包在 classday-releases。

## 已查到的事实（实施起点）

- `SettingsView.swift`（1267 行）：`ScrollView` + `VStack(spacing: 22)`，手写「我的」34pt 大标题；**不在任何 `NavigationStack` 里**（`RootView.swift:28` 是 TabView 的「我的」页签，直接放 `SettingsView()`）。六个分区用 `section(title)`  helper 平铺，`section` = 标题文字 + `.settingsCard()`；`.settingsCard()`（`SettingsView.swift:732`）= `Theme.elevated` 背景、圆角 20、默认 padding 16。`settingsRow(icon:color:title:value:showsChevron:action:)` 已是图标 + 标题 + 摘要值 + `>` 的 Button，可直接复用为导航行。
- App 内**没有任何 `NavigationLink` / `navigationDestination` / `DisclosureGroup`**（全仓 grep 为零）。子页（`ChangelogView`、`CalendarImportView`、`MailCancelView`）各自在 sheet 里建自己的 `NavigationStack`。所以导航式是 App 内第一次用 push 导航，`NavigationStack` 需要新包一层。
- 六个分区现状（`SettingsView.swift`）：
  - 学期：名称/简称输入框、开始日期 DatePicker、总周数 Stepper、结束日期（自动推算）、「保存学期」按钮。
  - 假期与不上课时段：假期列表（可删）、新增时段（名称 + 起止日期 + 「添加时段」）、「校历导入」行（sheet `CalendarImportView`）、「邮件停课识别」行（sheet `MailCancelView`）、停课记录列表（可删）。假期/停课每次改动**立即保存**（`saveHolidays()` → `updateSemester`）。
  - 上课时间：每节起止 DatePicker（`ForEach(semester.periods)`）、添加/删除一节、「保存节次与学期」按钮、30 分钟 × 20 节 / 45 分钟 × 10 节模板按钮、noteCard（写明保存会连同学期名称、周数和默认提醒一起写入本机）。
  - 提醒：默认提前分钟 Stepper、通知权限状态 + 「检查」按钮、被拒时「打开系统设置去允许」行、noteCard。**没有自己的保存按钮**，靠学期/上课时间页的保存连带写入。
  - 数据：「导出 JSON」「导入 JSON」「智能导入课表」「恢复演示数据」「清空课程」五行 + noteCard。导出用 SettingsView 本地 `@State exporting` + `.fileExporter`；导入/智能导入/恢复/清空用 AppModel 的 flag（`showImporter`、`showSmartImport`、`confirmReset`、`confirmClear`），其中 JSON 导入的 `fileImporter` 挂在 `RootView.swift:96`。
  - 关于：App 图标 + 名称 + 版本胶囊、说明文案、「更新日志」行（sheet `ChangelogView`）、「检查更新」行（`UpdateService` + AppModel 共享下载状态：下载进度、ShareLink、浏览器下载链接、SideStore 安装步骤文案）。
- 共享草稿是核心约束：学期/上课时间/提醒共用 SettingsView 的 `@State semester` 草稿，`onAppear`/`onChange` 用 `lastSyncedSemester` 守卫从 `model.document.semester` 同步；三个分区都走 `AppModel.updateSemester()`（`AppModel.swift:448`，StoreCodec 校验 + 持久化；节次变化时先把旧文档存进课表库备份）保存。
- Theme（`Theme.swift`）：自适应浅/深；卡片 `Theme.elevated`（浅 #F4F6FB / 深 #242833）、`accent` #3A6BFF、`ink`/`secondary`/`line` 均自适应。Msats 截图是深色单一样式——Classday 不抄它的颜色，只借分组与行的结构。
- 无障碍：SettingsView 目前无 `accessibilityLabel`；`NavigationLink` 行在 VoiceOver 下默认读出标题与「按钮」，无需额外标注（实施时确认 chevron 是装饰性的）。
- 回归清单（`Docs/REGRESSION_CHECKLIST.md`）有设置相关项（设置 → 外观/动效页、提醒、AI 草稿确认、低电量提示），本批要补子页的检查项。

## 做法

选导航式，不做原地展开。已定决策见下，实施按这个做。

### 首页结构

- 在 `RootView` 的 TabView 里给「我的」页签包一层 `NavigationStack`（一处改动，tab 结构不动）；「我的」手写大标题改为 `.navigationTitle("我的")`（系统大标题，观感一致）。
- 首页保留顶部主题/考试卡片（不动），六个分区变六行，分两张卡片：
  - 第一张「课表」：上课时间、学期、假期与不上课时段。
  - 第二张「通用」：提醒、数据、关于。
- 每行复用现有 `settingsRow`：图标 + 标题 + 摘要值 + `>`，点行 push 进子页。摘要值（行内状态，仿截图 Apple Watch 行的「已连接」）：
  - 上课时间：「N 节 · 08:00–17:30」（首节开始–末节结束）；
  - 学期：「名称 · 共 N 周」；
  - 假期与不上课时段：「N 段假期 · M 条停课」，无则「未设置」；
  - 提醒：「提前 N 分钟 · 通知已允许/未允许」；
  - 数据：无摘要（或「本地存储」）；
  - 关于：「版本 X.Y.Z」。
- 行图标沿用各分区现有的 `iconBadge` 图标（上课时间 `clock.fill`、学期 `calendar`、假期 `beach.umbrella.fill`、提醒 `bell.fill`、数据 `square.and.arrow.up.fill`、关于 `info.circle.fill`，实施时以 SF Symbols 现有图标为准，不新造）。

### 子页

- 每个分区一个专属 View，内容从现有 `section(...)` 里原样搬过去：控件、文案、noteCard、分区分隔线都不动；子页用 `.navigationTitle` + inline 标题。
- 上课时间子页：每节起止选择器、添加/删除、模板按钮、noteCard 全搬；节次多时子页内滚动。
- 假期子页：假期列表、新增时段、校历导入行、邮件停课识别行、停课记录全搬；两个导入流程仍开 sheet（不动）。
- 关于子页：App 头、说明、更新日志行（仍开 sheet）、检查更新整块（下载进度/ShareLink/浏览器链接/安装步骤）全搬；下载状态仍读 AppModel 共享状态（与 RootView 的拦截弹窗共用，不另起状态）。

### 草稿与保存（本批最关键的一点）

- 草稿仍归 SettingsView 所有，通过 `Binding<Semester>` 传给学期/上课时间/提醒三个子页（`NavigationLink` 的 destination 闭包里传 binding）；各子页保留自己的保存按钮（「保存学期」「保存节次与学期」），保存语义与现在完全一致（走同一个 `updateSemester`，节次变化照样先备份）。
- **提醒页新增「保存提醒」按钮**：现状是提醒没有保存按钮，靠别的页连带保存；分页面后必须补，否则在提醒页改完、直接返回，改动永远写不进去。按钮样式与另两个保存按钮一致。
- 假期/停课保持立即保存，不动。
- 导出 JSON 的 `.fileExporter` 从 SettingsView 根部移到数据子页本地 `@State`（`exporting` / `exportDocument` 只在导出用）；导入/智能导入/恢复/清空仍走 AppModel 的 flag（`RootView` 挂的 `fileImporter` 与确认弹窗不受影响）。
- 未保存就返回：**保持现有行为**——草稿留在内存里，回来还能看到未保存的修改；不新增「放弃修改？」确认弹窗（本批不做，以后要加再议）。实施时不要自作主张加弹窗。

### 样式与无障碍

- 沿用现有 `settingsRow` / `settingsCard` / `iconBadge`，不新增视觉语言；卡片圆角 20、`Theme.elevated`，行高与现有行一致；深色/浅色都走 Theme 自适应。
- 小屏（iPhone SE 4.7"）：首页只有两张卡片共六行，无需滚动；子页是滚动列表，与现状一致，无新增小屏风险。
- VoiceOver：导航行默认可读（标题 + 按钮）；chevron 是装饰，不另加标注；子页控件沿用现有可访问性。

### 测试与验证

- 无 Core 改动、无 schema 改动、无新单测（纯界面重组）。
- CI：`version-snapshot` + `classday-ios-ipa` 构建通过；workflow 的主题截图作为外观核对（截图是产物、不是断言）。
- 回归清单（`Docs/REGRESSION_CHECKLIST.md`）补项：每个子页进出、保存、返回后草稿仍在；提醒页保存按钮生效；数据页导出/导入/清空流程；关于页检查更新与下载流程。
- 真机点验（叶原野）：六个子页逐个点一遍，改一项、保存、返回、再进，确认值还在；再确认未保存返回不丢草稿。

## 已定决策（用户已指定，不用再问）

- D-0 导航式 vs 原地展开：**导航式**。用户原话是分区分开列、点进分区看，再加截图指定仿照铁纪「自己」页（分组导航行 + 点进子页面）。`DisclosureGroup` 原地展开不做。

## 需要叶原野拍板的决策

- D1 分组方式：两张卡片（课表 3 行 + 通用 3 行，推荐）还是一张卡片六行？推荐两张——与截图的分组节奏一致，首页也更短。
- D2 子页里 tab bar 显隐：保留（推荐，可随时跳回今日/周览）还是隐藏（多一点纵向空间）？
- D3 未保存返回：保持现有行为不弹窗（推荐）还是加「放弃修改？」确认？
- D4 版本号：进 2.9.1（2026-11-12 决定：2.9.0 先发同名课程合并，设置页顺延到 2.9.1；不进 2.8.0，2.8.0 已发版）。
- D5 提醒保存方式：提醒页新增保存按钮（推荐，与学期/上课时间一致）还是改成改动即保存？
- D6 顶卡（主题/考试、作业、导入和分享）保持 sheet 不动（推荐）还是也改成 push 子页？

## 任务拆分（实施时用，2–5 分钟粒度）

- T1：`RootView` 里给「我的」页签包 `NavigationStack`，「我的」标题改 `.navigationTitle`；删手写大标题。
- T2：抽六个子页 View（学期/假期/上课时间/提醒/数据/关于），内容从现有 `section` 原样搬；首页六行 + 摘要值，分两张卡片。
- T3：草稿 `Binding<Semester>` 下传给三个子页；提醒页加保存按钮；导出 `.fileExporter` 下移到数据子页。
- T4：关于页搬运（更新行、下载进度、ShareLink、安装步骤文案原样）。
- T5：回归清单补子页检查项；跑 CI（构建 + 主题截图核对）。
- T6：整分支评审 → draft PR → CI → 按主规则合。

## 留给实施时定

- 每行摘要值的具体文案（先按「做法」里的写，实施时对照真机微调）。
- 子页里 `section` 标题是否保留（建议去掉分区标题，子页标题就是导航栏标题；实施时看效果定）。
- tab bar 在子页的显隐（等 D2 批）。
