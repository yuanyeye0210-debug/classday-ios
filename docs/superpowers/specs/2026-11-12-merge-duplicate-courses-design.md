# 同名课程自动合并 — 设计

> Status: **待 Eric 审批**（设计通过后才开分支实施）。
> Branch: `feat/merge-duplicate-courses`，从 main `538815ab` 建（写本文时 main 已走到 PR #8 合并 `318b5d15`；实施时 rebase 到当时 main）。
> Companion plan: 待设计批准后写 `docs/superpowers/plans/2026-11-12-merge-duplicate-courses.md`。

## Background（已核实，不是假设）

用户原话：系统自动识别课程里面相同名称的课程合并成一个课程，因为要录入期中考试成绩了，不可能给两个相同的课程录两边成绩。

### 课程模型：一条 Course = 一门课，可含多个上课时间

- `Course`（`Classday/ClassdayCore/Sources/ClassdayCore/Models.swift:236-250`）：`id: UUID`、`name`、`teacher`、`location`（没有叫 `room` 的字段）、`department`、`note`、`colorID`、`kind`、`weeks: [Int]`（整门课共用，去重排序）、`meetings: [Meeting]`、`reminderLeadMinutes: Int?`、`credits: Double`、`grade: Double?`、`gradeScheme: GradeScheme?`。
- `Meeting`（`Models.swift:136-148`）：`id: UUID`、`weekday`（1=周一）、`startPeriod`、`endPeriod`。只有节次，没有时钟时间（几点由 `Semester.periods` 换算）。
- 存储：App Group 下 `classday-store.json`，UTF-8 JSON，schema v1。`StoreDocument`（`Models.swift:418-434`）顶层是 `courses: [Course]` 平铺数组，**没有任何按名称的唯一约束**；`StoreCodec.validate`（`Store.swift:172-196`）只查 `id` 重复，不查 `name`。
- 设计意图的证据：演示数据 6 门课共 10 个 meeting，同一门课的多个 meeting 共用一个 `Course.id`（如高等数学周一 + 周三两个 meeting）。所以**按模型设计，一门课每周多节应是一条 Course + 多个 Meeting，而不是多条 Course**。
- `id` 每次新建都是现场 `UUID()`（手动 `CourseEditorView.swift:324`、OCR `OCRImportView.swift:499`、Fénix `ScheduleExtras.swift:479`）；只有 ICS 导入用确定性 `stableUUID(key)`（`ScheduleExtras.swift:447`）。

### 同名两条课是怎么来的（四条路都会造）

- 手动添加：`AppModel.saveCourse`（`AppModel.swift:418-424`）只按 `id` 匹配，存在则替换、否则 `append`，**没有任何按 name 的查重**。再添一门同名课直接变成第二条。
- ICS 导入：`ICSImporter.parse`（`ScheduleExtras.swift:345-368`）按 `name|location` 分组；同名同教室合并进一个 Course（追加 Meeting），**同名不同教室就是两个 Course**。
- OCR / 文本 / 表格导入：`ScheduleTextImporter.group`（`ScheduleExtras.swift:1018-1036`）按 `name|teacher|firstWeek|lastWeek|customWeeks` 分组，**不含地点**；同名不同老师、或同名但周次范围不同（如 1–8 周与 9–16 周）会分成两个草稿，各建一条 Course。只有一个橙色“已有同名课”角标提示（`OCRImportView.swift:190,557`），**不拦截**。
- Fénix 同步：按 `name|location` 分组（`ScheduleExtras.swift:477`），但 `id` 每次调用都随机，只能靠签名拦截。
- JSON 整份导入 / 分享课表：整表替换，文件自带两条同名即原样保留。

现有的唯一一道课程去重关口是 `AppModel.importCalendar`（`AppModel.swift:918-960`）：同时满足“id 未出现”且“签名未出现”才追加，签名 = `name|location|全部 meeting（weekday:start-end，排序拼接）`。它拦不住的情况：同名但教室不同、时间不同（签名不同即放行）；且**只在 `importCalendar` 入口生效**，手动添加和 JSON 导入不走它。三路解析器的分组 key 各不相同（`name|location` vs `name|teacher|周次`），同一门课换个字段就会分到不同组。

### 成绩：长在 Course 身上，按课程 id 寻址

