# 2.9.5-D 关于与公开更新清单

触发：关于页简介混有其他产品名称或过多版本变更；旧更新源停用，Android 后备路径还跳过完整校验。预期：原创功能简介，版本/日志/检查更新保留；仅使用本人已选公开清单，未发布时明确提示。

实际源码：iOS 主 App Info.plist 显式引用 MARKETING_VERSION 与 CURRENT_PROJECT_VERSION；Widget 原本已引用，保持单一键。打包工作流从已构建 Info.plist 读取版本命名 IPA。源码 iOS/Android 2.9.5、Android 20905；历史设备安装包是否正确不能靠源码检查证明。

iOS 的 ClassdayUpdateManifestURL 可配置公开 HTTPS 地址，默认 https://gitlab.com/yuanyeye0210/classday-releases/-/raw/main/latest.json；Android 默认同址且 check 可注入来源。实际 GitHub API/raw 后备请求已移除。未发布、无法公开读取、网络失败、无效清单分别提示。关于改原创简介，详细变更进日志；Android 保持版本独立展示，检查移到后台并防重复点击。

Android 下载改为流式累计字节和摘要，体积必须与清单完全一致、SHA-256 必须匹配，超体积停止；拒绝不安全文件名、非公开 HTTPS 地址和缺失校验，失败不启动安装。iOS 既有下载校验保留。

## 发布格式说明（仅供将来自动化准备，不写发布库）

清单 schema_version=1，channels 含 ios/android，未发布通道可为 null。非空通道含 latest、mandatory、min_supported_version、previous、releases；release 含 version、file、download_url、sha256、size、published_at、changelog。如下仅是结构示意，所有占位值均须替换：

```json
{"schema_version":1,"channels":{"ios":null,"android":{"latest":"2.9.5","mandatory":false,"min_supported_version":"0","previous":null,"releases":[{"version":"2.9.5","file":"Classday-android-v2.9.5.apk","download_url":"https://example.invalid/Classday-android-v2.9.5.apk","sha256":"替换为真实64位十六进制SHA256","size":123,"published_at":"真实ISO时间","changelog":["中文变更"]}]}}}
```

iOS release 同结构、文件为 IPA。不能将示意直接发布；必须核对真实文件的体积、SHA、地址与版本。只有整批完成且本人明确要求发布时才由自动化写公开库并上传产物；私有 raw 地址和密钥不能进入 App。

验证：核心 JVM 98 项通过，新增完整性/不安全元数据/清单未发布提示测试。项目、版本快照、diff 和 Bundle/产物命名契约检查通过；检查中发现的 Widget 重复键已去除后重新通过。无 Swift/Xcode/Android SDK，平台编译、真实包版本、远程清单/下载/安装和截图审美仍未验收。没有访问或写入发布库，没有运行安装。待用户要求后再推送；iOS 待用户要求推送后云端构建。

## 流式下载测试补充

实际下载适配器现在调用核心 UpdatePackageStager，通过注入 source 和 install 闭包复用同一条生产门槛，不是另写一份测试专用逻辑。新增 6 项覆盖完整成功且源关闭、短/长包及错摘要拒绝安装和清理、连接失败、途中断流、非法元数据不请求源并保留无关文件、安装入口异常。最终核心 JVM 110 项通过（含地图测试）。HTTP 适配器的真实响应/重定向、Android 安装器和 iOS 服务层仍未实机验收，不能说全部网络/平台行为已通过。
