import SwiftUI
import UtterLeafCore

struct UsageView: View {
    @ObservedObject var store: LocalStore
    @State private var showingDetails = false
    @State private var showingBilling = false
    private var recent: [UsageCall] {
        let now = Date()
        return store.combinedCalls.filter { $0.price.currency == "CNY" && $0.started >= now.addingTimeInterval(-30 * 86400) && $0.started <= now }
    }
    var body: some View {
        PageHeading(title: "每次开口，都算得清楚。", subtitle: "听写与会议共享预算 · 费用估算与实际核对分别保留")
        Surface {
            let window = store.usageCloud.cache.window(days: 30)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("iCloud 用量同步").font(LeafType.headline)
                    Text(store.usageCloud.status).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    if let time = store.usageCloud.cache.lastSync {
                        Text("最近成功 " + Date(timeIntervalSince1970: time).formatted()).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    }
                }
                Spacer()
                Button(store.usageCloud.syncing ? "同步中…" : "立即同步") { Task { await store.usageCloud.sync() } }.disabled(store.usageCloud.syncing)
            }
            Text("近 30 天设备来源 · Mac " + money(window["mac"] as? Double ?? 0, "CNY") + " · iPhone " + money(window["phone"] as? Double ?? 0, "CNY"))
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            Text("仅同步用量与预算；录音、转录正文和 API Key 留在本机。每分钟自动检查，离线时保留记录。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }
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
                    Text("本机回执明细").font(LeafType.headline)
                    Text("汇总包含跨设备用量；完整 API 回执仅在原设备保留").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("查看明细") { showingDetails = true }.buttonStyle(.bordered).handCursor()
            }
        }.sheet(isPresented: $showingDetails) { UsageDetailsView(store: store) }
        DisclosureGroup("官方核对与同步", isExpanded: $showingBilling) { BillingSyncView(store: store).padding(.top, 12) }
            .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
    }
    private func unit(_ purpose: UsagePurpose, title: String, unit: String) -> some View {
        let calls = recent.filter { purpose.matches($0, jobs: store.combinedJobs) }
        let summary = UsageSummary(calls: calls, jobs: store.combinedJobs)
        let rate = purpose == .meeting ? summary.perHour : summary.perThousand
        return VStack(alignment: .leading, spacing: 8) {
            Text(title + " · " + unit).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            Text(rate.map { money($0, "CNY") } ?? "暂无样本").font(.system(size: LeafType.scaled(21), weight: .medium, design: .rounded)).monospacedDigit()
            if summary.unknown >= 5 { Text("\(summary.unknown) 次金额未知，未计入").font(LeafType.caption).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
