//
//  UnityInteractiveBaseController.swift
//  Tiger
//
//  Created by king on 2022/4/26.
//

import Foundation

protocol SafeThread {
    func beSafe(_ block: @escaping ()-> Void)
}

internal extension SafeThread {
    func beSafe(_ block: @escaping ()-> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async {
                block()
            }
        }
    }
}

// Blurrr工程里面使用的锁封装
final class BLUnfairLock {
    private let unfairLock: os_unfair_lock_t

    init() {
        unfairLock = .allocate(capacity: 1)
        unfairLock.initialize(to: os_unfair_lock())
    }

    deinit {
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    private func lock() {
        os_unfair_lock_lock(unfairLock)
    }

    private func unlock() {
        os_unfair_lock_unlock(unfairLock)
    }
    
    func doLock<T>(_ closure: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try closure()
    }

    func doLock(_ closure: () throws -> Void) rethrows {
        lock(); defer { unlock() }
        try closure()
    }
}
