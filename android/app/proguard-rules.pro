# DS Bar 发布构建的 ProGuard/R8 规则。

# --- Flutter ---
# Flutter 官方 flutter_proguard_rules.pro 已随构建自动应用（只 -dontwarn 与
# 保留 FlutterPlugin 实现类），无需再写 -keep class io.flutter.** { *; }。
# 但嵌入层大量按类名反射（FlutterActivity/FlutterFragment 注册、FlutterJNI
# 加载、插件登记），所以只允许裁剪成员、不允许改类名。
-keepnames class io.flutter.** { *; }
-dontwarn io.flutter.**

# --- RemoteViews 自定义通知 ---
# RemoteViews 在系统进程里按名字反射调用控件方法（setTextViewText、
# setViewVisibility、setBackgroundResource 等），R8 若裁掉这些方法或控件类，
# 通知会在 StatusBar 里 inflate 失败并被静默丢弃。必须保留。
-keep class android.widget.RemoteViews { *; }
-keep class android.widget.TextView { *; }
-keep class android.widget.ImageView { *; }
-keep class android.widget.LinearLayout { *; }
-keep class android.view.View { *; }

# 通知相关入口
-keep class com.cnefan.ds_bar.BalanceNotification { *; }
-keep class com.cnefan.ds_bar.BalanceTileService { *; }

# --- 浏览器登录 ---
# 三个类都由 MainActivity 直接调用，R8 能正常裁剪与改名，不需要 keep。
# 唯一注意：PlatformLogin 用构建期字符串拼 URL，不涉及反射查找类名。

# --- JobScheduler ---
# JobService 由系统按 manifest 里的类名反射实例化，名字不能改。
-keep class com.cnefan.ds_bar.RefreshJobService { *; }

# --- 保留注解与泛型签名，避免 JSON 反射出错 ---
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# --- org.json ---
# 项目里大量用 JSONObject.opt* 做防御式解析，不涉及反射，无需额外规则。

# 保留行号，便于线上崩溃定位
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
