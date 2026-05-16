import SwiftUI

struct ScoreEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let holeNumber: Int
    let par: Int
    var existingScore: Int?
    var existingPutts: Int?
    let onSave: (Int, Int?, Bool?, Bool?) -> Void

    @State private var score: Int
    @State private var putts: Int
    @State private var fairwayHit: Bool?
    @State private var gir: Bool?

    init(holeNumber: Int, par: Int,
         existingScore: Int? = nil, existingPutts: Int? = nil,
         onSave: @escaping (Int, Int?, Bool?, Bool?) -> Void) {
        self.holeNumber = holeNumber
        self.par = par
        self.existingScore = existingScore
        self.existingPutts = existingPutts
        self.onSave = onSave
        _score = State(initialValue: existingScore ?? par)
        _putts = State(initialValue: existingPutts ?? 2)
        _fairwayHit = State(initialValue: nil)
        _gir = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TCTheme.background.ignoresSafeArea()
                TrueCarryBackground().ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        holeHeader
                        scoreSection
                        puttsSection
                        fairwaySection
                        girSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Hole \(holeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TCTheme.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(score, putts, fairwayHit, gir)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.gold)
                }
            }
        }
    }

    // MARK: Hole Header

    private var holeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOLE \(holeNumber)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TCTheme.textMuted)
                    .tracking(2)
                Text("Par \(par)")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(TCTheme.textPrimary)
            }
            Spacer()
            scoreBadge
        }
        .tcCard()
    }

    private var scoreBadge: some View {
        let diff = score - par
        return VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(diff < 0 ? TCTheme.sage : diff == 0 ? TCTheme.cyan : TCTheme.gold)
            Text(scoreLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(diff < 0 ? TCTheme.sage : diff == 0 ? TCTheme.cyan : TCTheme.gold)
        }
    }

    private var scoreLabel: String {
        let diff = score - par
        switch diff {
        case ..<(-1): return "Eagle"
        case -1:      return "Birdie"
        case 0:       return "Par"
        case 1:       return "Bogey"
        case 2:       return "Double"
        default:      return "+\(diff)"
        }
    }

    // MARK: Score Stepper

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Score")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(1.5)

            HStack(spacing: 20) {
                stepperButton(icon: "minus", action: { if score > 1 { score -= 1 } })
                Text("\(score)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
                    .frame(minWidth: 60, alignment: .center)
                stepperButton(icon: "plus", action: { score += 1 })
            }
            .frame(maxWidth: .infinity)
        }
        .tcCard()
    }

    // MARK: Putts Stepper

    private var puttsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Putts")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(1.5)

            HStack(spacing: 20) {
                stepperButton(icon: "minus", action: { if putts > 0 { putts -= 1 } })
                Text("\(putts)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.cyan)
                    .frame(minWidth: 60, alignment: .center)
                stepperButton(icon: "plus", action: { putts += 1 })
            }
            .frame(maxWidth: .infinity)
        }
        .tcCard()
    }

    private func stepperButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TCTheme.textSecondary)
                .frame(width: 52, height: 52)
                .background(TCTheme.panelRaised)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Fairway

    private var fairwaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fairway")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(1.5)

            HStack(spacing: 10) {
                toggleChip("Hit", selected: fairwayHit == true,  color: TCTheme.sage) { fairwayHit = true  }
                toggleChip("Miss", selected: fairwayHit == false, color: TCTheme.danger) { fairwayHit = false }
                toggleChip("N/A", selected: fairwayHit == nil,   color: TCTheme.textMuted) { fairwayHit = nil  }
            }
        }
        .tcCard()
    }

    // MARK: GIR

    private var girSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Green in Regulation")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(1.5)

            HStack(spacing: 10) {
                toggleChip("Yes", selected: gir == true,  color: TCTheme.sage)   { gir = true  }
                toggleChip("No",  selected: gir == false, color: TCTheme.danger) { gir = false }
                toggleChip("N/A", selected: gir == nil,   color: TCTheme.textMuted) { gir = nil }
            }
        }
        .tcCard()
    }

    private func toggleChip(_ label: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? .black : TCTheme.textMuted)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(selected ? color : TCTheme.panelRaised)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(selected ? color : TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
