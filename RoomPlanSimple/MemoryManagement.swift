import Foundation
import UIKit

protocol MemoryManageable: AnyObject {
    func performMemoryCleanup()
}

final class MemoryManager {
    static let shared = MemoryManager()
    
    private var managedObjects = NSHashTable<AnyObject>.weakObjects()
    
    private init() {
        setupMemoryWarningObserver()
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    func register(_ object: MemoryManageable) {
        managedObjects.add(object)
    }
    
    func unregister(_ object: MemoryManageable) {
        managedObjects.remove(object)
    }
    
    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received - cleaning up managed objects")
        
        let objects = managedObjects.allObjects.compactMap { $0 as? MemoryManageable }
        objects.forEach { $0.performMemoryCleanup() }
        
        // Force image cache cleanup
        URLCache.shared.removeAllCachedResponses()
        
        // Suggest garbage collection
        autoreleasepool {
            // Empty autoreleasepool to release temporary objects
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Weak Reference Wrappers

final class WeakRef<T: AnyObject> {
    weak var value: T?
    
    init(_ value: T?) {
        self.value = value
    }
}

final class WeakArray<T: AnyObject> {
    private var items: [WeakRef<T>] = []
    
    var count: Int {
        return allValues.count
    }
    
    var allValues: [T] {
        items.compactMap { $0.value }
    }
    
    func append(_ value: T) {
        items.append(WeakRef(value))
    }
    
    func remove(_ value: T) {
        items.removeAll { $0.value === value }
    }
    
    func compact() {
        items.removeAll { $0.value == nil }
    }
    
    func removeAll() {
        items.removeAll()
    }
}

// MARK: - Closure Capture Helper

struct CaptureList<T: AnyObject> {
    weak var weakSelf: T?
    
    init(_ object: T) {
        self.weakSelf = object
    }
    
    func execute(_ closure: (T) -> Void) {
        guard let strongSelf = weakSelf else { return }
        closure(strongSelf)
    }
    
    func executeAsync(on queue: DispatchQueue = .main, _ closure: @escaping (T) -> Void) {
        queue.async { [weak weakSelf] in
            guard let strongSelf = weakSelf else { return }
            closure(strongSelf)
        }
    }
}

// MARK: - Timer Helper with Weak References

final class WeakTimer {
    private weak var target: AnyObject?
    private let action: (AnyObject) -> Void
    private var timer: Timer?
    
    init(target: AnyObject, interval: TimeInterval, repeats: Bool, action: @escaping (AnyObject) -> Void) {
        self.target = target
        self.action = action
        
        self.timer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: repeats
        ) { [weak self] _ in
            guard let self = self, let target = self.target else {
                self?.invalidate()
                return
            }
            self.action(target)
        }
    }
    
    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        invalidate()
    }
}

// MARK: - Resource Pool for Reusable Objects

final class ResourcePool<T> {
    private var availableResources: [T] = []
    private var inUseResources: Set<ObjectIdentifier> = []
    private let maxPoolSize: Int
    private let factory: () -> T
    
    init(maxSize: Int, factory: @escaping () -> T) {
        self.maxPoolSize = maxSize
        self.factory = factory
    }
    
    func acquire() -> T {
        if let resource = availableResources.popLast() {
            if let object = resource as? AnyObject {
                inUseResources.insert(ObjectIdentifier(object))
            }
            return resource
        } else {
            let newResource = factory()
            if let object = newResource as? AnyObject {
                inUseResources.insert(ObjectIdentifier(object))
            }
            return newResource
        }
    }
    
    func release(_ resource: T) {
        if let object = resource as? AnyObject {
            inUseResources.remove(ObjectIdentifier(object))
        }
        
        if availableResources.count < maxPoolSize {
            availableResources.append(resource)
        }
    }
    
    func drain() {
        availableResources.removeAll()
        inUseResources.removeAll()
    }
}

// MARK: - Memory Monitoring

final class MemoryMonitor {
    static let shared = MemoryMonitor()
    
    private init() {}
    
    var currentMemoryUsage: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: 1) { pointer in
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         pointer,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0
    }
    
    func logMemoryUsage(context: String) {
        let usage = currentMemoryUsage
        print("💾 Memory Usage [\(context)]: \(String(format: "%.2f", usage)) MB")
    }
}