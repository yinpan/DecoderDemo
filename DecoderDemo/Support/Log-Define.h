//
//  Log-Define.h
//  DecoderDemo
//
//  Created by yinpan on 2024/6/4.
//

#include <syslog.h>

#ifndef Log_Define_h
#define Log_Define_h

#ifdef DEBUG
#define NSLogDebug(fmt, ...) NSLog((@"[DEBUG] %s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define NSLogDebug(...)
#endif

#define NSLogInfo(fmt, ...) NSLog((@"[INFO] " fmt), ##__VA_ARGS__)
#define NSLogWarning(fmt, ...) NSLog((@"[WARNING] " fmt), ##__VA_ARGS__)
#define NSLogError(fmt, ...) NSLog((@"[ERROR] " fmt), ##__VA_ARGS__)


#ifdef DEBUG

#define log4cplus_fatal(category, logFmt, ...) \
syslog(LOG_CRIT, "%s:" logFmt, category,##__VA_ARGS__); \

#define log4cplus_error(category, logFmt, ...) \
syslog(LOG_ERR, "%s:" logFmt, category,##__VA_ARGS__); \

#define log4cplus_warn(category, logFmt, ...) \
syslog(LOG_WARNING, "%s:" logFmt, category,##__VA_ARGS__); \

#define log4cplus_info(category, logFmt, ...) \
syslog(LOG_WARNING, "%s:" logFmt, category,##__VA_ARGS__); \

#define log4cplus_debug(category, logFmt, ...) \
syslog(LOG_WARNING, "%s:" logFmt, category,##__VA_ARGS__); \


#else

#define log4cplus_fatal(category, logFmt, ...); \

#define log4cplus_error(category, logFmt, ...); \

#define log4cplus_warn(category, logFmt, ...); \

#define log4cplus_info(category, logFmt, ...); \

#define log4cplus_debug(category, logFmt, ...); \

#endif


#endif /* Log_Define_h */





