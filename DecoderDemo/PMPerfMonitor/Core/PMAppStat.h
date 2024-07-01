//
//  PMAppStat.h
//  Demo
//
//  Created by yinpan on 2023/8/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PMAppStat : NSObject

/// 当前App占用的内存
@property (nonatomic, readonly, class) int64_t memory;

/// 当前可用的内存
@property (nonatomic, readonly, class) CGFloat availableSizeOfMemory;

/// 当前CPU的使用率
@property (nonatomic, readonly, class) double cpuUsedByAllThreads;

/// 当前设备占用的内存
@property (nonatomic, readonly, class) int64_t memoryDeviceUsed;

/// 当前设备的物理内存
@property (nonatomic, readonly, class) int64_t physicalMemory;

@end

NS_ASSUME_NONNULL_END
