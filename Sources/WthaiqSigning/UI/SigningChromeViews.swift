#if os(iOS)
import UIKit

/// The title bar: a close button on the leading side and the title in the middle.
final class SigningHeaderView: UIView {
    let titleLabel = UILabel()
    let closeButton = UIButton(type: .system)
    private let separator = UIView()

    init(title: String, closeLabel: String, showsCloseButton: Bool) {
        super.init(frame: .zero)
        backgroundColor = .systemBackground

        titleLabel.text = title
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: symbol), for: .normal)
        closeButton.tintColor = .label
        closeButton.accessibilityLabel = closeLabel
        closeButton.isHidden = !showsCloseButton
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(closeButton)
        addSubview(separator)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),

            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 56),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -56),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

/// The loading and error screens shown over the web view.
final class SigningStatusView: UIView {
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?

    let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let iconView = UIImageView()
    private let retryButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let stack = UIStackView()

    init(tint: SigningColor) {
        super.init(frame: .zero)
        backgroundColor = .systemBackground

        spinner.hidesWhenStopped = true
        spinner.color = .secondaryLabel

        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        iconView.isAccessibilityElement = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        var retryConfiguration = UIButton.Configuration.filled()
        retryConfiguration.baseBackgroundColor = tint.uiColor
        retryConfiguration.baseForegroundColor = tint.foregroundUIColor
        retryConfiguration.cornerStyle = .medium
        retryConfiguration.buttonSize = .large
        retryButton.configuration = retryConfiguration
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)

        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.baseForegroundColor = tint.uiColor
        closeConfiguration.buttonSize = .large
        closeButton.configuration = closeConfiguration
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let arranged: [UIView] = [spinner, iconView, titleLabel, messageLabel, retryButton, closeButton]
        for item in arranged {
            stack.addArrangedSubview(item)
        }
        stack.setCustomSpacing(20, after: messageLabel)
        stack.setCustomSpacing(4, after: retryButton)
        addSubview(stack)

        let guide = readableContentGuide
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -24),
            retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            messageLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func showLoading(text: String) {
        iconView.isHidden = true
        titleLabel.isHidden = true
        retryButton.isHidden = true
        closeButton.isHidden = true
        messageLabel.isHidden = false
        messageLabel.text = text
        spinner.accessibilityLabel = text
        spinner.startAnimating()
        accessibilityViewIsModal = false
    }

    func showError(title: String, message: String, symbolName: String, retryTitle: String?, closeTitle: String?) {
        spinner.stopAnimating()
        iconView.image = UIImage(systemName: symbolName)
        iconView.isHidden = iconView.image == nil
        titleLabel.isHidden = false
        titleLabel.text = title
        messageLabel.isHidden = false
        messageLabel.text = message
        retryButton.isHidden = retryTitle == nil
        retryButton.configuration?.title = retryTitle
        closeButton.isHidden = closeTitle == nil
        closeButton.configuration?.title = closeTitle
        accessibilityViewIsModal = true
    }
}
#endif
