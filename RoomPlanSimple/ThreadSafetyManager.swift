import Foundation
import Combine

// MARK: - Thread Safety Protocols

protocol ThreadSafe {
    var lock: NSLock { get }
    func performSynchronized<T>(_ block: () throws -> T) rethrows -> T
}

extension ThreadSafe {
    func performSynchronized<T>(_ block: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try block()
    }
}

// MARK: - Atomic Property Wrapper

@propertyWrapper
struct Atomic<T> {
    private let lock = NSLock()
    private var _value: T
    
    init(wrappedValue: T) {
        self._value = wrappedValue
    }
    
    var wrappedValue: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
    
    var projectedValue: Atomic<T> { self }
    
    func mutate(_ mutation: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        mutation(&_value)
    }
}

// MARK: - Thread-Safe Collections

final class ThreadSafeArray<T>: ThreadSafe {
    let lock = NSLock()
    private var _array: [T] = []
    
    var count: Int {
        performSynchronized { _array.count }
    }
    
    var isEmpty: Bool {
        performSynchronized { _array.isEmpty }
    }
    
    func append(_ element: T) {
        performSynchronized { _array.append(element) }
    }
    
    func append(contentsOf elements: [T]) {
        performSynchronized { _array.append(contentsOf: elements) }
    }
    
    func remove(at index: Int) {
        performSynchronized {
            guard index < _array.count else { return }
            _array.remove(at: index)
        }
    }
    
    func removeAll() {
        performSynchronized { _array.removeAll() }
    }
    
    func removeFirst(_ k: Int = 1) {
        performSynchronized {
            let countToRemove = min(k, _array.count)
            _array.removeFirst(countToRemove)
        }
    }
    
    subscript(index: Int) -> T? {
        performSynchronized {
            guard index >= 0 && index < _array.count else { return nil }
            return _array[index]
        }
    }
    
    func forEach(_ body: (T) throws -> Void) rethrows {
        let copy = performSynchronized { _array }
        try copy.forEach(body)
    }
    
    func map<U>(_ transform: (T) throws -> U) rethrows -> [U] {
        let copy = performSynchronized { _array }
        return try copy.map(transform)
    }
    
    func filter(_ isIncluded: (T) throws -> Bool) rethrows -> [T] {
        let copy = performSynchronized { _array }
        return try copy.filter(isIncluded)
    }
    
    func first(where predicate: (T) throws -> Bool) rethrows -> T? {
        let copy = performSynchronized { _array }
        return try copy.first(where: predicate)
    }
    
    func toArray() -> [T] {
        performSynchronized { _array }
    }
}

final class ThreadSafeDictionary<Key: Hashable, Value>: ThreadSafe {
    let lock = NSLock()
    private var _dictionary: [Key: Value] = [:]
    
    var count: Int {
        performSynchronized { _dictionary.count }
    }
    
    var isEmpty: Bool {
        performSynchronized { _dictionary.isEmpty }
    }
    
    subscript(key: Key) -> Value? {
        get {
            performSynchronized { _dictionary[key] }
        }
        set {
            performSynchronized { _dictionary[key] = newValue }
        }
    }
    
    func removeValue(forKey key: Key) -> Value? {
        performSynchronized { _dictionary.removeValue(forKey: key) }
    }
    
    func removeAll() {
        performSynchronized { _dictionary.removeAll() }
    }
    
    func keys() -> [Key] {
        performSynchronized { Array(_dictionary.keys) }
    }
    
    func values() -> [Value] {
        performSynchronized { Array(_dictionary.values) }
    }
    
    func toDictionary() -> [Key: Value] {
        performSynchronized { _dictionary }
    }
}

// MARK: - Main Thread Execution Helper

final class MainThreadExecutor {
    static func execute(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    static func executeSync<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        } else {
            return DispatchQueue.main.sync(execute: block)
        }
    }
}

// MARK: - Async/Await Threading Manager

