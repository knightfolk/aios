import Foundation
import AIOSCore

/// Deterministic admission: dependency-free work that fits the remaining
/// resource envelope, in priority order, up to the concurrency cap.
public struct Scheduler: Sendable {
    public struct WorkOrder: Sendable, Equatable {
        public var taskID: TaskID
        public var dependencies: [TaskID]
        public var resourceCost: ResourceBudget
        public var priority: Int

        public init(taskID: TaskID, dependencies: [TaskID] = [], resourceCost: ResourceBudget, priority: Int = 0) {
            self.taskID = taskID
            self.dependencies = dependencies
            self.resourceCost = resourceCost
            self.priority = priority
        }
    }

    public struct Configuration: Sendable {
        public var maxConcurrentAttempts: Int
        public var availableMemoryGB: Double
        public var availableComputeCores: Int

        public init(maxConcurrentAttempts: Int = 2, availableMemoryGB: Double = 16, availableComputeCores: Int = 8) {
            self.maxConcurrentAttempts = maxConcurrentAttempts
            self.availableMemoryGB = availableMemoryGB
            self.availableComputeCores = availableComputeCores
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func admit(pending: [WorkOrder], running: [WorkOrder]) -> [WorkOrder] {
        let slotsFree = max(0, configuration.maxConcurrentAttempts - running.count)
        guard slotsFree > 0 else { return [] }

        let memoryCommitted = running.reduce(0.0) { $0 + ($1.resourceCost.maxMemoryGB ?? 0) }
        let coresCommitted = running.reduce(0) { $0 + ($1.resourceCost.maxComputeCores ?? 0) }
        let busyTasks = Set(running.map(\.taskID))

        var admitted: [WorkOrder] = []
        var memoryUsed = memoryCommitted
        var coresUsed = coresCommitted

        for order in pending.sorted(by: { $0.priority > $1.priority }) {
            guard admitted.count < slotsFree else { break }
            // Ready = every dependency is finished (not pending, not running).
            let ready = order.dependencies.allSatisfy { dependency in
                !pending.contains { $0.taskID == dependency } && !busyTasks.contains(dependency)
            }
            guard ready else { continue }

            let neededMemory = order.resourceCost.maxMemoryGB ?? 0
            let neededCores = order.resourceCost.maxComputeCores ?? 0
            guard memoryUsed + neededMemory <= configuration.availableMemoryGB,
                  coresUsed + neededCores <= configuration.availableComputeCores else { continue }

            admitted.append(order)
            memoryUsed += neededMemory
            coresUsed += neededCores
        }
        return admitted
    }
}
