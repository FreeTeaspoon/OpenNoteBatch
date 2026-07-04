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
    var sections: [SectionNode] = []
    var sectionGroups: [SectionGroupNode] = []
}

struct SectionGroupNode: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var notebookID: String?
    var parentPath: String = ""
    var sections: [SectionNode] = []
    var sectionGroups: [SectionGroupNode] = []
}

struct SectionNode: Identifiable, Codable, Equatable {
    var id: String
    var displayName: String
    var notebookID: String?
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
    var mediaType: String?
    var pageTitle: String
    var pageID: String
    var kind: String
}

struct ImportItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileURL: URL
    var state: BatchStatus = .ready
    var message: String = ""
}

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case export = "Export"
    case `import` = "Import"
    case account = "Account"

    var id: String { rawValue }
}

enum ToolID: String, CaseIterable, Identifiable {
    case attachmentList
    case tagList
    case replacePageTitle
    case search
    case findLost
    case sectionSize
    case copySections
    case exportText
    case exportHTML
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
    var title: String
    var subtitle: String
    var symbol: String
    var isGraphSupported: Bool

    static let all: [ToolDefinition] = [
        .init(id: .attachmentList, tab: .home, title: "Attachment List", subtitle: "Scan pages and save embedded file attachments.", symbol: "paperclip", isGraphSupported: true),
        .init(id: .tagList, tab: .home, title: "Tag List", subtitle: "List tags found in OneNote page HTML.", symbol: "tag", isGraphSupported: true),
        .init(id: .replacePageTitle, tab: .home, title: "Replace Page Title", subtitle: "Find and replace matching page titles.", symbol: "textformat.abc.dottedunderline", isGraphSupported: true),
        .init(id: .search, tab: .home, title: "Search", subtitle: "Search selected pages by title or body text.", symbol: "magnifyingglass", isGraphSupported: true),
        .init(id: .findLost, tab: .home, title: "Find Lost", subtitle: "Detect inaccessible or moved sections where Graph exposes enough metadata.", symbol: "folder.badge.questionmark", isGraphSupported: false),
        .init(id: .sectionSize, tab: .home, title: "Section Size", subtitle: "Estimate section size from exportable page resources.", symbol: "ruler", isGraphSupported: false),
        .init(id: .copySections, tab: .home, title: "Copy Sections", subtitle: "Copy selected pages into another section.", symbol: "rectangle.stack.badge.plus", isGraphSupported: true),
        .init(id: .exportText, tab: .export, title: "Export pages to TXT files", subtitle: "Write selected pages as plain text.", symbol: "doc.plaintext", isGraphSupported: true),
        .init(id: .exportHTML, tab: .export, title: "Export pages to HTML files", subtitle: "Write selected pages as raw OneNote HTML.", symbol: "doc.richtext", isGraphSupported: true),
        .init(id: .backup, tab: .export, title: "Backup", subtitle: "Export HTML, text, attachments, and a manifest.", symbol: "externaldrive.badge.timemachine", isGraphSupported: true),
        .init(id: .importText, tab: .import, title: "Import txt files to OneNote", subtitle: "Create pages from text files.", symbol: "doc.text", isGraphSupported: true),
        .init(id: .importHTML, tab: .import, title: "Import HTML files to OneNote", subtitle: "Create pages from HTML files.", symbol: "curlybraces.square", isGraphSupported: true),
        .init(id: .importImages, tab: .import, title: "Import Images to OneNote", subtitle: "Create pages containing selected images.", symbol: "photo", isGraphSupported: true),
        .init(id: .importTree, tab: .import, title: "Import Tree to OneNote", subtitle: "Create pages from a folder tree of text and HTML files.", symbol: "folder", isGraphSupported: true),
        .init(id: .importMacNotes, tab: .import, title: "Import Mac Notes files to OneNote", subtitle: "Use exported files from Apple Notes as import input.", symbol: "note", isGraphSupported: true),
        .init(id: .importGoogleKeep, tab: .import, title: "Import Google Keep files to OneNote", subtitle: "Import Google Takeout Keep HTML files.", symbol: "lightbulb", isGraphSupported: true),
        .init(id: .importEvernote, tab: .import, title: "Import Evernote", subtitle: "Import simple ENEX notes into OneNote pages.", symbol: "elephant", isGraphSupported: true),
        .init(id: .restore, tab: .import, title: "Restore", subtitle: "Restore pages from an OpenNote Batch backup manifest.", symbol: "arrow.counterclockwise", isGraphSupported: true),
        .init(id: .account, tab: .account, title: "Microsoft Account", subtitle: "Sign in, re-login, and review permissions.", symbol: "person.crop.circle", isGraphSupported: true)
    ]
}
