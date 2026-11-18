# ClassDay 待用户要求后再推送

本地模式是默认工作方式。本分支上尚未推送的提交列 Here。只有用户明确要求更新 GitHub 或发版时，由自动化/Grok 只推 `autoloop/improvements`，不要推 `main`，不要 force push，然后跑 CI 并发布。不要因此向用户发卡片。

更新时间（伦敦时间）：2026-11-15 07:52

政策更新（伦敦时间）：2026-11-15 02:01 UTC：本地模式改为长期默认，等用户要求再推送，不再按「GitHub 恢复后」自动推送。

## GitLab 推送记录（仅 GitLab，非 GitHub）

- 2026-11-15 04:13 伦敦时间 | 5388b9e | 用户已同意推送到 GitLab 后，已把 codemagic.yaml 提交 5388b9e（在 "Build unsigned iphoneos app and widget" 前增加 "Install Metal toolchain" 步骤）推到 GitLab 私有项目 gitlab.com/yyy-group9390046/YYY-project 的 `main`。GitHub 未推送，以下提交对 GitHub 仍待用户要求后再推送。

- 2026-11-15 03:57 里斯本时间 | 258f21a | 用户明确同意（「可以，把 ClassDay 推到 GitLab 并用 Codemagic 打包」）后，已把 autoloop/improvements（10f276d）+ codemagic.yaml 提交 258f21a 推到 GitLab 私有项目 gitlab.com/yyy-group9390046/YYY-project 的 `main` 和 `autoloop/improvements`，供 Codemagic 打无签名 IPA（工作流 classday-ios-unsigned）。GitHub 未推送，以下提交对 GitHub 仍待用户要求后再推送。

## 当前未推送或待核对的提交

- 2026-11-15 08:38 伦敦时间 | 69b6603 | autoloop/improvements | 功能 5–8 源码范围与验收证据清单，明确平台/真机/审美待办；文档检查通过，无产品逻辑变更；待用户要求后再推送。

- 2026-11-15 08:21 伦敦时间 | 3f728e5 | autoloop/improvements | Android 分项成绩保存前拒绝无效算法与保留的越界分数；先复现两项失败，修复后 JVM 74 项通过，平台/真机未验收；待用户要求后再推送。

- 2026-11-15 08:00 伦敦时间 | e0144f9 | autoloop/improvements | Android 已有评分规则的分项成绩录入/保存，衔接期末预测；核心 JVM 72 项通过，平台/设备保存撤销未验收；待用户要求后再推送。

- 2026-11-15 07:52 伦敦时间 | 2ebaa7f | autoloop/improvements | 补测试：拍照残留清理只删普通文件、跳过时间不可读的条目，防止误删同名目录或未知时间文件；核心 JVM 69 项通过，平台/真机未验收；待用户要求后再推送。

- 2026-11-15 07:42 伦敦时间 | 46e20f9 | autoloop/improvements | Android 拍照中断后过期临时照片恢复清理，保护活动/近期/无关文件；JVM 68 项通过，平台/真机未验收；待用户要求后再推送。

- 2026-11-15 07:40 伦敦时间 | f2d163d | autoloop/improvements | 文案：拍照导入说明补上「只在本机识别、只追加不替换、取消或没读出来都不改课表」，失败提示按清晰度和 16 MB 上限说明，关于页本版说明改写并与按钮统一用「识别」；仅字符串，静态项目检查、git diff --check 和核心 JVM 66 项通过；本机无 Android SDK，界面未编译；待用户要求后再推送。

- 2026-11-15 07:34 伦敦时间 | 65a7e94 | autoloop/improvements | 补测试：钉住拍照临时文件的目录隔离（同名文件在别的目录不被删）、16 MB 大小边界、占位目录拒绝、重复清理与非法文件名、符号链接越界不解析；核心 JVM 66 项通过，静态项目检查与 git diff --check 通过；相机/OCR/界面未验收；待用户要求后再推送。

- 2026-11-15 07:22 伦敦时间 | 262cb53 | autoloop/improvements | Android 直接拍照识别入口与本次临时照片清理，复用既有权限声明和文件共享配置；核心 JVM 63 项通过，平台/相机/OCR 未验收；待用户要求后再推送。

- 2026-11-15 07:04 伦敦时间 | 020360b | autoloop/improvements | 修正 iOS 今日测试两处 isEmpty 属性误调用；静态检查通过，Swift 测试/编译未验收；待用户要求后再推送。

