import SwiftUI
import WebKit
import UtterLeafCore

struct MinutesQuotaView: View {
    @ObservedObject var quota: MinutesQuotaStore
    @State private var login = false
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 60)) { context in
            Surface {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("飞书妙记 · 官方额度", systemImage: "cloud").font(LeafType.headline).foregroundStyle(LeafTheme.serviceBlue)
                        Text("Lark / 飞书账户权益 · 与本地 CNY 预算分开").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    }
                    Spacer(minLength: 12)
                    Button { quota.refresh(force: true) } label: {
                        HStack(spacing: 6) {
                            if quota.checking { ProgressView().controlSize(.small) }
                            Text(quota.checking ? "查询中…" : "立即查询")
                        }.frame(width: 92)
                    }.disabled(quota.checking).buttonStyle(.bordered).handCursor()
                    Button("登录飞书") { login = true }.buttonStyle(.bordered).handCursor()
                }
                if let value = quota.snapshot {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(number(value.remainingMinutes)).font(.system(size: LeafType.scaled(27), weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(value.remainingMinutes == 0 ? .orange : LeafTheme.serviceBlue)
                        Text("分钟可用 · 语音转文字").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    }
                    if let total = value.totalMinutes, total > 0 {
                        ProgressView(value: value.remainingMinutes, total: total).tint(LeafTheme.serviceBlue)
                            .accessibilityLabel("妙记官方语音转文字额度").accessibilityValue("剩余 \(number(value.remainingMinutes)) 分钟，总额 \(number(total)) 分钟")
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 30) { sourceRows(value) }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 10) { sourceRows(value) }
                    }
                    Text("最近成功查询 \(stamp(value.fetched))").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    if let next = value.nextRefresh, next <= Date() {
                        Text("已到官方恢复时间，等待重新查询；当前显示上次结果。")
                            .font(LeafType.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text(quota.checking ? "正在读取官方权益…" : "尚未连接，登录后显示官方剩余额度。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                if let error = quota.errorCode {
                    Text(errorText(error)).font(LeafType.caption).foregroundStyle(.orange)
                }
            }.overlay(RoundedRectangle(cornerRadius: 18).stroke(LeafTheme.serviceBlue.opacity(0.3)))
                .tint(LeafTheme.serviceBlue)
                .onChange(of: context.date) { _, _ in quota.refresh() }
        }.task { quota.refresh() }
            .sheet(isPresented: $login, onDismiss: { quota.endLogin() }) { loginSheet }
            .onChange(of: quota.snapshot?.fetched) { _, _ in if quota.errorCode == nil { login = false } }
    }
    @ViewBuilder private func sourceRows(_ snapshot: MinutesQuotaSnapshot) -> some View {
        ForEach(snapshot.sources) { source in
            Text("\(source.title) · 剩余 \(number(source.remaining))"
                 + (source.amount.map { " / \(number($0)) 分钟" } ?? " 分钟")
                 + (source.refresh.map { "（官方恢复 \(stamp($0))）" } ?? ""))
                .font(LeafType.caption).foregroundStyle(LeafTheme.ink).monospacedDigit()
        }
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func stamp(_ value: Date) -> String {
        let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN")
        format.timeZone = .current; format.dateFormat = "yyyy/MM/dd HH:mm zzz"
        return format.string(from: value)
    }
    private func errorText(_ code: String) -> String {
        switch code {
        case "busy": return "录音或处理期间暂停额度查询，结束后可再试。"
        case "login": return "需要登录或登录已过期。请点“登录飞书”；已有结果保留为上次查询值。"
        case "timeout": return "查询超时，上次结果已保留，可稍后重试。"
        case "storage": return "已查询，但本机缓存保存失败。"
        case "response": return "官方返回格式暂不兼容，上次结果已保留。"
        default: return "暂时无法连接飞书，上次结果已保留。"
        }
    }
    private var loginSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("登录飞书妙记").font(LeafType.headline)
                    Text("登录保留在言叶独立的网站会话中，只查询额度，不上传录音。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("关闭") { login = false }.keyboardShortcut(.cancelAction)
            }
            MinutesLoginBrowser(browser: quota.webView)
            HStack {
                Text("完成登录后会自动查询；若未更新，可点右侧按钮。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                Spacer()
                Button(quota.checking ? "查询中…" : "刷新额度") { quota.refresh(force: true) }.disabled(quota.checking)
            }
        }.padding(20).frame(minWidth: 650, idealWidth: 780, minHeight: 600, idealHeight: 730)
            .foregroundStyle(LeafTheme.ink).background(LeafTheme.mist).onAppear { quota.beginLogin() }
    }
}

private struct MinutesLoginBrowser: NSViewRepresentable {
    let browser: WKWebView
    func makeNSView(context: Context) -> WKWebView { browser }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
