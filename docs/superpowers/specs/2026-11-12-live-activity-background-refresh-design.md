# Live Activity 后台刷新后续方案 — 设计

批准：待叶原野批。本设计只定方案，不写实现。

## 意图和为什么

锁屏 Live Activity 显示“下一节”课。2026-11-12 用户报 bug：已结束的课“优化与算法 10:00–11:30”还在锁屏岛上倒计时往上数。原因是 `NextClassActivity.sync` 只在课表保存/磁盘变化时跑，从不在前台打开或定时器时跑。PR #9 修了它（已合 main，随 2.8.0 发版）：A + B——前台打开时同步 + `BGAppRefreshTask` 后台刷新。

修完留了一个已知缺口：**后台刷新链在周末会断**。周五最后一节课结束后，下一次快照变化（周一 00:00 翻转出“下一节”）在 56 小时开外，超过 `nextBoundary` 的 36 小时 horizon，于是根本不排下一个后台任务；周一早上锁屏没有 Live Activity，要等用户打开 App 才恢复。长假（3 天以上无课）同理，链断得更久。

本设计解决的就是这个缺口：让后台刷新链跨过周末与长假，并且让周一早上出现的 Activity 是活的、内容正确的，而不是过期内容。

## 目标

- 周五晚上之后不再出现“链断了、整个周末没有任何后台任务”的状态；周一 00:00 前后有一次后台唤醒。
- 周一第一节课开始时，锁屏上有内容正确的 Live Activity（而不是空的、过期的、或正好在 08:00 被系统结束的）。
- 过期内容永不以“还在倒计时”的样子出现：Activity 过期后要么被结束消失，要么显示明确的过期态。
- 不改数据模型、不改 Core schema、不改 SideStore 分发；不新增服务器（无 APNs、无推送）。

## 非目标

- 不做推送通知服务器；不接 APNs，不用 push-to-start（没有服务器，且那是另一套架构）。
- 不改 Live Activity 的视觉样式（锁屏卡片与灵动岛布局不动，只加过期态分支）。
- 不改小组件的视觉样式（只延长它的时间线 horizon）。
- 不碰提醒系统（本地通知提醒已存在，本设计只在方案 D 里复用它的预约机制，不改它）。
- 不改课表、学期、假期的任何业务逻辑。

## 反目标

- 不用 `NSTimer` / 后台常驻来“保活”（iOS 没有通用保活 API，后台进程会被挂起，纯属浪费电）。
- 不把 horizon 无限延长（Apple 建议 `earliestBeginDate` 不超过一周；约得越远，系统越可能忽略）。
- 不为了“准时”而每 15 分钟约一次后台任务（系统会按使用习惯与预算节流，约了也不跑，反而拉低 App 的后台任务成功率，影响以后被调度）。
- 不在用户没开通知权限时强行发通知（方案 D 的通知只在已授权时预约）。

## 约束

- 本机是 Linux，没有 Swift、Xcode、模拟器和真机。所有验证只能走 GitHub Actions CI（`classday-ios-ipa.yml` 的构建 + 主题截图）与叶原野真机点验；后台任务的实际触发时机只能在真机上观察，CI 测不到。
- 安卓版在 GitHub 上没找到（2026-11-12 已查）。本批只保证共享逻辑、数据结构和行为跨平台可用，不写安卓代码；唤醒时间的计算（纯日期数学）放 Core，iOS 的 `BGTaskScheduler` 调用留在 App 层。
- 分发不变：侧载，LocalDevPN + SideStore，安装包在 classday-releases。
- 后台刷新是 best-effort：系统按使用习惯、电池、低电量模式决定是否/何时跑；用户强退 App 或关掉“后台 App 刷新”后，链断，直到下次打开 App。

## 已核实的系统限制（设计依据，2026-11-12 查证）

