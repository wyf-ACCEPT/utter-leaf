import SwiftUI
import WebKit
import UtterLeafCore

struct MinutesQuotaView: View {
    @ObservedObject var accounts: MinutesAccountStore
    @State private var editing: MinutesProfileEdit?
    @State private var login: MinutesProfileLogin?
    @State private var pendingLogin: UUID?
    @State private var operationError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = operationError ?? accounts.error {
                Label(message, systemImage: "exclamationmark.triangle").font(LeafType.caption).foregroundStyle(.orange)
            }
            MinutesQuotaCard(quota: accounts.active, profile: accounts.profile, profiles: accounts.profiles,
                select: { id in do { try accounts.select(id); operationError = nil } catch { operationError = error.localizedDescription } },
                add: { editing = MinutesProfileEdit(profile: nil) },
                rename: { editing = MinutesProfileEdit(profile: accounts.profile) },
                automatic: { do { try accounts.useAutomaticName(accounts.selected); operationError = nil } catch { operationError = error.localizedDescription } },
                openLogin: { login = MinutesProfileLogin(id: accounts.selected) })
                .id(accounts.selected)
        }.sheet(item: $editing, onDismiss: {
            if let id = pendingLogin, accounts.selected == id { login = MinutesProfileLogin(id: id) }
            pendingLogin = nil
        }) { request in
            MinutesProfileEditor(initialName: request.profile?.displayName ?? suggestedName, adding: request.profile == nil) { name in
                if let profile = request.profile { try accounts.rename(profile.id, name: name) }
                else { pendingLogin = try accounts.add(name: name) }
                operationError = nil
            }
        }.sheet(item: $login) { request in
            if request.id == accounts.selected {
                MinutesLoginSheet(quota: accounts.active, name: accounts.profile.menuName(in: accounts.profiles), close: { login = nil })
            }
        }
    }
    private var suggestedName: String {
        var index = accounts.profiles.count + 1
        while accounts.profiles.contains(where: { $0.name == "账号 \(index)" }) { index += 1 }
        return "账号 \(index)"
    }
}

private struct MinutesQuotaCard: View {
    @ObservedObject var quota: MinutesQuotaStore
    let profile: MinutesAccountProfile
    let profiles: [MinutesAccountProfile]
    var select: (UUID) -> Void
    var add: () -> Void
    var rename: () -> Void
    var automatic: () -> Void
    var openLogin: () -> Void
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 60)) { context in
            Surface {
                HStack(alignment: .center, spacing: 14) {
                    Label("飞书妙记 · 官方额度", systemImage: "cloud").font(LeafType.headline).foregroundStyle(LeafTheme.serviceBlue)
                    Spacer(minLength: 12)
                    MinutesQuotaActions(authentication: quota.authentication, checking: quota.checking, profile: profile, profiles: profiles,
                                        refresh: { quota.refresh(force: true) }, login: openLogin, select: select, add: add, rename: rename, automatic: automatic)
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
        case "login": return "需要登录或登录已过期。请在右上角账号菜单选择“登录飞书”；已有结果保留为上次查询值。"
        case "timeout": return "查询超时，上次结果已保留，可稍后重试。"
        case "storage": return "已查询，但本机缓存保存失败。"
        case "response": return "官方返回格式暂不兼容，上次结果已保留。"
        default: return "暂时无法连接飞书，上次结果已保留。"
        }
    }
}

private struct MinutesLoginSheet: View {
    @ObservedObject var quota: MinutesQuotaStore
    let name: String
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("登录飞书 · " + name).font(LeafType.headline)
                    Text("此账号使用独立登录会话，只查询额度，不上传录音。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("关闭", action: close).keyboardShortcut(.cancelAction)
            }
            MinutesLoginBrowser(browser: quota.webView)
            HStack {
                Text("完成登录后会自动查询；若未更新，可点右侧按钮。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                Spacer()
                CardHeaderButton(title: quota.checking ? "查询中…" : "刷新额度", busy: quota.checking, tint: LeafTheme.serviceBlue) { quota.refresh(force: true) }.disabled(quota.checking)
            }
        }.padding(20).frame(minWidth: 650, idealWidth: 780, minHeight: 600, idealHeight: 730)
            .foregroundStyle(LeafTheme.ink).background(LeafTheme.mist).onAppear { quota.beginLogin() }
            .onDisappear { quota.endLogin() }
            .onChange(of: quota.authentication) { _, value in if value == .authenticated { close() } }
    }
}

private struct MinutesProfileEdit: Identifiable {
    let id = UUID()
    let profile: MinutesAccountProfile?
}
private struct MinutesProfileLogin: Identifiable { let id: UUID }

private struct MinutesProfileEditor: View {
    let initialName: String
    let adding: Bool
    var save: (String) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(adding ? "添加飞书账号" : "重命名账号").font(.system(size: 24, weight: .medium))
            Text(adding ? "名称仅用于本机区分账号；登录和额度将独立保存。" : "修改本机显示名称，不会改变飞书登录。")
                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            LabeledContent("账号名称") {
                TextField("账号名称", text: $name).leafInput().accessibilityLabel("飞书账号名称")
            }
            if let error { Text(error).font(LeafType.caption).foregroundStyle(.orange) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(adding ? "添加并登录" : "保存名称") {
                    do { try save(name); dismiss() } catch { self.error = error.localizedDescription }
                }.buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 480).foregroundStyle(LeafTheme.ink).background(LeafTheme.mist)
            .onAppear { name = initialName }
    }
}

struct MinutesQuotaActions: View {
    let authentication: MinutesQuotaStore.Authentication
    let checking: Bool
    let profile: MinutesAccountProfile
    let profiles: [MinutesAccountProfile]
    var refresh: () -> Void
    var login: () -> Void
    var select: (UUID) -> Void
    var add: () -> Void
    var rename: () -> Void
    var automatic: () -> Void
    private var accountName: String { profile.menuName(in: profiles) }
    private var status: String {
        if authentication == .authenticated { return "已登录" }
        if checking && authentication == .unverified { return "验证中…" }
        return authentication == .required ? "未登录" : "待验证"
    }
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CardHeaderButton(title: checking ? "查询中…" : "立即查询", busy: checking, tint: LeafTheme.serviceBlue, action: refresh)
                .disabled(checking)
            CardHeaderMenu(title: accountName + " · " + status,
                           symbol: authentication == .authenticated ? "checkmark.circle.fill" : "person.crop.circle",
                           busy: checking && authentication == .unverified, tint: LeafTheme.serviceBlue) {
                ForEach(profiles) { entry in
                    Button { select(entry.id) } label: {
                        if entry.id == profile.id { Label(entry.menuName(in: profiles), systemImage: "checkmark") }
                        else { Text(entry.menuName(in: profiles)) }
                    }
                }
                Divider()
                if authentication != .authenticated { Button("登录飞书…", action: login) }
                Button("添加账号…", action: add)
                Button("重命名当前账号…", action: rename)
                if profile.identity != nil && !profile.usesAutomaticName {
                    Button("使用飞书姓名与组织", action: automatic)
                }
            }
            .accessibilityLabel("切换飞书账号，当前 " + accountName + "，" + status)
            .help(accountName + "：" + status + "。点击切换或管理账号；各账号官方额度与本地 CNY 预算分开，不合并计算。")
        }
    }
}

private struct MinutesLoginBrowser: NSViewRepresentable {
    let browser: WKWebView
    func makeNSView(context: Context) -> WKWebView { browser }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
