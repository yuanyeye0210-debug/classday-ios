# 设置页改导航式分组 — 实施计划

> 设计：`docs/superpowers/specs/2026-11-12-settings-collapsible-sections-design.md`（已批准，2026-11-12 16:34，全部按推荐来）
> 分支：`feat/settings-collapsible-sections`，工作区 `~/workspace/worktrees/classday-ios-settings-collapsible`，基于 main `318b5d15`
> 状态：main 未动，无需 rebase。2.8.0 升版分支 `release/2.8.0-version-bump` 在走 PR，**别动它**。本批不改任何版本号（进 2.8.1 是发版口径）。

## 已定决策（不再讨论）

- D-0 导航式（分组导航行 + 点进子页面），仿照铁纪「自己」页布局；不做 DisclosureGroup 原地展开。
- D1 两张卡片：第一张「课表」（上课时间、学期、假期与不上课时段），第二张「通用」（提醒、数据、关于）。
- D2 子页里保留底部 tab 栏（NavigationStack 包在 TabView 的「我的」页签内，默认即保留）。
- D3 未保存就返回：保持现有行为，不加「放弃修改？」弹窗。
- D4 版本：进 2.8.1，不进 2.8.0；本批不改版号。
- D5 提醒页新增「保存提醒」按钮（与学期/上课时间的保存按钮同样式），不要改成改动即保存。
- D6 顶部卡片（主题 / 考试、作业、导入和分享）保持 sheet 不动。

## 关键约束（违反即返工）

- **草稿与保存**：学期 / 上课时间 / 提醒共用 `SettingsView` 的 `@State semester` 草稿，走同一个 `AppModel.updateSemester()` 保存；草稿通过 `Binding<Semester>` 传给三个子页；各子页保留自己的保存按钮；假期 / 停课保持立即保存（`saveHolidays()` → `updateSemester`）；未保存返回时草稿留在内存，回来还能看到。**不要**自作主张加弹窗或改保存语义。
- **只搬运，不改行为**：六个分区里的控件、文案、noteCard、分区分隔线原样搬；导入 / 导出 / 检查更新 / 校历导入 / 邮件停课识别的逻辑不动。
- **无新文件**：所有新子页 View 都写在 `Classday/ClassdayApp/Sources/SettingsView.swift` 内，**不要**新建 Swift 文件，不要动 pbxproj，不要跑 `generate_xcodeproj.py`。
- **样式**：复用现有 `settingsRow` / `settingsCard` / `iconBadge` 与 `Theme`（自适应浅/深），不抄铁纪的深色硬编码；chevron 是装饰性的，不另加无障碍标注。
- **范围**：无 Core 改动、无 schema 改动、不新增单测；不改 SideStore 分发。
- **本机无 Swift/Xcode**：构建与截图只能走 GitHub Actions CI；不要假装本地跑过。CI 由父 agent 在推分支 / 开 PR 后跑，本计划只做到评审干净为止。
- 每任务评审出现 Critical 必须修掉再往下走。

## 文件位置（已核实）

- `Classday/ClassdayApp/Sources/SettingsView.swift`（1267 行）：`SettingsView` body（ScrollView + 手写「我的」34pt 大标题，行 44–47）、六个 `section(...)`（学期 66、假期 102、上课时间 193、提醒 232、数据 269、关于 299）、`.fileExporter`（行 441）、`section()` helper（行 582）、`settingsCard` View extension（行 732，子页可直接用）。
- `Classday/ClassdayApp/Sources/RootView.swift`：TabView（行 15），「我的」页签直接放 `SettingsView()`（行 28）；JSON 导入的 `.fileImporter` 挂在行 96，**不动**。
- `Classday/Docs/REGRESSION_CHECKLIST.md`：回归清单。

## 任务拆分（顺序执行，都改同一个文件，必须串行）

### T1 — NavigationStack 与标题

- `RootView.swift`：只给「我的」页签包一层 `NavigationStack`（TabView 结构不动，其他三个页签不动）。
- `SettingsView.swift`：删手写「我的」34pt 大标题，ScrollView 加 `.navigationTitle("我的")`（系统大标题）。
- 验证：grep 确认 SettingsView 里没有 34pt 手写标题；`python3 Classday/Tools/check_project.py` 通过；preflight grep（见下）干净。提交：`settings: wrap My tab in NavigationStack, use system large title`。

### T2 — 学期 / 上课时间 / 提醒三个子页（含 Binding 与提醒保存按钮）

