allprojects {
    repositories {
        // 本地预置的 Flutter 引擎产物。storage.googleapis.com 直连常被限速到 100KB/s 以下，
        // 由 scripts/prefetch-flutter-engine.sh 预下载；目录存在才生效。
        maven { url = uri("${rootDir}/../.flutter-m2") }
        // 国内镜像优先，缺失时回落官方仓库。
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
