import Foundation
import SwiftSoup

/// consumer application's opt-in cleanup policy for publisher-specific article chrome.
///
/// This is intentionally separate from the Mozilla Readability port. Callers must
/// gate both cleanup phases behind `ReadabilityExtensions.publisherChromeCleanup`.
/// The supplied callbacks preserve the core extractor's title, phrasing, and link
/// density semantics without coupling this policy to `ArticleGrabber` state.
final class PublisherChromeCleaner: ProcessorBase {
  typealias TitleMatcher = (_ heading: Element, _ articleTitle: String) -> Bool
  typealias LinkDensity = (_ element: Element, _ textLength: Int) -> Double
  typealias PhrasingClassifier = (_ element: Element) -> Bool

  private let regEx: RegExUtil

  private let actionComponentPattern = try! NSRegularExpression(
    pattern: "(print|mail|facebook|twitter|hatena|bookmark|share|dialog).*",
    options: [.caseInsensitive]
  )
  private let subscriptionComponentPattern = try! NSRegularExpression(
    pattern: "(paid|subscribe|register|login)",
    options: [.caseInsensitive]
  )
  private let profileComponentPattern = try! NSRegularExpression(
    pattern: "^(writer|author)\\s*profile$",
    options: [.caseInsensitive]
  )
  private let relatedSectionHeadingPattern = try! NSRegularExpression(
    pattern: "(related|recommended|関連記事|関連トピック|ジャンル)",
    options: [.caseInsensitive]
  )
  private let prLabelPattern = try! NSRegularExpression(
    pattern: #"^\s*\[?\s*PR\s*\]?\s*$"#,
    options: [.caseInsensitive]
  )

  init(regEx: RegExUtil) {
    self.regEx = regEx
  }

  /// Removes publisher-specific chrome before Mozilla's final conditional cleanup.
  func clean(
    articleContent: Element,
    articleTitle: String?,
    creatorNames: [String],
    titleMatcher: TitleMatcher,
    linkDensity: @escaping LinkDensity
  ) {
    removeDuplicateTitleChrome(
      articleContent: articleContent,
      articleTitle: articleTitle,
      titleMatcher: titleMatcher
    )

    removeNodes(in: articleContent, tagName: "ul") { list in
      self.isArticleActionList(list)
    }

    removeNodes(in: articleContent, tagName: "div") { node in
      if self.isCompactNonPrintOrAdNode(node) { return true }
      if self.isCreatorBylineChrome(node, creatorNames: creatorNames) { return true }
      if self.isCompactRelatedSection(node, linkDensity: linkDensity) { return true }
      return false
    }

    removeNodes(in: articleContent, tagName: "section") { node in
      self.isCompactRelatedSection(node, linkDensity: linkDensity)
    }

    removeNodes(in: articleContent, tagName: "p") { paragraph in
      self.isPRLabel(paragraph)
    }

    removeCompactComponentContainers(
      in: articleContent,
      componentPattern: subscriptionComponentPattern,
      maximumTextLength: 500
    )
    removeComponentElements(
      in: articleContent,
      componentPattern: profileComponentPattern,
      maximumTextLength: 800
    )
  }

  /// Removes compact leading media/action chrome after conditional cleanup.
  func removeLeadingCompactTextChrome(
    from articleContent: Element,
    isPhrasingContent: PhrasingClassifier,
    linkDensity: LinkDensity
  ) {
    var current: Element? = articleContent
    while let container = current, let firstChild = container.children().firstSafe {
      if isPhrasingContent(firstChild) {
        break
      }
      if isCompactMediaActionChrome(firstChild, linkDensity: linkDensity) {
        printAndRemove(node: firstChild)
        continue
      }
      guard firstChild.children().count > 0 else { break }
      current = firstChild
    }
  }

