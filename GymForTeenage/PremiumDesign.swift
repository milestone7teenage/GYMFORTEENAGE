import SwiftUI

enum TeenTheme {
    static let ink = Color(red: 0.025, green: 0.027, blue: 0.035)
    static let surface = Color(red: 0.075, green: 0.078, blue: 0.094)
    static let raised = Color(red: 0.115, green: 0.118, blue: 0.138)
    static let lime = Color(red: 0.58, green: 1.0, blue: 0.04)
    static let ice = Color(red: 0.18, green: 0.82, blue: 1.0)
    static let violet = Color(red: 0.60, green: 0.42, blue: 1.0)
    static let muted = Color.white.opacity(0.48)
    static let line = Color.white.opacity(0.10)
}

struct TeenCard<Content: View>: View {
    let accent: Color?
    @ViewBuilder var content: Content
    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(TeenTheme.surface)
                    .overlay(alignment: .topLeading) {
                        if let accent {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(LinearGradient(colors: [accent.opacity(0.16), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(TeenTheme.line, lineWidth: 1))
    }
}

struct TeenMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var body: some View {
        TeenCard(accent: tint) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon).foregroundStyle(tint).font(.headline)
                Spacer(minLength: 4)
                Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit().frame(maxWidth: .infinity, alignment: .center)
                Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(TeenTheme.muted).lineLimit(1).frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity).frame(height: 116, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TeenSectionTitle: View {
    let title: String
    let detail: String?
    init(_ title: String, detail: String? = nil) { self.title = title; self.detail = detail }
    var body: some View {
        if let detail {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text(detail).font(.caption.weight(.medium)).foregroundStyle(TeenTheme.muted)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(title).font(.system(.title3, design: .rounded, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TeenPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct TeenEmpty: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(TeenTheme.lime)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(TeenTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
    }
}

struct TeenPill: View {
    let title: String
    let tint: Color
    var body: some View {
        Text(title).font(.caption2.weight(.bold)).foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(tint.opacity(0.13), in: Capsule())
    }
}

struct CompactMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(.footnote, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1)
                Text(title.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(TeenTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TeenTheme.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(TeenTheme.line, lineWidth: 1))
    }
}

enum TechniqueGuide {
    static func instruction(for id: String) -> String {
        switch id {
        case "butterfly": return "Сядь с опорой спины, сведи лопатки и расположи локти на уровне груди. Своди рукояти плавно перед собой, не сталкивая их; возвращай руки медленно, сохраняя лёгкое сгибание локтей."
        case "tbar": return "Упрись грудью в подушку или устойчиво наклони корпус, сохраняя нейтральную спину. Тяни рукоять к нижним рёбрам, ведя локти назад; опускай вес под контролем и не дёргай корпусом."
        case "shoulder": return "Настрой сиденье так, чтобы рукояти были около плеч. Прижми спину к опоре, держи запястья ровно и локти немного впереди корпуса. Выжимай вверх без прогиба поясницы и мягко опускай до комфортной глубины."
        case "curlleg": return "Совмести ось тренажёра с коленом, валик размести чуть выше пяток. Держи таз и корпус на опоре, сгибай колени плавно, затем медленно выпрямляй ноги, не бросая вес."
        case "extendleg": return "Совмести ось тренажёра с коленями, валик положи на нижнюю часть голени. Держи спину у опоры, выпрямляй колени без резкого замка и опускай вес медленно."
        case "hammer": return "Встань устойчиво, локти держи рядом с корпусом, ладони направь друг к другу. Поднимай гантели сгибанием локтей без раскачки и поворота корпуса; опускай медленно."
        case "triceps": return "Зафиксируй локти у боков и держи запястья прямыми. Разгибай руки вниз до комфортного выпрямления, не двигая плечами; верни рукоять плавно, сохраняя контроль."
        case "hammerpress": return "Отрегулируй сиденье, чтобы рукояти были на уровне середины груди. Прижми спину к опоре, сведи лопатки и выжимай рукояти вперёд без болезненного растяжения; верни их контролируемо."
        case "pullup": return "Возьмись за перекладину удобным хватом и начни движение из устойчивого виса. Опускай плечи от ушей, веди локти вниз и подтянись без раскачки. Опускайся медленно; используй помощь тренажёра, если нужно."
        case "raises": return "Возьми лёгкие гантели, слегка согни локти и наклони корпус вперёд с ровной спиной. Поднимай руки в стороны до комфортного уровня, не пожимая плечами; опускай плавно."
        case "hack": return "Прижми спину и таз к опоре, поставь стопы устойчиво на платформу. Опускайся сгибанием коленей в безболезненном диапазоне, удерживая колени по направлению носков; выжимай через всю стопу без жёсткого замка коленей."
        case "cablebiceps": return "Встань устойчиво перед блоком, локти держи близко к корпусу. Согни руки без движения плеч и раскачки, затем медленно распрями их, сохраняя контроль троса."
        case "incline": return "Установи спинку под умеренным наклоном, стопы поставь на пол. Сведи лопатки, держи запястья над локтями и опускай вес к верхней части груди в комфортной глубине. Выжимай без отрыва спины и таза."
        case "pulldown": return "Зафиксируй бёдра под упорами и возьмись за рукоять комфортно широким хватом. Слегка отклонись, опусти плечи и веди локти вниз к бокам. Не тяни за голову и не раскачивай корпус; возвращай рукоять медленно."
        case "seatedbiceps": return "Сядь устойчиво, плечо и локоть рабочей руки зафиксируй на опоре. Сгибай локоть без подъёма плеча и вращения корпуса, затем медленно опускай гантель до комфортного разгибания."
        default: return "Работай плавно и в комфортном диапазоне. Сохраняй устойчивое положение корпуса, не делай рывков и остановись при боли."
        }
    }
}
