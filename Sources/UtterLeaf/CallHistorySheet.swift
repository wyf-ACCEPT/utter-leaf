import SwiftUI
import UtterLeafCore

struct CallHistorySheet: View {
    @ObservedObject var store: LocalStore
    let calls: [UsageCall]
    let filterDescription: String
    @Environment(\.dismiss) private var dismiss
    @State private var limit = 30
    @State private var detail: UsageCall?
    private var rows: [UsageCall] {
        let current = Dictionary(uniqueKeysWithValues: store.database.calls.map { ($0.id, $0) })
        return calls.compactMap { current[$0.id] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("调用明细").font(.system(size: 25, weight: .medium))
                    Text(filterDescription).font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(.bordered).handCursor().keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 10) {
                    if rows.isEmpty {
                        Label("当前筛选没有调用记录。调整日期、供应商或模型后再查看。", systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(LeafTheme.muted).frame(maxWidth: .infinity, minHeight: 160)
                    }
                    ForEach(Array(rows.prefix(limit))) { call in
                        Button { detail = call } label: {
                            HStack(spacing: 12) {
                                Image(systemName: call.status == .succeeded ? "checkmark.circle" : "circle.dashed")
                                    .foregroundStyle(LeafTheme.leaf)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(call.provider) · \(call.model)").font(.system(size: LeafType.scaled(13), weight: .medium))
                                    Text("\(call.started.formatted(date: .abbreviated, time: .shortened)) · \(statusText(call.status))")
                                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                                }
                                Spacer()
                                Text(callAmount(call)).font(.system(size: LeafType.scaled(12), design: .monospaced))
                                Image(systemName: "chevron.right").font(LeafType.caption)
                            }.padding(15).background(LeafTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(CallHistoryRowStyle())
                    }
                    if rows.count > limit {
                        Button("加载更多调用") { limit += 30 }.buttonStyle(.bordered).handCursor().padding(.vertical, 8)
                    }
                }.padding(.trailing, 8)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("已显示 \(min(limit, rows.count)) / \(rows.count) 次 · 点击记录查看回执或核对实际费用")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
        }.padding(24).frame(width: 700, height: 550)
            .foregroundStyle(LeafTheme.ink).background(LeafTheme.mist)
            .sheet(item: $detail) { CallDetail(store: store, call: $0) }
    }
}
