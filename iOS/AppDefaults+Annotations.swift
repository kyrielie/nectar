//
//  AppDefaults+Annotations.swift
//  Nectar
//

import Foundation
import Articles

extension AppDefaults {

	/// The color HighlightColorPopover's note-icon path (which creates a
	/// highlight without the person picking a color) falls back to, and
	/// the starting selection in the annotations toolbar menu's "Default
	/// Highlight Color" submenu below. Yellow, matching
	/// HighlightColorPopover/AnnotationEditorView's own fallback default.
	var defaultAnnotationColor: Annotation.Color {
		get {
			guard let rawValue = AppDefaults.string(for: Key.defaultAnnotationColor),
				  let color = Annotation.Color(rawValue: rawValue) else {
				return .yellow
			}
			return color
		}
		set {
			AppDefaults.setString(for: Key.defaultAnnotationColor, newValue.rawValue)
		}
	}

	/// How a new highlight gets created from a text selection --
	/// HighlightColorPopover.swift (popup), a native-menu "Highlight"
	/// item (PreloadedWebView.buildMenu(with:)), or neither. Popup is
	/// the default, matching this feature's original (only) behavior
	/// before this setting existed.
	var annotationCreationMethod: AnnotationCreationMethod {
		get {
			guard let rawValue = AppDefaults.string(for: Key.annotationCreationMethod),
				  let method = AnnotationCreationMethod(rawValue: rawValue) else {
				return .popup
			}
			return method
		}
		set {
			AppDefaults.setString(for: Key.annotationCreationMethod, newValue.rawValue)
		}
	}
}
