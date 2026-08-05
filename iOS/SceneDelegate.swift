//
//  AppDelegate.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 6/28/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import UIKit
import UserNotifications
import Account

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

	var window: UIWindow?
	var coordinator: SceneCoordinator!

	// UIWindowScene delegate

	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {

		window!.tintColor = Assets.Colors.primaryAccent

		let rootViewController = window!.rootViewController as! RootSplitViewController
		rootViewController.presentsWithGesture = true
		rootViewController.showsSecondaryOnlyButton = true
		rootViewController.preferredDisplayMode = UISplitViewController.DisplayMode(rawValue: AppDefaults.shared.splitViewPreferredDisplayMode) ?? .oneBesideSecondary

		// On first run on iPad, show all three columns so the sidebar is visible
		if AppDefaults.shared.isFirstRun && UIDevice.current.userInterfaceIdiom == .pad {
			rootViewController.preferredDisplayMode = .twoBesideSecondary
		}

		coordinator = SceneCoordinator(rootSplitViewController: rootViewController)
		rootViewController.coordinator = coordinator
		rootViewController.delegate = coordinator

		coordinator.restoreWindowState(activity: session.stateRestorationActivity)

		updateUserInterfaceStyle()

		NotificationCenter.default.addObserver(self, selector: #selector(handleUserInterfaceColorPaletteDidUpdate(_:)), name: .userInterfaceColorPaletteDidUpdate, object: AppDefaults.self)
		NotificationCenter.default.addObserver(self, selector: #selector(handleAccentColorDidChange(_:)), name: .accentColorDidChange, object: nil)

		if connectionOptions.urlContexts.first?.url != nil {
			self.scene(scene, openURLContexts: connectionOptions.urlContexts)
			return
		}

		if let shortcutItem = connectionOptions.shortcutItem {
			handleShortcutItem(shortcutItem)
			return
		}

		if let notificationResponse = connectionOptions.notificationResponse {
			coordinator.handle(notificationResponse)
			return
		}

		// Handle activities from external sources (Handoff, Spotlight, Siri Shortcuts).
		// Skip handling session.stateRestorationActivity since UserDefaults now handles state restoration.
		if let userActivity = connectionOptions.userActivities.first {
			coordinator.handle(userActivity)
		}
	}

	func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
		appDelegate.resumeIfNecessary()
		handleShortcutItem(shortcutItem)
		completionHandler(true)
	}

	func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
		appDelegate.resumeIfNecessary()
		coordinator.handle(userActivity)
	}

	func sceneDidEnterBackground(_ scene: UIScene) {
		coordinator.didEnterBackground()
		appDelegate.prepareAccountsForBackground()
	}

	func sceneWillEnterForeground(_ scene: UIScene) {
		appDelegate.resumeIfNecessary()
		appDelegate.prepareAccountsForForeground()
		coordinator.resetFocus()
	}

	func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
		return coordinator.stateRestorationActivity
	}

	// API

	func handle(_ response: UNNotificationResponse) {
		appDelegate.resumeIfNecessary()
		coordinator.handle(response)
	}

	func suspend() {
		coordinator.suspend()
	}

	func cleanUp(conditional: Bool) {
		coordinator.cleanUp(conditional: conditional)
	}

	// Handle Opening of URLs

	func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
		guard let context = urlContexts.first else { return }

		DispatchQueue.main.async {

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				self.coordinator.dismissIfLaunchingFromExternalAction()
			}

			let urlString = context.url.absoluteString

			// Handle the feed: and feeds: schemes
			if urlString.starts(with: "feed:") || urlString.starts(with: "feeds:") {
				let normalizedURLString = urlString.normalizedURL
				if normalizedURLString.mayBeURL {
					self.coordinator.showAddFeed(initialFeed: normalizedURLString, initialFeedName: nil)
				}
			}



			let filename = context.url.standardizedFileURL.path
			if filename.hasSuffix(ArticleTheme.nnwThemeSuffix) {
				self.coordinator.importTheme(filename: filename)
				return
			}

			// Handle theme URLs: netnewswire://theme/add?url={url}
			guard let comps = URLComponents(url: context.url, resolvingAgainstBaseURL: false),
				  "theme" == comps.host,
				 let queryItems = comps.queryItems else {
				return
			}

			if let providedThemeURL = queryItems.first(where: { $0.name == "url" })?.value {
				if let themeURL = URL(string: providedThemeURL) {
					let request = URLRequest(url: themeURL)

					DispatchQueue.main.async {
						NotificationCenter.default.post(name: .didBeginDownloadingTheme, object: nil)
					}
					let task = URLSession.shared.downloadTask(with: request) { location, _, error in
						guard
							  let location = location else { return }

						Task { @MainActor in
							do {
								try ArticleThemeDownloader.shared.handleFile(at: location)
							} catch {
								NotificationCenter.default.post(name: .didFailToImportThemeWithError, object: nil, userInfo: ["error": error])
							}
						}
					}
					task.resume()
				} else {
					print("No theme URL")
					return
				}
			} else {
				return
			}
		}
	}
}

private extension SceneDelegate {

	func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
		switch shortcutItem.type {
		case "com.ranchero.NetNewsWire.FirstUnread":
			coordinator.selectFirstUnreadInAllUnread()
		case "com.ranchero.NetNewsWire.ShowSearch":
			coordinator.showSearch()
		case "com.ranchero.NetNewsWire.ShowAdd":
			coordinator.showAddFeed()
		default:
			break
		}
	}

	@objc func handleUserInterfaceColorPaletteDidUpdate(_ notification: Notification) {
		assert(Thread.isMainThread)
		Task {
			updateUserInterfaceStyle()
		}
	}

	/// `window.tintColor` is set once from `Assets.Colors.primaryAccent` at
	/// scene connection (line 22) and not read again on its own -- unlike
	/// most `Assets.Colors.primaryAccent`/`.secondaryAccent` call sites,
	/// which are tintColor assignments re-evaluated on every draw/appearance
	/// change, `window.tintColor` only changes when explicitly reassigned.
	/// This mirrors `handleUserInterfaceColorPaletteDidUpdate` for the same
	/// reason: a property set once needs an explicit update path when its
	/// source value changes after the fact.
	@objc func handleAccentColorDidChange(_ notification: Notification) {
		assert(Thread.isMainThread)
		window?.tintColor = Assets.Colors.primaryAccent
	}

	@MainActor func updateUserInterfaceStyle() {
		switch AppDefaults.userInterfaceColorPalette {
		case .automatic:
			self.window?.overrideUserInterfaceStyle = .unspecified
		case .light:
			self.window?.overrideUserInterfaceStyle = .light
		case .dark:
			self.window?.overrideUserInterfaceStyle = .dark
		}
	}
}