- 2026-11-15 06:58 伦敦时间 | bd02449 | autoloop/improvements | 补测试：钉住课间空档时今日首页仍指向当天下一节、已完成数只计已结束课程、今日列表不变；静态项目检查与 git diff --check 通过，核心 JVM 61 项通过；本机无 Xcode，Swift 新测试与 iOS 编译待用户要求推送后云端构建；待用户要求后再推送。

- 2026-11-15 06:48 伦敦时间 | 1c0033f | autoloop/improvements | iOS 今日首页状态抽到 Core，新增四组边界测试；静态项目检查通过，Swift 测试/平台编译/真机未验收；待用户要求后再推送。

- 2026-11-15 06:31 伦敦时间 | ee2a414 | autoloop/improvements | 两端今日首页突出下一节与今天课程，iOS 次要安排折叠、Android 新增今日入口；核心 JVM 61 项通过，平台编译/真机/审美未验收；待用户要求后再推送。

- 2026-11-15 06:25 伦敦时间 | e8a6d47 | autoloop/improvements | 期末预测无效规则提示补上小数录入口径和示例（30% 写 0.3），避免把「合计为 1，即 100%」误读成可填 30/70；仅两端文案，项目检查与 git diff --check 通过；Swift/Android 界面未构建；待用户要求后再推送。

- 2026-11-15 06:22 伦敦时间 | 036e6f1 | autoloop/improvements | 补测试：把期末预测权重钉在 0–1 小数语义（0.3/0.7 可算，30/70 这类百分数判为无效规则），与「每条合计需为 1，即 100%」提示一致；核心 JVM 58 项通过，Swift 新增测试未执行；待用户要求后再推送。

- 2026-11-15 06:14 伦敦时间 | ec6864d | autoloop/improvements | 期末预测规则错误提示把「每条合计需为 100%」改为「每条合计需为 1，即 100%」，与权重按 0–1 小数录入一致；仅文案，项目检查与 git diff --check 通过；Swift/Android 界面未构建；待用户要求后再推送。

- 2026-11-15 06:08 伦敦时间 | 460f501 | autoloop/improvements | Android 我的页外观控件移到二级页并整理界面审美复核材料；静态检查通过，平台编译/真机/视觉未验收；待用户要求后再推送。

- 2026-11-15 06:04 伦敦时间 | 48fbb14 | autoloop/improvements | 期末成绩预测文案：更新日志从已发布的 2.9.3 移到 2.9.4 并补进标题，两端结果/缺成绩/规则错误提示统一并说明「多条算法取最容易达到的一条」；仅文案，项目检查与核心 JVM 57 项通过；Swift 单测及两端界面未验证；待用户要求后再推送。

- 2026-11-15 05:58 伦敦时间 | 15dff20 | autoloop/improvements | 补测试：期末预测在任一算法缺成绩时不给出精确最低分、零权重不要求录分、重复分项/空分支等无效规则；PDF 大页降采样尺寸和 10 页含分隔符文字上限；核心 JVM 57 项通过，Swift 新增测试未执行；待用户要求后再推送。

- 2026-11-15 05:52 伦敦时间 | b97b760 | autoloop/improvements | Android PDF 导入文案：补全页数/大小/本机识别/预览不替换说明，Word 说明挪回对应按钮下；仅文案，静态检查通过；Android 界面/APK 未构建；待用户要求后再推送。

- 2026-11-15 05:49 伦敦时间 | 4c76c3f | autoloop/improvements | 补 Android PDF 导入策略边界单测（渲染不超过 2 倍、10 万字含分页符的上下边界、每张空白页都按页序提示），核心 JVM 54 项通过；Android 渲染/OCR/界面/APK 未验收；待用户要求后再推送。

- 2026-11-15 05:46 伦敦时间 | 3e476f0 | autoloop/improvements | 两端期末成绩预测核心与现有成绩页入口，Android 核心 JVM 51 项通过；Swift 测试及两端界面/构建未验收；待用户要求后再推送。

- 2026-11-15 04:55 伦敦时间 | 6175743 | autoloop/improvements | Android PDF 逐页本机 OCR 导入及限制策略，预览确认后追加；核心 JVM 47 项通过，Android 渲染/OCR/界面/APK 未验收；待用户要求后再推送。

