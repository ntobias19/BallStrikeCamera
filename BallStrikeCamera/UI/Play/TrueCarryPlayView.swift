import SwiftUI

struct TrueCarryPlayView: View {
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController
    @State private var showCamera     = false
    @State private var showRangeSetup = false
    @State private var showSim        = false
    @State private var showCourseFlow = false
    @State private var showCourseMode = false
    @State private var selectedCourse: GolfCourse?
    @State private var selectedTeeBox: TeeBox?
    @State private var selectedMode: PlayMode = .range

    enum PlayMode { case range, sim, course }

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    headerSection
                    modePickerSection
                    sessionSetupCard
                    startButton
                    quickChipsRow
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen().ignoresSafeArea().statusBarHidden(true)
        }
        .sheet(isPresented: $showSim) { SimModeView() }
        .sheet(isPresented: $showCourseFlow) {
            if let uid = session.currentUser?.id {
                NavigationStack {
                    CourseSearchView(userId: uid) { course, tee in
                        selectedCourse = course
                        selectedTeeBox = tee
                        showCourseFlow = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showCourseMode = true
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
        .fullScreenCover(isPresented: $showCourseMode) {
            if let uid = session.currentUser?.id,
               let course = selectedCourse,
               let tee = selectedTeeBox {
                CourseModeGPSHoleView(
                    userId: uid,
                    backend: session.backend,
                    initialCourse: course,
                    initialTeeBox: tee
                )
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Play")
                .font(.system(size: 32, weight: .black))
                .foregroundColor(TCTheme.textPrimary)
            Text("Choose a mode and set up your session.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: Mode Picker

    private var modePickerSection: some View {
        VStack(spacing: 10) {
            TCModeCard(
                icon: "target",
                title: "Range Mode",
                subtitle: "Practice freely. Track carry, spin, ball speed & club path.",
                accent: TCTheme.cyan,
                action: { selectedMode = .range }
            )
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(selectedMode == .range ? TCTheme.cyan.opacity(0.50) : Color.clear, lineWidth: 2)
            )

            TCModeCard(
                icon: "display",
                title: "Simulator Mode",
                subtitle: "Send shots to GSPro, OGS, or any OpenAPI simulator over WiFi.",
                accent: TCTheme.gold,
                action: { selectedMode = .sim }
            )
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(selectedMode == .sim ? TCTheme.gold.opacity(0.50) : Color.clear, lineWidth: 2)
            )

            TCModeCard(
                icon: "map.fill",
                title: "Course Mode",
                subtitle: "Track every shot on-course with GPS rangefinder and scoring.",
                accent: TCTheme.sage,
                action: { selectedMode = .course }
            )
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(selectedMode == .course ? TCTheme.sage.opacity(0.50) : Color.clear, lineWidth: 2)
            )
        }
    }

    // MARK: Session Setup

    private var sessionSetupCard: some View {
        VStack(spacing: 0) {
            TCSectionHeader(title: "Session Setup")
                .padding(.bottom, 12)
            VStack(spacing: 0) {
                setupRow(icon: "figure.golf", label: "Club", value: "7 Iron", accent: TCTheme.sage)
                TCDivider()
                setupRow(icon: "flag.fill", label: "Course", value: "Pebble Beach", accent: TCTheme.gold)
                TCDivider()
                setupRow(icon: "hand.raised.fill", label: "Handedness",
                         value: session.userProfile?.handedness.rawValue ?? "Right",
                         accent: TCTheme.cyan)
                TCDivider()
                setupRow(icon: "location.fill", label: "GPS", value: "Active", accent: TCTheme.sage)
            }
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1)
            )
        }
    }

    private func setupRow(icon: String, label: String, value: String, accent: Color) -> some View {
        TCSettingsRow(icon: icon, title: label, value: value, accent: accent)
    }

    // MARK: Start Button

    private var startButton: some View {
        TCPrimaryGoldButton(
            title: buttonTitle,
            icon: buttonIcon,
            action: handleStart
        )
    }

    private var buttonTitle: String {
        switch selectedMode {
        case .range:  return "Open Camera"
        case .sim:    return "Start Sim Session"
        case .course: return "Find a Course"
        }
    }

    private var buttonIcon: String {
        switch selectedMode {
        case .range:  return "camera.fill"
        case .sim:    return "display"
        case .course: return "magnifyingglass"
        }
    }

    private func handleStart() {
        switch selectedMode {
        case .range:  showCamera = true
        case .sim:    showSim = true
        case .course: showCourseFlow = true
        }
    }

    // MARK: Quick Chips

    private var quickChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chipButton("Use Last Setup", icon: "arrow.clockwise") {}
                chipButton("Choose Club", icon: "figure.golf") {}
                chipButton("Saved Sessions", icon: "list.bullet") {}
                chipButton("Sim History", icon: "clock") {}
            }
            .padding(.horizontal, 2)
        }
    }

    private func chipButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(TCTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(TCTheme.panel)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
