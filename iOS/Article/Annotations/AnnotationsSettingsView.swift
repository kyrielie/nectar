//
//  AnnotationsSettingsView.swift
//  NetNewsWire-iOS
//
//  Pushed from SettingsViewController's Articles section ("Highlights &
//  Notes" row), following the same UIHostingController-push pattern as
//  AO3AccountSettingsView/ArticleThemeListView elsewhere in this app.
//
//  Contains: the unscoped AnnotationsListView (2.5's "see everything I've
//  ever highlighted" surface -- the toolbar menu's two scoped entries in
//  ArticleViewController.annotationsMenu() are the fast, in-context path;
//  this is the browse-everything path), the toolbar-button toggle (so the
//  button can be turned on without a trip through the separate Full
//  Screen Reading toolbar customizer), the default highlight color
//  picker, and the CSV/SQLite export entry points.
//
//  Export and cross-article navigation both need UIKit-side machinery
//  (UIDocumentPickerViewController, SceneCoordinator) this view has no
//  access to on its own, so they're threaded in as closures from
//  SettingsViewController rather than this view reaching into UIKit
//  directly -- same "view only reports what the person chose" shape
//  AnnotationEditorView already uses for onSave/onDelete.
//

import SwiftUI
import Account
import Articles

struct AnnotationsSettingsView: View {

	/// Presents the CSV export account picker / document picker. Takes a
	/// source view + rect the same way SettingsViewController's other
	/// export entry points do, for the popover's anchor on iPad.
	var onExportCSV: (_ sourceView: UIView, _ sourceRect: CGRect) -> Void

	/// Presents the SQLite export path (which is really "Export Articles"
	/// -> SQLite, since annotations ride along with that export
	/// automatically -- see ArticleSQLiteExportTable).
	var onExportSQLite: (_ sourceView: UIView, _ sourceRect: CGRect) -> Void

	/// Navigates to the article/chapter containing this annotation and
	/// scrolls to/flashes its highlight -- see
	/// SettingsViewController.navigateToAnnotationFromSettings.
	var onNavigateToAnnotation: (_ annotation: Annotation, _ account: Account) -> Void

	@AppStorage(AppDefaults.Key.articleToolbarShowAnnotations) private var showToolbarButton = false
	@State private var defaultColor: Annotation.Color = AppDefaults.shared.defaultAnnotationColor

	/// AnnotationsListView needs a single Account. Per docs/ambrosia-feed.md,
	/// Nectar's usual shape is one local account, so the first (only, in
	/// the common case) account is used directly rather than adding a
	/// second account-picker UI here -- if there genuinely are multiple
	/// accounts, this still shows the first one's highlights rather than
	/// showing nothing, and export (which does support multi-account) is
	/// still reachable either way.
	private var primaryAccount: Account? {
		AccountManager.shared.sortedAccounts.first
	}

	var body: some View {
		List {
			if let primaryAccount {
				Section {
					NavigationLink {
						AnnotationsListView(account: primaryAccount, scope: .everything) { annotation in
							onNavigateToAnnotation(annotation, primaryAccount)
						}
					} label: {
						Text("All Highlights", comment: "Annotations settings: link to unscoped list")
					}
				}
			}

			Section {
				Toggle(NSLocalizedString("Show Toolbar Button", comment: "Annotations settings: toolbar button toggle"), isOn: $showToolbarButton)
			} footer: {
				Text("Adds a highlighter button to the article reader's top toolbar.", comment: "Annotations settings: toolbar button toggle footer")
			}

			Section {
				colorPicker
			} header: {
				Text("Default Highlight Color", comment: "Annotations settings: default color section header")
			}

			Section {
				ExportRow(title: NSLocalizedString("Export as CSV…", comment: "Annotations settings: CSV export row")) { sourceView, sourceRect in
					onExportCSV(sourceView, sourceRect)
				}
				ExportRow(title: NSLocalizedString("Export as SQLite…", comment: "Annotations settings: SQLite export row")) { sourceView, sourceRect in
					onExportSQLite(sourceView, sourceRect)
				}
			} header: {
				Text("Export", comment: "Annotations settings: export section header")
			}
		}
		.navigationTitle(Text("Highlights & Notes", comment: "Annotations settings navigation title"))
		.navigationBarTitleDisplayMode(.inline)
	}

	private var colorPicker: some View {
		HStack(spacing: 16) {
			ForEach(Annotation.Color.allCases, id: \.self) { color in
				Button {
					defaultColor = color
					AppDefaults.shared.defaultAnnotationColor = color
				} label: {
					Circle()
						.fill(color.swiftUIColor)
						.frame(width: 32, height: 32)
						.overlay {
							if color == defaultColor {
								Circle()
									.strokeBorder(Color.primary, lineWidth: 2)
									.padding(-3)
							}
						}
				}
				.accessibilityLabel(color.accessibilityLabel)
				.accessibilityAddTraits(color == defaultColor ? .isSelected : [])
			}
			Spacer()
		}
		.padding(.vertical, 4)
	}
}

/// A tappable row that hands SwiftUI's UIKit-backed frame/view up to a
/// UIKit closure -- the same source-view/source-rect shape
/// SettingsViewController's own export rows need for their popover
/// anchor, but SwiftUI Buttons don't expose a UIView directly. Wraps a
/// small UIViewRepresentable purely to get at that view.
private struct ExportRow: View {

	let title: String
	let action: (_ sourceView: UIView, _ sourceRect: CGRect) -> Void

	var body: some View {
		AnchorReadingButton(title: title, action: action)
	}
}

private struct AnchorReadingButton: UIViewRepresentable {

	let title: String
	let action: (_ sourceView: UIView, _ sourceRect: CGRect) -> Void

	func makeUIView(context: Context) -> UIButton {
		var configuration = UIButton.Configuration.plain()
		configuration.title = title
		configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
		configuration.titleAlignment = .leading

		let button = UIButton(configuration: configuration)
		button.contentHorizontalAlignment = .leading
		button.addTarget(context.coordinator, action: #selector(Coordinator.tapped(_:)), for: .touchUpInside)
		context.coordinator.action = action
		return button
	}

	func updateUIView(_ uiView: UIButton, context: Context) {
		context.coordinator.action = action
		var configuration = uiView.configuration
		configuration?.title = title
		uiView.configuration = configuration
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(action: action)
	}

	// @MainActor on the whole type, not just tapped(_:) below: UIKit
	// dispatches target-action on the main thread, but the compiler can't
	// verify that for an @objc method unless the enclosing type is
	// actor-isolated, and makeUIView/updateUIView (which read/write
	// `action` on this Coordinator) are themselves main-actor-isolated by
	// the UIViewRepresentable protocol -- isolating the whole class keeps
	// every access point consistent rather than isolating tapped(_:) alone.
	@MainActor final class Coordinator {
		var action: (_ sourceView: UIView, _ sourceRect: CGRect) -> Void

		init(action: @escaping (_ sourceView: UIView, _ sourceRect: CGRect) -> Void) {
			self.action = action
		}

		@objc func tapped(_ sender: UIButton) {
			action(sender, sender.bounds)
		}
	}
}
