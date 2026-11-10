import SwiftUI

struct ReferenceEntry: Identifiable, Hashable {
    let sign: String
    let meaning: String
    var id: String { sign }

    init(_ sign: String, _ meaning: String) {
        self.sign = sign
        self.meaning = meaning
    }
}

enum ReferenceTopic: String, CaseIterable, Identifiable {
    case prosigns, qcodes, abbreviations
    var id: Self { self }

    var title: String {
        switch self {
        case .prosigns: "Prosigns"
        case .qcodes: "Q-codes"
        case .abbreviations: "Abbreviations"
        }
    }

    var entries: [ReferenceEntry] {
        switch self {
        case .prosigns:
            return [
                .init("AR", "End of message"),
                .init("SK", "End of contact"),
                .init("BT", "Break / new paragraph"),
                .init("KN", "Over, named station only"),
                .init("K", "Over, anyone may reply"),
                .init("BK", "Break-in, quick back to you"),
                .init("AS", "Wait"),
                .init("HH", "Error (eight dits)"),
                .init("CL", "Closing down"),
                .init("SOS", "Distress"),
            ]
        case .qcodes:
            return [
                .init("QRL", "Is the frequency in use? / Busy"),
                .init("QRM", "Interference from other stations"),
                .init("QRN", "Static, atmospheric noise"),
                .init("QRO", "Increase power / high power"),
                .init("QRP", "Reduce power / low power (5 W or less)"),
                .init("QRQ", "Send faster"),
                .init("QRS", "Send slower"),
                .init("QRT", "Stop sending / closing down"),
                .init("QRU", "Nothing more for you"),
                .init("QRV", "Ready, available"),
                .init("QRX", "Wait, stand by"),
                .init("QRZ", "Who is calling me?"),
                .init("QRG", "Your exact frequency"),
                .init("QSB", "Signals fading"),
                .init("QSK", "Full break-in"),
                .init("QSL", "Received and understood / confirmation card"),
                .init("QSO", "A contact"),
                .init("QSY", "Change frequency"),
                .init("QTH", "Location"),
                .init("QTR", "Exact time"),
            ]
        case .abbreviations:
            return [
                .init("CQ", "Calling any station"), .init("DE", "From, this is"),
                .init("TU", "Thank you"), .init("TNX", "Thanks"), .init("FB", "Fine business, excellent"),
                .init("UR", "Your, you're"), .init("RST", "Readability, strength, tone"),
                .init("5NN", "599, with cut numbers"), .init("OP", "Operator"),
                .init("HR", "Here"), .init("ES", "And"), .init("HW", "How (copy)?"),
                .init("CPY", "Copy"), .init("SIG", "Signal"), .init("RIG", "Radio"),
                .init("ANT", "Antenna"), .init("PWR", "Power"), .init("WX", "Weather"),
                .init("TEMP", "Temperature"), .init("AGN", "Again"), .init("PSE", "Please"),
                .init("SRI", "Sorry"), .init("ABT", "About"), .init("FER", "For"),
                .init("NW", "Now"), .init("B4", "Before"), .init("WKD", "Worked"),
                .init("GM", "Good morning"), .init("GA", "Good afternoon"), .init("GE", "Good evening"),
                .init("GN", "Good night"), .init("OM", "Old man, any male operator"),
                .init("YL", "Young lady, any female operator"), .init("DR", "Dear"),
                .init("GL", "Good luck"), .init("HPE", "Hope"), .init("CUL", "See you later"),
                .init("CFM", "Confirm"), .init("BURO", "QSL bureau"),
                .init("73", "Best regards"), .init("88", "Love and kisses"), .init("72", "Best QRP regards"),
            ]
        }
    }
}

/// Searchable side panel of prosigns, Q-codes and abbreviations.
struct ReferencePanel: View {
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search, e.g. QRS or “slower”", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            List {
                ForEach(ReferenceTopic.allCases) { topic in
                    let rows = topic.entries.filter {
                        filter.isEmpty || $0.sign.localizedCaseInsensitiveContains(filter)
                            || $0.meaning.localizedCaseInsensitiveContains(filter)
                    }
                    if !rows.isEmpty {
                        Section(topic.title) {
                            ForEach(rows) { e in ReferenceRow(entry: e) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

/// Click to insert the sign at the cursor in the open note.
private struct ReferenceRow: View {
    let entry: ReferenceEntry
    @State private var hovering = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .insertText, object: entry.sign + " ")
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.sign)
                    .font(.body.monospaced().weight(.semibold))
                    .frame(minWidth: 44, alignment: .leading)
                Text(entry.meaning)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "text.insert")
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Insert \(entry.sign) into the note")
    }
}
