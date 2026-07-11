import sys

path = "Shared/Timeline/ArticleSorter.swift"

with open(path, "r") as f:
    content = f.read()

changes = 0

old_title = '''	static func sortedByTitle(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			let title1 = article1.title ?? ""
			let title2 = article2.title ?? ""
			switch title1.localizedCaseInsensitiveCompare(title2) {'''
new_title = '''	static func sortedByTitle(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			let title1 = article1.title ?? ""
			let title2 = article2.title ?? ""
			return switch title1.localizedCaseInsensitiveCompare(title2) {'''

if old_title in content:
    content = content.replace(old_title, new_title, 1)
    changes += 1
else:
    print("WARNING: sortedByTitle anchor not found")

old_author = '''	static func sortedByAuthor(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			let name1 = article1.sortableAuthorName
			let name2 = article2.sortableAuthorName
			switch name1.localizedCaseInsensitiveCompare(name2) {'''
new_author = '''	static func sortedByAuthor(articles: [Article], sortDirection: ComparisonResult) -> [Article] {
		articles.sorted { article1, article2 in
			let name1 = article1.sortableAuthorName
			let name2 = article2.sortableAuthorName
			return switch name1.localizedCaseInsensitiveCompare(name2) {'''

if old_author in content:
    content = content.replace(old_author, new_author, 1)
    changes += 1
else:
    print("WARNING: sortedByAuthor anchor not found")

if changes == 2:
    with open(path, "w") as f:
        f.write(content)
    print("Applied both fixes to ArticleSorter.swift.")
else:
    print(f"Only {changes}/2 applied — check warnings above, file may use different whitespace (tabs vs spaces).")
    sys.exit(1)
