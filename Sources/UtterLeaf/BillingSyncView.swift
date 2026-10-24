import SwiftUI
import UtterLeafCore

struct BillingSyncView: View {
    @ObservedObject var store: LocalStore
    @State private var settings = false
    private var ledger: BillingLedger { store.database.billingLedger ?? BillingLedger() }
    private var config: BillingConfiguration { store.database.preferences.billing ?? BillingConfiguration() }
    var body: some View {
        Surface {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("官方核对").font(LeafType.headline)
                    Text(config.enabled ? "App 运行时每 20 分钟同步 · 唤醒后补查" : "自动同步已关闭")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                Spacer()
                Button("同步设置") { settings = true }.buttonStyle(.bordered).handCursor()
                Button { store.billingSync.request(force: true) } label: {
                    HStack(spacing: 7) {
                        if store.billingSyncing { ProgressView().controlSize(.small) }
                        Text(store.billingSyncing ? "核对中" : "立即核对")
                    }.frame(width: 100)
                }.buttonStyle(.bordered).handCursor().disabled(store.billingSyncing)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("豆包 · 官方实例账单").font(LeafType.headline)
                if let success = ledger.doubao.succeeded, ledger.scope == config.instanceID {
                    let amount = ledger.bills.reduce(Decimal.zero) { $0 + $1.payable }
                    Text("近 30 天已出账应付 \(billingMoney(amount, "CNY")) · \(ledger.bills.count) 条明细")
                    Text("最近成功 \(stamp(success))；小时账单可能延迟数小时，空结果不代表免费。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    if config.exclusiveInstance, !ledger.bills.isEmpty {
                        let comparison = BillComparison(bills: ledger.bills, calls: store.database.calls)
                        if comparison.matchedCalls > 0 {
                            Text("相同账单区间：本地估算 \(money(comparison.localEstimate, "CNY")) · 官方应付 \(billingMoney(comparison.official, "CNY")) · 差额 \(money(comparison.difference, "CNY"))")
                                .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                            if comparison.unknownCalls > 0 { Text("该区间另有 \(comparison.unknownCalls) 次本地金额未知，差额尚不能判断为计费异常。").font(LeafType.caption).foregroundStyle(.orange) }
                        } else { Text("已出账区间内暂无本地调用可比较。").font(LeafType.caption).foregroundStyle(LeafTheme.muted) }
                    }
                } else {
                    Text(config.hasScope ? "尚未成功拉取账单" : "待配置账单实例 ID 与个人只读凭证")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                }
                syncError(ledger.doubao)
                Text("实例账单可能含其他应用消费；仅在确认实例专用后比较。汇总账单不会分摊成逐次实际费用。")
                    .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("DeepSeek · 账户余额参考").font(LeafType.headline)
                if let snapshot = ledger.balances.last {
                    ForEach(snapshot.balances, id: \.currency) { balance in
                        Text("\(balance.currency) 可用余额 \(billingMoney(balance.total, balance.currency))")
                            .monospacedDigit()
                    }
                    Text("最近成功 \(stamp(snapshot.fetched)) · \(snapshot.available ? "账户可用" : "账户余额不可用")")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                } else { Text("尚未同步余额").font(LeafType.caption).foregroundStyle(LeafTheme.muted) }
                syncError(ledger.deepSeek)
                Text("公开接口返回账户余额，不是逐笔账单。充值、赠金、其他应用消费均会影响余额；不会据此改写听写费用。")
                    .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            }
        }.sheet(isPresented: $settings) { BillingSettings(store: store) }
    }
    private func stamp(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
    @ViewBuilder private func syncError(_ status: BillingSyncStatus) -> some View {
        if let code = status.errorCode {
            Text("\(status.attempted.map { stamp($0) + " · " } ?? "")\(billingErrorDescription(code))")
                .font(LeafType.caption).foregroundStyle(.orange)
        }
    }
}
func billingMoney(_ amount: Decimal, _ currency: String) -> String { money(NSDecimalNumber(decimal: amount).doubleValue, currency) }
func billingErrorDescription(_ code: String) -> String {
    switch code {
    case "credential_missing", "credential_empty": return "缺少本机查询凭证，请在同步设置中查看配置方法。"
    case "credential_file_permissions": return "个人凭证文件权限需为 600。"
    case "billing_scope_missing": return "豆包账单实例 ID 待配置，DeepSeek 仍可独立同步。"
    case "billing_scope_mismatch": return "返回账单范围与所选实例不符，已拒绝计入。"
    case "billing_remote_error": return "账单接口返回错误，请检查只读权限与实例范围。"
    case "billing_invalid_response": return "官方返回不完整或格式不符，已保留上次成功结果。"
    case "billing_page_limit": return "账单数量超过本次查询上限，未计入不完整结果。"
    case "billing_cancelled": return "同步中断，稍后会补查。"
    default: return "查询未完成（\(code)），保留上次成功结果；可检查网络、Clash 与查询权限后重试。"
    }
}
struct BillingSettings: View {
    @ObservedObject var store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BillingConfiguration()
    @State private var initial = BillingConfiguration()
    @State private var discard = false
    @State private var keysAvailable = false
    private var valid: Bool { [draft.instanceID, draft.product].allSatisfy { $0.count <= 256 && !$0.contains(where: { $0.isNewline }) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("官方核对设置").font(.system(size: 25, weight: .medium))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("每 20 分钟自动同步", isOn: $draft.enabled)
                    Text("仅在 App 运行时查询；睡眠期间不唤醒电脑，恢复后补查。自动查询避开正在录音与整理的时段。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    Divider()
                    Text("豆包 · 个人火山账单").font(LeafType.headline)
                    LabeledContent("账单实例 ID") { TextField("费用中心中的 InstanceNo", text: $draft.instanceID).leafInput().accessibilityLabel("豆包账单实例 ID") }
                    LabeledContent("产品代码（可选）") { TextField("账单中的 Product", text: $draft.product).leafInput().accessibilityLabel("豆包账单产品代码") }
                    Text("实例 ID 不一定等于语音 App ID。留空时暂停豆包查询，仍可同步 DeepSeek。只读凭证可查询的范围取决于火山账户授权。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    Toggle("确认此账单实例仅用于 UtterLeaf，显示区间差额", isOn: $draft.exclusiveInstance)
                    Text("仅查询最近 30 天；重复账单按明细 ID 去重。小时汇总不会分摊到单次调用，也不会覆盖手工核对金额。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    Label(keysAvailable ? "本机账单凭证可读" : "本机账单凭证待配置", systemImage: keysAvailable ? "checkmark.circle" : "key")
                    Text("用个人火山 IAM 只读子用户创建 AK/SK，在 ~/.llm.env 配置以下变量，或保存到 Keychain 的 network.utterleaf.personal 服务：\nUTTERLEAF_VOLC_ACCESS_KEY_ID\nUTTERLEAF_VOLC_SECRET_ACCESS_KEY\n文件权限保持 600；不要在聊天或仓库里粘贴密钥。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted).textSelection(.enabled)
                    HStack {
                        Link("打开火山控制台", destination: URL(string: "https://console.volcengine.com/")!)
                        Spacer()
                        Button("重新检查凭证") { refreshKeys() }.buttonStyle(.bordered).handCursor()
                    }
                    Divider()
                    Text("DeepSeek · 余额查询").font(LeafType.headline)
                    Text("沿用本机 DEEPSEEK_API_KEY。只保存余额快照，不上传录音或正文。余额变化不自动计为 UtterLeaf 的实际费用。")
                        .font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    if !valid { Text("实例 ID 与产品代码最多 256 个字符，且不能包含换行。").font(LeafType.caption).foregroundStyle(.orange) }
                }.padding(.trailing, 6)
            }
            HStack {
                Button("取消") { cancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存设置") {
                    draft.instanceID = draft.instanceID.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.product = draft.product.trimmingCharacters(in: .whitespacesAndNewlines)
                    if draft.instanceID != initial.instanceID || draft.product != initial.product {
                        var ledger = store.database.billingLedger ?? BillingLedger(); ledger.bills = []; ledger.scope = nil; ledger.doubao = BillingSyncStatus()
                        store.database.billingLedger = ledger
                    }
                    store.database.preferences.billing = draft; store.save(); dismiss()
                    if draft.enabled { store.billingSync.request() }
                }.buttonStyle(PrimaryStyle()).disabled(!valid || store.billingSyncing)
            }
        }.padding(26).frame(width: 640, height: 620).foregroundStyle(LeafTheme.ink).background(LeafTheme.mist)
            .onAppear { draft = store.database.preferences.billing ?? BillingConfiguration(); initial = draft; refreshKeys() }
            .confirmationDialog("放弃尚未保存的同步设置？", isPresented: $discard) {
                Button("放弃修改", role: .destructive) { dismiss() }; Button("继续编辑", role: .cancel) {}
            }
    }
    private func cancel() { if draft != initial { discard = true } else { dismiss() } }
    private func refreshKeys() { keysAvailable = Credentials.available("UTTERLEAF_VOLC_ACCESS_KEY_ID") && Credentials.available("UTTERLEAF_VOLC_SECRET_ACCESS_KEY") }
}