  private func removeDuplicateTitleChrome(
    articleContent: Element,
    articleTitle: String?,
    titleMatcher: TitleMatcher
  ) {
    guard let articleTitle, !articleTitle.isEmpty else { return }

    let normalizedTitle = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let leadingArticleText = getInnerText(articleContent, regEx: regEx)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let headings = (try? articleContent.select("h1, h2").array()) ?? []
    for heading in headings {
      let headingText = getInnerText(heading, regEx: regEx)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let isDuplicate =
        titleMatcher(heading, articleTitle)
        || (!headingText.isEmpty && normalizedTitle.hasPrefix(headingText))
      // Restrict the fallback to leading chrome so a later section heading
      // that merely resembles the document title is never removed.
      guard isDuplicate,
        !headingText.isEmpty,
        leadingArticleText.hasPrefix(headingText)
      else { continue }

      let wrapper = heading.parent()
      printAndRemove(node: heading)

      guard let wrapper,
        wrapper !== articleContent,
        wrapper.children().count == 1,
        !wrapper.getChildNodes().contains(where: { node in
          guard let text = node as? TextNode else { return false }
          return regEx.hasContent(text.getWholeText())
        }),
        let onlyChild = wrapper.children().firstSafe
      else { continue }

      _ = try? onlyChild.remove()
      _ = try? wrapper.replaceWith(onlyChild)
    }
  }

  private func isArticleActionList(_ list: Element) -> Bool {
    let dataContentType = list.attrOrEmpty("data-content-type")
    let componentText = componentNames(in: list).joined(separator: " ")
    let text = getInnerText(list, regEx: regEx)
    let hasActionComponent = matches(actionComponentPattern, in: componentText)
    let hasActionText =
      text.contains("印刷") || text.range(of: "share", options: .caseInsensitive) != nil
      || text.contains("シェア") || text.range(of: "facebook", options: .caseInsensitive) != nil
      || text.range(of: "twitter", options: .caseInsensitive) != nil

    if dataContentType.caseInsensitiveCompare("Article") == .orderedSame,
      hasActionComponent || hasActionText
    {
      return true
    }
    if hasActionComponent, text.count < 300 {
      return true
    }
    return false
  }

  private func isCompactNonPrintOrAdNode(_ node: Element) -> Bool {
    let matchString = node.classNameSafe() + " " + node.idSafe()
    let lower = matchString.lowercased()
    guard lower.contains("notprint") || lower.contains("admod") else { return false }
    return getInnerText(node, regEx: regEx).count < 500
  }

  private func isCreatorBylineChrome(_ node: Element, creatorNames: [String]) -> Bool {
    guard !creatorNames.isEmpty else { return false }
    let text = getInnerText(node, regEx: regEx)
    guard !text.isEmpty, text.count <= 200 else { return false }
    let compactText = compactedComparableText(text)
    let compactCreatorNames =
      creatorNames
      .map(compactedComparableText)
      .filter { !$0.isEmpty }
    guard !compactCreatorNames.isEmpty,
      compactCreatorNames.allSatisfy(compactText.contains)
    else { return false }
    guard
      ((try? node.select("h1, h2, h3, h4, h5, h6, img, figure, picture, iframe, object, embed")
        .count) ?? 0) == 0
    else {
      return false
    }
    if compactText == compactCreatorNames.joined() {
      return hasFollowingArticleBody(after: node)
    }

    // A compact row with every JSON-LD creator and an actual time element is
    // a semantic metadata signal; CSS names alone are intentionally ignored.
    return ((try? node.select("time").count) ?? 0) > 0
  }

  private func isCompactMediaActionChrome(_ node: Element, linkDensity: LinkDensity) -> Bool {
    let text = getInnerText(node, regEx: regEx)
    guard text.count <= 250 else { return false }
    let imageCount = (try? node.select("img").count) ?? 0
    guard imageCount > 0, imageCount <= 4 else { return false }
    if ((try? node.select(
      "h1, h2, h3, h4, h5, h6, figure, picture, iframe, object, embed, input, button, select, textarea"
    ).count) ?? 0) > 0 {
      return false
    }
    let linkCount = (try? node.select("a").count) ?? 0
    let listCount = (try? node.select("ul, ol").count) ?? 0
    let hasActionMarker = matches(
      actionComponentPattern, in: node.classNameSafe() + " " + node.idSafe())
    guard linkCount > 0, listCount > 0 || hasActionMarker else {
      return false
    }
    if text.count > 40 {
      guard linkDensity(node, javaScriptStringLength(text)) > 0.35 else { return false }
    }
    return hasFollowingArticleBody(after: node)
  }

