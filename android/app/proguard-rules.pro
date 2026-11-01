# DS Bar 发布构建的 ProGuard/R8 规则。

# --- Flutter ---
-keep class io.flutter.** { *; }
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
