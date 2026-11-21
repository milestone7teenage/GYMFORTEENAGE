import SwiftUI
import UserNotifications

struct RecurringTaskView: View {
    @Environment(TaskStore.self) private var taskStore
    @Environment(TaskNotificationManager.self) private var notificationManager
    @State private var showingAddTask = false
    @State private var newTaskTitle = ""
    @State private var newTaskTime = Date()
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(taskStore.recurringTasks) { task in
                    RecurringTaskRow(task: task)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTask(task)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                }
            }
            .navigationTitle("Регулярные задачи")
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
                        DatePicker("Время", selection: $newTaskTime, displayedComponents: .hourAndMinute)
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
                if taskStore.recurringTasks.isEmpty {
                    ContentUnavailableView(
                        "Нет регулярных задач",
                        systemImage: "repeat",
                        description: Text("Добавьте регулярную задачу с ежедневным временем выполнения")
                    )
                }
            }
        }
    }
    
    private func saveNewTask() {
        Task {
            let granted = await notificationManager.requestAuthorization()
            if granted {
                let task = RecurringTask(title: newTaskTitle, time: newTaskTime)
                taskStore.addRecurringTask(task)
                notificationManager.scheduleRecurringTaskNotification(for: task)
                showingAddTask = false
                newTaskTitle = ""
            }
        }
    }
    
    private func deleteTask(_ task: RecurringTask) {
        taskStore.deleteRecurringTask(task)
        notificationManager.cancelRecurringTaskNotification(for: task)
    }
}

struct RecurringTaskRow: View {
    let task: RecurringTask
    @Environment(TaskStore.self) private var taskStore
    
    var body: some View {
        HStack {
            Button {
                toggleTaskCompletion(task)
            } label: {
                Image(systemName: task.isCompletedToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompletedToday ? .green : .secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(task.isCompletedToday ? .secondary : .primary)
                    .strikethrough(task.isCompletedToday, color: .secondary)
                
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(task.time.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func toggleTaskCompletion(_ task: RecurringTask) {
        if task.isCompletedToday {
            // Можно сбросить выполнение, если нужно
            var updatedTask = task
            updatedTask.isCompletedToday = false
            taskStore.updateRecurringTask(updatedTask)
        } else {
            taskStore.markRecurringTaskCompleted(task)
        }
    }
}