//+------------------------------------------------------------------+
//|                        Version.mqh                                |
//|              EA Version Management Constants                      |
//+------------------------------------------------------------------+
#property strict

// 版本号定义（语义化版本：MAJOR.MINOR.PATCH）
// - MAJOR: 重大架构变更
// - MINOR: 里程碑完成（M1=1, M2=2, ...）
// - PATCH: Bug修复/小优化

#define EA_VERSION_MAJOR    2
#define EA_VERSION_MINOR    2
#define EA_VERSION_PATCH    0
#define EA_VERSION_STRING   "2.2.0"

// 里程碑状态
#define MILESTONE_M1_COMPLETE  false   // Mean Reversion Family
#define MILESTONE_M2_COMPLETE  false   // Trend Pullback Family
#define MILESTONE_M3_COMPLETE  false   // XAUUSD Alpha

// 构建信息（可由 CI/CD 注入）
#define EA_BUILD_DATE     __DATE__
#define EA_BUILD_TIME     __TIME__
#define EA_GIT_BRANCH     "EA_2.0.0"
#define EA_GIT_COMMIT     "429f7c3"

//+------------------------------------------------------------------+
//| 获取版本字符串                                                       |
//+------------------------------------------------------------------+
string GetEAVersion() {
    return EA_VERSION_STRING;
}

//+------------------------------------------------------------------+
//| 获取完整版本信息                                                     |
//+------------------------------------------------------------------+
string GetEABuildInfo() {
    return StringFormat("EA v%s | Branch: %s | Build: %s %s",
        EA_VERSION_STRING, EA_GIT_BRANCH, EA_BUILD_DATE, EA_BUILD_TIME);
}
