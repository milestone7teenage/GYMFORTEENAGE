import SwiftUI
import UserNotifications

struct OneTimeTaskView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskNotificationManager.self) private var notificationManager
    @State private var showingAddTask = false
    @State private var newTaskTitle = ""
    @State private var newTaskDueDate = Date()
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(taskStore.oneTimeTasks) { task in
                    OneTimeTaskRow(task: task)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                postponeTask(task)
                            } label: {
                                Label("+30 мин", systemImage: "clock.arrow.circlepath")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTask(task)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .onAppear {
                            // Проверяем, было ли открыто уведомление для этой задачи
                            checkIfNotificationWasOpened(for: task)
                        }
                }
            }
            .navigationTitle("Разовые задачи")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                NavigationStack {
                    Form {
                        TextField("Название", text: $newTaskTitle)
                        DatePicker("Дата и время", selection: $newTaskDueDate)
                    }
                    .navigationTitle("Новая задача")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") {
                                showingAddTask = false
                                newTaskTitle = ""
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Сохранить") {
                                saveNewTask()
                            }
                            .disabled(newTaskTitle.isEmpty)
                        }
                    }
                }
            }
            .overlay {
                if taskStore.oneTimeTasks.isEmpty {
                    ContentUnavailableView(
                        "Нет разовых задач",
                        systemImage: "checklist",
                        description: Text("Добавьте разовую задачу с датой и временем выполнения")
                    )
                }
            }
            .onAppear {
                checkForOpenedNotification()
            }
        }
    }
    
    private func checkForOpenedNotification() {
        let defaults = UserDefaults.standard
        if let taskType = defaults.string(forKey: "lastOpenedNotificationTaskType"),
           let taskIdString = defaults.string(forKey: "lastOpenedNotificationTaskId"),
           taskType == "oneTime",
           let taskId = UUID(uuidString: taskIdString) {
            
            // Находим задачу и помечаем как прочитанную
            if let task = taskStore.oneTimeTasks.first(where: { $0.id == taskId }) {
                var updatedTask = task
                updatedTask.isRead = true
                taskStore.updateOneTimeTask(updatedTask)
                
                // Удаляем оставшиеся уведомления
                notificationManager.cancelOneTimeTaskNotifications(for: updatedTask)
            }
            
            // Очищаем сохраненные данные
            defaults.removeObject(forKey: "lastOpenedNotificationTaskType")
            defaults.removeObject(forKey: "lastOpenedNotificationTaskId")
        }
    }
    
    private func checkIfNotificationWasOpened(for task: OneTimeTask) {
        let defaults = UserDefaults.standard
        if let taskIdString = defaults.string(forKey: "lastOpenedNotificationTaskId"),
           let taskId = UUID(uuidString: taskIdString),
           task.id == taskId {
            
            // Помечаем задачу как прочитанную
            var updatedTask = task
            updatedTask.isRead = true
            taskStore.updateOneTimeTask(updatedTask)
            
            // Очищаем сохраненные данные
            defaults.removeObject(forKey: "lastOpenedNotificationTaskType")
            defaults.removeObject(forKey: "lastOpenedNotificationTaskId")
        }
    }
    
    private func saveNewTask() {
        Task {
            let granted = await notificationManager.requestAuthorization()
            if granted {
                let task = OneTimeTask(title: newTaskTitle, dueDate: newTaskDueDate)
                taskStore.addOneTimeTask(task)
                notificationManager.scheduleOneTimeTaskNotifications(for: task)
                showingAddTask = false
                newTaskTitle = ""
            }
        }
    }
    
    private func deleteTask(_ task: OneTimeTask) {
        taskStore.deleteOneTimeTask(task)
        notificationManager.cancelOneTimeTaskNotifications(for: task)
    }
    
    private func postponeTask(_ task: OneTimeTask) {
        var updatedTask = task
        updatedTask.dueDate = task.dueDate.addingTimeInterval(30 * 60) // +30 минут
        updatedTask.isRead = false
        taskStore.updateOneTimeTask(updatedTask)
        notificationManager.scheduleOneTimeTaskNotifications(for: updatedTask)
    }
}

struct OneTimeTaskRow: View {
    let task: OneTimeTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.isRead ? .secondary : .primary)
                    .strikethrough(task.isRead, color: .secondary)
                Spacer()
                if task.isRead {
                    Text("Прочитано")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.1), in: Capsule())
                }
            }
            
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.dueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if task.dueDate < Date() {
                    Text("Просрочено")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.1), in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}