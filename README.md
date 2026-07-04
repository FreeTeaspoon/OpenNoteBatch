# OpenNote Batch

OpenNote Batch is an open-source native macOS OneNote batch utility inspired by
the workflow of OneNote Batch for Mac, implemented with original SwiftUI code
and Microsoft Graph.

It uses Microsoft sign-in with OAuth authorization-code + PKCE and calls Graph
as the signed-in user. You must use your own Microsoft app registration; this
project does not reuse any vendor client ID, private assets, or app code.

## Main Features

- Native macOS SwiftUI interface with Home, Export, Import, and Help workspaces.
- Microsoft account sign-in choices for personal, global work/school, China
  work/school, and OneNote personal account modes.
- Notebook and section browser.
- Attachment list scan and bulk save.
- Page search across title or content.
- Tag list scan from OneNote page HTML.
- Export selected pages to text, HTML, or backup folders.
- Import text, HTML, images, and simple folder trees into OneNote sections.
- Account status and re-login screen.
- Keychain storage for Microsoft OAuth tokens.
- Settings for your own Microsoft client ID, redirect URI, tenant override, and
  exporter-only vs full-batch permission presets.

Some OneNote Batch features map to Microsoft Graph limitations. The app keeps
those tools visible and reports precise Graph/API limits in the status table
instead of silently pretending they worked.

## Microsoft App Registration

Create an app registration in Microsoft Entra, then add a **Mobile and desktop
applications** redirect URI:

```text
msauth.com.openbatch.opennotebatch://auth
```

The app bundle identifier is:

```text
com.openbatch.opennotebatch
```

Enable public client flows if your tenant requires it.

Recommended delegated Graph scopes for the broad clone-like feature set:

```text
openid profile offline_access User.Read Notes.ReadWrite Notes.ReadWrite.All Notes.Create Files.ReadWrite.All Sites.ReadWrite.All
```

For attachment export only, you can usually use:

```text
openid profile offline_access User.Read Notes.Read
```

Paste the client ID into OpenNote Batch's Settings sheet before signing in.

## Using the App

1. Open Settings and paste your Microsoft client ID.
2. Choose the permission preset:
   - **Attachment Exporter** for read-only export workflows.
   - **Full Batch Tools** for import, copy, rename, and backup workflows.
3. Sign in from the account card or Account workspace.
4. Click **Load** to fetch notebooks, sections, and pages.
5. Check pages or sections in the sidebar.
6. Pick a Home, Export, or Import tool and run it.

For Attachment List, leaving the save folder blank lists attachments only.
Choosing a save folder downloads matching attachments.

Features that Microsoft Graph does not expose safely, such as exact native
section-size reporting or lost-section recovery, remain visible but return
explicit unsupported/partial-support results.

## Build

```bash
swift build -c release
```

Run from source:

```bash
swift run OpenNoteBatch
```

Create a local `.app` bundle:

```bash
./scripts/package-app.sh
open .build/OpenNoteBatch.app
```

Run tests:

```bash
swift test
```

## References

- Microsoft Graph OneNote overview:
  https://learn.microsoft.com/en-us/graph/integrate-with-onenote
- Get OneNote content and structure:
  https://learn.microsoft.com/en-us/graph/onenote-get-content
- Create OneNote pages:
  https://learn.microsoft.com/en-us/graph/api/section-post-pages
- Add files and images to OneNote pages:
  https://learn.microsoft.com/en-us/graph/onenote-images-files
- Microsoft identity authorization code flow:
  https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow
