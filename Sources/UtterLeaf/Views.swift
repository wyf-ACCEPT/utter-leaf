import SwiftUI
import AppKit
import AVFoundation
import UtterLeafCore

enum LeafTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let mist = adaptive(0xF5F8F6, 0x141C18)
    static let surface = adaptive(0xFFFFFF, 0x1E2922)
    static let leaf = adaptive(0x2D5E46, 0x9FD6B5)
    static let ink = adaptive(0x1B2A23, 0xE7F0EA)
    static let muted = adaptive(0x5B6A62, 0xA8BBB0)
    static let line = adaptive(0xD3DDD6, 0x35463C)
    static let usageDictation = adaptive(0xA1ADA6, 0x3F594A)
    static let usageMeeting = adaptive(0x939F98, 0x4B6555)
    static let actionInk = adaptive(0xFFFFFF, 0x102A1C)
    static func scheme(_ preference: String?) -> ColorScheme? {
        switch preference ?? "dark" { case "light": return .light; case "system": return nil; default: return .dark }
    }
    static func apply(_ preference: String?) {
        switch preference ?? "dark" { case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "system": NSApp.appearance = nil; default: NSApp.appearance = NSAppearance(named: .darkAqua) }
    }
}
enum LeafType {
    static func scaled(_ base: CGFloat) -> CGFloat { max(12, base * 1.18) }
    static let caption = Font.system(size: 14)
    static let headline = Font.system(size: 17, weight: .semibold)
}
struct LeafSegment<Value: Hashable>: Identifiable {
    var value: Value
    var title: String
    var id: Value { value }
    init(_ value: Value, _ title: String) { self.value = value; self.title = title }
}
struct LeafSegments<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let items: [LeafSegment<Value>]
    @Namespace private var indicator
    @State private var hovered: Value?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            HStack(spacing: 3) {
                ForEach(items) { item in
                    Button { selection = item.value } label: {
                        Text(item.title).font(.system(size: 14, weight: selection == item.value ? .semibold : .regular))
                            .multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 8)
                            .foregroundStyle(selection == item.value ? LeafTheme.actionInk : LeafTheme.muted)
                            .background {
                                if selection == item.value {
                                    RoundedRectangle(cornerRadius: 10).fill(LeafTheme.leaf)
                                        .matchedGeometryEffect(id: "selection", in: indicator)
                                } else if hovered == item.value {
                                    RoundedRectangle(cornerRadius: 10).fill(LeafTheme.leaf.opacity(0.14))
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).handCursor().onHover { hovered = $0 ? item.value : nil }
                        .accessibilityAddTraits(selection == item.value ? .isSelected : [])
                        .accessibilityLabel(item.title).help(item.title)
                }
            }.padding(4).background(LeafTheme.mist, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(LeafTheme.line.opacity(0.8)))
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: selection)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                .onMoveCommand { direction in
                    guard let index = items.firstIndex(where: { $0.value == selection }) else { return }
                    let step = direction == .left ? -1 : direction == .right ? 1 : 0
                    guard step != 0 else { return }
                    selection = items[min(max(index + step, 0), items.count - 1)].value
                }
        }.accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}
struct LeafMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 22, y: 73)); p.addCurve(to: CGPoint(x: 75, y: 18), control1: CGPoint(x: 10, y: 53), control2: CGPoint(x: 24, y: 21))
        p.addCurve(to: CGPoint(x: 40, y: 79), control1: CGPoint(x: 87, y: 54), control2: CGPoint(x: 66, y: 82))
        p.addLine(to: CGPoint(x: 22, y: 88)); p.closeSubpath()
        // The cutout is a leaf vein that bends into a spoken wave.
        p.move(to: CGPoint(x: 31, y: 66)); p.addCurve(to: CGPoint(x: 44, y: 48), control1: CGPoint(x: 38, y: 63), control2: CGPoint(x: 36, y: 48))
        p.addCurve(to: CGPoint(x: 53, y: 56), control1: CGPoint(x: 49, y: 48), control2: CGPoint(x: 48, y: 56))
        p.addCurve(to: CGPoint(x: 69, y: 34), control1: CGPoint(x: 60, y: 56), control2: CGPoint(x: 61, y: 40))
        p.addCurve(to: CGPoint(x: 57, y: 64), control1: CGPoint(x: 67, y: 46), control2: CGPoint(x: 65, y: 63))
        p.addCurve(to: CGPoint(x: 43, y: 57), control1: CGPoint(x: 48, y: 67), control2: CGPoint(x: 47, y: 56))
        p.addCurve(to: CGPoint(x: 31, y: 66), control1: CGPoint(x: 40, y: 57), control2: CGPoint(x: 38, y: 68)); p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 100, y: rect.height / 100)).applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

