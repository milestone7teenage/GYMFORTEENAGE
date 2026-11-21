import Foundation
import SwiftUI

struct OneTimeTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var dueDate: Date
    var isRead: Bool
    
    init(id: UUID = UUID(), title: String, dueDate: Date, isRead: Bool = false) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isRead = isRead
    }
}

struct RecurringTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var time: Date // только время
    var isCompletedToday: Bool
    var lastCompletionDate: Date?
    
    init(id: UUID = UUID(), title: String, time: Date, isCompletedToday: Bool = false, lastCompletionDate: Date? = nil) {
        self.id = id
        self.title = title
        self.time = time
        self.isCompletedToday = isCompletedToday
        self.lastCompletionDate = lastCompletionDate
    }
}

@MainActor
@Observable
final class TaskStore {
    private let oneTimeTasksKey = "oneTimeTasks"
    private let recurringTasksKey = "recurringTasks"
    
    var oneTimeTasks: [OneTimeTask] = [] {
        didSet { saveOneTimeTasks() }
    }
    
    var recurringTasks: [RecurringTask] = [] {
        didSet { saveRecurringTasks() }
    }
    
    init() {
        loadOneTimeTasks()
        loadRecurringTasks()
        resetDailyCompletionStatus()
    }
    
    private func loadOneTimeTasks() {
        guard let data = UserDefaults.standard.data(forKey: oneTimeTasksKey) else { return }
        do {
            oneTimeTasks = try JSONDecoder().decode([OneTimeTask].self, from: data)
        } catch {
            print("Ошибка загрузки разовых задач: \(error)")
        }
    }
    
    private func loadRecurringTasks() {
        guard let data = UserDefaults.standard.data(forKey: recurringTasksKey) else { return }
        do {
            recurringTasks = try JSONDecoder().decode([RecurringTask].self, from: data)
        } catch {
            print("Ошибка загрузки регулярных задач: \(error)")
        }
    }
    
    private func saveOneTimeTasks() {
        do {
            let data = try JSONEncoder().encode(oneTimeTasks)
            UserDefaults.standard.set(data, forKey: oneTimeTasksKey)
        } catch {
            print("Ошибка сохранения разовых задач: \(error)")
        }
    }
    
    private func saveRecurringTasks() {
        do {
            let data = try JSONEncoder().encode(recurringTasks)
            UserDefaults.standard.set(data, forKey: recurringTasksKey)
        } catch {
            print("Ошибка сохранения регулярных задач: \(error)")
        }
    }
    
    func resetDailyCompletionStatus() {
        let today = Calendar.current.startOfDay(for: Date())
        for i in recurringTasks.indices {
            if let lastDate = recurringTasks[i].lastCompletionDate,
               Calendar.current.startOfDay(for: lastDate) < today {
                recurringTasks[i].isCompletedToday = false
            }
        }
    }
    
    func addOneTimeTask(_ task: OneTimeTask) {
        oneTimeTasks.append(task)
    }
    
    func addRecurringTask(_ task: RecurringTask) {
        recurringTasks.append(task)
    }
    
    func deleteOneTimeTask(_ task: OneTimeTask) {
        oneTimeTasks.removeAll { $0.id == task.id }
    }
    
    func deleteRecurringTask(_ task: RecurringTask) {
        recurringTasks.removeAll { $0.id == task.id }
    }
    
    func updateOneTimeTask(_ task: OneTimeTask) {
        if let index = oneTimeTasks.firstIndex(where: { $0.id == task.id }) {
            oneTimeTasks[index] = task
        }
    }
    
    func updateRecurringTask(_ task: RecurringTask) {
        if let index = recurringTasks.firstIndex(where: { $0.id == task.id }) {
            recurringTasks[index] = task
        }
    }
    
    func markRecurringTaskCompleted(_ task: RecurringTask) {
        if let index = recurringTasks.firstIndex(where: { $0.id == task.id }) {
            recurringTasks[index].isCompletedToday = true
            recurringTasks[index].lastCompletionDate = Date()
        }
    }
    
    func markOneTimeTaskAsRead(_ task: OneTimeTask) {
        if let index = oneTimeTasks.firstIndex(where: { $0.id == task.id }) {
            oneTimeTasks[index].isRead = true
        }
    }
}