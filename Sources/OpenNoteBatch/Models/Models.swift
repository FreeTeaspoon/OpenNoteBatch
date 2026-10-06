import Foundation

enum AccountKind: String, CaseIterable, Identifiable, Codable {
    case microsoftPersonal
    case globalWorkSchool
    case chinaWorkSchool
    case oneNotePersonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microsoftPersonal: "Microsoft Personal Account"
        case .globalWorkSchool: "Microsoft Global School or Work Account"
        case .chinaWorkSchool: "Microsoft Chinese School or Work Account"
        case .oneNotePersonal: "OneNote Personal Account"
        }
    }

    var subtitle: String {
        switch self {
        case .microsoftPersonal: "Personal notebooks and OneDrive-backed content."
        case .globalWorkSchool: "Organization, school, or Microsoft 365 tenant notebooks."
        case .chinaWorkSchool: "21Vianet operated Microsoft cloud endpoints."
        case .oneNotePersonal: "Personal OneNote mode with OneNote-focused scopes."
        }
    }

    var symbol: String {
        switch self {
        case .microsoftPersonal: "cloud.fill"
        case .globalWorkSchool: "building.2.crop.circle.fill"
        case .chinaWorkSchool: "globe.asia.australia.fill"
        case .oneNotePersonal: "note.text"
        }
    }

    var authorityHost: String {
        switch self {
        case .chinaWorkSchool: "https://login.chinacloudapi.cn"
        default: "https://login.microsoftonline.com"
        }
    }

    var graphRoot: String {
        switch self {
        case .chinaWorkSchool: "https://microsoftgraph.chinacloudapi.cn/v1.0"
        default: "https://graph.microsoft.com/v1.0"
        }
    }

    var defaultTenant: String {
        switch self {
        case .microsoftPersonal, .oneNotePersonal: "consumers"
        case .globalWorkSchool: "organizations"
        case .chinaWorkSchool: "organizations"
        }
    }
}

enum PermissionPreset: String, CaseIterable, Identifiable, Codable {
    case exporter
    case fullBatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exporter: "Attachment Exporter"
        case .fullBatch: "Full Batch Tools"
        }
    }

    var scopes: [String] {
        switch self {
        case .exporter:
            ["openid", "profile", "offline_access", "User.Read", "Notes.Read"]
        case .fullBatch:
            [
                "openid",
                "profile",
                "offline_access",
                "User.Read",
                "Notes.ReadWrite",
                "Notes.ReadWrite.All",
                "Notes.Create",
                "Files.ReadWrite.All"
            ]
        }
    }
}

struct AppSettings: Codable, Equatable {
    var clientID: String = ""
    var redirectURI: String = "msauth.com.openbatch.opennotebatch://auth"
    var tenantOverride: String = ""
    var permissionPreset: PermissionPreset = .fullBatch
    var outputDirectoryPath: String? = nil

    func tenant(for accountKind: AccountKind) -> String {
        tenantOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? accountKind.defaultTenant
            : tenantOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GraphAccount: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var email: String
    var accountKind: AccountKind
}

struct TokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scope: String?
    var tokenType: String

    var isExpired: Bool {
        Date().addingTimeInterval(120) >= expiresAt
    }
}

struct NotebookNode: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var createdDateTime: Date? = nil
    var sections: [SectionNode] = []
    var sectionGroups: [SectionGroupNode] = []
}

struct SectionGroupNode: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var notebookID: String?
    var createdDateTime: Date? = nil
    var parentPath: String = ""
    var sections: [SectionNode] = []
    var sectionGroups: [SectionGroupNode] = []
}

struct SectionNode: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var notebookID: String?
    var createdDateTime: Date? = nil
    var groupPath: String = ""
    var pages: [PageNode] = []
}

struct PageNode: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var createdDateTime: Date?
    var lastModifiedDateTime: Date?
    var contentURL: String?
    var notebookName: String?
    var sectionName: String?
    var level: Int? = nil
    var order: Int? = nil
}

enum OneNoteOrdering {
    static func pages(_ pages: [PageNode]) -> [PageNode] {
        pages.enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = lhs.element.order ?? Int.max
                let rhsOrder = rhs.element.order ?? Int.max
                return lhsOrder == rhsOrder ? lhs.offset < rhs.offset : lhsOrder < rhsOrder
            }
            .map(\.element)
    }
}

enum BatchStatus: String, Codable {
    case ready
    case running
    case success
    case warning
    case failed
    case unsupported
}

struct BatchResult: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var path: String
    var status: BatchStatus
    var message: String
}

struct BatchTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var progress: Double
    var status: BatchStatus
}

struct AttachmentResource: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileName: String
    var resourceURL: URL
    var alternateResourceURL: URL? = nil
    var mediaType: String?
    var pageTitle: String
    var pageID: String
    var kind: String
    var pageTop: Double? = nil
    var pageLeft: Double? = nil
    var displayWidth: Double? = nil
    var displayHeight: Double? = nil
    var documentIndex: Int = 0
}

struct OneNotePageContent: Equatable {
    var html: String
    var inkML: [String] = []
}

struct InkStroke: Equatable {
    var points: [CGPoint]
    var colorHex: String
    var width: Double
    var opacity: Double
}

