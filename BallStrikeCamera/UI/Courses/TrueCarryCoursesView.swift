import SwiftUI

struct TrueCarryCoursesView: View {
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController
    @State private var showCourseSearch = false
    @State private var showCourseMode   = false
    @State private var selectedCourse: GolfCourse?
    @State private var selectedTeeBox: TeeBox?

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    headerSection
                    startRoundCard
                    recentRoundsSection
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCourseSearch) {
            if let uid = session.currentUser?.id {
                NavigationStack {
                    CourseSearchView(userId: uid) { course, tee in
                        selectedCourse = course
                        selectedTeeBox = tee
                        showCourseSearch = false
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
            Text("Courses")
                .font(.system(size: 32, weight: .black))
                .foregroundColor(TCTheme.textPrimary)
            Text("Track every round on the course.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: Start Round Card

    private var startRoundCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(colors: [TCTheme.sage, TCTheme.deepGreen],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: TCTheme.cardRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: TCTheme.cardRadius))

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start a Round")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("GPS rangefinder + launch monitor data for every shot.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TCTheme.textSecondary)
                }
                TCPrimaryGoldButton(title: "Find a Course", icon: "magnifyingglass") {
                    showCourseSearch = true
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
        .shadow(color: TCTheme.sage.opacity(0.12), radius: 18, x: 0, y: 6)
    }

    // MARK: Recent Rounds

    private var recentRoundsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Recent Rounds")
            VStack(spacing: 10) {
                roundRow(course: "Pebble Beach",     date: "Yesterday",   score: "+3", holes: 9)
                roundRow(course: "Augusta National", date: "3 days ago",  score: "E",  holes: 18)
                roundRow(course: "TPC Sawgrass",     date: "Last week",   score: "+5", holes: 18)
            }
        }
    }

    private func roundRow(course: String, date: String, score: String, holes: Int) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(TCTheme.sage.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "flag.fill")
                        .font(.system(size: 16))
                        .foregroundColor(TCTheme.sage)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(course)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("\(holes) holes · \(date)")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            Text(score)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(scoreColor(score))
        }
        .tcCard()
    }

    private func scoreColor(_ score: String) -> Color {
        if score == "E"             { return TCTheme.cyan }
        if score.hasPrefix("-")     { return TCTheme.sage }
        return TCTheme.textPrimary
    }
}