- 2026-11-15 05:00 伦敦时间 | c849855 | autoloop/improvements | iOS 侧载小组件共享组与快照镜像修复及配套单元测试；本地 Python 校验通过，iOS 待用户要求推送后云端构建；待用户要求后再推送。

- 2026-11-15 04:36 伦敦时间 | b553942 | autoloop/improvements | Android 普通周课表长按拖拽，复用整学期冲突检查与撤销；核心 JVM 43 项通过，界面编译/真机未验收；待用户要求后再推送。

- 2026-11-15 03:48 伦敦时间 | 39125d8 | autoloop/improvements | Android 单工作表 Excel .xlsx 本地导入和确认追加；核心 JVM 39 项通过，Android 界面/APK 未构建；待用户要求后再推送。

- 2026-11-15 03:29 伦敦时间 | 87a9896 | autoloop/improvements | Android Word .docx 正文/普通表格本地导入，确认后追加；核心 JVM 33 项测试通过，Android 界面/APK 未构建；待用户要求后再推送。

- 2026-11-15 03:10 伦敦时间 | 8b423ca | autoloop/improvements | Android 粘贴邮件课表、本地识别及确认追加入口；核心 JVM 26 项测试通过，Android 界面/APK 未构建；待用户要求后再推送。

- 2026-11-15 03:07 里斯本时间 | a5cc77d | autoloop/improvements | 应用 N 纯白毛玻璃图标到 iOS AppIcon 与 Android app_icon；icon_background 已是 #FFFFFF，自适应前景 inset 保持 8%；待用户要求后再推送。

- 2026-11-15 02:50 伦敦时间 | 5f2b60f | autoloop/improvements | Siri 两个课表意图、核心答案单测、上课专注自动化说明及更新日志；已有 ScheduleAnswersTests 单元测试覆盖；待用户要求后再推送。iOS 待用户要求推送后云端构建。
- 2026-11-15 02:45 伦敦时间 | 0d9b48c | autoloop/improvements | iOS 小组件时间线快照及共享回退修复；待用户要求后再推送。
- Android / core test and docs commits (4a56b08, 7e9d44f, 76e1de6, fe4836c); 待用户要求后再推送。

- 2026-11-15 12:31 伦敦时间 | 82f0f08 | autoloop/improvements | 2.9.5-A 两端统一导入数据、JSON/ICS 确认、移除演示恢复及同步版本；本地核心 74 项/项目/版本快照检查通过，界面/平台/真机未验收；待用户要求后再推送。

- 2026-11-15 12:54 伦敦时间 | abf09c8 | autoloop/improvements | 2.9.5-B 第一步：两端自动应用内上课专注和减扰，核心 JVM 77 项通过；Swift/平台/真机/审美未验收，语音/系统过滤/勿扰仍待完成；待用户要求后再推送。

- 2026-11-15 13:16 伦敦时间 | f5b15c6 | autoloop/improvements | 2.9.5-B 语音查课：Siri 短句/课堂入口、Android 标准查询/手机中文识别；核心 JVM 84 项及静态检查通过，平台/语音/真机未验收，Focus Filter/勿扰仍待完成；待用户要求后再推送。

- 2026-11-15 13:41 伦敦时间 | 03c8b51 | autoloop/improvements | 2.9.5-B 系统界面过滤/可选独立上课勿扰，默认关闭且需明确同意及授权；核心 JVM 90 项及静态检查通过，平台/Swift/系统授权/后台真机/审美未验收；待用户要求后再推送。

- 2026-11-15 14:05 伦敦时间 | 157a0be | autoloop/improvements | 2.9.5-C 审计后整理学习页、数据功能归位、移除主路径 Fénix/iCloud、补齐校验后的任务编辑；核心 JVM 95 项及静态检查通过，平台/真机/审美未验收；待用户要求后再推送。

- 2026-11-15 14:51 伦敦时间 | 95989e7 | autoloop/improvements | 2.9.5-D 原创关于、公开清单来源/明确失败提示、严格体积与 SHA 下载校验、版本元数据核对；核心 JVM 98 项及静态检查通过，平台/网络安装/实际包版本/审美未验收；待用户要求后再推送。

- 2026-11-15 15:03 伦敦时间 | 57917da | autoloop/improvements | 2.9.5-E iOS 地图搜索选点预览、Android 已安装地图与步行路线、坐标校验及提示；核心 JVM 104 项通过，平台/真实地图/审美未验收；待用户要求后再推送。

