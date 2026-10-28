import SwiftUI
import UtterLeafCore

struct UsageBudgetView: View {
    @ObservedObject var store: LocalStore
    @State private var editing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Surface {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("表达额度").font(LeafType.headline)
                    Text(store.usageCloud.cache.lastSync == nil ? "本机缓存预算 · CNY" : "跨设备滚动预算 · CNY").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("调整预算") { editing = true }.buttonStyle(.bordered).handCursor()
            }
            budgetRow(days: 7, limit: store.database.preferences.weeklyBudget ?? 5)
            budgetRow(days: 30, limit: store.database.preferences.monthlyBudget ?? 20)
            Divider().overlay(LeafTheme.line)
            sharedSummary
            Text("包含听写与会议的豆包 ASR + DeepSeek 已知估算；已写字数与预计还能写按短听写口径，不受下方筛选影响。额度仅作提醒，超出后仍可录音；不是供应商余额。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }.sheet(isPresented: $editing) { BudgetEditor(store: store) }
    }
    @ViewBuilder private func budgetRow(days: Int, limit: Double) -> some View {
        let budget = UsageBudget(calls: store.combinedCalls, jobs: store.combinedJobs, days: days, limit: limit)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近 \(days) 天").font(.system(size: LeafType.scaled(16), weight: .medium))
                Spacer()
                Text("剩余 \(String(format: "%.1f", budget.remainingFraction * 100))%")
                    .font(.system(size: LeafType.scaled(22), weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle().fill(budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf).frame(width: geometry.size.width * budget.remainingFraction)
                    Rectangle().fill(LeafTheme.usageDictation).frame(width: geometry.size.width * budget.dictationFraction)
                    Rectangle().fill(LeafTheme.usageMeeting).frame(width: geometry.size.width * budget.meetingFraction)
                }.clipShape(Capsule())
            }.frame(height: 10)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: budget.dictationFraction)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: budget.meetingFraction)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: budget.remainingFraction)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("最近 \(days) 天额度构成")
                .accessibilityValue("听写 \(percent(budget.dictationFraction))，会议 \(percent(budget.meetingFraction))，剩余 \(percent(budget.remainingFraction))")
            HStack(spacing: 18) {
                legend("剩余", budget.remainingFraction, budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf)
                legend("听写", budget.dictationFraction, LeafTheme.usageDictation)
                legend("会议", budget.meetingFraction, LeafTheme.usageMeeting)
            }.font(LeafType.caption)
            HStack {
                Text("已用 \(money(budget.spent, "CNY")) · 预算 \(money(budget.limit, "CNY"))")
                Spacer()
                Text("剩余 \(money(budget.remaining, "CNY"))")
            }.font(LeafType.caption).monospacedDigit().foregroundStyle(LeafTheme.muted)
            if let remaining = budget.remainingCharacters {
                Text("已写 \(budget.writtenCharacters.formatted()) 字 · 预计还能写 \(thousands(remaining)) 千字")
                    .help("按本周期听写的最终稿字符数统计，含标点和空白。同一次听写只计一次；预览和复制均计入，清除正文后保留计数。")
                    .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            } else {
                Text("已写 \(budget.writtenCharacters.formatted()) 字 · 完成听写后估算剩余字数。")
                    .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            }
            if budget.spent > budget.limit {
                Text("已超出预算 \(money(budget.spent - budget.limit, "CNY"))，仍可继续录音；条内按两类已知消耗占比分配。")
                    .font(LeafType.caption).foregroundStyle(.orange)
            }
        }.padding(.vertical, 6)
    }
    @ViewBuilder private var sharedSummary: some View {
        let budget = UsageBudget(calls: store.combinedCalls, jobs: store.combinedJobs, days: 30, limit: store.database.preferences.monthlyBudget ?? 20)
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

private struct BudgetEditor: View {
    @ObservedObject var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var week = ""
    @State private var month = ""
    private var valid: Bool { [week, month].allSatisfy { Double($0).map { $0.isFinite && $0 > 0 && $0 <= 1_000_000 } == true } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("调整表达额度").font(.system(size: 25, weight: .medium))
            Text("共享提醒预算，不会修改 API 账户或停止录音。按最近 7 天 / 30 天滚动统计。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            LabeledContent("7 天预算 · CNY") { TextField("5", text: $week).leafInput().accessibilityLabel("7 天预算 CNY") }
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