- **Live Activity 最长 8 小时**（Apple 官方文档）：从创建起算 8 小时后系统自动结束它，立即从灵动岛移除；锁屏上最多再留 4 小时（总计 12 小时）。`update` 不延长这 8 小时；只有 end + 重新 request 才能重开一个 8 小时窗口。
- **`staleDate` 只标记过期，不删除**：过了 `staleDate`，系统把 `context.isStale` 置 true，UI 要自己按这个状态渲染；否则计时器（`Text(date, style: .timer)` 是系统画的）会一直往上数——这正是 11-12 那个 bug 的视觉形态。
- **结束策略**：`end(nil, dismissalPolicy: .immediate)` 立刻消失；`.default` 由系统决定，最多留 4 小时；`.after(date)` 留到指定时间（最多 4 小时后）。
- **`BGAppRefreshTask`**：每次约 30 秒执行时间；`earliestBeginDate` 的意思是“不早于这个时间”，不是“在这个时间跑”；系统按 App 使用习惯、电池、低电量模式调度，可能晚几小时或根本不跑；低电量模式与后台刷新被关时不跑；用户强退 App 后不跑，直到下次打开；Apple 建议不要约超过一周以后。
- **WidgetKit 时间线**：时间线条目是预计算的未来状态，系统按时间线本地渲染，**不需要 App 唤醒**；`.after(date)` 只是刷新请求，不是保证；每个小组件每天约 40–70 次刷新预算（观测值，非 Apple 承诺的数字），用得多会被节流；条目至少间隔约 5 分钟。
- **36 小时上限是 Classday 自己定的**，不是 iOS 的限制：`NextClassSnapshot.nextBoundary(horizon: 36h)` 与 `WidgetProjection.horizon = 36h`。Apple 只建议不超过一周。

## 已查到的事实（实施起点）

调用链（main e2efb19，`Classday/` 下，`VersionArchive` 除外）：

