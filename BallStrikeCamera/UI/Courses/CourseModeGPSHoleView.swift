import SwiftUI

struct CourseModeGPSHoleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var camera: CameraController
    @StateObject private var vm: CourseRoundViewModel

    @State private var showCamera       = false
    @State private var showScoreEntry   = false
    @State private var showScorecard    = false
    @State private var showFinishAlert  = false

    let initialCourse: GolfCourse?
    let initialTeeBox: TeeBox?

    init(userId: UUID, backend: AppBackend,
         initialCourse: GolfCourse? = nil,
         initialTeeBox: TeeBox? = nil) {
        _vm = StateObject(wrappedValue: CourseRoundViewModel(userId: userId, backend: backend))
        self.initialCourse = initialCourse
        self.initialTeeBox = initialTeeBox
    }

    var body: some View {
        ZStack {
            TCTheme.background.ignoresSafeArea()
            TrueCarryBackground().ignoresSafeArea()

            if vm.roundActive, let round = vm.activeRound {
                activeHoleView(round: round)
            } else {
                loadingView
            }
        }
        .task {
            if let course = initialCourse, let tee = initialTeeBox {
                await vm.startRound(course: course, teeBox: tee)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen(context: ShotContext(sourceMode: .course,
                                                  holeNumber: vm.currentHole?.holeNumber,
                                                  holePar: vm.currentHole?.par,
                                                  courseName: vm.activeRound?.courseName))
                .ignoresSafeArea()
                .statusBarHidden(true)
        }
        .sheet(isPresented: $showScoreEntry) {
            if let hole = vm.currentHole {
                ScoreEntryView(
                    holeNumber: hole.holeNumber,
                    par: hole.par,
                    existingScore: hole.score,
                    existingPutts: hole.putts
                ) { score, putts, fairway, gir in
                    let idx = vm.currentHoleIndex
                    Task { await vm.setScore(holeIndex: idx, score: score,
                                            putts: putts, fairwayHit: fairway, gir: gir) }
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showScorecard) {
            if let round = vm.activeRound {
                NavigationStack {
                    ScorecardView(round: round, course: vm.selectedCourse)
                }
                .preferredColorScheme(.dark)
            }
        }
        .alert("Finish Round?", isPresented: $showFinishAlert) {
            Button("Finish & Save", role: .destructive) {
                Task { await vm.finishRound(); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(TCTheme.gold)
                .scaleEffect(1.4)
            Text("Setting up round…")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
        }
    }

    // MARK: Active Hole

    @ViewBuilder
    private func activeHoleView(round: CourseRound) -> some View {
        let currentHole = round.holes[min(vm.currentHoleIndex, round.holes.count - 1)]
        let summary = round.scoreSummary
        let diff = summary.totalScore - summary.totalPar

        VStack(spacing: 0) {
            // Top Bar
            topBar(round: round, diff: diff)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    holeCard(hole: currentHole)
                    actionButtons
                    holeNavigator(round: round)
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 16)
            }
        }
    }

    private func topBar(round: CourseRound, diff: Int) -> some View {
        HStack(spacing: 12) {
            Button { showFinishAlert = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(TCTheme.panel)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(spacing: 1) {
                Text(round.courseName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                Text(round.teeBoxName + " Tees")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }

            Spacer()

            // Score to par badge
            VStack(spacing: 1) {
                Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(diff < 0 ? TCTheme.sage : diff == 0 ? TCTheme.cyan : TCTheme.textPrimary)
                Text("to par")
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textMuted)
            }

            Button { showScorecard = true } label: {
                Image(systemName: "list.number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
                    .frame(width: 36, height: 36)
                    .background(TCTheme.gold.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(TCTheme.gold.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 14)
        .background(TCTheme.panel)
        .overlay(Rectangle().fill(TCTheme.border).frame(height: 1), alignment: .bottom)
    }

    private func holeCard(hole: RoundHole) -> some View {
        VStack(spacing: 0) {
            // Accent top stripe
            LinearGradient(colors: [TCTheme.sage, TCTheme.gold],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: TCTheme.cardRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: TCTheme.cardRadius))

            VStack(spacing: 16) {
                // Hole header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HOLE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(TCTheme.textMuted)
                            .tracking(2)
                        Text("\(hole.holeNumber)")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundColor(TCTheme.textPrimary)
                    }

                    Spacer()

                    VStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text("PAR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TCTheme.textMuted)
                                .tracking(2)
                            Text("\(hole.par)")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(TCTheme.cyan)
                        }

                        if let score = hole.score {
                            let scoreDiff = score - hole.par
                            VStack(spacing: 2) {
                                Text("SCORE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(TCTheme.textMuted)
                                    .tracking(2)
                                Text("\(score)")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundColor(scoreDiff < 0 ? TCTheme.sage :
                                                     scoreDiff == 0 ? TCTheme.textPrimary : TCTheme.gold)
                            }
                        }
                    }
                }

                // Stats row
                HStack(spacing: 0) {
                    holeStatCell(icon: "flag.fill", label: "Putts",
                                 value: hole.putts.map { "\($0)" } ?? "—",
                                 color: TCTheme.gold)
                    holeStatCell(icon: "arrow.left.and.right", label: "Fairway",
                                 value: hole.fairwayHit.map { $0 ? "Hit" : "Miss" } ?? "—",
                                 color: hole.fairwayHit == true ? TCTheme.sage : TCTheme.textMuted)
                    holeStatCell(icon: "circlebadge.fill", label: "GIR",
                                 value: hole.greenInRegulation.map { $0 ? "Yes" : "No" } ?? "—",
                                 color: hole.greenInRegulation == true ? TCTheme.sage : TCTheme.textMuted)
                }
            }
            .padding(18)
            .background(TCTheme.panel)
        }
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
    }

    private func holeStatCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Hit Shot — primary gold
            TCPrimaryGoldButton(title: "Hit Shot", icon: "camera.fill") {
                showCamera = true
            }

            HStack(spacing: 10) {
                // Add Score
                Button { showScoreEntry = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                        Text("Add Score")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(TCTheme.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TCTheme.cyan.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(TCTheme.cyan.opacity(0.30), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Scorecard
                Button { showScorecard = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.number")
                            .font(.system(size: 14, weight: .bold))
                        Text("Scorecard")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(TCTheme.sage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TCTheme.sage.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(TCTheme.sage.opacity(0.30), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Hole Navigator

    private func holeNavigator(round: CourseRound) -> some View {
        HStack(spacing: 12) {
            Button {
                if vm.currentHoleIndex > 0 { vm.goToHole(vm.currentHoleIndex - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(vm.currentHoleIndex > 0 ? TCTheme.textSecondary : TCTheme.textMuted.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .background(TCTheme.panel)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
            }
            .disabled(vm.currentHoleIndex == 0)
            .buttonStyle(.plain)

            Spacer()

            Text("Hole \(vm.currentHoleIndex + 1) of \(round.holes.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)

            Spacer()

            let isLast = vm.currentHoleIndex >= round.holes.count - 1
            if isLast {
                Button { showFinishAlert = true } label: {
                    Text("Finish")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(TCTheme.goldGradient)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button { vm.advanceHole() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(TCTheme.panel)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
