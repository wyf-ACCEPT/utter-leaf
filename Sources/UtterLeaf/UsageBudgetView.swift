import SwiftUI
import UtterLeafCore

struct UsageBudgetView: View {
    @ObservedObject var store: LocalStore
    @State private var editing = false
    @State private var showingInfo = false
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 60)) { _ in
            content(now: Date())
        }.sheet(isPresented: $editing) { BudgetEditor(store: store) }
    }
    private func content(now: Date) -> some View {
        Surface(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("表达额度").font(LeafType.headline)
                        Button { showingInfo = true } label: {
                            Image(systemName: "info.circle").font(.system(size: 16)).frame(width: 28, height: 28)
                        }.buttonStyle(.plain).handCursor().foregroundStyle(LeafTheme.muted)
                            .accessibilityLabel("表达额度说明").help("查看统计口径与预算说明")
                            .popover(isPresented: $showingInfo, arrowEdge: .top) {
                                Text("包含听写与会议的豆包 ASR + DeepSeek 已知估算；已写字数与预计还能写按短听写口径，不受明细筛选影响。额度仅作提醒，超出后仍可录音；不是供应商余额。字数含标点与空白，同一次听写只计一次，清除正文后保留计数。")
                                    .font(LeafType.caption).foregroundStyle(LeafTheme.ink).padding(20).frame(width: 360)
                                    .background(LeafTheme.surface)
                            }
                    }
                    Text(store.usageCloud.cache.lastSync == nil ? "本机缓存预算 · CNY" : "跨设备共享预算 · CNY").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("调整预算") { editing = true }.buttonStyle(.bordered).handCursor()
            }
            budgetRow(days: 7, limit: store.database.preferences.weeklyBudget ?? 5, now: now)
            budgetRow(days: 30, limit: store.database.preferences.monthlyBudget ?? 20, now: now)
            Divider().overlay(LeafTheme.line)
            sharedSummary(now: now)
        }
    }
    @ViewBuilder private func budgetRow(days: Int, limit: Double, now: Date) -> some View {
        let budget = UsageBudget(calls: store.combinedCalls, jobs: store.combinedJobs, days: days, limit: limit, now: now)
        let window = UsageWindow(days: days, now: now), title = days == 7 ? "本周" : "最近 30 天"
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: LeafType.scaled(16), weight: .medium))
                Spacer()
                Text("剩余 \(String(format: "%.1f", budget.remainingFraction * 100))%")
                    .font(.system(size: LeafType.scaled(22), weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf)
            }
            Text(budgetRange(window)).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            BudgetCompositionBar(budget: budget, title: title, height: 8)
            HStack(spacing: 18) {
                legend("剩余", budget.remainingFraction, budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf)
                legend("听写", budget.dictationFraction, LeafTheme.usageDictation)
                legend("会议", budget.meetingFraction, LeafTheme.usageMeeting)
            }.font(LeafType.caption)
            metrics(budget)
            if budget.spent > budget.limit {
                Text("已超出预算 \(money(budget.spent - budget.limit, "CNY"))，仍可继续录音；条内按两类已知消耗占比分配。")
                    .font(LeafType.caption).foregroundStyle(.orange)
            }
        }.padding(.vertical, 2)
    }
    private func metrics(_ budget: UsageBudget) -> some View {
        let moneyText = "已用 \(money(budget.spent, "CNY")) · 预算 \(money(budget.limit, "CNY"))"
        let projection = budget.remainingCharacters.map { "预计还能写 \(thousands($0)) 千字" } ?? "暂无剩余字数估算"
        let writing = "已写 \(budget.writtenCharacters.formatted()) 字 · " + projection
        let remaining = "剩余 \(money(budget.remaining, "CNY"))"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(moneyText + " · " + writing).fixedSize()
                Spacer(minLength: 0)
                Text(remaining).fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(moneyText); Spacer(minLength: 4); Text(remaining) }
                Text(writing)
            }
        }.font(LeafType.caption).foregroundStyle(LeafTheme.muted).monospacedDigit()
    }
    @ViewBuilder private func sharedSummary(now: Date) -> some View {
        let budget = UsageBudget(calls: store.combinedCalls, jobs: store.combinedJobs, days: 30, limit: store.database.preferences.monthlyBudget ?? 20, now: now)
        Text("近 30 天支出 · 听写 \(money(budget.dictationEstimated, "CNY")) · 会议 \(money(budget.meetingEstimated, "CNY"))")
            .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        if budget.unknown >= 5 {
            Text("近 30 天有 \(budget.unknown) 次调用缺少用量回执，尚不能估算；剩余额度可能偏高。")
                .font(LeafType.caption).foregroundStyle(.orange)
        }
    }
    private func percent(_ fraction: Double) -> String { String(format: "%.1f%%", fraction * 100) }
    private func legend(_ title: String, _ fraction: Double, _ color: Color) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 7, height: 7); Text("\(title) \(percent(fraction))").monospacedDigit() }.foregroundStyle(LeafTheme.muted)
    }
    private func thousands(_ characters: Double) -> String { String(format: "%.1f", characters / 1000) }
}

