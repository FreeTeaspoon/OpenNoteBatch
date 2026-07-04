import Foundation

struct BatchRunner {
    let repository: OneNoteRepository
    let exportService: ExportService
    let importService: ImportService

    func unsupported(_ tool: ToolDefinition) -> [BatchResult] {
        [
            BatchResult(
                name: tool.title,
                path: "",
                status: .unsupported,
                message: "Microsoft Graph does not expose enough public OneNote data for this feature to be safely automated yet."
            )
        ]
    }
}