- 2026-11-15 15:05 伦敦时间 | 1a681d8 | autoloop/improvements | 生产下载使用可测流式完整性/安装门槛，连接/短长包/错摘要/中断/安装失败回归；核心 JVM 110 项通过，真实 HTTP/安装器/iOS 服务仍未验收；待用户要求后再推送。

- 2026-11-15 15:07 伦敦时间 | 380a397 | autoloop/improvements | iOS 统一导入由根视图单一呈现，避免依赖未选中标签页；项目与集成静态检查通过，真机跨页未验收；待用户要求后再推送。

- 2026-11-15 15:12 伦敦时间 | e7a65f6 | autoloop/improvements | 替补测试轮：补公开更新源固定为 GitLab 且不再含停用 GitHub、带坐标的 geo 搜索保留编码地名的回归用例；核心 JVM 112 项与静态检查通过，平台/真实地图/安装未验收；待用户要求后再推送。

- 2026-11-15 15:34 伦敦时间 | bd29054 | autoloop/improvements | 2.9.5 中文日志校准：教室导航按平台写清（iOS 搜点预览、Android 可选系统/高德/百度地图，无坐标按名称搜索）、更新包体积与 SHA-256 校验及失败提示、数据页导入不再只在今日页弹出；项目与版本快照检查通过，Swift/界面/真机/审美未验收；待用户要求后再推送。

- 2026-11-15 15:37 伦敦时间 | 4628362 | autoloop/improvements | 修正 Swift 日志测试为 2.9.5，保留六版本历史；项目、版本快照及日志静态检查通过，Swift 未运行；待用户要求后再推送。

- 2026-11-15 15:42 伦敦时间 | e48d3a0 | autoloop/improvements | 测试轮：静态检查新增「共享导入弹窗必须挂在根视图、不得只装在今日页」的守卫（覆盖 380a397 回归），项目与版本快照检查通过；Swift 未编译、真机跨页未验收；待用户要求后再推送。

- 2026-11-15 15:47 伦敦时间 | a7abdbd | autoloop/improvements | 2.9.5 中文日志措辞再校对：iOS「未验收的 iCloud 入口」改为「iCloud 同步入口已移除」，Android「补齐任务编辑」改为「考试和作业都能编辑，填错会提示并保留内容」；只动文案，未改逻辑；项目与版本快照检查通过，Swift/Android 界面未编译；待用户要求后再推送。

- 2026-11-15 15:52 伦敦时间 | 5cbaa96 | autoloop/improvements | 文案：iOS 2.9.5 日志「回归数据页」改为「都放回数据页」，Android 日志补「数据页不再提供恢复演示数据入口」；只改字符串，项目/版本快照/核心 JVM 112 项通过，Swift/Android 界面未编译；待用户要求后再推送。

- 2026-11-15 18:54 伦敦时间 | e634793 | autoloop/improvements | 测试轮 c120dd0..605e839：补周导航同日保留、跨日/换学期重置、首尾边界反向翻页及夏令时/闰日/跨年回归；Android 核心 JVM 117 项、iOS 项目静态检查通过；Swift 测试与 Android 界面/手势未运行，iOS 待用户要求推送后云端构建；待用户要求后再推送。

- 2026-11-15 20:55 伦敦时间 | e05ab44 | autoloop/improvements | 修复双端智能导入按当前学期准确映射上下课时间；Android 核心 JVM 118 项及项目/快照静态检查通过；设备未验收，iOS 待用户要求推送后云端构建；待用户要求后再推送。

- 2026-11-15 20:58 伦敦时间 | 2d0d2b4 | autoloop/improvements | 测试轮 e634793..e05ab44：补智能导入重复时刻、缺节、倒序、缺失时刻、乱序作息及混合有效安排元数据保留回归；Android 核心 JVM 121 项、iOS 项目静态检查通过；Swift/设备未验收，iOS 待用户要求推送后云端构建；待用户要求后再推送。

- 2026-11-15 21:01 伦敦时间（GMT） | 3bcd593 | autoloop/improvements | 文案：新增 2.9.6 智能导入说明，区分两端不匹配处理并说明既有课程不自动修正；待用户要求后再推送。

- 2026-11-15 21:10 GMT（伦敦时间）· `e2307e9` · `autoloop/improvements`：双端 ICS 文件/订阅课程按当前学期作息准确映射，无法对应时跳过并在确认界面提示；Android 核心 122 项通过，Swift 回归已补未运行。待用户要求后再推送；iOS 待用户要求推送后云端构建。