actor ThreadingManager {
    private var runningTasks: [String: Task<Void, Never>] = [:]
    
    func cancelTask(named name: String) {
        runningTasks[name]?.cancel()
        runningTasks.removeValue(forKey: name)
    }
    
    func cancelAllTasks() {
        for task in runningTasks.values {
            task.cancel()
        }
        runningTasks.removeAll()
    }
    
    func executeTask(named name: String, priority: TaskPriority = .medium, operation: @escaping () async -> Void) {
        // Cancel existing task with the same name
        cancelTask(named: name)
        
        // Create new task
        let task = Task(priority: priority) {
            await operation()
            // Clean up completed task
            await self.removeCompletedTask(named: name)
        }
        
        runningTasks[name] = task
    }
    
    private func removeCompletedTask(named name: String) {
        runningTasks.removeValue(forKey: name)
    }
    
    var activeTaskCount: Int {
        runningTasks.count
    }
    
    var activeTaskNames: [String] {
        Array(runningTasks.keys)
    }
}

// MARK: - Background Queue Manager

final class BackgroundQueueManager {
    static let shared = BackgroundQueueManager()
    
    private let highPriorityQueue = DispatchQueue(label: "com.roomplan.high-priority", qos: .userInitiated, attributes: .concurrent)
    private let backgroundQueue = DispatchQueue(label: "com.roomplan.background", qos: .background, attributes: .concurrent)
    private let serialQueue = DispatchQueue(label: "com.roomplan.serial", qos: .utility)
    
    private init() {}
    
    // Execute high-priority work that affects UI
    func executeHighPriority<T>(_ work: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        highPriorityQueue.async {
            do {
                let result = try work()
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // Execute background work that doesn't affect UI immediately
    func executeBackground<T>(_ work: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        backgroundQueue.async {
            do {
                let result = try work()
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // Execute work that must be done serially to avoid race conditions
    func executeSerial<T>(_ work: @escaping () throws -> T, completion: @escaping (Result<T, Error>) -> Void) {
        serialQueue.async {
            do {
                let result = try work()
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - State Synchronization

final class StateSynchronizer<State> {
    @Atomic private var _state: State
    private let stateChangeQueue = DispatchQueue(label: "com.roomplan.state", qos: .userInitiated)
    private var observers: [(State) -> Void] = []
    private let observersLock = NSLock()
    
    init(initialState: State) {
        self._state = initialState
    }
    
    var currentState: State {
        return _state
    }
    
    func updateState(_ newState: State) {
        _state = newState
        notifyObservers(newState)
    }
    
    func updateState(using transform: @escaping (State) -> State) {
        stateChangeQueue.async { [weak self] in
            guard let self = self else { return }
            
            let currentState = self._state
            let newState = transform(currentState)
            self._state = newState
            
            DispatchQueue.main.async {
                self.notifyObservers(newState)
            }
        }
    }
    
    func addObserver(_ observer: @escaping (State) -> Void) {
        observersLock.lock()
        defer { observersLock.unlock() }
        observers.append(observer)
        
        // Notify immediately of current state
        observer(currentState)
    }
    
    private func notifyObservers(_ state: State) {
        observersLock.lock()
        let currentObservers = observers
        observersLock.unlock()
        
        for observer in currentObservers {
            observer(state)
        }
    }
}

// MARK: - Publisher Thread Safety Extension

extension Published.Publisher {
    func receiveOnMain() -> AnyPublisher<Output, Failure> {
        receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    func subscribeOnBackground() -> AnyPublisher<Output, Failure> {
        subscribe(on: DispatchQueue.global(qos: .background))
            .eraseToAnyPublisher()
    }
}

// MARK: - Debounced Executor

final class DebouncedExecutor {
    private let queue: DispatchQueue
    private var pendingWorkItem: DispatchWorkItem?
    private let lock = NSLock()
    
    init(queue: DispatchQueue = DispatchQueue.main) {
        self.queue = queue
    }
    
    func execute(after delay: TimeInterval, action: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        
        // Cancel pending work
        pendingWorkItem?.cancel()
        
        // Create new work item
        let workItem = DispatchWorkItem(block: action)
        pendingWorkItem = workItem
        
        // Schedule execution
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}

// MARK: - Thread Safety Utilities

extension NSLock {
    func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}

// Thread-safe singleton pattern helper
final class ThreadSafeSingleton<T> {
    private var instance: T?
    private let lock = NSLock()
    private let factory: () -> T
    
    init(factory: @escaping () -> T) {
        self.factory = factory
    }
    
    func getInstance() -> T {
        if let existingInstance = instance {
            return existingInstance
        }
        
        return lock.withLock {
            if let existingInstance = instance {
                return existingInstance
            }
            
            let newInstance = factory()
            instance = newInstance
            return newInstance
        }
    }
}