//
//  TextReplacementPerWorkOverrideView.swift
//  NetNewsWire-iOS
//
//  Step 7 of the text-replacement feature's build order: the per-work
//  override editor, scoped to one bookKey, for the reader-insert names
//  table only (see TextReplacementPerWorkOverride's own header comment
//  for why this doesn't extend to the typo/quote-conversion
//  categories). Pushed from TextReplacementSettingsView's Reader-Insert
//  Names section as a NavigationLink, surfaced whenever a "current
//  work" is resolvable at all (see currentWork on that view) --
//  contextual-surfacing decision made here rather than guessing at the
//  plan's own unspecified fandom/tag-matching heuristic ("could be as
//  simple as matching the work's fandom/relationship tags against a
//  fandom the person has previously set a per-work override for"): that
//  heuristic isn't concretely specified anywhere in the plan, and
//  showing the entry point for any resolvable current work is strictly
//  more discoverable than trying to guess when a person would want it,
//  at the cost of one always-visible row instead of a conditionally
//  hidden one. If the tag-matching heuristic is wanted later, it would
//  narrow when this row appears, not change what this view itself does.
//
//  Same read/write shape as AppDefaults.shared.textReplacementPerWorkOverride
//  elsewhere: this view reads the full TextReplacementPerWorkOverride,
//  edits only its own bookKey's table via a local @State copy, and
//  writes the whole value back on change -- there is no partial-update
//  API on AppDefaults for this, the same way textReplacementCustomTable/
//  textReplacementReaderInsertTable are read/written whole from
//  TextReplacementSettingsView.
//

import SwiftUI
import Articles

struct TextReplacementPerWorkOverrideView: View {

	let bookKey: String
	let workTitle: String

	@State private var table: TextReplacementRuleTable

	init(bookKey: String, workTitle: String) {
		self.bookKey = bookKey
		self.workTitle = workTitle
		let existing = AppDefaults.shared.textReplacementPerWorkOverride.table(forBookKey: bookKey)
		_table = State(initialValue: existing ?? TextReplacementRuleTable())
	}

	var body: some View {
		List {
			Section {
				ForEach($table.rules) { $rule in
					VStack(alignment: .leading, spacing: 4) {
						TextField(NSLocalizedString("Find", comment: "Text replacement rule: input field placeholder"), text: $rule.input)
						TextField(NSLocalizedString("Replace With", comment: "Text replacement rule: output field placeholder"), text: $rule.output)
							.foregroundStyle(.secondary)
					}
					.swipeActions(edge: .trailing, allowsFullSwipe: false) {
						Button(role: .destructive) {
							table.rules.removeAll { $0.id == rule.id }
						} label: {
							Image(systemName: "trash")
						}
					}
				}
				Button {
					table.rules.append(TextReplacementRule(input: "", output: ""))
				} label: {
					Label {
						Text("Add Rule", comment: "Text replacement settings: add rule button label")
					} icon: {
						Image(systemName: "plus.circle")
					}
				}
			} footer: {
				Text("These rules apply only to \(workTitle) and take precedence over your Reader-Insert Names table above for any token they cover. Tokens not listed here still use the table above.", comment: "Per-work override: scope-clarifying footer")
			}
		}
		.navigationTitle(Text("Override for This Work", comment: "Per-work override navigation title"))
		.navigationBarTitleDisplayMode(.inline)
		.onChange(of: table) {
			var override = AppDefaults.shared.textReplacementPerWorkOverride
			override.setTable(table, forBookKey: bookKey)
			AppDefaults.shared.textReplacementPerWorkOverride = override
		}
	}
}
