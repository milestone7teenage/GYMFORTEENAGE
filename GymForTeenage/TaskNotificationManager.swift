import Foundation
import UserNotifications

@MainActor
@Observable
final class TaskNotificationManager {
    static let shared = TaskNotificationManager()
    
    private init() {}
    
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            return granted
        } catch {
            print("Ошибка запроса разрешения на уведомления: \(error)")
            return false
        }
    }
    
    func scheduleOneTimeTaskNotifications(for task: OneTimeTask) {
        let center = UNUserNotificationCenter.current()
        
        // Удаляем старые уведомления для этой задачи
        center.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: task))
        center.removeDeliveredNotifications(withIdentifiers: notificationIdentifiers(for: task))
        
        // Создаем 12 уведомлений с интервалом 5 минут
        for minuteOffset in stride(from: 0, through: 55, by: 5) {
            let triggerDate = task.dueDate.addingTimeInterval(TimeInterval(minuteOffset * 60))
            
            // Проверяем, что дата не в прошлом
            if triggerDate > Date() {
                let content = UNMutableNotificationContent()
                content.title = "Разовая задача"
                content.body = task.title
                content.sound = .default
                content.userInfo = [
                    "taskType": "oneTime",
                    "taskId": task.id.uuidString
                ]
                
                // Используем interruptionLevel если доступно
                if #available(iOS 15.0, *) {
                    content.interruptionLevel = .timeSensitive
                }
                
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(0, triggerDate.timeIntervalSinceNow),
                    repeats: false
                )
                
                let identifier = "oneTime-\(task.id.uuidString)-\(minuteOffset)"
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )
                
                center.add(request) { error in
                    if let error = error {
                        print("Ошибка планирования уведомления: \(error)")
                    }
                }
            }
        }
    }
    
    func scheduleRecurringTaskNotification(for task: RecurringTask) {
        let center = UNUserNotificationCenter.current()
        let identifier = "recurring-\(task.id.uuidString)"
        
        // Удаляем старое уведомление
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: task.time)
        
        let content = UNMutableNotificationContent()
        content.title = "Регулярная задача"
        content.body = task.title
        content.sound = .default
        content.userInfo = [
            "taskType": "recurring",
            "taskId": task.id.uuidString
        ]
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        center.add(request) { error in
            if let error = error {
                print("Ошибка планирования регулярного уведомления: \(error)")
            }
        }
    }
    
    func cancelOneTimeTaskNotifications(for task: OneTimeTask) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers(for: task))
        center.removeDeliveredNotifications(withIdentifiers: notificationIdentifiers(for: task))
    }
    
    func cancelRecurringTaskNotification(for task: RecurringTask) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["recurring-\(task.id.uuidString)"])
    }
    
    private func notificationIdentifiers(for task: OneTimeTask) -> [String] {
        return (0...11).map { "oneTime-\(task.id.uuidString)-\($0 * 5)" }
    }
    
    func handleNotificationResponse(_ response: UNNotificationResponse) -> (taskType: String, taskId: String)? {
        let userInfo = response.notification.request.content.userInfo
        guard let taskType = userInfo["taskType"] as? String,
              let taskId = userInfo["taskId"] as? String else {
            return nil
        }
        return (taskType, taskId)
    }
}