- 2026-11-15 21:23 GMT（伦敦时间）· `9ff6834` · `autoloop/improvements`：双端智能导入保留源文件写明的节次，只写开始时间或时间没写全的行不再整条丢掉；节次与时间互相矛盾时跳过/阻止导入并说明原因，不再静默按其中一边写入。Android 核心 JVM 123 项通过，Swift 回归已补未运行。待用户要求后再推送；iOS 待用户要求推送后云端构建。

- 2026-11-15 21:23 GMT（伦敦时间）· `ea00f60` · `autoloop/improvements`：更新 2.9.6 智能导入说明，写清节次优先、半截时间与矛盾时间的处理；待用户要求后再推送。

- 2026-11-15 21:31 GMT（伦敦时间）· `8c0e73d` · `autoloop/improvements`：本机测试补充：源文件节次超出当前学期时，若同时写全了上下课时间则按时间导入，不再整条丢掉；节次有效但与时间矛盾时仍会提示。Android 核心 JVM 123 项通过，Swift 回归已补未运行。待用户要求后再推送；iOS 待用户要求推送后云端构建。

- 2026-11-15 21:44 GMT（伦敦时间）· `f62ed70` · `autoloop/improvements`：只写一半时间（例如只有开始时间）时以节次为准，不再因半截时间判为冲突；两端规则一致。Android 核心 JVM 123 项通过，Swift 回归已补未运行。待用户要求后再推送；iOS 待用户要求推送后云端构建。

- 2026-11-15 21:43 GMT（伦敦时间）· `a9a24ed` · `autoloop/improvements`：粘贴文字与拍照/相册识别出的文本行不再丢掉写明的节次，同时写了上下课时间也以节次为准、时间只用来核对，半截时间不再猜成冲突；Android 界面里只写「第3-4节」不再落到第一节。Android 核心 JVM 124 项通过，Swift 回归已补未运行。待用户要求后再推送；iOS 待用户要求推送后云端构建。

- 2026-11-15 21:57 GMT（伦敦时间）· `bf805c1` · `autoloop/improvements`：测试轮 784454e..44f9c10 补测：只写结束时间时同样以节次为准，节次超出学期且只有半截时间时明确跳过；两端各补对称用例。Android 核心 JVM 124 项通过，Swift 未编译未运行。待用户要求后再推送；iOS 待用户要求推送后云端构建。

- 2026-11-15 22:05 GMT（伦敦时间）· `537444d` · `autoloop/improvements`：安卓发布签名密码不再写在 build.gradle.kts 里，改为读环境变量 CLASSDAY_KEYSTORE_FILE / CLASSDAY_STORE_PASSWORD / CLASSDAY_KEY_ALIAS / CLASSDAY_KEY_PASSWORD（本机已设为用户环境变量），没有时读不进 git 的 android/keystore/signing.properties；都没有则发布包不签名。signingReport 验证 release 仍用原证书签名。待用户要求后再推送。

- 2026-11-15 23:25 GMT（伦敦时间）· `c9d98bf` · `autoloop/improvements`：修 bug（卡片 308/309）安卓应用编译失败与考场名含 % 崩溃；新增 CourseReminder/ExamCopy 与 12 项 JVM 回归，核心 136 项、`:app:assembleDebug` 通过（未碰签名）；考试页真机显示与滑动手势未验收，iOS 待用户要求推送后云端构建。待用户要求后再推送。


- 2026-11-16 00:47 GMT（伦敦时间）· `7fb9bfe` · `autoloop/improvements`：按本人决定移除安卓语音查课表（Assistant capability、搜索快捷方式、classday://query、语音查课页与 ScheduleAnswers）；iOS Siri 不动。核心 129 项、`:app:assembleDebug` 通过。待用户要求后再推送。

- 2026-11-16 00:49 GMT（伦敦时间）· `4b53d31` · `autoloop/improvements`：2.9.6-G 两端版本升到 2.9.6（Android 20906）与更新日志；VersionArchive/previous 刷新为提交树的 2.9.5；check_version_snapshot / check_project 通过。iOS 待用户要求推送后云端构建。待用户要求后再推送。

- 2026-11-16 00:54 GMT（伦敦时间）· `5ebb045` · `autoloop/improvements`：安卓今日/学习/详情不再拿已结束考试当最近一场或显示 0 天后开考（审查第 147、164 条）；ExamTimeline + 7 项测试。待用户要求后再推送。