- **没有独立的 Grade / Score 模型。**成绩就是 `Course` 上的两个字段：`grade: Double?`（百分制总分，nil = 未录入）和 `gradeScheme: GradeScheme?`（记分规则：分项 + 权重，多算法取最高，折合百分制）。写成绩的入口 `AppModel.setCourseGrade` / `setCourseGradeScheme`（`AppModel.swift:844-856`）都按 `id` 定位：`firstIndex(where: { $0.id == courseID })`。
- 录入入口只有一个：课程详情页的成绩卡（`CourseDetailView.swift:129-164`）→ `GradeEditorView(courseID: UUID)`（`:538` 起）。**没有选课列表**，课程在进详情页那一刻就已由 `courseID` 定死。两种录入方式：直接填总分（0–100），或记分规则模式（分项名自由文本 + 权重）。
- 同名两条课的现状：**必须给每条各录一遍**，没有任何跨条目同步。汇总也不按名分组：`weightedScoreAverage` / `gpaAverage` / `earnedCredits`（`AppModel.swift:860-893`）是对 `grade != nil` 的全部条目逐条按学分加权——**同名两条各算一次、学分也 double 计**。
- **没有“期中”这个概念。**全仓 grep `midterm` / `期中` 零命中。`ExamEvent`（`ScheduleExtras.swift:80-96`）只有时间地点备注，没有分数字段，也不分期中/期末；它关联课程用的是 `courseName: String`（按名，不按 id）。记分规则的分项名是自由文本，默认分项就叫“期末考试”——期中只要当作总成绩录，或当作一个分项名录，现有模型已够用。本批**不新增“期中”类型**。

### 谁在消费“课程身份”

- 展示层的基本单位处处是 `Occurrence`（一门课 × 一个 Meeting × 一周，`ScheduleEngine.swift:173`，id = `courseID-meetingID-week`）。今日页、周览（网格/日记）、小组件（小/中/扇形/锁屏）、提醒、灵动岛的“下一节”全部按 Occurrence 取数、按时间排序，**没有一处按课程名分组或合并**。
- 课程的权威身份是 `Course.id (UUID)` + `Meeting.id (UUID)`；深链 `classday://course/<courseID>?meeting=<meetingID>`（`Models.swift:496-514`）。
- 灵动岛：`NextClassSnapshot.make`（`ActivityBridge.swift:39-76`）取 `currentOccurrence` / `nextOccurrence`（时间排序，不是按名）；Activity 身份键是 `courseID` 字符串；`NextClassActivity.syncAsync`（`NextClassActivity.swift:32-55`）命中同一 courseID 则 update，否则结束旧 activity 重建。
- 提醒：`NotificationPlan`（`NotificationPlan.swift:23-88`）按每个 Occurrence 生成，通知 id = `classday-<courseID>-<meetingID>-<日期>-<时间>`；`ReminderScheduler.apply`（`ReminderScheduler.swift:38-55`）每次先清掉全部 `classday-` 前缀待发通知再重建（全量替换）。
- 停课记录锚定 `courseID`（`CancellationParser.parseAI`，`ScheduleExtras.swift:2101-2110`，AI 按名模糊匹配，取 `first` 的那一条；`SemesterCalendar.swift:117-130` 按 `courseID` 生效）。
- 考试 / 作业锚定 `courseName` 字符串（`ExamEvent.courseName`、`HomeworkTask.courseName`），不存 course id；考试取颜色时 `first { $0.name == exam.courseName }`（`RootView.swift:1114`）。
- `OccurrenceOverride`（`ScheduleExtras.swift:46-56`）：`id`、`courseID`、`meetingID`、`week`、`kind` 等，锚定 courseID + meetingID（取消/改期某节、延后 10 分钟都靠它）。

## 1. 合并键：只比规范化后的名称