- 新建 `SemesterSettingsView`、`PeriodsSettingsView`、`ReminderSettingsView`（都在 SettingsView.swift 内），内容从现有三个 `section(...)` 原样搬：控件、文案、noteCard、保存按钮（学期「保存学期」、上课时间「保存节次与学期」）都不动。
- 草稿：`Binding<Semester>` 从 SettingsView 传给三个子页；`timeBinding` / `clockDate` / `clockText` / `addPeriod` / `applyPeriodTemplate` / `removeLastPeriod` 等 helper 随使用方走（移到子页内或保持 SettingsView 私有并传 binding/闭包，选改动最小的方案）。
- 提醒页按 D5 新增「保存提醒」按钮，样式与另两个保存按钮一致，走同一个 `updateSemester()`。
- 首页先加这三行（NavigationLink + settingsRow 复用，摘要值按设计：上课时间「N 节 · 首节–末节」、学期「名称 · 共 N 周」、提醒「提前 N 分钟 · 通知已允许/未允许」），放进第一张「课表」卡片（上课时间、学期）与第二张「通用」卡片（提醒）；其余三行在 T3 补。
- 验证：preflight grep 干净；check_project.py 通过；旧的三个 section 块已删，无残留引用。提交：`settings: extract semester/periods/reminders sub-pages with shared draft binding`。

### T3 — 假期 / 数据 / 关于三个子页

- 新建 `HolidaySettingsView`、`DataSettingsView`、`AboutSettingsView`（SettingsView.swift 内），内容原样搬。
- 假期：`showCalendarImport` / `showMailCancel` / `newHolidayName` / `newHolidayStart` / `newHolidayEnd` 等 @State 下移到子页；`saveHolidays()` 立即保存语义不动；校历导入与邮件停课识别仍开 sheet。
- 数据：`exporting` / `exportDocument` @State 与 `.fileExporter` 下移到数据子页；导入 / 智能导入 / 恢复 / 清空仍走 AppModel 的 flag（RootView 的 fileImporter 不动）。
- 关于：`showChangelog` / `checkingUpdate` @State 下移到子页；更新日志仍开 sheet；检查更新整块（下载进度、ShareLink、浏览器下载链接、SideStore 安装步骤文案）原样搬，仍读 AppModel 共享下载状态。
- 首页补齐三行：假期「N 段假期 · M 条停课，无则未设置」、数据无摘要（或「本地存储」）、关于「版本 X.Y.Z」。
- 验证：同 T2。提交：`settings: extract holidays/data/about sub-pages`。

### T4 — 首页收尾 + 回归清单 + 预检

- 首页最终形态：顶部主题/考试卡片不动 + 两张卡片六行（NavigationLink 行，行间细分隔线）；删掉六个旧 `section(...)` 调用（T2/T3 已删各自分区，此处确认无残留）；`section()` helper 如已无人用则删除，仍有人用则保留。
- `Classday/Docs/REGRESSION_CHECKLIST.md` 补子页检查项：每个子页进出、保存、返回后草稿仍在；提醒页保存按钮生效；数据页导出/导入/清空流程；关于页检查更新与下载流程。
- 全分支 preflight：`grep -rn "throw$" --include="*.swift" Classday`、`grep -rn "catch is CancellationError" --include="*.swift" Classday`、`grep -rn "= \." --include="*.swift" Classday/ClassdayApp/Sources`（只查改动文件， benign 的 `.default` 命中需逐条确认不是 SwiftData 模型默认值）；`python3 Classday/Tools/check_project.py` 通过。
- 提交：`settings: finish grouped navigation home, add regression checklist items`（清单可与代码同提交或单独提交，选其一并注明）。

### T5 — 整分支评审（协调员发起，评审子 agent 执行）

- 审整个 `feat/settings-collapsible-sections` 分支相对 main `318b5d15` 的 diff：导航结构、草稿与保存语义、六个子页内容完整性（有无控件/文案丢失）、样式复用、D-0–D6 落地情况。
- Critical 必须修掉再汇报；无 Critical/Important 方可汇报完成。
- CI（version-snapshot + classday-ios-ipa 构建与主题截图）由父 agent 推分支/开 PR 后跑，不在本计划内。

## 汇报给父 agent 时要给的

- 各任务提交（含 SHA）与评审结果；preflight 与 check_project 结果；明确说明 CI 未跑（待父 agent 推分支/开 PR 后跑）。
- 叶原野真机点验清单：六个子页逐个点一遍，改一项、保存、返回、再进，确认值还在；未保存返回确认草稿不丢；提醒页保存按钮生效；数据页导出/导入/清空；关于页检查更新与下载流程。
