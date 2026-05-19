import SwiftUI

struct ScoreEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore

    let holeNumber: Int
    let par: Int
    var existingScore: Int?
    var existingPutts: Int?
    var holeYardage: Int?
    var handicap: Int?
    let onSave: (Int, Int?, Bool?, Bool?) -> Void

    @State private var score: Int
    @State private var putts: Int
    @State private var teeResult: String = "Fairway"
    @State private var fairwayHit: Bool?
    @State private var gir: Bool?
    @State private var mishit = false

    private let pageBackground = Color(red: 0.89, green: 0.92, blue: 0.95)
    private let sheetBackground = Color(red: 0.985, green: 0.988, blue: 0.992)
    private let cardBorder = Color(red: 0.81, green: 0.87, blue: 0.93)
    private let softBlue = Color(red: 0.84, green: 0.90, blue: 0.96)
    private let buttonBlue = Color(red: 0.27, green: 0.50, blue: 0.78)
    private let olive = Color(red: 0.76, green: 0.87, blue: 0.24)
    private let textInk = Color(red: 0.20, green: 0.28, blue: 0.37)
    private let mutedInk = Color(red: 0.40, green: 0.50, blue: 0.60)

    init(holeNumber: Int, par: Int,
         existingScore: Int? = nil, existingPutts: Int? = nil,
         holeYardage: Int? = nil, handicap: Int? = nil,
         onSave: @escaping (Int, Int?, Bool?, Bool?) -> Void) {
        self.holeNumber = holeNumber
        self.par = par
        self.existingScore = existingScore
        self.existingPutts = existingPutts
        self.holeYardage = holeYardage
        self.handicap = handicap
        self.onSave = onSave
        _score = State(initialValue: existingScore ?? par)
        _putts = State(initialValue: existingPutts ?? 2)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    mapHeader
                    Spacer(minLength: 0)
                }

                scoreSheet
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var mapHeader: some View {
        ZStack(alignment: .top) {
            GeneratedFairwayView()
                .frame(height: 260)
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.10), Color.black.opacity(0.34)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 16) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                VStack(spacing: 6) {
                    Text(ordinal(holeNumber).uppercased())
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    HStack(spacing: 12) {
                        Text("Par \(par)")
                        if let holeYardage {
                            Text("\(holeYardage) yds")
                        }
                        if let handicap {
                            Text("Hcp \(handicap)")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.94))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.34))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
    }

    private var scoreSheet: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cardBorder)
                .frame(width: 44, height: 6)
                .padding(.top, 10)
                .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    playerHeader
                    divider
                    scoringPanel
                    divider
                    detailPanel
                    saveFooter
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .ignoresSafeArea(edges: .bottom)
    }

    private var playerHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.43, green: 0.23, blue: 0.29))
                    .frame(width: 42, height: 42)
                Circle()
                    .strokeBorder(Color.white.opacity(0.92), lineWidth: 2)
                    .frame(width: 42, height: 42)
                Text(userInitials)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(userName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(textInk)
                    Text(existingScore == nil ? "New" : "Saved")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(mutedInk)
                }

                HStack(spacing: 6) {
                    Text(scoreSummaryLabel)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(scoreSummaryColor)
                    Text(scoreDeltaText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(mutedInk)
                }
            }

            Spacer()

            Button(action: saveAndDismiss) {
                Text("Enter")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 74, height: 64)
                    .background(buttonBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var scoringPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            metricStepper(
                title: "Score",
                value: score,
                accent: softBlue,
                decrement: { if score > 1 { score -= 1 } },
                increment: { score += 1 }
            )

            metricStepper(
                title: "Putts",
                value: putts,
                accent: softBlue,
                decrement: { if putts > 0 { putts -= 1 } },
                increment: { putts += 1 }
            )

            teeShotPad
                .frame(maxWidth: .infinity)
        }
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Round Details")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(textInk)

                HStack(spacing: 10) {
                    detailChip("GIR", selected: gir == true, tint: olive) { gir = true }
                    detailChip("No GIR", selected: gir == false, tint: softBlue) { gir = false }
                    detailChip("Auto", selected: gir == nil, tint: Color.white) { gir = nil }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Shot Tags")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(textInk)

                HStack(spacing: 10) {
                    Button {
                        mishit.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mishit ? "xmark.circle.fill" : "circle")
                            Text(mishit ? "Mis-Hit" : "Clean Strike")
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(mishit ? textInk : mutedInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(mishit ? olive.opacity(0.60) : Color.white)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(mishit ? olive.opacity(0.9) : cardBorder, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)

                    Text(teeResultLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(buttonBlue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(buttonBlue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var saveFooter: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(mutedInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1.5)
                )

            Button(action: saveAndDismiss) {
                Text("Save Score")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(buttonBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func metricStepper(title: String,
                               value: Int,
                               accent: Color,
                               decrement: @escaping () -> Void,
                               increment: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(mutedInk)

            VStack(spacing: 12) {
                roundStepperButton(icon: "plus", action: increment)

                Text("\(value)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(textInk)

                roundStepperButton(icon: "minus", action: decrement)
            }
            .frame(width: 58)
            .padding(.vertical, 10)
            .background(accent)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
            )
        }
        .frame(width: 64)
    }

    private func roundStepperButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.98))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(buttonBlue)
            }
        }
        .buttonStyle(.plain)
    }

    private var teeShotPad: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tee Shot")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(mutedInk)

            ZStack {
                teeOuterButton(
                    systemImage: "arrow.up.left",
                    selected: teeResult == "Short Left",
                    offset: CGSize(width: -8, height: -44)
                ) {
                    teeResult = "Short Left"
                }

                teeOuterButton(
                    systemImage: "chevron.left",
                    selected: teeResult == "Left",
                    offset: CGSize(width: -54, height: 0)
                ) {
                    teeResult = "Left"
                }

                teeOuterButton(
                    systemImage: "chevron.right",
                    selected: teeResult == "Right",
                    offset: CGSize(width: 54, height: 0)
                ) {
                    teeResult = "Right"
                }

                teeOuterButton(
                    systemImage: "arrow.down.right",
                    selected: teeResult == "Short Right",
                    offset: CGSize(width: 8, height: 44)
                ) {
                    teeResult = "Short Right"
                }

                Button {
                    teeResult = "Fairway"
                    mishit = false
                } label: {
                    Text("HIT")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(textInk)
                        .frame(width: 68, height: 68)
                        .background(olive)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.92), lineWidth: 4)
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(width: 170, height: 170)
            .frame(maxWidth: .infinity)

            Text(teeResultLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(mutedInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(softBlue.opacity(0.75))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func teeOuterButton(systemImage: String,
                                selected: Bool,
                                offset: CGSize,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(selected ? buttonBlue : mutedInk)
                .frame(width: 54, height: 54)
                .background(selected ? Color.white : softBlue.opacity(0.95))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(selected ? buttonBlue.opacity(0.30) : Color.white.opacity(0.85), lineWidth: 3)
                )
        }
        .buttonStyle(.plain)
        .offset(offset)
    }

    private func detailChip(_ title: String,
                            selected: Bool,
                            tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(selected ? textInk : mutedInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(selected ? tint : Color.white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(selected ? tint.opacity(0.95) : cardBorder, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(cardBorder.opacity(0.72))
            .frame(height: 1)
    }

    private var scoreDelta: Int { score - par }

    private var scoreSummaryLabel: String {
        scoreLabel(scoreDelta)
    }

    private var scoreSummaryColor: Color {
        scoreLabelColor(scoreDelta)
    }

    private var scoreDeltaText: String {
        if scoreDelta == 0 { return "E" }
        return scoreDelta > 0 ? "+\(scoreDelta)" : "\(scoreDelta)"
    }

    private var teeResultLabel: String {
        switch teeResult {
        case "Fairway": return "Center Cut"
        case "Short Left": return "Short Left"
        case "Short Right": return "Short Right"
        default: return teeResult
        }
    }

    private func saveAndDismiss() {
        fairwayHit = teeResult == "Fairway"
        onSave(score, putts, fairwayHit, gir)
        dismiss()
    }

    private func scoreLabel(_ diff: Int) -> String {
        switch diff {
        case ..<(-1): return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double"
        default: return "+\(diff)"
        }
    }

    private func scoreLabelColor(_ diff: Int) -> Color {
        if diff < 0 { return Color(red: 0.29, green: 0.60, blue: 0.30) }
        if diff == 0 { return buttonBlue }
        return Color(red: 0.76, green: 0.53, blue: 0.22)
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private var userName: String {
        session.userProfile?.displayName ?? "Player"
    }

    private var userInitials: String {
        let parts = userName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].first ?? "P").uppercased()
                + String(parts[1].first ?? "L").uppercased()
        }
        return String(userName.prefix(2)).uppercased()
    }
}
