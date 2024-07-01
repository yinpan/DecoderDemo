//
//  PMAppStat.m
//  Demo
//
//  Created by yinpan on 2023/8/18.
//

#import "PMAppStat.h"
#import <mach/mach.h>
#import <mach/mach_types.h>
#import <pthread.h>
#import <os/proc.h>
#import <sys/sysctl.h>

@implementation PMAppStat

+ (int64_t)memory {
    int64_t memory = self.memoryFootprint;
    if (memory) {
        return memory;
    }
    return self.memoryAppUsed;
}

+ (int64_t)memoryAppUsed {
    struct task_basic_info info;
    mach_msg_type_number_t size = (sizeof(task_basic_info_data_t) / sizeof(natural_t));
    kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
    if (kerr == KERN_SUCCESS) {
        return info.resident_size;
    } else {
        return 0;
    }
}

+ (int64_t)memoryFootprint {
    task_vm_info_data_t vmInfo;
    vmInfo.phys_footprint = 0;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count);
    if (result != KERN_SUCCESS)
        return 0;

    return vmInfo.phys_footprint;
}

+ (CGFloat)availableSizeOfMemory {
    if (@available(iOS 13.0, *)) {
        return os_proc_available_memory() / 1024.0 / 1024.0;
    }
    return 0.0f;
}

+ (int64_t)memoryDeviceUsed {
    int mib[2];
    int64_t physical_memory;
    size_t length;
    
    mib[0] = CTL_HW;
    mib[1] = HW_MEMSIZE;
    length = sizeof(int64_t);
    sysctl(mib, 2, &physical_memory, &length, NULL, 0);
    
    vm_statistics64_data_t vmStats;
    mach_msg_type_number_t infoCount = HOST_VM_INFO64_COUNT;
    
    kern_return_t kernReturn = host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vmStats, &infoCount);
    
    if (kernReturn != KERN_SUCCESS) {
        NSLog(@"Error with host_statistics64(): %d", kernReturn);
        return 0;
    }
    
    int64_t usedMemory = (int64_t)vmStats.active_count + (int64_t)vmStats.inactive_count + (int64_t)vmStats.wire_count;
    usedMemory *= (int64_t)vm_page_size;
    return usedMemory;
}

+ (int64_t)physicalMemory {
    int mib[2];
    int64_t physical_memory;
    size_t length;
    
    mib[0] = CTL_HW;
    mib[1] = HW_MEMSIZE;
    length = sizeof(int64_t);
    sysctl(mib, 2, &physical_memory, &length, NULL, 0);
    return physical_memory;
}

+ (double)cpuUsedByAllThreads {
    double totalUsageRatio = 0;
    double maxRatio = 0;

    thread_info_data_t thinfo;
    thread_act_array_t threads;
    thread_basic_info_t basic_info_t;
    mach_msg_type_number_t count = 0;
    mach_msg_type_number_t thread_info_count = THREAD_INFO_MAX;

    if (task_threads(mach_task_self(), &threads, &count) == KERN_SUCCESS) {
        for (int idx = 0; idx < count; idx++) {
            if (thread_info(threads[idx], THREAD_BASIC_INFO, (thread_info_t)thinfo, &thread_info_count) == KERN_SUCCESS) {
                basic_info_t = (thread_basic_info_t)thinfo;

                if (!(basic_info_t->flags & TH_FLAGS_IDLE)) {
                    double cpuUsage = basic_info_t->cpu_usage / (double)TH_USAGE_SCALE;
                    if (cpuUsage > maxRatio) {
                        maxRatio = cpuUsage;
                    }
                    totalUsageRatio += cpuUsage;
                }
            }
        }

        assert(vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_t)) == KERN_SUCCESS);
    }
    return totalUsageRatio;
}

@end
