//
//  TimelineHeaderView.swift
//  NetNewsWire
//
//  Created by Stuart Breckenridge on 27/01/2026.
//  Copyright © 2026 Ranchero Software. All rights reserved.
//

final class TimelineHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "TimelineHeaderView"

    let label = UILabel()

    /// Optional trailing detail label, e.g. ToolbarsCustomizerViewController's
    /// "3/4" used-slots badge next to the functions-section header. Hidden
    /// and empty by default so TimelineCustomizerCollectionViewController's
    /// existing single-centered-label usage is untouched -- callers that
    /// want it set `detailLabel.text` and `detailLabel.isHidden = false`
    /// explicitly.
    let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.isHidden = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label

        addSubview(label)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            label.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor, constant: -8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -8),
            detailLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            detailLabel.centerYAnchor.constraint(equalTo: label.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        detailLabel.text = nil
        detailLabel.isHidden = true
        detailLabel.textColor = .secondaryLabel
    }
}
