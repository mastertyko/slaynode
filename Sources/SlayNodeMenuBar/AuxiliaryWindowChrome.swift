import AppKit
import SwiftUI

struct AuxiliaryWindowBackdrop: View {
    let accent: Color

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 90)
                .offset(x: -150, y: -120)

            Circle()
                .fill(Color.orange.opacity(0.07))
                .frame(width: 220, height: 220)
                .blur(radius: 110)
                .offset(x: 180, y: 120)
        }
    }
}

struct AuxiliaryWindowShell<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AuxiliaryWindowBackdrop(accent: accent)
                .ignoresSafeArea()

            content
                .padding(24)
        }
    }
}

struct AuxiliaryHeroCard<Trailing: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.16))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.08), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12))
                )
        )
    }
}

struct AuxiliarySectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(accent)

                Text(title)
                    .font(.headline)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.05), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08))
                )
        )
    }
}

struct AuxiliaryPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .foregroundStyle(tint)
    }
}

struct AuxiliaryPrimaryButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(configuration.isPressed ? 0.10 : 0.16),
                                        tint.opacity(configuration.isPressed ? 0.01 : 0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(tint.opacity(configuration.isPressed ? 0.14 : 0.18))
                    )
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.04 : 0.08),
                radius: configuration.isPressed ? 4 : 10,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

@MainActor
func slayNodeAppIcon() -> NSImage? {
    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let appIcon = NSImage(contentsOf: iconURL) {
        return appIcon
    }

    return NSApp.applicationIconImage
}