private func budgetRange(_ window: UsageWindow) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy/MM/dd HH:mm"
    return "\(formatter.string(from: window.start)) → \(formatter.string(from: window.end)) UTC" + (window.isWeekly ? " · 周一更新" : " · 滚动统计")
}

struct BudgetCompositionBar: View {
    let budget: UsageBudget
    let title: String
    var height: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle().fill(budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf).frame(width: geometry.size.width * budget.remainingFraction)
                Rectangle().fill(LeafTheme.usageDictation).frame(width: geometry.size.width * budget.dictationFraction)
                Rectangle().fill(LeafTheme.usageMeeting).frame(width: geometry.size.width * budget.meetingFraction)
            }.clipShape(Capsule())
        }.frame(height: height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: budget.remainingFraction)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: budget.dictationFraction)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: budget.meetingFraction)
            .accessibilityElement(children: .ignore).accessibilityLabel(title + "额度构成")
            .accessibilityValue(String(format: "剩余 %.1f%%，听写 %.1f%%，会议 %.1f%%", budget.remainingFraction * 100, budget.dictationFraction * 100, budget.meetingFraction * 100))
    }
}

struct SidebarBudgetView: View {
    @ObservedObject var store: LocalStore
    var openUsage: () -> Void
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 60)) { _ in
            let now = Date(), limit = store.database.preferences.weeklyBudget ?? 5
            let budget = UsageBudget(calls: store.combinedCalls, jobs: store.combinedJobs, days: 7, limit: limit, now: now)
            Button(action: openUsage) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("本周额度").foregroundStyle(LeafTheme.ink)
                        Spacer(minLength: 4)
                        Text(String(format: "%.1f%%", budget.remainingFraction * 100))
                            .foregroundStyle(budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf).monospacedDigit()
                    }.font(LeafType.caption)
                    BudgetCompositionBar(budget: budget, title: "本周", height: 6)
                    Text("剩余 \(money(budget.remaining, "CNY")) / \(money(budget.limit, "CNY"))")
                        .font(.system(size: LeafType.scaled(11))).monospacedDigit().foregroundStyle(LeafTheme.muted)
                    Text("周一 00:00 UTC 更新").font(.system(size: LeafType.scaled(10))).foregroundStyle(LeafTheme.muted)
                }.padding(12).background(LeafTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).handCursor()
                .help(budgetRange(UsageWindow(days: 7, now: now)) + "。查看用量与费用；这是本地提醒预算，不是供应商余额。")
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("本周额度，剩余 \(money(budget.remaining, "CNY"))，预算 \(money(budget.limit, "CNY"))，查看用量与费用")
        }
    }
}

private struct BudgetEditor: View {
    @ObservedObject var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var week = ""
    @State private var month = ""
    private var valid: Bool { [week, month].allSatisfy { Double($0).map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } == true } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("调整表达额度").font(.system(size: 25, weight: .medium))
            Text("共享提醒预算，不会修改 API 账户或停止录音。周预算每周一 00:00 UTC 更新；30 天预算仍滚动统计。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            LabeledContent("每周预算 · CNY") { TextField("5", text: $week).leafInput().accessibilityLabel("每周预算 CNY") }
            LabeledContent("30 天预算 · CNY") { TextField("20", text: $month).leafInput().accessibilityLabel("30 天预算 CNY") }
            Text(valid ? "字数额度根据近期完整听写的费用与最终稿字数估算。" : "请输入大于 0、且不超过 1,000,000 的有效金额。")
                .font(LeafType.caption).foregroundStyle(valid ? LeafTheme.muted : .orange).frame(minHeight: 36, alignment: .top)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存预算") {
                    store.database.preferences.weeklyBudget = Double(week)
                    store.database.preferences.monthlyBudget = Double(month)
                    store.save(); dismiss()
                }.buttonStyle(PrimaryStyle()).disabled(!valid).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 480)
            .foregroundStyle(LeafTheme.ink).background(LeafTheme.mist)
            .onAppear {
                week = String(store.database.preferences.weeklyBudget ?? 5)
                month = String(store.database.preferences.monthlyBudget ?? 20)
            }
    }
}
