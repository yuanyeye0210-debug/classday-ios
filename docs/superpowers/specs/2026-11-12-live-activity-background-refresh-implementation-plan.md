# Live Activity 后台刷新后续 — 实施计划

批准：2026-11-12 22:59，叶原野选“第一个：按推荐的来 A+B+C，不做通知”。
设计：`docs/superpowers/specs/2026-11-12-live-activity-background-refresh-design.md`（已批，照此做，不重设计）。
基线：main `e2efb197`（2.9.1 已发版）。分支：`feat/live-activity-background-refresh`（从 main 切）。
版本 bump 不在本分支做（合 main 后另开 bump 批，版本号待定）。

## 已拍板的决策（D1–D7，按设计推荐值）

- D1：接受后台刷新 best-effort（某次唤醒被跳过 = 恢复晚一天），不加 D。
- D2：课前唤醒 = 第一节课前 **60 分钟**。
- D3：过期态文案 = “已结束，打开课曜查看下一节”（锁屏卡片与灵动岛展开态；compact/minimal 保持图标）。
- D4：不做 D（本地通知兜底）。
- D5：horizon **7 天**；心跳 = **固定每天午夜**（不是 now+24h）。
- D6：小组件时间线 horizon 同步 **7 天**；`maximumEntries` 40 不变；超 40 时优先保留午夜 + 每节课开始，丢弃课结束条目。
- D7：关于页加一行提示（后台刷新已关时）。

## 任务（2–5 分钟粒度，TDD：先写失败测试，再写最少实现，再重构）

### T1 — Core：horizon 7 天 + 心跳（A）
- T1.1 `ClassdayCore/Sources/ClassdayCore/ActivityBridge.swift`：`nextBoundary` 默认 horizon 36h → 7 天（`nextBoundary(horizon:)` 参数保留，默认值改 7 天；调用点核对）。
- T1.2 `ClassdayApp/Sources/NextClassActivity.swift`：`scheduleBackgroundRefresh` 的 nil 分支不再直接 return，改为排心跳 = 下一个午夜（`Calendar.nextDate(after:matching: .hour=0, minute=0)` 思路，按仓内既有写法）；心跳回调复用现有任务回调（先 sync 再 schedule），不新增任务类型、不改 Info.plist。
- T1.3 `ClassdayCore/Tests/ClassdayCoreTests/ActivitySnapshotTests.swift`：补用例——周五 16:00 → 周一 00:00（56h）；7 天长假无课 → 心跳落在下一个午夜；心跳后仍无边界时不死循环。**更新旧断言** `testNextBoundaryOnRestDayAndHorizon` 里“周五 16:00 返回 nil”（新 horizon 下改为周一 00:00），必须改测试，不绕过。
- T1.4 自查：心跳里只做读本地 store + 算快照 + 可能的 ActivityKit 调用；失败时仍 `setTaskCompleted(success: true)`（别改成 false）。

### T2 — Core：课前唤醒 + 极端长课日重建（B，依赖 T1）
- T2.1 Core 新增纯日期计算 `nextWakeDate`（放 Core，与 App 的 `BGTaskScheduler` 调用分离；或给 `nextBoundary` 返回边界类型——二选一，按仓内风格定）：下一个变化是“午夜翻转”且翻转后第一课在 8 小时开外 → 唤醒时间 = 首课前 60 分钟；当天内的课界不受影响。
- T2.2 极端长课日规则：Activity 已存活约 7 小时且后面还有课时，end + 重新 request 一次（重开 8 小时窗口）；平时不触发。实现位置按 `syncAsync` 现有结构定（`NextClassActivity.swift:24`）。
- T2.3 补用例：午夜翻转 + 首课 8 小时开外 → 唤醒时间为首课前 60 分钟；当天内课界不变；长课日重建分支（可用注入 now / fake clock 的方式测，照仓内既有测试写法）。

### T3 — Widget：isStale 分支 + 时间线 7 天（C）
- T3.1 `ClassdayWidget/Sources/ExtraWidgets.swift`：`NextClassActivityWidget` 按 `context.isStale` 渲染过期态（锁屏卡片与灵动岛展开态显示 D3 文案，不再显示往上数的计时器；compact/minimal 保持图标）。
- T3.2 `ClassdayCore/Sources/ClassdayCore/WidgetProjection.swift:165`：`timelinePlan` horizon 36h → 7 天；条目筛选按 D6（优先午夜 + 每节课开始，超 40 丢弃课结束条目）；`refreshAfter` 语义不变。
- T3.3 补 `timelinePlan` 用例：7 天 horizon 内条目覆盖到下周一第一节课；条目数 ≤40；`refreshAfter` 正确。

### T4 — App：关于页后台刷新提示（C / D7）
- T4.1 App 检查 `backgroundRefreshStatus`（`UIApplication.shared.backgroundRefreshStatus`），关了时在“关于”页加一行提示，文案如“后台刷新已关，锁屏下一节只在打开 App 后更新”（文案按 App 内既有风格微调，保持中文）。
- T4.2 该提示只读状态、不引导改系统设置以外的事；不新增权限请求。

### T5 — 回归清单 + 评审
- T5.1 `Docs/REGRESSION_CHECKLIST.md` 补一节（新 §11）：周末断档场景、长假场景、过期态显示、后台刷新被关的提示、强退后的行为（预期：断，需重开 App，前台重种生效）。
- T5.2 swift_ci_preflight 扫描：`grep -rn "throw$"`, `catch is CancellationError`, 返回值函数缺 `return`, SwiftData enum 默认 `=.x`——全部清零后才算完。
- T5.3 整分支评审（0 Critical 才能推；Important/Minor 记入报告）。

## 不做的事

- 不做 D（通知预约/取消、ReminderScheduler 复用）。
- 不改数据模型、Core schema、Info.plist、视觉样式（除 isStale 分支外）、提醒系统、课表/学期/假期逻辑。
- 不加 `BGProcessingTask`、不接 APNs、不缩短唤醒间隔、不动 `staleDate` 语义。
- 不做版本 bump（另批）。

## 验证（本机无 Swift，只能走 CI）

- 本地不声称任何 Swift 测试通过；只做 grep 扫描 + 代码走读。
- 推分支后由主 agent 开 draft PR 触发 CI（`classday-ios-ipa.yml`：version-snapshot + ipa 构建 + 主题截图核对 isStale 外观）；CI 绿 + 评审 clean → 按主规则自动合 main。
- 真机点验（叶原野，CI 测不到）：周五最后一节后不再打开 App，周一早上看锁屏（Activity 是否在第一节课前出现、内容是否正确）；低电量模式；强退后行为；关后台刷新后关于页提示。

## 协调员守则

- 先读 `~/workspace/custom-skills/superpowers/SKILL.md` 与 `~/workspace/custom-skills/swift_ci_preflight/SKILL.md`，再读 `~/workspace/vendor/superpowers/skills/subagent-driven-development/SKILL.md` 与 `writing-plans/SKILL.md`。
- 每任务派一个 fresh 子代理，TDD（红-绿-重构），每任务后评审；Critical 阻塞，先修再继续。
- 工作树：`~/workspace/worktrees/classday-ios-live-activity-refresh`，分支 `feat/live-activity-background-refresh`（从 e2efb197 切；设计文档 untracked，先 commit 进分支）。
- 只做本地工作：**不推分支、不开 PR、不合 main**——推/PR/CI/合由主 agent 接手。
- 结束时给主 agent 一份终报：改了哪些文件、每任务测试与评审结果、已知未验证项（真机点验清单）、有无 Important/Minor 遗留。
