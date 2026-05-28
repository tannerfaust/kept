import Combine
import Foundation
import os
import SwiftUI

struct KeptBreadcrumb: Identifiable, Equatable, Hashable {
    let title: String
    let key: String

    var id: String { key }

    static func tab(_ tab: KeptTab) -> KeptBreadcrumb {
        KeptBreadcrumb(title: tab.title, key: "tab.\(tab.rawValue)")
    }

    static func pact(_ pact: Pact) -> KeptBreadcrumb {
        KeptBreadcrumb(title: pact.title, key: "pact.\(pact.id.uuidString)")
    }

    static func section(_ title: String) -> KeptBreadcrumb {
        KeptBreadcrumb(title: title, key: "section.\(title.lowercased())")
    }

    static func sheet(_ title: String) -> KeptBreadcrumb {
        KeptBreadcrumb(title: title, key: "sheet.\(title.lowercased())")
    }

    static func flow(_ title: String) -> KeptBreadcrumb {
        KeptBreadcrumb(title: title, key: "flow.\(title.lowercased())")
    }
}

@MainActor
final class KeptBreadcrumbTrail: ObservableObject {
    @Published private(set) var segments: [KeptBreadcrumb] = []

    var pathString: String {
        segments.map(\.title).joined(separator: " › ")
    }

    func update(_ segments: [KeptBreadcrumb]) {
        guard self.segments != segments else { return }
        self.segments = segments
        KeptBreadcrumbLog.ui("Trail updated", path: pathString)
    }

    func recordInteraction(_ name: String) {
        KeptBreadcrumbLog.interaction(name, path: pathString)
    }

    func backendContext(action: String) -> String {
        let trail = pathString
        return trail.isEmpty ? action : "\(trail) → \(action)"
    }
}

enum KeptBreadcrumbLog {
    private static let uiLogger = Logger(subsystem: "com.kept.app", category: "Breadcrumbs.UI")
    private static let interactionLogger = Logger(subsystem: "com.kept.app", category: "Breadcrumbs.Interaction")
    private static let backendLogger = Logger(subsystem: "com.kept.app", category: "Breadcrumbs.Backend")

    static func ui(_ event: String, path: String) {
        uiLogger.info("\(event, privacy: .public): \(path, privacy: .public)")
    }

    static func interaction(_ name: String, path: String) {
        interactionLogger.info("\(name, privacy: .public) @ \(path, privacy: .public)")
    }

    static func backend(
        method: String,
        path: String,
        breadcrumb: String?,
        statusCode: Int?
    ) {
        let status = statusCode.map(String.init) ?? "—"
        let context = breadcrumb ?? "—"
        backendLogger.info("\(method, privacy: .public) \(path, privacy: .public) [\(status, privacy: .public)] ctx=\(context, privacy: .public)")
    }
}

struct KeptBreadcrumbBar: View {
    @EnvironmentObject private var trail: KeptBreadcrumbTrail

    var body: some View {
        if trail.segments.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(trail.segments.enumerated()), id: \.element.id) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Color.black.opacity(0.35))
                        }
                        Text(crumb.title)
                            .font(.caption.weight(.black))
                            .foregroundStyle(index == trail.segments.count - 1 ? KeptColor.ink : Color.black.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Location: \(trail.pathString)")
        }
    }
}

private struct KeptBreadcrumbScreenModifier: ViewModifier {
    @EnvironmentObject private var trail: KeptBreadcrumbTrail
    let segments: [KeptBreadcrumb]

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            KeptBreadcrumbBar()
            content
        }
        .onAppear { trail.update(segments) }
        .onChange(of: segments.map(\.key)) { _, _ in
            trail.update(segments)
        }
    }
}

extension View {
    func keptScreenBreadcrumbs(_ segments: [KeptBreadcrumb]) -> some View {
        modifier(KeptBreadcrumbScreenModifier(segments: segments))
    }
}

protocol KeptBackendBreadcrumbCarrier: AnyObject {
    var requestBreadcrumb: String? { get set }
}

extension KeptBackendBreadcrumbCarrier {
    func applyBreadcrumbHeader(to request: inout URLRequest) {
        guard let requestBreadcrumb, !requestBreadcrumb.isEmpty else { return }
        request.setValue(requestBreadcrumb, forHTTPHeaderField: "X-Kept-Breadcrumb")
    }
}