- 2026-11-16 00:57 GMT（伦敦时间）· `c2f8110` · `autoloop/improvements`：安卓课表日期条点选本周其他日期生效，周视图/列表跟随（审查第 145 条）；4 项测试，模拟器核对。待用户要求后再推送。

- 2026-11-16 01:02 GMT（伦敦时间）· `01f8ec7` · `autoloop/improvements`：安卓页面文字与背景统一按系统深浅色取色，删除无调用旧视图（审查第 130 条）。核心 140 项、assembleDebug 通过。待用户要求后再推送。

- 2026-11-16 01:12 GMT（伦敦时间）· `a648f10` · `autoloop/improvements`：安卓导入时源节次本学期不存在、改按时间导入会写明替换，确认页显示起止节次与时间（审查第 216 条）。核心 141 项、assembleDebug 通过。待用户要求后再推送。

- 2026-11-16 01:15 GMT（伦敦时间）· `5ead51a` · `autoloop/improvements`：iOS 识别结果编辑页提示与实际导入规则一致（审查第 214 条）。iOS 待用户要求推送后云端构建。待用户要求后再推送。

- 2026-11-16 01:08 GMT（伦敦时间）· `3778027` · `autoloop/improvements`：iOS 导入编辑页提示去掉「本学期没有这些节次」（起止倒序或缺节次时也成立），2.9.6 智能导入说明同步按时间替换规则。check_project / check_version_snapshot / git diff --check 通过；纯文案未跑平台构建。iOS 待用户要求推送后云端构建。待用户要求后再推送。

- 2026-11-16 01:08 GMT（伦敦时间）· `9f06255` · `autoloop/improvements`：两端 2.9.6 更新日志补本轮修复（考场名含 % 崩溃、已结束考试倒计时、日期条点选、深色对比、导入按时间替换）；纯文案，静态检查通过。待用户要求后再推送。
- 2026-11-16 01:21 GMT（伦敦时间）· `d094f3d` · `autoloop/improvements`：iOS 2.9.6 更新日志的导入说明按实际提示收紧（iOS 编辑页只提示「将按下方时间导入」，只有 Android 写明替换成哪几节），避免夸大；纯文案，classday/Tools/check_project.py 与 git diff --check 通过，未跑平台构建。待用户要求后再推送。
- 2026-11-16 01:27 GMT（伦敦时间）· `6063ac7` · `autoloop/improvements`：2.9.5-A–E 安卓模拟器逐项截图验收记录（本机 debug 构建通过，A–E 均通过）；2.9.6 本地源码完成、可交由自动化打包。iOS 待用户要求推送后云端构建。待用户要求后再推送。
- 2026-11-16 03:25 GMT（伦敦时间）· `1d5aa7e` · `autoloop/improvements`：2.9.6 智能导入说明按平台收准（iOS 只提示按下方时间导入，只有 Android 预览写明替换成了哪几节），与 2.9.6 更新日志口径一致；纯文案，Classday/Tools/check_project.py 与 git diff --check 通过，未跑平台构建。待用户要求后再推送。
- 2026-11-16 12:59 GMT（伦敦时间）· `204c27b` · `autoloop/improvements`：修 R-0002——Android 二级页面按系统返回键改为返回上一页（顶层 BackHandler 接已有返回栈，首页仍按系统默认退出）；纯 UI 导航，未改版本号/数据/签名，check_project 通过，未跑平台构建与模拟器，待测试岗复核。待用户要求后再推送。

- 2026-11-16 21:25 GMT（伦敦时间）· `8048429` · `autoloop/improvements`：2.9.7 双端同步——安卓包体 60.5 MB→21.4 MB（限制 ABI、开 R8/资源裁剪、图标库换 icons-core、移除下线登录依赖）；安卓补上每节课「提前 N 分钟」提醒与考试/作业提醒（新增 core ReminderPlan + Receiver + 独立通道，与 iOS NotificationPlan 同口径）；iOS 合并成绩冲突不再 precondition 崩溃；两端清理 Fénix/iCloud 残留；数据格式文档与 JSON Schema 回正；版本升至 2.9.7（Android 20907）。安卓单元测试 167 项全绿、check_project/check_version_snapshot 通过；iOS 未编译（本机无 Xcode），IPA 待云端构建。已本地提交，待用户要求后再推送。