- 键 = `normalize(name)`：去首尾空白、删掉全部空白字符（含全角空格 U+3000）、ASCII 字母小写、全角 ASCII 转半角（Ａ→A、（→( 等）。**不做简繁转换**（无依赖、易误判；“发”与“發”在课程名里基本不会同时出现）。
- 只比名称，不加老师/教室/周次。理由：同一份学期文档里，同名基本就是同一门课（不同教室/不同老师只是同一门课的排课差异）；用户的痛点是成绩，而成绩在现实里就是按课程名给的。加老师会把“同一门课两个老师”又拆开，等于没解决。
- 风险与兜底：同名但确实是两门不同的课（极少，如同名不同老师的课）会被分到同一组——由第 3 节的确认界面兜底：每组列出各条记录的老师/地点/节次，用户可以把某条排除出组，排除后它保持独立。

## 2. 合并范围：底层模型合并，不是只在成绩处合并显示

- 只在成绩录入处“看起来合并”解决不了问题：成绩是 `Course` 各自的字段，GPA/学分也是按条目逐条算的。必须把多条 `Course` 记录真正合成一条，成绩才只有一个地方录、GPA 才只算一次。
- 合并是一次文档变换，不改 schema：schema 仍是 v1，不新增字段、不升版。合并后的 `Course` 仍是标准 `Course`，导出 JSON、导入、分享都不受影响。

## 3. 合成后各条怎么保留（推荐规则）

- 主记录（survivor）= 当前文档顺序里的第一条。稳定、可预测，不依赖没有记录的创建时间。
- `meetings` = 各条的并集，按 `(weekday, startPeriod, endPeriod)` 去重；**meeting id 全部保留**（不重新生成），这样 `OccurrenceOverride` 的 `meetingID` 仍能对上。
- `weeks` = 各条并集，去重排序。
- `teacher` / `location` / `department` / `note` / `colorID` / `kind` / `credits`：取主记录的；其他记录的值在确认界面里列出来给用户看。如果各条老师不同，组里显示一条提醒（“老师不一致，请确认是同一门课”）。
- `reminderLeadMinutes`：主记录的；主记录为 nil 则取第一条非 nil 的。
- 成绩（`grade` / `gradeScheme`）：
  - 只有一条有成绩 → 保留它。
  - 两条都没有 → nil。
  - 两条都有且值相同 → 保留。
  - 两条都有且值不同 → **冲突**，不静默覆盖。确认界面里该组标出冲突，用户二选一后该组才能合并（未选时该组的合并按钮禁用）。默认不替用户选。
- 被合并掉的记录删除；主记录保留自己的 `id`（不生成新 id），这样深链、提醒、灵动岛都锚定在主记录上。

## 4. 已录成绩与关联数据的迁移

| 数据 | 锚定方式 | 合并时怎么做 |
|---|---|---|
| 成绩（grade / gradeScheme） | 长在 Course 上 | 按第 3 节规则处理，冲突进确认界面 |
| `OccurrenceOverride`（取消/改期/延后） | `courseID` + `meetingID` | 被移过来的 meeting 对应的 override，把 `courseID` 改写成主记录 id；`meetingID` 不变（meeting id 保留了） |
| 停课记录 | `courseID` | 同上，改写成主记录 id；`courseID == nil` 的全天记录不动 |
| 考试 / 作业 | `courseName` 字符串 | 不动（名称不变）；合并后考试取颜色不再有“取第一条”的歧义 |
| 提醒 | 按 Occurrence 生成，id 含 courseID+meetingID | 不用迁移：保存后 `persist` 全量重算并重建通知，旧 id 被 `apply` 清掉 |
| 灵动岛 / 小组件 | 按 Occurrence 取数，身份键 courseID | 不用迁移：下一次重算即按新文档渲染；若下一节的 courseID 变了，旧 activity 按现有逻辑结束重建 |
| 系统日历同步 | Occurrence id（含 courseID） | 旧条目会被认作“不在新文档里”而删除、新条目重建——表现是日历里该课的事件被删了重建一次，内容不变 |
| 深链 | `classday://course/<旧 id>` | 指向被删记录的旧链接打不开（可接受；这类链接只在小组件 chip 和通知里出现，且都会随下一次重算刷新） |

## 5. 自动合还是先提示用户确认（推荐：自动检测 + 一次确认）

- **不静默自动合并。**合并是破坏性操作（删记录、换 id），且有误判可能（同名不同课）。用户原话的“自动”理解为“系统自动识别、找出来”，不是“一声不吭就合了”。
- 界面：“全部课程”页在存在同名组时出现“合并重复课程”入口（显示组数，如“发现 2 组同名课程”）；点进是合并确认页：每组一张卡，列出组内各条的老师、地点、节次、周次、成绩状态；每组可单独确认合并、也可“全部合并”；可把某条排除出组；有成绩冲突的组先选成绩再合。
- 导入后提示：任何一次 `importCalendar` 之后，若新文档里出现同名组，顶部横幅提示“发现 N 组同名课程，去合并”，点进确认页。OCR 的“已有同名课”角标保留，不拦截导入。
- 导入时不拦截、不改三路解析器的分组 key：那三个 key 各不相同是有原因的（地点/老师/周次各自代表不同维度的区分），统一它们是更大的重构，不在本批。

## 6. 备份 / 可撤销

- 合并执行前，把当前整份文档自动存一份进课表库（`StoredTimetable`，现有 `duplicateTimetable` 的机制），名字如“合并前备份 11-12 16:30”。用户在课表库里随时可以恢复。不另做撤销栈、不新增数据结构。

## 7. 版本：不进 2.8.0

- 2.8.0 已定发版（2026-11-12 16:15 叶原野定），PR #8 已合（`318b5d15`），升版分支已在跑。**本批默认不塞进 2.8.0**。
- 推荐：下一版 **2.9.0**（面向用户的功能，按以往 minor 号的用法）。备选 2.8.1（如果他想把这批当补丁发）。由他拍板（决策 D5）。

## Architecture

- 纯逻辑放 `ClassdayCore`（走 `swift test`，CI 跑）：新建 `CourseMerger.swift`（暂定名，实施时对照仓库命名）——`normalizeCourseName(_:)`、`findDuplicateGroups(courses:) -> [DuplicateGroup]`、`merge(group:primary:gradeChoice:) -> (Course, CourseIDRemap)`，以及 `applyRemap(overrides:cancellations:remap:)`。全部纯函数，不碰磁盘、不碰 `UserDefaults`。
- App 层薄薄一层：`MergeReviewView`（确认页）、“全部课程”页入口、导入后横幅；`AppModel.applyCourseMerge`（先把当前文档存进课表库备份，再应用合并、持久化，`persist` 触发的提醒/灵动岛/小组件刷新沿用现有链路）。
- 不改 schema v1，不动工作流，不升版本（版本号由发版决策定，不在本批里顺手改）。

## Android sync

- 共享的是合并算法与规范化规则：分组 key、规范化步骤（去空白、小写、全角转半角）、并集规则、成绩冲突规则都是纯逻辑，写在共享模型上，Android 可直接复用。
- 只有确认页 UI、横幅、入口位置是 iOS 专属（SwiftUI、UserDefaults 均不涉及——本批不用 UserDefaults）。
- 不改 schema，所以 `classday-releases` 与 `DATA_SCHEMA.md` 不用改；实施时在 `DATA_SCHEMA.md` 加一句注：同名课程由 App 合并，schema 本身不禁止同名（现状已如此）。

## Testing

- Core 单元测试（`swift test`，CI）：规范化（首尾空白、全角空格、大小写、全角字符）、分组（同名不同老师进一组、同名但规范化后不同不进组）、meeting/week 并集去重、成绩保留/冲突检测、override 与停课记录的 courseID 改写、无重复时 no-op、meeting id 与主记录 id 保留。
- App 层：`xcodebuild` 构建通过 + 评审；确认页交互与横幅没有单元测试目标，靠评审。
- 真机（叶原野）：拿他自己的真实课表跑一次合并：成绩还在、GPA 对、提醒与灵动岛正常、课表库里有合并前备份；再从备份恢复一次，确认恢复可用。

## 任务拆分（给 plan 用）

1. Core：名称规范化 + 分组（TDD，先写 failing test）。
2. Core：合并 + 成绩冲突模型（TDD）。
3. Core：override / 停课记录改写（TDD）。
4. App：确认页 UI + 入口 + 导入后横幅。
5. App：执行合并 + 课表库备份 + 持久化。
6. 测试与文档：`DATA_SCHEMA.md` 注一句、回归清单加一项（同名课合并后成绩/GPA/提醒正常）。
7. 整分支评审 → draft PR → CI → 按主规则合 main → 汇报 + 预览（确认页可交互模型）。

## 需要 Eric 拍板的决策

- **D1 合并键**：只比规范化后的名称（推荐） vs 名称 + 老师。推荐只比名称——同名不同老师在同一份学期文档里基本就是同一门课；加老师会把要解决的问题又拆开。
- **D2 合并方式**：自动检测 + 一次确认（推荐） vs 完全静默自动合并 vs 只手动触发。如果他坚持全自动，至少保留一条事后横幅“已合并 N 组，可在课表库恢复”。
- **D3 成绩冲突**：用户二选一（推荐） vs 静默保留主记录的。推荐二选一——成绩是他要录的东西，静默丢一个说不过去。
- **D4 导入后提示**：导入后有同名组就弹横幅（推荐） vs 只在“全部课程”页放入口、导入后不提示。
- **D5 版本**：下一版 2.9.0（推荐） vs 2.8.1 vs 攒到再下一批。2.8.0 已定，不进。
- **D6 老师不一致的组**：只提醒、不阻止合并（推荐） vs 老师不一致的组不自动进候选、只手动合。