struct ImportItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileURL: URL
    var state: BatchStatus = .ready
    var message: String = ""
}

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case export = "Export"
    case home = "Home"
    case `import` = "Import"
    case account = "Account"

    var id: String { rawValue }
}

enum ToolID: String, CaseIterable, Identifiable {
    case tagList
    case replacePageTitle
    case search
    case findLost
    case sectionSize
    case copySections
    case exportText
    case exportHTML
    case exportAttachmentsAndImages
    case exportCombinedPDF
    case backup
    case importText
    case importHTML
    case importImages
    case importTree
    case importMacNotes
    case importGoogleKeep
    case importEvernote
    case restore
    case account

    var id: String { rawValue }
}

struct ToolDefinition: Identifiable, Equatable {
    var id: ToolID
    var tab: WorkspaceTab
    var group: String
    var title: String
    var subtitle: String
    var symbol: String
    var isGraphSupported: Bool

    static let all: [ToolDefinition] = [
        .init(id: .search, tab: .home, group: "Everyday tools", title: "Search", subtitle: "Search selected pages by title or body text.", symbol: "magnifyingglass", isGraphSupported: true),
        .init(id: .tagList, tab: .home, group: "Everyday tools", title: "Tag List", subtitle: "List tags found in OneNote page HTML.", symbol: "tag", isGraphSupported: true),
        .init(id: .replacePageTitle, tab: .home, group: "Everyday tools", title: "Replace Page Title", subtitle: "Find and replace matching page titles.", symbol: "textformat.abc.dottedunderline", isGraphSupported: true),
        .init(id: .copySections, tab: .home, group: "Everyday tools", title: "Copy Sections", subtitle: "Copy selected pages into another section.", symbol: "rectangle.stack.badge.plus", isGraphSupported: true),
        .init(id: .findLost, tab: .home, group: "Limited support", title: "Find Inaccessible Sections", subtitle: "Inspect Graph metadata for sections that may have moved or become unavailable.", symbol: "folder.badge.questionmark", isGraphSupported: false),
        .init(id: .sectionSize, tab: .home, group: "Limited support", title: "Estimate Section Size", subtitle: "Estimate size from page resources that Microsoft Graph exposes.", symbol: "ruler", isGraphSupported: false),
        .init(id: .exportAttachmentsAndImages, tab: .export, group: "Recommended exports", title: "Export Attachments & Images", subtitle: "Save file attachments, embedded images, annotations, and page PDFs together.", symbol: "square.and.arrow.down", isGraphSupported: true),
        .init(id: .exportCombinedPDF, tab: .export, group: "Recommended exports", title: "Create Combined Annotated PDF", subtitle: "Merge selected rendered OneNote pages into one PDF with clickable contents.", symbol: "doc.richtext", isGraphSupported: true),
        .init(id: .exportText, tab: .export, group: "Recommended exports", title: "Export Pages to TXT", subtitle: "Write selected pages as plain text.", symbol: "doc.plaintext", isGraphSupported: true),
        .init(id: .exportHTML, tab: .export, group: "Recommended exports", title: "Export Pages to HTML", subtitle: "Write selected pages as raw OneNote HTML.", symbol: "doc.richtext", isGraphSupported: true),
        .init(id: .backup, tab: .export, group: "Other exports", title: "Backup", subtitle: "Export HTML, text, attachments, and a manifest.", symbol: "externaldrive.badge.timemachine", isGraphSupported: true),
        .init(id: .importText, tab: .import, group: "Common formats", title: "Import TXT Files", subtitle: "Create pages from text files.", symbol: "doc.text", isGraphSupported: true),
        .init(id: .importHTML, tab: .import, group: "Common formats", title: "Import HTML Files", subtitle: "Create pages from HTML files.", symbol: "curlybraces.square", isGraphSupported: true),
        .init(id: .importImages, tab: .import, group: "Common formats", title: "Import Images", subtitle: "Create pages containing selected images.", symbol: "photo", isGraphSupported: true),
        .init(id: .importTree, tab: .import, group: "Other formats", title: "Import Folder Tree", subtitle: "Create pages from a folder tree of text and HTML files.", symbol: "folder", isGraphSupported: true),
        .init(id: .importMacNotes, tab: .import, group: "Other formats", title: "Import Apple Notes Files", subtitle: "Use exported files from Apple Notes as import input.", symbol: "note", isGraphSupported: true),
        .init(id: .importGoogleKeep, tab: .import, group: "Other formats", title: "Import Google Keep Files", subtitle: "Import Google Takeout Keep HTML files.", symbol: "lightbulb", isGraphSupported: true),
        .init(id: .importEvernote, tab: .import, group: "Other formats", title: "Import Evernote", subtitle: "Import simple ENEX notes into OneNote pages.", symbol: "elephant", isGraphSupported: true),
        .init(id: .restore, tab: .import, group: "Other formats", title: "Restore Backup", subtitle: "Restore pages from an OpenNote Batch backup manifest.", symbol: "arrow.counterclockwise", isGraphSupported: true),
        .init(id: .account, tab: .account, group: "Account", title: "Microsoft Account", subtitle: "Sign in, re-login, and review permissions.", symbol: "person.crop.circle", isGraphSupported: true)
    ]
}
