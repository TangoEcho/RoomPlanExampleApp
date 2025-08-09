import UIKit

// Spectrum corporate branding and design system
struct SpectrumBranding {
    
    // MARK: - Colors
    struct Colors {
        // Primary Spectrum brand colors
        static let spectrumBlue = UIColor(red: 0.0, green: 0.122, blue: 0.247, alpha: 1.0) // #001F3F
        static let spectrumRed = UIColor(red: 0.863, green: 0.078, blue: 0.235, alpha: 1.0) // #DC143C
        static let spectrumSilver = UIColor(red: 0.753, green: 0.753, blue: 0.753, alpha: 1.0) // #C0C0C0
        static let spectrumGreen = UIColor(red: 0.133, green: 0.694, blue: 0.298, alpha: 1.0) // #228B4C
        
        // Supporting colors
        static let lightBlue = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        static let darkBlue = UIColor(red: 0.0, green: 0.08, blue: 0.16, alpha: 1.0)
        
        // Status colors for WiFi coverage
        static let excellentSignal = UIColor(red: 0.133, green: 0.694, blue: 0.298, alpha: 1.0) // Green
        static let goodSignal = UIColor(red: 1.0, green: 0.714, blue: 0.0, alpha: 1.0) // Yellow/Orange
        static let fairSignal = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0) // Orange
        static let poorSignal = UIColor(red: 0.863, green: 0.078, blue: 0.235, alpha: 1.0) // Spectrum Red
        
        // UI colors
        static let cardBackground = UIColor.systemBackground
        static let secondaryBackground = UIColor.secondarySystemBackground
        static let textPrimary = UIColor.label
        static let textSecondary = UIColor.secondaryLabel
        
        // Theme colors for UI components
        static let primary = spectrumBlue
        static let accent = spectrumRed
        static let secondary = spectrumSilver
        static let success = excellentSignal
        static let warning = goodSignal
        static let error = poorSignal
    }
    
    // MARK: - Typography
    struct Typography {
        static let titleFont = UIFont.boldSystemFont(ofSize: 24)
        static let headlineFont = UIFont.boldSystemFont(ofSize: 20)
        static let bodyFont = UIFont.systemFont(ofSize: 16)
        static let captionFont = UIFont.systemFont(ofSize: 14)
        static let smallFont = UIFont.systemFont(ofSize: 12)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    static let cornerRadius: CGFloat = 12
    static let buttonCornerRadius: CGFloat = 8
    
    // MARK: - Helper Methods
    static func configureNavigationBar(_ navigationBar: UINavigationBar) {
        navigationBar.backgroundColor = Colors.spectrumBlue
        navigationBar.barTintColor = Colors.spectrumBlue
        navigationBar.tintColor = .white
        navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: Typography.headlineFont
        ]
        navigationBar.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: Typography.titleFont
        ]
    }
    
    static func createSpectrumButton(title: String, style: ButtonStyle = .primary) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = Typography.bodyFont
        button.layer.cornerRadius = buttonCornerRadius
        button.translatesAutoresizingMaskIntoConstraints = false
        
        switch style {
        case .primary:
            button.backgroundColor = Colors.spectrumBlue
            button.setTitleColor(.white, for: .normal)
        case .secondary:
            button.backgroundColor = Colors.spectrumSilver
            button.setTitleColor(Colors.spectrumBlue, for: .normal)
        case .accent:
            button.backgroundColor = Colors.spectrumRed
            button.setTitleColor(.white, for: .normal)
        }
        
        // Add shadow for depth
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowOpacity = 0.1
        button.layer.shadowRadius = 4
        
        return button
    }
    
    static func createSpectrumLabel(text: String, style: LabelStyle = .body) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        switch style {
        case .title:
            label.font = Typography.titleFont
            label.textColor = Colors.spectrumBlue
        case .headline:
            label.font = Typography.headlineFont
            label.textColor = Colors.textPrimary
        case .body:
            label.font = Typography.bodyFont
            label.textColor = Colors.textPrimary
        case .caption:
            label.font = Typography.captionFont
            label.textColor = Colors.textSecondary
        }
        
        return label
    }
    
    static func signalStrengthColor(for strength: Int) -> UIColor {
        switch strength {
        case -50...0:
            return Colors.excellentSignal
        case -70..<(-50):
            return Colors.goodSignal
        case -85..<(-70):
            return Colors.fairSignal
        default:
            return Colors.poorSignal
        }
    }
    
    enum ButtonStyle {
        case primary
        case secondary
        case accent
    }
    
    enum LabelStyle {
        case title
        case headline
        case body
        case caption
    }
}

// MARK: - UIView Extensions for Spectrum Branding
extension UIView {
    func applySpectrumCardStyle() {
        backgroundColor = SpectrumBranding.Colors.cardBackground
        layer.cornerRadius = SpectrumBranding.cornerRadius
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 8
    }
    
    func applySpectrumBorder() {
        layer.borderWidth = 1
        layer.borderColor = SpectrumBranding.Colors.spectrumSilver.cgColor
    }
}

// MARK: - UIButton Extensions
extension UIButton {
    func applySpectrumStyle(_ style: SpectrumBranding.ButtonStyle = .primary) {
        titleLabel?.font = SpectrumBranding.Typography.bodyFont
        layer.cornerRadius = SpectrumBranding.buttonCornerRadius
        
        switch style {
        case .primary:
            backgroundColor = SpectrumBranding.Colors.spectrumBlue
            setTitleColor(.white, for: .normal)
        case .secondary:
            backgroundColor = SpectrumBranding.Colors.spectrumSilver
            setTitleColor(SpectrumBranding.Colors.spectrumBlue, for: .normal)
        case .accent:
            backgroundColor = SpectrumBranding.Colors.spectrumRed
            setTitleColor(.white, for: .normal)
        }
        
        // Add depth
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 4
    }
}