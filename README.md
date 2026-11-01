# ds-bar · DeepSeek 用量与余额

安卓应用：主页展示 DeepSeek 账户余额、token 用量、按 key / 按模型明细；通知栏常驻余额；快捷设置磁贴一键查看。界面 Flutter，取数与后台任务在 Kotlin 原生层。

## 下载安装

已编译的安装包在 [Releases](https://github.com/cnefan31/ds-bar/releases) 页。按设备架构选一个：

| 文件 | 体积 | 适用 |
| --- | --- | --- |
| `app-arm64-v8a-release.apk` | 7.2 MB | 绝大多数真机 |
| `app-armeabi-v7a-release.apk` | 6.6 MB | 32 位老机型 |
| `app-x86_64-release.apk` | 7.3 MB | 模拟器 |

不确定架构时用 arm64-v8a；装错了系统会拒绝安装并提示 ABIs 不兼容。

```bash
adb install -r app-arm64-v8a-release.apk
```

签名证书为自签（CN=DS Bar），安装时系统会提示「未知来源」。
后续版本沿用同一证书，可直接覆盖升级。

## 功能

| 模块 | 内容 |
| --- | --- |
| 账户余额 | 官方 `GET /user/balance`：总余额、充值、赠送、可用状态 |
| 今日用量 | 消费、token、请求次数，缓存命中/未命中/输出构成条 |
| 本月用量 | 逐日柱状图 + 合计 |
| 按 API Key | 每个 key 的本月消费、token、请求与今日消费 |
| 按模型 | 每个模型的 token 占比、消费、缓存命中率 |
| Key 状态 | 每个已配置 key 的有效性校验（打码展示） |
| 通知栏 | 常驻通知：余额 + 今日消费 + 本月消费（无操作按钮，点卡进 App） |
| 快捷磁贴 | 快捷设置面板显示余额，点按刷新 |
| 后台刷新 | 平台 `JobScheduler` 定时（最少 15 分钟），仅联网时执行，重启后保留 |

## 数据来源

| 数据 | 接口 | 鉴权 | 稳定性 |
| --- | --- | --- | --- |
| 余额 | `https://api.deepseek.com/user/balance` | API Key | 官方公开接口 |
| 本月用量 / 消费 | `https://platform.deepseek.com/api/v0/usage/amount`、`usage/cost` | 平台 userToken | 网页私有接口，可能变更 |
| 今日用量 | `https://platform.deepseek.com/api/v0/usage/export`（本地时区窗口） | 平台 userToken | 同上 |
| 分 key 明细 | `https://platform.deepseek.com/api/v0/usage/export`（本月 CSV） | 平台 userToken | 同上 |

DeepSeek 官方公开 API 只有余额与模型列表，没有按时间或按 key 的 token 用量接口。因此：

- 余额走官方接口，凭据只需一个有效 API Key。
- token 用量走开放平台网页接口，需要浏览器登录态的 `userToken`。
- 余额是账户级数据：同一账号下所有 key 共享同一个余额，不存在「每个 key 各自余额」。
- 分 key 用量按平台侧 `api_key_name` 聚合，本地 key 名称与平台名称一致时对照才准确。

### 获取 userToken

1. 浏览器登录 <https://platform.deepseek.com>；
2. F12 → Application → Local Storage → `https://platform.deepseek.com`；
3. 复制 `userToken` 的值（形如 `{"value":"..."}` 时取 `value` 字段）；
4. 粘贴到 App「设置 → 平台 userToken」。

若接口返回非 JSON 或 401，补上同域 `Cookie` 再试。userToken 会过期，过期后重新复制。

## 安全

- 凭据只存应用私有 `SharedPreferences`，不上传任何第三方服务器。
- 所有请求由手机直连 `deepseek.com`，无中转。
- 凭据明文不进入 Dart 层缓存；界面只显示「已配置 / 未配置」与打码后的 key。
- 通知栏与磁贴只显示金额与 token 数，不显示 key。

## 架构

| Flutter (Dart) | Android 原生 (Kotlin) |
| --- | --- |
| `main.dart` 入口与主题 | `MainActivity` MethodChannel 桥 |
| `src/app_state.dart` 全局状态 | `DsRepository` 取数 + 汇总快照 |
| `src/native_bridge.dart` 通道封装 | `DsHttp` 原生 HTTP |
| `src/models.dart` 防御式解析 | `UsageParser` JSON / CSV 解析 |
| `src/ui/home_page.dart` 概览 | `DsPrefs` 配置与缓存 |
| `src/ui/settings_page.dart` 设置 | `BalanceNotification` 常驻通知 |
| `src/ui/charts.dart` 图表 | `BalanceTileService` 快捷磁贴 |
| `src/format.dart` 展示格式化 | `RefreshJobService` 定时刷新 |
| `src/theme.dart` 设计 token | `Fmt` 金额 / token 格式化 |

设计取舍：取数与聚合全部在原生层。定时任务、通知栏、磁贴都在原生侧运行，若聚合放在 Dart，后台刷新时无法更新通知与磁贴。Dart 只做展示与配置写入，通过单一 MethodChannel 通信。

数据流：

```
DsRefresh.perform()
  → DsRepository.refresh()       逐 key 查余额、拉平台用量、汇总
  → 写 SharedPreferences 缓存
  → BalanceNotification.show()   更新常驻通知
  → BalanceTile.requestUpdate()  更新磁贴
```

界面读同一份缓存快照，三处显示永远一致。

## 构建

环境要求：Flutter 3.47+、JDK 17+、Android SDK（compileSdk 36）、minSdk 24。

```bash
flutter pub get
bash scripts/prefetch-flutter-engine.sh debug   # 首次构建前跑一次，见下
flutter test                                    # 37 个 Dart 单测 + 界面渲染测试
flutter analyze                                 # 静态检查（当前零告警）
flutter build apk --debug                       # 调试包
bash scripts/build-release.sh                   # 发布包：split-per-abi 三个分包（默认）
bash scripts/build-release.sh universal         # 发布包：三架构合一的单包
```

发布包请用 `scripts/build-release.sh`，不要直接跑 `flutter build apk --release`：

- 默认产出 **split-per-abi 三个分包**，每架构一个，各自最小：

  | 包 | 体积 | 适用 |
  | --- | --- | --- |
  | `app-arm64-v8a-release.apk` | 7.2MB | 绝大多数真机 |
  | `app-armeabi-v7a-release.apk` | 6.6MB | 32 位老机型 |
  | `app-x86_64-release.apk` | 7.3MB | 模拟器 |

- `universal` 模式产出三架构合一的单包（约 21.2MB），任意设备直接装，分发最省事，
  代价是体积是分包的三倍。

`--target-platform` 是唯一有效的 ABI 选择入口——写在 `gradle.properties` 或
`defaultConfig.ndk.abiFilters` 均无效，因为引擎库由 `CopyFlutterJniLibsTask`
按 `target-platform` 注入，绕过 ndk 过滤。

Android 原生单测：

```bash
cd android && ./gradlew :app:testDebugUnitTest
```

真机端到端（验证 MethodChannel、原生解析、界面真实渲染）：

```bash
flutter test integration_test/native_e2e_test.dart -d <deviceId>
```

### 首次构建的网络坑

Gradle 从 `storage.googleapis.com/download.flutter.io` 拉 Flutter 引擎产物，国内直连常被限到 100KB/s 以下，一次构建要等半小时以上；同一域名用 curl 却正常。因此：

- `scripts/prefetch-flutter-engine.sh` 用 curl 并发预下载四个引擎产物到 `.flutter-m2/`；
- `android/build.gradle.kts` 把 `.flutter-m2` 作为首选 maven 仓库，缺失时自动回落官方源；
- Maven 依赖走 `maven.aliyun.com` 镜像优先（官方 Maven Central 走 Cloudflare，同样慢）。

`.flutter-m2/` 已加入 `.gitignore`，约 400MB。换 Flutter 版本后需重跑脚本。

安装到已连接设备：

```bash
flutter install
# 或按设备架构选分包
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk    # 绝大多数真机
adb install -r build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk  # 32 位老机型
adb install -r build/app/outputs/flutter-apk/app-x86_64-release.apk       # 模拟器
```

## 发布包体积

基线 49.8MB → 现每架构分包 6.6–7.3MB，削减 85% 以上。逐项来源（以 arm64 分包为例）：

| 措施 | 效果 | 代价 |
| --- | --- | --- |
| split-per-abi 分包（每包只带自己架构的 `.so`） | 49.8 → 17.5MB | 需按设备架构分发；universal 单包仍为 21.2MB |
| `.so` 改为可压缩（`useLegacyPackaging`） | 17.5 → 8.2MB | 安装时解压，占用磁盘 23MB |
| 移除 WorkManager，改用平台 `JobScheduler` | dex 1.48 → 1.02MB | 无 |
| ProGuard 去掉 `-keep class io.flutter.** { *; }`，改用 `-keepnames` | dex 1.02 → 0.73MB | 类名保留、成员可裁；官方 `flutter_proguard_rules.pro` 已覆盖真实反射需求 |
| 移除 `androidx.core`（用平台 Notification API） | 计入上项 | 无 |
| 移除未使用的 `cupertino_icons` | 0.26MB 字体 | 无 |
| `--split-debug-info` | 再降 0.2MB | 崩溃堆栈需 `flutter symbolize` 配合 `build/symbols` |

第三方依赖现状：本项目自己引入的运行时依赖为**零**；构建图里剩下的
`kotlin-stdlib` 与 `kotlinx-coroutines` 是 Flutter 嵌入层经
`androidx.lifecycle:lifecycle-common` 传递进来的，删不掉。
Kotlin 侧不接受任何 `implementation(...)`，`RefreshJobServiceTest` 会守住这条线；
同一测试也会拦住「把 `-keep class io.flutter.** { *; }` 加回来」这种让 dex 胖一倍的回退。

`libflutter.so` 与 `libapp.so` 的 ELF `PT_LOAD` 对齐为 64KB，满足 Android 15+
的 16KB page size 要求。

## 首次使用

1. 进「设置」；
2. 「API Keys」添加至少一个 `sk-` key，名称建议与平台侧一致；
3. 「平台 userToken」填入 userToken 并保存；
4. 回「概览」下拉刷新，或点右上角同步；
5. 需要通知栏余额：打开「通知栏常驻余额」，按系统提示授予通知权限；
6. 需要磁贴：打开「快速设置磁贴」，点「添加到快捷面板」把 DeepSeek 余额拖入面板。

没有凭据时可打开「演示数据」预览全部界面，数字为虚构。

## 已知限制

- 平台网页接口非官方，DeepSeek 改版会失效；失效时余额仍可用，用量区显示「用量不可用」。
- 今日用量按本地时区 0 点起算，跨时区时与实际略有偏差。
- 后台刷新受系统省电策略影响，实际间隔可能长于设定值。
- 分 key 用量以平台 `api_key_name` 为键，本地重命名不改变平台侧名称。
- 各 key 用量之和与账户总量会因 free tier、过期赠送额等出现小额差异，属正常。

## 测试

已实测通过的验证：

| 层次 | 命令 | 结果 |
| --- | --- | --- |
| Dart 单测 + 界面渲染 | `flutter test` | 37 条全过 |
| Kotlin 单测 | `cd android && ./gradlew :app:testDebugUnitTest` | 58 条全过 |
| 真机端到端 | `flutter test integration_test/native_e2e_test.dart -d <id>` | 3 条全过（HLK AL10 / Android 10） |
| 静态检查 | `flutter analyze` | No issues found |
| 构建 | `bash scripts/build-release.sh` | 分包 6.6–7.3MB；universal 21.2MB（基线 49.8MB） |

覆盖范围：

- 金额 / token / 计数 / 相对时间格式化，含 null、NaN、Infinity、负数边界；Kotlin 侧 `Fmt.money` 与 Dart 侧分级一致，同一数字在界面与通知里写法相同；
- 快照与配置的防御式解析：缺字段、类型错乱、非对象输入均不抛异常；
- CSV 解析：引号内逗号、转义引号、紧凑日期形式；
- 界面：完整数据下余额 / 今日 / 按 key / 按模型 / Key 状态均渲染正确；无凭据时不显示 0 元余额，而是配置引导；
- 端到端：MethodChannel 可用、原生快照结构可解析、演示数据真实上屏、通知与磁贴路径不抛异常。

尚未验证：真实账号的线上取数。需要填入真实 API Key 与 userToken 才能验，本机无可用凭据。
