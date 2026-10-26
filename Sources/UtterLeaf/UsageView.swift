import SwiftUI
import UtterLeafCore

struct UsageView: View {
    @ObservedObject var store: LocalStore
    @State private var showingDetails = false
    @State private var showingBilling = false
    private var recent: [UsageCall] {
        let now = Date()
        return store.database.calls.filter { $0.price.currency == "CNY" && $0.started >= now.addingTimeInterval(-30 * 86400) && $0.started <= now }
    }
    var body: some View {
        PageHeading(title: "每次开口，都算得清楚。", subtitle: "听写与会议共享预算 · 费用估算与实际核对分别保留")
        UsageBudgetView(store: store)
        Surface(title: "单位成本 · 最近 30 天") {
            HStack(alignment: .top, spacing: 24) {
                unit(.dictation, title: "听写", unit: "每千字")
                unit(.meeting, title: "会议", unit: "每小时")
            }
            Text("听写按最终稿字符数（含标点、空白）；会议按整场时长，同场多路 API 不重复累计时长。只计已知估算，实际费用以账单核对为准。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }
        Surface {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("筛选与明细").font(LeafType.headline)
                    Text("按用途、日期、供应商与模型查看回执和成本").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("查看明细") { showingDetails = true }.buttonStyle(.bordered).handCursor()
            }
        }.sheet(isPresented: $showingDetails) { UsageDetailsView(store: store) }
        DisclosureGroup("官方核对与同步", isExpanded: $showingBilling) { BillingSyncView(store: store).padding(.top, 12) }
            .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
    }
    private func unit(_ purpose: UsagePurpose, title: String, unit: String) -> some View {
        let calls = recent.filter { purpose.matches($0, jobs: store.database.jobs) }
        let summary = UsageSummary(calls: calls, jobs: store.database.jobs)
        let rate = purpose == .meeting ? summary.perHour : summary.perThousand
        return VStack(alignment: .leading, spacing: 8) {
            Text(title + " · " + unit).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            Text(rate.map { money($0, "CNY") } ?? "暂无样本").font(.system(size: LeafType.scaled(21), weight: .medium, design: .rounded)).monospacedDigit()
            if summary.unknown >= 5 { Text("\(summary.unknown) 次金额未知，未计入").font(LeafType.caption).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
