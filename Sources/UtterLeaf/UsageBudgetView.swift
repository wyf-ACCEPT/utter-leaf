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
                    Text("本地滚动预算 · CNY").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
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
        let budget = UsageBudget(calls: store.database.calls, jobs: store.database.jobs, days: days, limit: limit)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近 \(days) 天").font(.system(size: LeafType.scaled(16), weight: .medium))
                Spacer()
                Text("剩余 \(String(format: "%.1f", budget.remainingFraction * 100))%")
                    .font(.system(size: LeafType.scaled(22), weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf)
            }
            GeometryReader { geometry in
                Capsule().fill(LeafTheme.line.opacity(0.7))
                    .overlay(alignment: .leading) {
                        Capsule().fill(budget.remainingFraction <= 0.2 ? Color.orange : LeafTheme.leaf)
                            .frame(width: geometry.size.width * budget.remainingFraction)
                    }
            }.frame(height: 8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: budget.remainingFraction)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("最近 \(days) 天剩余额度")
                .accessibilityValue("\(String(format: "%.1f", budget.remainingFraction * 100)) 百分比")
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
                Text("已超出预算 \(money(budget.spent - budget.limit, "CNY"))，仍可继续录音。")
                    .font(LeafType.caption).foregroundStyle(.orange)
            }
        }.padding(.vertical, 6)
    }
    @ViewBuilder private var sharedSummary: some View {
        let budget = UsageBudget(calls: store.database.calls, jobs: store.database.jobs, days: 30, limit: store.database.preferences.monthlyBudget ?? 20)
        if let doubao = budget.doubaoFraction, let deepSeek = budget.deepSeekFraction {
            Text("近 30 天成本构成 · 豆包 \(String(format: "%.1f", doubao * 100))% · DeepSeek \(String(format: "%.1f", deepSeek * 100))%" + (budget.doubaoToDeepSeek.map { " · 约 \(String(format: "%.1f", $0)) : 1" } ?? ""))
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                .help("按近 30 天两项服务的已知估算计算，未知金额不参与占比。比值顺序为豆包 : DeepSeek。")
        } else {
            Text("近 30 天成本构成 · 暂无已知费用").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }
        if budget.unknown >= 5 {
            Text("近 30 天有 \(budget.unknown) 次调用缺少用量回执，尚不能估算；剩余额度可能偏高。")
                .font(LeafType.caption).foregroundStyle(.orange)
        }
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
            Text("本机提醒预算，不会修改 API 账户或停止录音。按最近 7 天 / 30 天滚动统计。")
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
