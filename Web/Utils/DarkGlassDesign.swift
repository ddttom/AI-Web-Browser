import SwiftUI
import AppKit

// Dark-Glass Design System Color Tokens
extension Color {
    // Base colors
    static let bgBase = Color(red: 0.043, green: 0.043, blue: 0.043) // #0B0B0B
    static let bgSurface = Color.white.opacity(0.06)
    
    // Text colors
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.35)
    
    // Accent colors
    static let accentBeam = Color(red: 1.0, green: 0.647, blue: 0.510).opacity(0.35) // #FFA582 @ 35%
    
    // Border colors
    static let borderGlass = Color.white.opacity(0.22)
    static let strokeCavedTop = Color.black.opacity(0.9)
    static let strokeCavedBot = Color.white.opacity(0.06)
}

// Glass Materials and Effects
struct GlassModifier: ViewModifier {
    let intensity: GlassIntensity
    
    enum GlassIntensity {
        case ultraThin
        case thin
        case regular
        case thick
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base glass surface
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.bgSurface)
                    
                    // Glass border
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.borderGlass, lineWidth: 1)
                    
                    // Subtle backdrop blur simulation
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .opacity(materialOpacity)
                }
            )
    }
    
    private var materialOpacity: Double {
        switch intensity {
        case .ultraThin: return 0.3
        case .thin: return 0.5
        case .regular: return 0.7
        case .thick: return 0.9
        }
    }
}

// Typography System
extension Font {
    static let webH1 = Font.system(size: 28, weight: .semibold, design: .default)
    static let webH2 = Font.system(size: 22, weight: .medium, design: .default)
    static let webBody = Font.system(size: 15, weight: .regular, design: .default)
    static let webMicro = Font.system(size: 12, weight: .regular, design: .default)
}

// Button Styles
struct GlassButtonStyle: ButtonStyle {
    let size: ButtonSize
    
    enum ButtonSize {
        case small, medium, large
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .medium: return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            case .large: return EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 10
            }
        }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(size.padding)
            .background(
                ZStack {
                    // Glass background
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .fill(Color.bgSurface)
                    
                    // Border
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .strokeBorder(Color.borderGlass, lineWidth: 1)
                    
                    // Interactive states
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: size.cornerRadius)
                            .fill(Color.white.opacity(0.1))
                    }
                }
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.08), value: configuration.isPressed)
    }
}

// Focus and Active States
struct FocusRingModifier: ViewModifier {
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive ? Color.accentBeam : Color.clear,
                        lineWidth: 2
                    )
                    .animation(.easeInOut(duration: 0.2), value: isActive)
            )
    }
}

// Caved Divider (following design system)
struct CavedDivider: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.strokeCavedTop)
                .frame(height: 1)
            Rectangle()
                .fill(Color.strokeCavedBot)
                .frame(height: 1)
        }
        .padding(.horizontal, 1)
    }
}

// Extensions for convenience
extension View {
    func glassBackground(_ intensity: GlassModifier.GlassIntensity = .regular) -> some View {
        self.modifier(GlassModifier(intensity: intensity))
    }
    
    func focusRing(_ isActive: Bool) -> some View {
        self.modifier(FocusRingModifier(isActive: isActive))
    }
}