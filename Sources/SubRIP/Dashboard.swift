import SwiftUI
import AppKit
import SubRIPCore

private let accent = Color(red: 0.69, green: 0.94, blue: 0.58)

struct Dashboard: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var editing: Subscription?
    @State private var settings = false
    @State private var cancellation: Subscription?
    @State private var sharing: Subscription?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SubRIP †").font(.system(size: 36, weight: .black, design: .rounded))
                        Text("안 쓰는 AI 구독, 편히 보내드리세요.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { settings = true } label: { Label("로그 연결", systemImage: "externaldrive") }
                    Button { adding = true } label: { Label("구독 추가", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                }
                let candidates = store.active.filter { store.assessment($0).verdict == .review }
                HStack(spacing: 14) {
                    metric("매달 나가는 돈", value: store.totals(store.active), caption: "등록된 월간 구독료")
                    metric("장례 후보", value: "\(candidates.count)개", caption: "14일 이상 관찰한 낮은 사용 빈도")
                    metric("다음 달 절약 후보", value: store.totals(candidates), caption: "해지 시 피할 수 있는 월 구독료")
                }
                if store.active.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 48)).foregroundStyle(accent)
                        Text("돈은 나가는데, AI는 쉬고 있나요?").font(.title2.bold())
                        Text("구독을 추가하고 사용한 날을 기록해 보세요.\n최소 14일 관찰 후 장례 후보를 찾을게요.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("첫 구독 추가") { adding = true }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                    }.frame(maxWidth: .infinity).padding(42).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                } else {
                    HStack {
                        Text("생존 확인 중").font(.title2.bold())
                        Spacer()
                        if store.scanning { ProgressView().controlSize(.small) }
                        Button("사용량 새로고침") { Task { await store.scan() } }.disabled(store.scanning)
                    }
                    ForEach(store.active) { item in
                        SubscriptionRow(item: item, assessment: store.assessment(item),
                                        edit: { editing = item }, share: { sharing = item }, cancel: { cancellation = item })
                    }
                }
                if !store.buried.isEmpty {
                    HStack {
                        Text("구독 공동묘지").font(.title2.bold())
                        Spacer()
                        Text("재구독하지 않으면 연 \(store.totals(store.buried, multiplier: 12)) 절약 예상")
                            .font(.caption).foregroundStyle(accent)
                    }
                    ForEach(store.buried) { item in
                        HStack {
                            Text("†").font(.largeTitle).foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text("안치 완료 · \(item.cancelledAt!.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("묘비 공유") { sharing = item }
                            Button("다시 살리기") { store.restore(item) }
                        }.padding(18).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                Text("토큰은 사용 기록이에요. 남은 구독 할당량이나 실제 낭비 금액을 뜻하지 않아요.\nChatGPT·Claude 웹, 모바일, 다른 기기 사용은 직접 기록해 주세요. 서비스 해지는 직접 진행해야 해요.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(5)
            }.padding(30)
        }
        .background(Color(red: 0.055, green: 0.065, blue: 0.06))
        .disabled(!store.ready)
        .sheet(isPresented: $adding) { SubscriptionEditor(item: Subscription()).environmentObject(store) }
        .sheet(item: $editing) { SubscriptionEditor(item: $0).environmentObject(store) }
        .sheet(isPresented: $settings) { Connections().environmentObject(store) }
        .sheet(item: $sharing) { ShareSheet(item: $0, assessment: store.assessment($0)).environmentObject(store) }
        .alert("서비스에서 해지를 완료했나요?", isPresented: Binding(get: { cancellation != nil }, set: { if !$0 { cancellation = nil } })) {
            Button("해지 완료로 기록") { if let item = cancellation { store.cancel(item) }; cancellation = nil }
            Button("돌아가기", role: .cancel) { cancellation = nil }
        } message: { Text("SubRIP은 실제 구독을 해지하지 않아요. 서비스의 결제 설정에서 직접 해지한 뒤 기록해 주세요.") }
        .alert("확인이 필요해요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("확인") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func metric(_ title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(accent).minimumScaleFactor(0.5).lineLimit(1)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SubscriptionRow: View {
    @EnvironmentObject var store: Store
    let item: Subscription
    let assessment: Assessment
    let edit: () -> Void
    let share: () -> Void
    let cancel: () -> Void
    @State private var day = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.title3.bold())
                    Text("\(store.money(item.monthlyPrice, currency: item.currency)) / 월 · \(assessment.nextBilling.formatted(date: .abbreviated, time: .omitted)) 갱신")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(assessment.verdict.rawValue).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(assessment.verdict == .review ? accent : .white.opacity(0.8))
                    .background(Color.white.opacity(0.07), in: Capsule())
                Button("편집", action: edit)
            }
            HStack(spacing: 24) {
                Label("이번 주기 사용 \(assessment.activeDays)일", systemImage: "calendar")
                if item.includesCLI { Label("\(assessment.tokens.formatted()) 토큰", systemImage: "terminal") }
                if let risk = assessment.riskScore { Text("미사용 빈도 점수 \(risk)/100") }
            }.font(.caption).foregroundStyle(.secondary)
            Text(assessment.explanation).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                DatePicker("사용한 날", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden().frame(width: 125)
                Button("사용 기록") { store.used(item, on: day) }
                Button("이번 주기, 돈값 했음") { store.markValue(item) }
                Spacer()
                Button("묘비 공유", action: share)
                Button("해지 기록", action: cancel).foregroundStyle(accent)
            }
        }.padding(20).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SubscriptionEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var item: Subscription
    @State private var price: String
    init(item: Subscription) {
        _item = State(initialValue: item)
        _price = State(initialValue: item.monthlyPrice > 0 ? String(item.monthlyPrice) : "")
    }
    private var valid: Bool {
        guard let amount = Double(price), amount.isFinite, amount > 0, amount <= 1_000_000_000 else { return false }
        return !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("구독 등록부").font(.title.bold())
            Form {
                Picker("서비스", selection: $item.provider) { ForEach(Provider.allCases) { Text($0.title).tag($0) } }
                TextField("플랜 이름", text: $item.name, prompt: Text("예: Claude Pro"))
                HStack {
                    TextField("월 구독료", text: $price)
                    Picker("통화", selection: $item.currency) { Text("USD").tag("USD"); Text("KRW").tag("KRW"); Text("EUR").tag("EUR") }.frame(width: 130)
                }
                DatePicker("결제일 (매월 같은 날짜)", selection: $item.billingAnchor, displayedComponents: .date)
                if item.provider.supportsCLI {
                    Toggle("이 구독으로 결제되는 CLI 로그 포함", isOn: $item.includesCLI)
                    Text("API 키·회사 계정의 사용은 개인 구독에 포함하지 마세요. 연결한 폴더는 이 구독 전용이어야 해요.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("웹·모바일·다른 기기의 사용한 날도 기록했어요", isOn: $item.coverageConfirmed)
                Toggle("이번 결제 주기에 중요한 가치를 얻었어요", isOn: $item.valuableThisCycle)
                Text("관찰은 등록일부터 시작해요. 최근 사용을 빠짐없이 기록했을 때만 체크해 주세요. 플랜별 총 토큰 할당량은 추정하지 않아요.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            HStack {
                Text("MVP는 월간 플랜을 지원해요.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("취소") { dismiss() }
                Button("저장") {
                    item.name = String(item.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                    item.monthlyPrice = Double(price)!
                    item.coverageConfirmedAt = item.coverageConfirmed ? Date() : nil
                    if item.valuableThisCycle { item.valueMarkedAt = Date() } else { item.valueMarkedAt = nil }
                    if !item.provider.supportsCLI { item.includesCLI = false }
                    store.upsert(item)
                    if store.error == nil { dismiss() }
                }.disabled(!valid).buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(26).frame(width: 540, height: 550).preferredColorScheme(.dark)
    }
}

struct Connections: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("로컬 사용량 연결").font(.title.bold())
            Text("직접 선택한 폴더의 JSONL 로그만 읽어요. 토큰·날짜를 저장하고 대화 내용은 저장·전송하지 않아요. 인증 파일이나 브라우저 기록은 읽지 않아요.")
                .foregroundStyle(.secondary)
            ForEach([Provider.claude, Provider.openai]) { provider in
                VStack(alignment: .leading, spacing: 10) {
                    Text(provider == .claude ? "Claude Code" : "Codex").font(.headline)
                    Text(provider == .claude ? "기본 위치: ~/.claude/projects" : "기본 위치: ~/.codex/sessions").font(.caption).foregroundStyle(.secondary)
                    let folder = provider == .claude ? store.data.claudeFolder : store.data.codexFolder
                    Text(folder ?? "연결하지 않음").font(.caption).textSelection(.enabled).lineLimit(2)
                    if let status = store.data.snapshot?.sources.first(where: { $0.provider == provider }) {
                        Text("\(statusLabel(status.status)) · 파일 \(status.files) · 손상 \(status.malformed) · 읽기 실패 \(status.unreadable) · 미지원 \(status.unsupported)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("폴더 선택") { store.chooseFolder(provider) }
                        Button("연결 해제") { store.disconnect(provider) }.disabled(folder == nil)
                    }.disabled(store.scanning)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("5분마다 앱이 실행 중일 때 갱신해요. 로그 형식은 변경될 수 있어요. 부분 수집이나 미지원 형식이면 해지 판단을 보류해요.").font(.caption).foregroundStyle(.secondary)
            HStack {
                if let date = store.data.scannedAt { Text("갱신: \(date.formatted())").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if store.scanning { ProgressView().controlSize(.small) }
                Button("새로고침") { Task { await store.scan() } }.disabled(store.scanning)
                Button("완료") { dismiss() }
            }
        }.padding(26).frame(width: 600).preferredColorScheme(.dark)
    }
    private func statusLabel(_ status: String) -> String {
        switch status {
        case "ok": return "수집 완료 (로컬 기록만)"
        case "partial": return "부분 수집 — 판단 보류"
        case "no_usage": return "사용 기록을 찾지 못함"
        case "missing": return "폴더 없음"
        case "unreadable": return "읽기 실패"
        default: return "연결하지 않음"
        }
    }
}
