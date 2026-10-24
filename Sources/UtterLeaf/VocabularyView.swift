import SwiftUI
import UtterLeafCore

struct VocabularyView: View {
    @ObservedObject var store: LocalStore
    @State private var query = ""
    @State private var limit = 30
    @State private var editing: VocabularyEntry?
    @State private var deleting: VocabularyEntry?
    @State private var feedback = ""
    var rows: [VocabularyEntry] {
        store.vocabulary.filter { query.isEmpty || ($0.term + " " + $0.aliases.joined(separator: " ") + " " + $0.note).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "词汇表", subtitle: "让人名、产品名和专业术语，保留你熟悉的拼写。")
            Surface {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("整理时，参考你的词汇").font(LeafType.headline)
                        Text("易错写法用于帮助理解语境；原始转写始终保留。关闭文字整理时，词汇表不生效。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
                    }
                    Spacer()
                    Button { editing = VocabularyEntry(term: "") } label: { Label("添加词条", systemImage: "plus") }.buttonStyle(PrimaryStyle())
                }
            }
            HStack {
                TextField("搜索词汇或易错写法", text: $query).leafInput().accessibilityLabel("搜索词汇表")
                if !query.isEmpty {
                    Button { query = ""; limit = 30 } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除词汇搜索")
                }
                Text("\(rows.count) 个词条").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            }.onChange(of: query) { _, _ in limit = 30 }
            if rows.isEmpty {
                Surface {
                    Text(query.isEmpty ? "还没有词条。添加一个经常识别错的人名或术语。" : "没有匹配的词条，试试其他关键词。")
                        .foregroundStyle(LeafTheme.muted)
                }
            }
            ForEach(Array(rows.prefix(limit))) { entry in
                Surface {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(entry.term).font(.system(size: 21, weight: .semibold)).textSelection(.enabled)
                            if !entry.aliases.isEmpty {
                                Text("易错写法：" + entry.aliases.joined(separator: "、")).font(LeafType.caption).foregroundStyle(LeafTheme.muted).textSelection(.enabled)
                            }
                            if !entry.note.isEmpty { Text(entry.note).font(LeafType.caption).foregroundStyle(LeafTheme.muted).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("启用", isOn: Binding(get: { store.vocabulary.first(where: { $0.id == entry.id })?.enabled ?? entry.enabled }, set: {
                            var updated = entry; updated.enabled = $0
                            do { try store.saveVocabulary(updated); feedback = $0 ? "已启用词条。" : "已停用词条。" }
                            catch { feedback = safeFailure(error).message }
                        })).toggleStyle(.switch).fixedSize()
                        Button("编辑") { editing = entry }.buttonStyle(.bordered).handCursor()
                        Button { deleting = entry } label: { Image(systemName: "trash") }.buttonStyle(.borderless).handCursor()
                            .foregroundStyle(.red).accessibilityLabel("删除词条 " + entry.term).help("删除词条")
                    }
                }
            }
            if rows.count > limit { Button("加载更多词条") { limit += 30 }.buttonStyle(.bordered).handCursor() }
            Text("录音开始时会固定本次使用的词汇表；修改影响下一次听写。“重新整理”会读取最新词汇表。词条仅保存在本机，启用的词条会随整理请求发送至你选择的 DeepSeek API。").font(LeafType.caption).foregroundStyle(LeafTheme.muted)
            if !feedback.isEmpty { Text(feedback).font(LeafType.caption).foregroundStyle(LeafTheme.leaf) }
        }
        .sheet(item: $editing) { entry in VocabularyEditor(store: store, entry: entry) { feedback = "已保存词条。" } }
        .confirmationDialog("删除词条？后续整理不再参考它。已有历史记录会保留。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let deleting { Button("删除 " + deleting.term, role: .destructive) { store.deleteVocabulary(deleting.id); self.deleting = nil; feedback = "已删除词条。" } }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }
}
struct VocabularyEditor: View {
    @ObservedObject var store: LocalStore
    let entry: VocabularyEntry
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var term: String
    @State private var aliases: String
    @State private var note: String
    @State private var enabled: Bool
    @State private var error = ""
    @State private var discard = false
    @FocusState private var termFocused: Bool
    init(store: LocalStore, entry: VocabularyEntry, onSave: @escaping () -> Void) {
        self.store = store; self.entry = entry; self.onSave = onSave
        _term = State(initialValue: entry.term); _aliases = State(initialValue: entry.aliases.joined(separator: "\n"))
        _note = State(initialValue: entry.note); _enabled = State(initialValue: entry.enabled)
    }
    var changed: Bool { term != entry.term || aliases != entry.aliases.joined(separator: "\n") || note != entry.note || enabled != entry.enabled }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry.term.isEmpty ? "添加词条" : "编辑词条").font(.system(size: 26, weight: .medium))
            VStack(alignment: .leading, spacing: 8) {
                Text("首选拼写").font(LeafType.headline)
                TextField("例如：Typeless", text: $term).leafInput(focus: $termFocused).accessibilityLabel("首选拼写")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("易错写法 · 每行一个").font(LeafType.headline)
                TextEditor(text: $aliases).font(.system(size: 16)).frame(height: 90).leafInput().accessibilityLabel("易错写法，每行一个")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("使用说明 · 可选").font(LeafType.headline)
                TextField("例如：语音输入 App；讨论字体时保留原词", text: $note).leafInput().accessibilityLabel("词条使用说明")
            }
            Toggle("启用此词条", isOn: $enabled)
            Text(error.isEmpty ? "只在语境匹配时规范拼写，避免把普通词语无条件替换。" : error)
                .font(LeafType.caption).foregroundStyle(error.isEmpty ? LeafTheme.muted : .red).frame(minHeight: 36, alignment: .topLeading)
            HStack {
                Button("取消") { if changed { discard = true } else { dismiss() } }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存词条", action: save).buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 600).font(.system(size: 16)).tint(LeafTheme.leaf)
            .foregroundStyle(LeafTheme.ink).background(LeafTheme.mist)
            .interactiveDismissDisabled(changed).onAppear { termFocused = true }
            .confirmationDialog("放弃未保存的词条修改？", isPresented: $discard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }; Button("继续编辑", role: .cancel) {}
            }
    }
    func save() {
        var updated = entry; updated.term = term; updated.aliases = aliases.components(separatedBy: .newlines)
        updated.note = note; updated.enabled = enabled
        do { try store.saveVocabulary(updated); onSave(); dismiss() }
        catch { self.error = safeFailure(error).message; termFocused = true }
    }
}