- `NextClassActivity.scheduleBackgroundRefresh(document:calendar:now:)`（`ClassdayApp/Sources/NextClassActivity.swift:9`）：算 `nextBoundary`，无边界就直接 return（**不排任务——链就是在这里断的**）；有边界就提交 `BGAppRefreshTaskRequest(identifier: "com.classday.app.refresh-next-class", earliestBeginDate: boundary)`。提交失败只记 `NSLog`。
- `NextClassActivity.syncAsync`（同文件 :24）：无快照 → 全部 Activity `.immediate` 结束；有快照 → 同 `courseID` 的 update，不同则全部 end 后重新 `Activity.request`（attributes 不可变，换课必须重建）。`ActivityContent(state, staleDate: snapshot.endsAt)`。
- `NextClassSnapshot.make`（`ClassdayCore/Sources/ClassdayCore/ActivityBridge.swift:38`）：上课中返回当前课（`phase: "上课中"`, `endsAt` = 下课时间）；否则返回**当天**的下一节（`phase: "下一节"`, `endsAt` = 上课时间）；下一节不在当天就返回 nil（休息日守卫：不让灵动岛为明天的课亮 24 小时以上）。
- `NextClassSnapshot.nextBoundary(after:document:calendar:horizon: 36h)`（同文件 :85）：候选 = 当前课结束、下一节开始、第一个快照发生变化的午夜；只取 `(date, date+36h]` 内的最小值。**周五 16:00 的用例已有测试锁定**：`ActivitySnapshotTests.testNextBoundaryOnRestDayAndHorizon` 断言周五 16:00 返回 nil（周一 00:00 在 56 小时外）；周六 12:00 返回周一 00:00（正好 36 小时，含端点）。
- `AppDelegate.application(didFinishLaunchingWithOptions:)`（`ClassdayApp/Sources/AppDelegate.swift:20`）：注册后台任务；回调里读 App Group 共享 store → `syncAsync` → `scheduleBackgroundRefresh` → `setTaskCompleted(success: true)`。注释写明：先 await ActivityKit 更新再完成任务，否则系统可能在更新还在飞时挂起 App。
- `AppModel.refreshLiveActivityIfNeeded(now:)`（`ClassdayApp/Sources/AppModel.swift:667`）：前台打开（`ClassdayApp.swift` 的 `scenePhase == .active`）与磁盘变化时调。**排程不经过 diff 门**（注释写明：休息日打开、快照 nil 也要排，否则链永远种不上）；ActivityKit 同步经过 `shouldUpdate` diff 门。`lastLiveActivitySnapshot`（同文件 :142）只活在内存里。
- `NextClassActivityWidget`（`ClassdayWidget/Sources/ExtraWidgets.swift`）：锁屏卡片与灵动岛只按 `context.state` 渲染，**从不读 `context.isStale`**（全仓 grep 为零）——过期后照样显示计时器。
- `LockNextWidget`（同文件，锁屏 accessory 小组件）：`LockNextView` 在条目时间点读共享 store 算 `NextClassSnapshot.make`，显示标题/地点/计时器；与 Live Activity 无关。
- `WidgetProjection.timelinePlan`（`ClassdayCore/Sources/ClassdayCore/WidgetProjection.swift:165`）：horizon 同样 36h，最多 40 条目，`refreshAfter` = 最后一条目时间（否则 now + max(15 分钟，6 小时））；`ClassdayProvider.getTimeline` 用 `.after(refresh)` 交给系统。
- `Info.plist`（`Classday/Config/Classday-Info.plist`）：`BGTaskSchedulerPermittedIdentifiers` = `com.classday.app.refresh-next-class`；`UIBackgroundModes` 只有 `fetch`；`NSSupportsLiveActivities` = true。部署目标 iOS 17.0。
- **App 从不检查 `backgroundRefreshStatus`**（全仓 grep 为零）：用户关掉后台刷新后，链断了也不会有任何提示。

断档的精确形态（已按代码推演）：

1. 周五最后一节 14:00–15:40 结束。15:40 的边界任务（周五白天种的）在系统允许时跑起来，sync 发现快照 nil，结束 Activity；再排程时 `nextBoundary` 为 nil → **不再排任务，链断**。
2. 周六、周日：没有任何后台唤醒。锁屏上什么也没有（Activity 已在周五被结束）。
3. 周一 00:00：快照翻转为“下一节”，但没有唤醒，Activity 不出现；要等用户周一早上打开 App，前台同步才重建。
4. 如果 15:40 那次任务被系统推迟/跳过（best-effort），周五的 Activity 会留在锁屏上，计时器越过 15:40 继续往上数——就是 11-12 报的 bug 的形态。

## 做法：四个方案

### 方案 A — 延长 horizon + 心跳续种（核心修复：修链）

**做法：**
- `nextBoundary` 的 horizon 从 36 小时放到 7 天（Apple 建议的上限内）。周五 16:00 就能直接算出周一 00:00（56 小时）这个边界并排上。
- `scheduleBackgroundRefresh` 在 `nextBoundary` 为 nil 时不再直接返回，改为排一个“心跳”：下一个午夜（实现时二选一：固定午夜，或 `now + 24h`——见 D5）。心跳任务里只做两件事：`syncAsync` + 重新排程。链在任何时候都不会死：有课的边界按边界走，没课的日子每天午夜心跳一次。
- 心跳与边界共用现有的任务回调（先 sync 再 schedule），不新增任务类型、不新增 Info.plist 项。

**覆盖的最长断档：** 理论上无限——链每天至少续种一次，跨周末（56h）与长假（数天无课）都能桥接；每次心跳后重新评估，最迟在有课那天的 00:00 前完成排程。

**可行性：** API 完全支持；`earliestBeginDate` 约到 7 天内在 Apple 建议范围内。但每次唤醒仍是 best-effort：系统可能推迟/跳过某一次（电池、低电量、后台刷新被关、强退）。一次心跳被跳过 = 恢复晚一天（下次心跳再试）。**A 解决“链断”，不保证“准时”。**

**耗电/节流风险：** 极低。有课的日子与现在完全一样（只在课界唤醒）；无课的日子每天最多一次 30 秒内的唤醒（读本地 store + 算快照 + 可能的 ActivityKit 调用，无网络）。但要注意：后台任务成功率影响系统以后的调度——心跳里不要做多余工作，失败时也要 `setTaskCompleted(success: true)`（现在就是这么做的，别改成 false，否则系统会降权）。

**改动面：** 小。Core：`nextBoundary` 的 horizon 参数（默认 36h→7 天，或新增心跳 fallback）；App 层：`scheduleBackgroundRefresh` 的 nil 分支。无 schema 改动，无 Info.plist 改动。

**CI 可验证：** 可以。`ActivitySnapshotTests` 补纯逻辑用例：周五 16:00 → 周一 00:00（56h）；7 天长假无课 → 心跳落在下一个午夜；心跳后重新排程仍为 nil 时不死循环。`classday-ios-ipa` 构建验证编译。

**A 不解决：** 8 小时 Activity 寿命（见方案 B）；任务迟到（周一 07:00 的任务可能 08:30 才跑）；用户强退/关后台刷新（无解，只能等前台打开）。

### 方案 B — 课前唤醒（解决 8 小时寿命；依赖 A）

**做法：** 在 A 的基础上，排程时区分边界类型：
- 若下一个变化是“午夜翻转”，且翻转后第一课在 8 小时开外，**不把任务约在午夜，约在第一节课开始前 60 分钟**（如周一 08:00 的课 → 约周一 07:00）。这次唤醒新建的 Activity 从 07:00 活到 15:00，覆盖第一节课全程。
- 午夜本身仍需一次唤醒来排程——由 A 的心跳完成（午夜心跳里 sync 发现快照仍是“下一节 08:00”，按本规则约出 07:00 的任务）。
- 一天课程从 08:00 排到 21:00 的极端情况：同一 Activity 从 07:00 创建只能活到 15:00，晚课会断。现有链式续种在每次课界都会跑 sync；需补一条规则：当 Activity 已存活超过约 7 小时且后面还有课时，end + 重新 request 一次（重开 8 小时窗口）。这个分支只在极端课表出现，平时不触发。

**覆盖的最长断档：** 与 A 相同（链不断）；额外保证周一第一节课开始时 Activity 是“刚建不久”的活卡片，而不是午夜创建、08:00 正好被系统结束的卡片。

**可行性：** 同 A。依赖系统准时性更强：07:00 的任务晚到 08:30 也能接受——Activity 出现晚，但内容正确（第一节课进行中）；配合方案 C 的锁屏小组件，用户在 08:00–08:30 之间仍有东西可看。

**耗电/节流风险：** 与 A 相同（每天最多一两次唤醒）。注意：不要把“课前 60 分钟”做成每节课都约——只对“跨天后的第一节课”用这条规则；当天内的课界沿用现有边界排程，否则唤醒次数翻倍。

**改动面：** 中。Core：`nextBoundary` 需要返回边界类型（午夜翻转 vs 课界），或新增一个 `nextWakeDate` 计算（纯日期数学，放 Core，与 App 的 `BGTaskScheduler` 调用分离）；App 层不动。测试：补“午夜翻转 + 首课 8 小时开外 → 唤醒时间为首课前 60 分钟”的用例。

**与 A 的关系：** B 依赖 A——没有 A 的链，周一 00:00 根本不会有唤醒去约 07:00 的任务。B 不能单独上；A 可以单独上（只是周一 08:00 的 Activity 可能正好过期）。

### 方案 C — 优雅降级：stale 渲染 + 锁屏小组件兜底（体验底线）

**做法（接受“周一早上 Live Activity 可能不在”，把底线做好）：**
1. `NextClassActivityWidget` 按 `context.isStale` 渲染过期态：过了 `staleDate` 就不再显示往上数的计时器，改显示“已结束，打开课曜查看下一节”（锁屏卡片与灵动岛展开态都改；compact/minimal 保持图标）。
2. `WidgetProjection.timelinePlan` 的 horizon 从 36 小时放到 7 天（与方案 A 的 horizon 对齐），`maximumEntries` 40 条不变——7 天约需每天午夜 + 每节课起止 ≈ 每周 30–40 条，刚好够；若不够，优先保留午夜与每节课开始，丢弃课结束条目。锁屏 accessory 小组件（`LockNextWidget`）靠预计算的时间线条目在周一 00:00 后显示“下一节 08:00 高等数学”——**小组件不需要 App 唤醒**，系统按时间线本地渲染。
3. 快照为 nil 时继续用 `.immediate` 结束过期 Activity（已实现，不动）；补一个诊断：App 检查 `backgroundRefreshStatus`，若用户关了后台刷新，在“关于”页提示一句“后台刷新已关，锁屏下一节只在打开 App 后更新”（文案待定）。

**覆盖的最长断档：** 锁屏小组件在周一早上大概率有正确内容（时间线条目已预计算）；Live Activity 缺席时用户看到的是明确提示，而不是过期课程。**C 不修复 Live Activity 本身**，只修“没东西看”和“看到错的东西”。

**可行性：** 全部是现有机制。`isStale` 是 ActivityKit 现成的状态；时间线延长只是改常数与条目筛选。风险在 WidgetKit 预算：`.after` 只是刷新请求，预算紧张时系统会晚服务；但时间线条目本身不需要刷新——条目一旦下发，系统按时间切换显示，不耗预算。

**耗电/节流风险：** 几乎为零。小组件不新增唤醒；只是时间线更长。

**改动面：** 小到中。Widget 层：`NextClassActivityWidget` 加 `isStale` 分支；Core：`timelinePlan` horizon 与条目筛选；App 层：关于页加一行后台刷新状态提示（可选）。

**CI 可验证：** 可以。`timelinePlan` 的纯逻辑用例（7 天 horizon 内条目覆盖到下周一第一节课；条目数 ≤40；`refreshAfter` 正确）；`isStale` 分支是 SwiftUI 视图代码，CI 只能验证编译，行为要真机看。

### 方案 D — 本地通知兜底（系统级准时唤醒；补充手段）

**做法：** 在周五最后一次同步时，若下一次课在 36 小时开外，用 `UNUserNotificationCenter` 预约一条本地通知在“第一节课前 60 分钟”（如周一 07:00）触发，文案如“下一节 08:00 高等数学，在 XX，点开查看”，点通知打开 App，前台同步立即重建 Activity。课表改动时取消重约（与现有提醒的预约/取消逻辑复用同一机制——`ReminderScheduler` 已在 App 内，见 `AppModel.refreshReminders`）。

**覆盖的最长断档：** 只要通知权限开着，周一早上用户必定被提醒；打开 App 后 Activity 立即恢复。**通知不受后台刷新预算、强退（已预约的通知在强退后仍会响）、低电量模式的影响**——这是它比 A/B 更“准时”的唯一原因。

**可行性：** 完全可行。但它是“提醒”不是“Live Activity”：用户看到的是一条横幅，不是锁屏卡片；不点开就还是没有 Activity。

**耗电/节流风险：** 零（系统级通知，无后台唤醒）。风险在打扰：每周一早上多一条通知；只在“下次课 >36 小时”时才约，且默认行为要由叶原野定（默认开 / 默认关 / 只在长假时开）。

**改动面：** 中。App 层：预约/取消逻辑（下次课 >36h 时约，课表改动/删除课表时取消）；不碰 Core 计算（复用 `nextBoundary` / `nextOccurrence` 的结果）。测试：预约决策的纯逻辑部分可测（何时约、约几点）；通知实际触发只能真机验证。

**定位：** 补充手段，不是替代。适合与 A/C 组合做“保底”，不适合单独作为方案（单独上 D，周一早上仍没有 Live Activity，只有横幅）。

### 考虑过但不推荐

- **`BGProcessingTask` 替代/补充 `BGAppRefreshTask`**：需要充电/空闲才跑，执行时间几分钟——对 30 秒的本地读盘刷新来说是杀鸡用牛刀，且调度比 App Refresh 更不积极。不推荐。
- **推送（APNs）/ push-to-start**：没有服务器。建一套推送服务只为叫醒周一的 Activity，成本与隐私代价都远超收益；且 push-to-start 要求 iOS 17.2+。不推荐。
- **缩短唤醒间隔（每 15 分钟约一次）**：系统按使用习惯与预算节流，约了也不跑；频繁提交失败的任务会拉低 App 的后台任务成功率，反而减少以后的调度机会。不推荐。
- **把 Activity 的 `staleDate` 设到很远**：`staleDate` 只是 freshness 标记，改它不延长 8 小时寿命，也不阻止计时器往上数。不推荐。

## 方案对比

|  | A：延长 horizon + 心跳 | B：课前唤醒（依赖 A） | C：优雅降级 + 小组件兜底 | D：本地通知兜底 |
|---|---|---|---|---|
| 解决的问题 | 链断（周末/长假无唤醒） | 8 小时寿命（午夜建的 Activity 到 08:00 过期） | 过期内容难看；Live Activity 缺席时无东西可看 | 唤醒不准时（系统可能迟到/跳过） |
| 覆盖的最长断档 | 无限（每天续种） | 与 A 相同 | 小组件：7 天预计算；Live Activity：不修复 | 通知准时；Activity 仍需用户点开 |
| iOS 限制下是否可行 | 是（7 天内在 Apple 建议范围） | 是 | 是（现有机制） | 是（需通知权限） |
| 耗电/节流风险 | 极低（无课日每天 ≤1 次 30 秒唤醒） | 与 A 相同 | 几乎为零 | 零（系统通知） |
| 改动面 | 小（Core horizon + 心跳分支） | 中（Core 边界类型/`nextWakeDate`） | 小到中（Widget isStale 分支 + 时间线 horizon） | 中（App 层预约/取消） |
| CI 可验证 | 是（纯逻辑测试） | 是（纯逻辑测试） | 部分（时间线逻辑可测；isStale 视图只能验编译） | 部分（预约决策可测；触发只能真机） |
| 失败时的样子 | 某次心跳被跳过 → 恢复晚一天 | 07:00 任务迟到 → Activity 晚出现但内容正确 | 小组件预算紧张 → 刷新晚到；Live Activity 仍可能缺席 | 用户关通知 → 完全失效 |
| 是否依赖其他方案 | 否 | 依赖 A | 否（可独立上） | 否（可独立上，但只作补充） |

## 推荐

**推荐 A + B 为主，C 一并做，D 作为可选保底。**

- A 是必选项：不断链，其他一切都无从谈起；改动最小、收益最大。
- B 是 A 的自然延伸：不加 B，A 修好的链会在周一 08:00 交出一个正好过期的 Activity——等于修了一半。B 的额外改动只在 Core 的排程计算里，不碰 App 层。
- C 的 `isStale` 分支是体验底线，成本小：即使 A/B 的某次唤醒被系统跳过，用户看到的也是“已结束，打开课曜查看”而不是往上数的过期计时器；小组件时间线延长则是目前唯一“不需要 App 唤醒就能在周一早上显示正确内容”的通道，值得同步做。
- D 只建议在叶原野接受“多一条周一早上通知”的前提下做；不接受就跳过，A+B+C 已覆盖绝大多数情况。

## 需要叶原野拍板的决策

- **D1：接受“后台刷新是 best-effort”吗？** A/B 的前提是系统可能推迟/跳过某次唤醒（一次跳过 = 恢复晚一天）。若要求“周一早上必须有”，则必须加 D 的通知兜底。
- **D2：课前唤醒的时间点：** 第一节课前 60 分钟（推荐，Activity 覆盖第一节课全程）还是 30 分钟（更贴近上课，但任务迟到的缓冲更小）？
- **D3：过期 Activity 的 UI：** 过了 `staleDate` 显示“已结束，打开课曜查看下一节”（推荐）还是直接结束消失（锁屏上什么都不留）？
- **D4：本地通知兜底（D）做不做：** 做的话默认开还是默认关？只在“下次课 >36 小时”时约，还是长假才约？
- **D5：horizon 放到几天：** 7 天（推荐，Apple 建议上限，覆盖国庆 7 天假）还是 3 天（更保守，单次约得更近，系统更可能执行）？心跳节奏：固定每天午夜（推荐，与课表按天走的节奏一致）还是 `now + 24h`？
- **D6：小组件时间线 horizon 是否同步延长（C）：** 延长到 7 天（推荐）还是保持 36 小时（小组件只兜底当天）？`maximumEntries` 40 条不够时，优先保留哪些条目（推荐：午夜 + 每节课开始，丢弃课结束条目）？
- **D7：后台刷新被关时的提示：** 在“关于”页加一行提示（推荐，文案待定）还是不提示（用户自己去系统设置看）？

## 测试与验证

- **CI（Swift 测试，`ClassdayCoreTests`）：**
  - `nextBoundary` 新 horizon：周五 16:00 → 周一 00:00（56h）；7 天长假无课 → 心跳落在下一个午夜；心跳后仍无边界时不死循环。
  - 课前唤醒：午夜翻转 + 首课 8 小时开外 → 唤醒时间为首课前 60 分钟；当天内的课界不受影响。
  - `timelinePlan` 新 horizon：条目覆盖到下周一第一节课；条目数 ≤40；`refreshAfter` 正确。
  - 预约决策（若做 D）：下次课 >36h 时约通知；课表改动时取消重约。
  - 现有用例要同步更新：`testNextBoundaryOnRestDayAndHorizon` 里“周五 16:00 返回 nil”的断言在新 horizon 下会变（改为周一 00:00），必须改测试而不是绕过它。
- **CI（构建）：** `version-snapshot` + `classday-ios-ipa` 通过；主题截图核对 `isStale` 分支的外观（截图是产物、不是断言）。
- **回归清单（`Docs/REGRESSION_CHECKLIST.md`）补项：** 周末断档场景、长假场景、过期态显示、后台刷新被关的提示、强退后的行为。
- **真机点验（叶原野，CI 测不到的部分）：**
  1. 周五最后一节课后不再打开 App，周一早上看锁屏：Live Activity 是否在第一节课前出现、内容是否正确。
  2. 低电量模式下一周末后看周一是否仍刷新。
  3. 强退 App 后周一是否断档（预期：断，需重开 App；验证前台重种是否生效）。
  4. 关掉“后台 App 刷新”后关于页提示是否出现。
  5. 通知兜底（若做 D）：周一 07:00 是否准时响，点开后 Activity 是否立即出现。

## 回滚

- 只改常数与新增分支，无 schema 改动、无迁移：回滚 = 把 horizon 改回 36 小时、删掉心跳分支（A/B），把 `isStale` 分支与时间线 horizon 改回（C），取消通知预约（D）。
- 回滚后回到现状：周末断档、过期内容按旧样子显示，不会比现在更差。
- 回滚不需要发版配合：下一次正常发版带回即可；但注意回滚后周一早上的 Activity 仍依赖用户打开 App。

## 任务拆分（实施时用，2–5 分钟粒度）

- T1：Core——`nextBoundary` horizon 36h→7 天；`scheduleBackgroundRefresh` 的 nil 分支改为心跳（下一个午夜）；补 `ActivitySnapshotTests` 用例，更新“周五 16:00 返回 nil”的旧断言。
- T2：Core——边界类型/`nextWakeDate`：午夜翻转 + 首课 8 小时开外时唤醒时间为首课前 60 分钟；补用例；极端长课日的 Activity 重建规则。
- T3：Widget——`NextClassActivityWidget` 加 `isStale` 分支；`timelinePlan` horizon 36h→7 天与条目筛选；补 `timelinePlan` 用例。
- T4：App——（若 D 批）本地通知预约/取消逻辑；关于页后台刷新状态提示（若 D7 批）。
- T5：回归清单补项；跑 CI（构建 + 主题截图核对）。
- T6：整分支评审 → draft PR → CI → 按主规则合；真机按点验清单验证。

## 留给实施时定

- 心跳的具体时刻：固定午夜还是 `now + 24h`（等 D5 批）。
- 课前唤醒的提前量：60 分钟还是 30 分钟（等 D2 批）。
- `isStale` 过期态的具体文案（等 D3 批）。
- 通知兜底的文案与默认开关（等 D4 批）。
- 7 天 horizon 内 `timelinePlan` 条目超 40 时的取舍细节（等 D6 批）。