struct Surface<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { Text(title).font(LeafType.headline) }
            content
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(LeafTheme.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(LeafTheme.line.opacity(0.65)))
    }
}
struct PrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PrimaryButtonFace(configuration: configuration) }
}
struct PageHeading: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: LeafType.scaled(32), weight: .medium, design: .rounded)).foregroundStyle(LeafTheme.ink)
            Text(subtitle).font(.system(size: LeafType.scaled(13))).foregroundStyle(LeafTheme.muted)
        }.padding(.bottom, 12)
    }
}
struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: LocalStore
    let pages = [("听写", "waveform"), ("会议", "person.2"), ("本地历史", "clock.arrow.circlepath"), ("词汇表", "character.book.closed"), ("用量与费用", "chart.bar.xaxis"), ("模型与设置", "slider.horizontal.3")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 10) {
                    LeafMark().fill(LeafTheme.leaf, style: FillStyle(eoFill: true)).frame(width: 34, height: 34).accessibilityLabel("言叶标志")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UtterLeaf").font(.system(size: LeafType.scaled(19), weight: .semibold, design: .rounded))
                        Text("言叶").font(.system(size: LeafType.scaled(11))).foregroundStyle(LeafTheme.muted)
                    }
                }.padding(.top, 14)
                VStack(spacing: 6) {
                    ForEach(pages, id: \.0) { page in
                        SidebarItem(title: page.0, icon: page.1, selected: model.route == page.0) { model.route = page.0 }
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 9) {
                    Text("给表达一点空间。").font(.system(size: LeafType.scaled(12))).foregroundStyle(LeafTheme.muted)
                    HStack { Text("Fn").font(.system(size: LeafType.scaled(12), design: .monospaced)); Text("开始 / 结束").font(.system(size: LeafType.scaled(11))) }
                        .foregroundStyle(LeafTheme.leaf)
                    Text("个人版 · 0.2.0").font(.system(size: LeafType.scaled(10))).foregroundStyle(LeafTheme.muted)
                }.padding(.bottom, 14)
            }.padding(20).frame(width: 220).background(LeafTheme.mist)
            Rectangle().fill(LeafTheme.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = store.storageError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                    switch model.route {
                    case "会议": MeetingsView(model: model.meetings, meetings: model.meetings.store)
                    case "本地历史": HistoryView(store: store)
                    case "词汇表": VocabularyView(store: store)
                    case "用量与费用": UsageView(store: store)
                    case "模型与设置": SettingsView(model: model, store: store)
                    default: DictationView(model: model, store: store)
                    }
                }.padding(34).frame(maxWidth: 1040).frame(maxWidth: .infinity)
            }.background(LeafTheme.mist.opacity(0.65))
        }.frame(minWidth: 900, minHeight: 680).font(.system(size: 16)).controlSize(.large).tint(LeafTheme.leaf).foregroundStyle(LeafTheme.ink).preferredColorScheme(LeafTheme.scheme(store.database.preferences.appearance))
            .onChange(of: store.database.preferences.appearance) { _, value in LeafTheme.apply(value) }
    }
}
struct LiveWaveform: View, Equatable {
    var meter: LiveAudioMeter
    var active: Bool
    var compact = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.meter === rhs.meter && lhs.active == rhs.active && lhs.compact == rhs.compact }
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.2 : 1.0 / 30, paused: !active)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let samples = meter.history.amplitudes(at: now, count: 32, window: 0.4)
            Canvas(rendersAsynchronously: true) { context, size in
                for layer in 0..<3 {
                    let speed = [3.4, -2.8, 4.1][layer]
                    let phase = reduceMotion ? 0 : now * speed + Double(layer) * 0.8
                    let points = SpeechWaveCurve.points(amplitudes: samples, phase: phase, layer: layer, count: compact ? 56 : 96)
                    var path = Path()
                    for (index, value) in points.enumerated() {
                        let point = CGPoint(x: size.width * Double(index) / Double(max(points.count - 1, 1)), y: size.height * (0.5 - value * 0.47))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(LeafTheme.leaf.opacity([0.95, 0.42, 0.2][layer])), style: StrokeStyle(lineWidth: layer == 0 ? 1.9 : 1.2, lineCap: .round, lineJoin: .round))
                }
            }
        }.frame(width: compact ? 82 : 220, height: compact ? 32 : 52)
            .accessibilityLabel("正在接收麦克风输入")
    }
}
struct DictationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: LocalStore
    @State private var confirmDiscard = false
    var body: some View {
        PageHeading(title: "让想法，自然落成文字。", subtitle: "在输入框按 Fn 开始，再按一次结束。整理完成后自动输入，继续你的思路。")
        Surface {
            VStack(spacing: 16) {
                HStack {
                    Label(status, systemImage: model.busy ? "circle.fill" : "leaf")
                        .font(.system(size: LeafType.scaled(12), weight: .medium)).foregroundStyle(LeafTheme.leaf)
                    Spacer()
                    Text(String(format: "%02d:%02d", Int(model.elapsed) / 60, Int(model.elapsed) % 60))
                        .font(.system(size: LeafType.scaled(13), design: .monospaced)).monospacedDigit().foregroundStyle(LeafTheme.muted)
                }
                if model.phase == .recording { LiveWaveform(meter: model.waveform, active: true).equatable().padding(.vertical, 14) }
                HStack(spacing: 12) {
                    if [.starting, .transcribing, .cleaning, .inserting].contains(model.phase) {
                        ProgressView().controlSize(.small)
                        Text(status).font(.system(size: LeafType.scaled(14))).frame(width: 120)
                    } else {
                        Button(action: model.toggle) {
                            Label(model.phase == .recording ? "结束录音" : "开始录音", systemImage: model.phase == .recording ? "stop.fill" : "mic.fill").frame(width: 112)
                        }.buttonStyle(PrimaryStyle()).disabled(model.inserting)
                    }
                    if model.busy { Button("取消", action: { model.abort() }).buttonStyle(.bordered).handCursor().keyboardShortcut(.cancelAction).disabled(model.inserting) }
                }.frame(height: 44)
                Text(store.database.preferences.pipeline?.title ?? "尚未选择 ASR · 前往模型与设置")
                    .font(.system(size: LeafType.scaled(12))).foregroundStyle(LeafTheme.muted)
            }.frame(maxWidth: .infinity)
        }
        if !model.message.isEmpty {
            Label(model.message, systemImage: model.phase == .error ? "exclamationmark.circle" : "info.circle")
                .font(.system(size: LeafType.scaled(12))).foregroundStyle(model.phase == .error ? .red : LeafTheme.muted)
                .textSelection(.enabled).accessibilityAddTraits(.updatesFrequently)
        }
        if !model.partial.isEmpty && model.busy {
            Surface(title: "正在识别") { Text(model.partial).font(.system(size: LeafType.scaled(15))).foregroundStyle(LeafTheme.muted).textSelection(.enabled) }
        }
        if model.phase == .preview || !model.raw.isEmpty {
            Surface {
                HStack {
                    Text("待输入的整理稿").font(LeafType.headline)
                    Spacer()
                    Text("\(TextEnvelope.characters(model.draft)) 字符").font(LeafType.caption.monospacedDigit()).foregroundStyle(LeafTheme.muted)
                }
                TextEditor(text: $model.draft).font(.system(size: LeafType.scaled(16))).lineSpacing(7)
                    .scrollContentBackground(.hidden).frame(minHeight: 190).leafInput().accessibilityLabel("可编辑的整理稿")
                    .disabled(model.busy || model.inserting)
                Divider()
                HStack {
                    Text("输入到 \(model.targetName)").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    Spacer()
                    Button("复制", action: model.copy).disabled(model.draft.isEmpty || model.busy)
                    Button(model.inserting ? "正在输入…" : "输入到原应用", action: model.insert).buttonStyle(PrimaryStyle())
                        .disabled(model.inserting || model.busy || model.draft.isEmpty)
                }
                DisclosureGroup("原始转写") { Text(model.raw).font(.system(size: LeafType.scaled(14))).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8) }
                HStack {
                    Button("重新整理", action: model.retryCleanup).disabled(model.busy || model.inserting)
                    Button("使用原始转写", action: model.useRaw).disabled(model.busy || model.inserting)
                    Spacer()
                    Button("放弃预览") { confirmDiscard = true }.disabled(model.busy || model.inserting)
                }.font(LeafType.caption)
            }
        } else if !model.busy {
            Surface(title: "在你的表达里，保留你。") {
                HStack(alignment: .top, spacing: 30) {
                    benefit("text.alignleft", "忠于原意", "去掉口吃与重复，保留语气和细节。")
                    benefit("arrow.up.left.and.arrow.down.right", "符号也听得懂", "分支名、括号与换行，自然说出来。")
                    benefit("arrow.up.left", "直接落到光标", "整理完成后自动输入，发出前由你把关。")
                }
            }
        }
        Text("音频与文字会发送至你选择的 API。录音仅存内存；本地正文可在设置中清除。")
            .font(.system(size: LeafType.scaled(11))).foregroundStyle(LeafTheme.muted)
        .confirmationDialog("放弃当前预览？已保存的本地历史仍会保留。", isPresented: $confirmDiscard) {
            Button("放弃预览", role: .destructive, action: model.discard)
            Button("保留预览", role: .cancel) {}
        }
    }
    var status: String {
        switch model.phase {
        case .idle: return "准备好，听你说"
        case .starting: return "连接麦克风与语音服务"
        case .recording: return "正在听 · 最长 5 分钟"
        case .transcribing: return "正在完成转写"
        case .cleaning: return "正在整理文字"
        case .inserting: return "正在输入到原应用"
        case .preview: return "文字已保留，等待处理"
        case .error: return "需要处理"
        }
    }
    func benefit(_ icon: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 23)).foregroundStyle(LeafTheme.leaf)
            Text(title).font(.system(size: LeafType.scaled(13), weight: .medium))
            Text(body).font(.system(size: LeafType.scaled(12))).foregroundStyle(LeafTheme.muted).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HistoryView: View {
    @ObservedObject var store: LocalStore
    @State private var query = ""
    @State private var limit = 30
    @State private var expanded: UUID?
    var rows: [HistoryJob] { store.database.jobs.filter { $0.kind != "meeting" && (query.isEmpty || ($0.finalText ?? "").localizedCaseInsensitiveContains(query) || ($0.rawText ?? "").localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        PageHeading(title: "说过的话，都有迹可循。", subtitle: "仅保存在这台 Mac · 原始转写与最终稿分开保留")
        HStack {
            TextField("搜索本地文字", text: $query).leafInput()
            if !query.isEmpty { Button { query = ""; limit = 30 } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
            Text("\(rows.count) 条").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }.onChange(of: query) { _, _ in limit = 30 }
        if rows.isEmpty { Surface { Label(query.isEmpty ? "还没有录音记录。开始一次听写，文字会保存在这里。" : "没有匹配的记录，试试其他关键词。", systemImage: "text.bubble").foregroundStyle(LeafTheme.muted) } }
        ForEach(Array(rows.prefix(limit))) { job in
            Surface {
                HStack {
                    Text(job.created.formatted(date: .abbreviated, time: .shortened)).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    Spacer()
                    Text(job.inserted ? "已输入" : job.status == "paste_dispatched" ? "已请求粘贴" : job.status).font(LeafType.caption).foregroundStyle(LeafTheme.leaf)
                    Button { expanded = expanded == job.id ? nil : job.id } label: { Image(systemName: expanded == job.id ? "chevron.up" : "chevron.down") }.accessibilityLabel("展开或收起记录")
                }
                Text(job.finalText ?? job.rawText ?? "正文未保留，调用用量仍可查看。")
                    .font(.system(size: LeafType.scaled(15))).lineSpacing(5).lineLimit(expanded == job.id ? nil : 3).textSelection(.enabled)
                HStack {
                    Text(job.pipeline.title).font(LeafType.caption)
                    Text("· \(Int(job.seconds)) 秒 · \(job.finalCharacters) 字符").font(LeafType.caption)
                    Spacer()
                    if let text = job.finalText { Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } }
                }.foregroundStyle(LeafTheme.muted)
                if expanded == job.id {
                    Divider()
                    Text("原始转写").font(LeafType.caption.bold())
                    Text(job.rawText ?? "未保留").textSelection(.enabled)
                    Text("Prompt: \(job.promptVersion)\nSHA-256: \(job.promptHash ?? "未使用整理")\n任务: \(job.id.uuidString)").font(.system(size: LeafType.scaled(10), design: .monospaced)).textSelection(.enabled).foregroundStyle(LeafTheme.muted)
                }
            }
        }
        if rows.count > limit { Button("加载更多") { limit += 30 }.buttonStyle(.bordered).handCursor() }
    }
}

struct UsageDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var purpose = UsagePurpose.all
    @ObservedObject var store: LocalStore
    @State private var days = 7
    @State private var provider = "全部"
    @State private var modelFilter = "全部"
    @State private var denominator = "最终稿"
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var endDate = Date()
    @State private var showingCalls = false
    var calls: [UsageCall] {
        store.database.calls.filter {
            (days == 0 || (days == -1 ? $0.started >= Calendar.current.startOfDay(for: startDate) && $0.started < Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate))! : $0.started >= Date().addingTimeInterval(-Double(days) * 86400)))
            && purpose.matches($0, jobs: store.database.jobs)
            && (provider == "全部" || $0.provider == provider) && (modelFilter == "全部" || $0.model == modelFilter)
        }
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text("筛选与费用明细").font(LeafType.headline); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).handCursor() }
            ScrollView { VStack(alignment: .leading, spacing: 18) { detailsContent }.padding(4) }
        }.padding(24).frame(width: 810, height: 660).background(LeafTheme.mist).foregroundStyle(LeafTheme.ink)
    }
    @ViewBuilder private var detailsContent: some View {
        LeafSegments(title: "用途", selection: $purpose, items: [LeafSegment(UsagePurpose.all, "全部"), LeafSegment(.dictation, "听写"), LeafSegment(.meeting, "会议")])
            .onChange(of: purpose) { _, _ in modelFilter = "全部" }
        LeafSegments(title: "日期", selection: $days, items: [LeafSegment(7, "最近 7 天"), LeafSegment(30, "最近 30 天"), LeafSegment(0, "全部"), LeafSegment(-1, "自定")])
        LeafSegments(title: "供应商", selection: $provider, items: [LeafSegment("全部", "全部"), LeafSegment("Doubao", "豆包"), LeafSegment("DeepSeek", "DeepSeek")])
            .onChange(of: provider) { _, _ in modelFilter = "全部" }
        LeafSegments(title: "模型", selection: $modelFilter, items: [LeafSegment("全部", "全部")] + availableModels.map { LeafSegment($0, modelTitle($0)) })
        LeafSegments(title: "每千字口径", selection: $denominator, items: [LeafSegment("最终稿", "最终稿"), LeafSegment("原始转写", "原始转写")])
        if days == -1 {
            HStack { DatePicker("从", selection: $startDate, in: ...endDate, displayedComponents: .date); DatePicker("至", selection: $endDate, in: startDate..., displayedComponents: .date) }
        }
        ForEach(summaryGroups, id: \.self) { group in
            let currency = group == "历史 USD" ? "USD" : "CNY"
            let rows = calls.filter { $0.price.currency == currency && (group == "端到端" || group == "历史 USD" || $0.provider == group) }
            let summary = UsageSummary(calls: rows, jobs: store.database.jobs)
            Surface(title: group == "端到端" ? "CNY · 端到端合计" : group == "Doubao" ? "CNY · 豆包 ASR" : group == "DeepSeek" ? "CNY · DeepSeek 整理" : "历史美元记录 · 保留原计价快照") {
                HStack(alignment: .top, spacing: 24) {
                    metric("已知估算", summary.hasEstimate || rows.isEmpty ? money(summary.estimated, currency) : "金额未知")
                    metric("已核对实际", summary.unbilled == rows.count ? "—" : money(summary.billed, currency))
                }
                HStack(spacing: 16) {
                    Text("\(rows.count) 次调用")
                    Text("成功 \(rows.filter { $0.status == .succeeded }.count)")
                    Text("失败/取消 \(rows.filter { [.failed, .cancelled, .interrupted].contains($0.status) }.count)")
                    Text("音频 \(String(format: "%.1f", summary.seconds / 60)) 分钟")
                }.font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                Text("输入 token \(rows.compactMap(\.inputTokens).reduce(0,+)) · 缓存命中 \(rows.compactMap(\.cachedTokens).reduce(0,+)) · 输出 token \(rows.compactMap(\.outputTokens).reduce(0,+))")
                    .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                if summary.unknown > 0 { Text("\(summary.unknown) 次金额未知，未计入估算合计；失败与取消仍可能计费。").font(LeafType.caption).foregroundStyle(.orange) }
                if summary.unbilled > 0 { Text("\(summary.unbilled) 次尚未核对实际账单。").font(LeafType.caption).foregroundStyle(LeafTheme.muted) }
            }
        }
        Text("每千字按 Unicode 标量字符数（含标点/空白）；每小时按相关任务音频时长。CNY 端到端合计包含 ASR 与整理，同一任务音频时长只计一次。历史外币快照单列，不自动改写。筛选模型可查看单项成本。无 token 回执时金额未知，不能视为免费。")
            .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        Surface {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("调用明细").font(LeafType.headline)
                    Text("当前筛选共 \(calls.count) 次 · 查看成功、失败与账单回执")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("查看明细") { showingCalls = true }.buttonStyle(.bordered).handCursor()
            }
        }
        Surface(title: "单位成本 · 当前筛选") {
            ForEach(summaryGroups, id: \.self) { group in
                let currency = group == "历史 USD" ? "USD" : "CNY"
                let rows = calls.filter { $0.price.currency == currency && (group == "端到端" || group == "历史 USD" || $0.provider == group) }
                let summary = UsageSummary(calls: rows, jobs: store.database.jobs)
                let chars = denominator == "最终稿" ? summary.finalCharacters : summary.rawCharacters
                VStack(alignment: .leading, spacing: 8) {
                    Text(group == "端到端" ? "CNY · 端到端合计" : group == "Doubao" ? "CNY · 豆包 ASR" : group == "DeepSeek" ? "CNY · DeepSeek 整理" : "USD · 历史记录").font(LeafType.headline)
                    HStack(spacing: 24) {
                        metric("每千字 · 估算", summary.hasEstimate && chars > 0 ? money(summary.estimated / Double(chars) * 1000, currency) : "不可计算")
                        metric("每小时 · 估算", summary.perHour.map { money($0, currency) } ?? "不可计算")
                    }
                    Text("实际每千字：\(summary.unbilled == 0 && !rows.isEmpty && chars > 0 ? money(summary.billed / Double(chars) * 1000, currency) : "待账单核对") · 实际每小时：\(summary.unbilled == 0 && !rows.isEmpty && summary.seconds > 0 ? money(summary.billed / summary.seconds * 3600, currency) : "待账单核对")")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    if group != summaryGroups.last { Divider().padding(.vertical, 8) }
                }
            }
        }
        Color.clear.frame(height: 0).sheet(isPresented: $showingCalls) {
            CallHistorySheet(store: store, calls: calls, filterDescription: "\(purpose == .all ? "全部用途" : purpose == .meeting ? "会议" : "听写") · \(days == 7 ? "最近 7 天" : days == 30 ? "最近 30 天" : days == 0 ? "全部日期" : "自定日期") · \(provider == "全部" ? "全部供应商" : provider) · \(modelFilter == "全部" ? "全部模型" : modelTitle(modelFilter))")
        }
    }
    var availableModels: [String] { Array(Set(store.database.calls.filter { (provider == "全部" || $0.provider == provider) && purpose.matches($0, jobs: store.database.jobs) }.map(\.model))).sorted() }
    func modelTitle(_ id: String) -> String {
        switch id { case "v2-final": return "结束后返回"; case "v2-realtime": return "实时模式"; case "v2-file": return "文件标准版"; case "deepseek-flash": return "DeepSeek Flash"; default: return id }
    }
    var summaryGroups: [String] { ["端到端", "Doubao", "DeepSeek"] + (calls.contains { $0.price.currency == "USD" } ? ["历史 USD"] : []) }
    func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) { Text(title).font(LeafType.caption).foregroundStyle(LeafTheme.muted); Text(value).font(.system(size: LeafType.scaled(20), weight: .medium, design: .rounded)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
func callAmount(_ call: UsageCall) -> String {
    if let amount = call.billedAmount { return money(amount, call.price.currency) + " 实际" }
    if let amount = call.estimatedAmount { return money(amount, call.price.currency) + " 估算" }
    return "金额未知"
}
func money(_ amount: Double, _ currency: String) -> String { (currency == "CNY" ? "¥" : "$") + String(format: "%.4f", amount) }
func statusText(_ status: CallStatus) -> String {
    switch status { case .pending: return "进行中"; case .succeeded: return "成功"; case .failed: return "失败"; case .cancelled: return "已取消"; case .interrupted: return "已中断" }
}
struct CallDetail: View {
    @ObservedObject var store: LocalStore
    let call: UsageCall
    @Environment(\.dismiss) var dismiss
    @State private var amount = ""
    @State private var reference = ""
    var valid: Bool { Double(amount).map { $0.isFinite && $0 >= 0 } == true && !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("调用回执").font(.system(size: 26, weight: .medium))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(call.provider) · \(call.model) · \(statusText(call.status))")
                    Text("请求 ID: \(call.requestID)\n业务 ID: \(call.jobID.uuidString)\n响应 ID: \(call.responseID ?? "—")\nLog ID: \(call.logID ?? "—")\nHTTP: \(call.httpStatus.map(String.init) ?? "—") · 服务状态: \(call.providerStatus ?? "—")\n错误: \(call.errorCode ?? "—")\n返回模型: \(call.returnedModel ?? "—")")
                        .font(.system(size: LeafType.scaled(11), design: .monospaced)).textSelection(.enabled)
                    Text("音频: \(String(format: "%.2f", call.seconds)) 秒\n输入 / 缓存 / 输出: \(call.inputTokens.map(String.init) ?? "—") / \(call.cachedTokens.map(String.init) ?? "—") / \(call.outputTokens.map(String.init) ?? "—") token")
                    Divider()
                    Text("计价快照 · \(call.price.version)").font(LeafType.headline)
                    Text(call.price.note).font(LeafType.caption)
                    Text("币种 \(call.price.currency) · 小时单价 \(call.price.hourly.map(String.init(describing:)) ?? "—")\n每百万 token 输入 / 缓存 / 输出：\(call.price.inputPerMillion.map(String.init(describing:)) ?? "—") / \(call.price.cachedPerMillion.map(String.init(describing:)) ?? "—") / \(call.price.outputPerMillion.map(String.init(describing:)) ?? "—")")
                        .font(LeafType.caption).textSelection(.enabled)
                    Text("估算依据：\(call.estimateBasis == "sent_audio_duration_v1" ? "已发送音频时长 × 本次计价快照；失败/取消也可能产生费用" : "调用用量与本次计价快照")").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    Text("估算: \(call.estimatedAmount.map { money($0, call.price.currency) } ?? "未知")\n实际: \(call.billedAmount.map { money($0, call.price.currency) } ?? "未核对")\nPrompt SHA-256: \(call.promptHash ?? "—")")
                        .font(LeafType.caption).textSelection(.enabled)
                    Divider()
                    Text("核对供应商账单").font(LeafType.headline)
                    Text("只有能够逐笔对应此请求的金额才能填写为实际。不要把余额变化当作单次费用。新的核对值会替换此条旧值。").font(LeafType.caption)
                    TextField("实际金额（\(call.price.currency)）", text: $amount).leafInput()
                    TextField("对应账单 ID 或核对依据（勿填私人正文）", text: $reference).leafInput()
                }
            }
            HStack { Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("保存核对金额") { var updated = call; updated.billedAmount = Double(amount); updated.billingReference = reference; store.update(updated); dismiss() }.disabled(!valid).buttonStyle(PrimaryStyle()) }
        }.padding(28).frame(width: 570, height: 610)
        .onAppear { amount = call.billedAmount.map(String.init(describing:)) ?? ""; reference = call.billingReference ?? "" }
    }
}