  private func hasFollowingArticleBody(after node: Element) -> Bool {
    var current: Element? = node
    while let element = current, let parent = element.parent() {
      var sibling = try? element.nextElementSibling()
      while let candidate = sibling {
        let text = getInnerText(candidate, regEx: regEx)
        let hasMedia = ((try? candidate.select("img, figure, picture").count) ?? 0) > 0
        if text.count >= 300 || (hasMedia && text.count >= 80) {
          return true
        }
        if text.count > 100 || hasMedia {
          return false
        }
        sibling = try? candidate.nextElementSibling()
      }
      current = parent
    }
    return false
  }

  private func isCompactRelatedSection(_ node: Element, linkDensity: LinkDensity) -> Bool {
    let text = getInnerText(node, regEx: regEx)
    guard text.count < 500 else { return false }
    let headingText = ((try? node.select("h1, h2, h3, h4, h5, h6").array()) ?? [])
      .map { getInnerText($0, regEx: regEx) }
      .joined(separator: " ")
    guard matches(relatedSectionHeadingPattern, in: headingText) else { return false }
    return linkDensity(node, javaScriptStringLength(text)) > 0.15
      || ((try? node.select("a").count) ?? 0) > 0
  }

  private func isPRLabel(_ paragraph: Element) -> Bool {
    matches(prLabelPattern, in: getInnerText(paragraph, regEx: regEx))
  }

  private func removeCompactComponentContainers(
    in articleContent: Element,
    componentPattern: NSRegularExpression,
    maximumTextLength: Int
  ) {
    let components = elements(in: articleContent).filter {
      matches(componentPattern, in: $0.attrOrEmpty("x-component-name"))
    }
    for component in components {
      var candidate: Element?
      var current: Element? = component
      while let element = current, element !== articleContent {
        let tagName = element.tagNameUTF8()
        if tagName == ReadabilityUTF8Arrays.div || tagName == ReadabilityUTF8Arrays.section
          || tagName == "aside".utf8Array
        {
          let textLength = getInnerText(element, regEx: regEx).count
          if textLength <= maximumTextLength {
            candidate = element
          }
        }
        current = element.parent()
      }
      if let candidate, candidate.parent() != nil {
        printAndRemove(node: candidate)
      }
    }
  }

  private func removeComponentElements(
    in articleContent: Element,
    componentPattern: NSRegularExpression,
    maximumTextLength: Int
  ) {
    let components = elements(in: articleContent).filter { component in
      let componentName = component.attrOrEmpty("x-component-name")
      return matches(componentPattern, in: componentName)
        && getInnerText(component, regEx: regEx).count <= maximumTextLength
    }
    for component in components where component.parent() != nil {
      printAndRemove(node: component)
    }
  }

  private func componentNames(in element: Element) -> [String] {
    elements(in: element).compactMap { node in
      let value = node.attrOrEmpty("x-component-name")
      return value.isEmpty ? nil : value
    }
  }

  private func elements(in element: Element) -> [Element] {
    var result: [Element] = []
    var stack = [element]
    while let current = stack.popLast() {
      result.append(current)
      for child in current.children().reversed() {
        stack.append(child)
      }
    }
    return result
  }

  private func compactedComparableText(_ text: String) -> String {
    String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
      .lowercased()
  }

  private func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
    regex.firstMatch(
      in: text,
      options: [],
      range: NSRange(location: 0, length: text.utf16.count)
    ) != nil
  }
}
