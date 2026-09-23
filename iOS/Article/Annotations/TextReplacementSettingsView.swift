//
//  TextReplacementSettingsView.swift
//  NetNewsWire-iOS
//
//  Pushed from SettingsViewController's Articles section ("Text
//  Replacement" row), following the same UIHostingController-push
//  pattern as AnnotationsSettingsView/ArticleThemeListView elsewhere in
//  this app. See the feature's own implementation plan, "Settings
//  screen" for the five sections below and their ordering.
//
//  The Edit History section links into AnnotationsListView with
//  scope: .everything, same entry point AnnotationsSettingsView's own
//  "All Highlights" row already uses -- now the combined "This
//  book"/"All" tabbed viewer described in the plan's "Consolidated
//  viewer" section (AnnotationsListView itself grew the tab switcher;
//  no separate screen was needed). Opened from here with no book in
//  context, so it only ever offers the All tab -- see
//  AnnotationsListView.showsTabSwitcher.
//
//  The Reader-insert names section's "per-work override" entry point
//  is a NavigationLink to TextReplacementPerWorkOverrideView, shown
//  whenever currentWork is non-nil -- see that view's own header
//  comment for the contextual-surfacing decision (any resolvable
//  current work, not the plan's unspecified fandom/tag-matching
//  heuristic).
//

import SwiftUI
import Account
import Articles
import AnnotationsKit

struct TextReplacementSettingsView: View {

	/// Navigates to the article/chapter containing this annotation and
	/// scrolls to/flashes its highlight -- same shape as
	/// AnnotationsSettingsView's onNavigateToAnnotation, reused for the
	/// Edit History row's AnnotationsListView.
	var onNavigateToAnnotation: (_ annotation: Annotation, _ account: Account) -> Void

	/// The work currently open behind Settings (via SceneCoordinator.
	/// currentArticleViewController), if any -- resolved by
	/// SettingsViewController at push time, the same way
	/// navigateToAnnotationFromSettings resolves the current article for
	/// a different purpose. nil when Settings was opened with no article
	/// on screen (e.g. compact-width, still on the timeline); the
	/// per-work override link is hidden in that case, per this screen's
	/// contextual-surfacing decision -- see
	/// TextReplacementPerWorkOverrideView's own header comment.
	var currentWork: (bookKey: String, title: String)?

	@AppStorage(AppDefaults.Key.textReplacementApplyAutomatically) private var applyAutomatically = true
	@AppStorage(AppDefaults.Key.textReplacementTypoFixesEnabled) private var typoFixesEnabled = true
	@AppStorage(AppDefaults.Key.textReplacementQuoteConversionEnabled) private var quoteConversionEnabled = false

	@State private var readerInsertTable = AppDefaults.shared.textReplacementReaderInsertTable
	@State private var customTable = AppDefaults.shared.textReplacementCustomTable
	@State private var editHistoryCount: Int?

	/// AnnotationsListView needs a single Account -- same reasoning
	/// AnnotationsSettingsView's own primaryAccount uses (Nectar's usual
	/// shape is one local account; see docs/ambrosia-feed.md).
	private var primaryAccount: Account? {
		AccountManager.shared.sortedAccounts.first
	}

	var body: some View {
		List {
			Section {
				Toggle(isOn: $applyAutomatically) {
					Text("Apply Automatically on Open", comment: "Text replacement settings: master toggle label")
				}
			} footer: {
				Text("Original text is never changed -- every replacement below is reviewable and reversible in Edit History.", comment: "Text replacement settings: non-destructive guarantee footer")
			}

			Section {
				ruleRows($readerInsertTable)
				if let currentWork {
					NavigationLink {
						TextReplacementPerWorkOverrideView(bookKey: currentWork.bookKey, workTitle: currentWork.title)
					} label: {
						Text("Override for \(currentWork.title)", comment: "Text replacement settings: per-work override row label")
					}
				}
			} header: {
				Text("Reader-Insert Names", comment: "Text replacement settings: reader-insert section header")
			} footer: {
				Text("Replaces placeholder tokens like (Y/N) with a name you choose. Leave Replace With empty to leave a placeholder untouched.", comment: "Text replacement settings: reader-insert section footer")
			}

			Section {
				Toggle(isOn: $typoFixesEnabled) {
					Text("Common Typo Fixes", comment: "Text replacement settings: typo fixes toggle label")
				}
				Toggle(isOn: $quoteConversionEnabled) {
					Text("British-to-American Quotes", comment: "Text replacement settings: quote conversion toggle label")
				}
			} header: {
				Text("Style Corrections", comment: "Text replacement settings: style corrections section header")
			} footer: {
				Text("British-to-American Quotes converts dialogue marks, not every apostrophe -- contractions and possessives are left alone.", comment: "Text replacement settings: quote conversion clarifying footer")
			}

			Section {
				ruleRows($customTable)
				addRuleRow($customTable)
			} header: {
				Text("Custom Rules", comment: "Text replacement settings: custom rules section header")
			} footer: {
				Text("Your own find-and-replace pairs, for anything the typo table above doesn't cover.", comment: "Text replacement settings: custom rules section footer")
			}

			Section {
				if let primaryAccount {
					NavigationLink {
						AnnotationsListView(account: primaryAccount, scope: .everything) { annotation in
							onNavigateToAnnotation(annotation, primaryAccount)
						}
					} label: {
						HStack {
							Text("Edit History", comment: "Text replacement settings: edit history row label")
							Spacer()
							if let editHistoryCount {
								Text("\(editHistoryCount)", comment: "Text replacement settings: edit history count")
									.foregroundStyle(.secondary)
							}
						}
					}
				}
			} header: {
				Text("Edit History", comment: "Text replacement settings: edit history section header")
			}
		}
		.navigationTitle(Text("Text Replacement", comment: "Text replacement settings navigation title"))
		.navigationBarTitleDisplayMode(.inline)
		.onChange(of: readerInsertTable) {
			AppDefaults.shared.textReplacementReaderInsertTable = readerInsertTable
		}
		.onChange(of: customTable) {
			AppDefaults.shared.textReplacementCustomTable = customTable
		}
		.task {
			guard let primaryAccount else { return }
			let all = await primaryAccount.fetchAllAnnotations()
			editHistoryCount = all.filter { $0.originalText != nil }.count
		}
	}

	/// One row per rule: two text fields ("Find" / "Replace With"),
	/// deletable via swipe -- same swipeActions-to-delete shape
	/// DinosaursView already establishes for a person-editable list in
	/// this app.
	@ViewBuilder
	private func ruleRows(_ table: Binding<TextReplacementRuleTable>) -> some View {
		ForEach(table.rules) { $rule in
			VStack(alignment: .leading, spacing: 4) {
				TextField(NSLocalizedString("Find", comment: "Text replacement rule: input field placeholder"), text: $rule.input)
				TextField(NSLocalizedString("Replace With", comment: "Text replacement rule: output field placeholder"), text: $rule.output)
					.foregroundStyle(.secondary)
			}
			.swipeActions(edge: .trailing, allowsFullSwipe: false) {
				Button(role: .destructive) {
					table.wrappedValue.rules.removeAll { $0.id == rule.id }
				} label: {
					Image(systemName: "trash")
				}
			}
		}
	}

	private func addRuleRow(_ table: Binding<TextReplacementRuleTable>) -> some View {
		Button {
			table.wrappedValue.rules.append(TextReplacementRule(input: "", output: ""))
		} label: {
			Label {
				Text("Add Rule", comment: "Text replacement settings: add rule button label")
			} icon: {
				Image(systemName: "plus.circle")
			}
		}
	}
}
