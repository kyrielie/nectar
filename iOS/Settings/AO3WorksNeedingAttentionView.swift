//
//  AO3WorksNeedingAttentionView.swift
//  NetNewsWire-iOS
//
//  Pushed from the AO3 settings screen. Lists works with a pending content
//  update, a word-count regression flag, or a confirmed-missing flag, newest
//  first, with Retry Now / Review Update and a Clear Content swipe action.
//  Separate from Manage Storage on purpose: that list is sorted by stored
//  size and only includes works that have stored content, so a work flagged
//  missing with no content can never appear there.
//
//  See docs/ao3-works-needing-attention.md.
//

import SwiftUI

struct AO3WorksNeedingAttentionView: View {

	@State private var viewModel: AO3WorksNeedingAttentionViewModel
	private let onReviewUpdate: (_ accountID: String, _ articleID: String) -> Void

	init(
		viewModel: AO3WorksNeedingAttentionViewModel = AO3WorksNeedingAttentionViewModel(),
		onReviewUpdate: @escaping (_ accountID: String, _ articleID: String) -> Void
	) {
		_viewModel = State(initialValue: viewModel)
		self.onReviewUpdate = onReviewUpdate
	}

	var body: some View {
		Group {
			if viewModel.rows.isEmpty {
				if viewModel.hasLoaded {
					ContentUnavailableView(
						NSLocalizedString("Nothing Needs Attention", comment: "Works Needing Attention: empty state title"),
						systemImage: "checkmark.circle",
						description: Text(NSLocalizedString("Works with an update waiting for review, or that Nectar could not refresh from AO3, show up here.", comment: "Works Needing Attention: empty state description"))
					)
				} else {
					ProgressView()
				}
			} else {
				List {
					Section {
						ForEach(viewModel.rows) { row in
							rowView(row)
								.swipeActions(edge: .trailing, allowsFullSwipe: false) {
									Button(role: .destructive) {
										Task { await viewModel.clearContent(row) }
									} label: {
										Text(NSLocalizedString("Clear Content", comment: "Clear Content button"))
									}
								}
						}
					} footer: {
						Text(NSLocalizedString("Retry Now checks AO3 again right away. Clear Content removes a work's stored text but keeps its title, status and notes.", comment: "Works Needing Attention footer"))
					}
				}
			}
		}
		.navigationTitle(Text(NSLocalizedString("Works Needing Attention", comment: "AO3 settings: works needing attention screen title")))
		.navigationBarTitleDisplayMode(.inline)
		.task {
			await viewModel.refresh()
		}
		.alert(
			NSLocalizedString("Retry", comment: "Works Needing Attention: retry alert title"),
			isPresented: Binding(
				get: { viewModel.notice != nil },
				set: { if !$0 { viewModel.notice = nil } }
			)
		) {
			Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {}
		} message: {
			Text(viewModel.notice ?? "")
		}
	}

	private func rowView(_ row: AO3AttentionRowData) -> some View {
		HStack(alignment: .center, spacing: 12) {
			VStack(alignment: .leading, spacing: 2) {
				Text(row.title)
					.lineLimit(2)
				Text(stateLabel(row.state))
					.font(.subheadline)
					.foregroundStyle(.secondary)
				Text(row.date, format: .dateTime.month().day().year())
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 8)
			actionButton(row)
		}
		.contextMenu {
			if row.state == .pendingUpdate {
				Button(NSLocalizedString("Review Update", comment: "Works Needing Attention: open the work to review its pending update")) {
					onReviewUpdate(row.accountID, row.articleID)
				}
			} else {
				Button(NSLocalizedString("Retry Now", comment: "Works Needing Attention: check AO3 for this work again")) {
					Task { await viewModel.retryNow(row) }
				}
			}
			Button(NSLocalizedString("Clear Content", comment: "Clear Content button"), role: .destructive) {
				Task { await viewModel.clearContent(row) }
			}
		}
	}

	@ViewBuilder
	private func actionButton(_ row: AO3AttentionRowData) -> some View {
		if row.state == .pendingUpdate {
			Button(NSLocalizedString("Review Update", comment: "Works Needing Attention: open the work to review its pending update")) {
				onReviewUpdate(row.accountID, row.articleID)
			}
			.buttonStyle(.borderless)
		} else {
			Button(NSLocalizedString("Retry Now", comment: "Works Needing Attention: check AO3 for this work again")) {
				Task { await viewModel.retryNow(row) }
			}
			.buttonStyle(.borderless)
		}
	}

	private func stateLabel(_ state: AO3AttentionState) -> String {
		switch state {
		case .pendingUpdate:
			return NSLocalizedString("Pending update", comment: "Works Needing Attention: a changed version is waiting for review")
		case .notFound:
			return NSLocalizedString("Not found on AO3", comment: "Works Needing Attention: AO3 confirmed the work is missing")
		case .regressionFlagged:
			return NSLocalizedString("Flagged after a smaller-than-expected feed report", comment: "Works Needing Attention: a feed reported far fewer words than the stored text")
		}
	}
}
