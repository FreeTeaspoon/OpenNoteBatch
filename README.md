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
- Combined attachment and embedded-image export, with optional annotations and a PDF for each page.
- Page search across title or content.
- Tag list scan from OneNote page HTML.
- Export selected pages to text, HTML, or backup folders.
- Export embedded images in their visual top-to-bottom order, with optional
  full-page annotated composites that preserve ink outside image bounds and a
  PDF for each OneNote page.
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

The combined attachment and image export writes to `Downloads/OpenNote Batch` by
default. Its options independently control file attachments, embedded images,
page annotations, and a PDF for each page. Individual embedded images are kept,
and enabling page annotations also writes a page-level `*-annotated.png` file;
the page PDF uses that full-page composite when it can preserve the OneNote
coordinates.

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

The package script uses a stable local signing identity plus a separately
cached Keychain helper. The helper's executable hash does not change when the
main app is rebuilt, so Keychain approval survives normal rebuilds. Set it up
once on a development Mac:

```bash
./scripts/setup-local-signing.sh
./scripts/package-app.sh
```

When switching an existing installation from ad-hoc signing, the first launch
migrates the two existing Microsoft credentials to the stable helper. macOS
may ask once for each existing credential; choose **Always Allow**. Later
launches, refreshes, and rebuilds should not show those dialogs again. Keep the
cached helper at:

```text
~/Library/Application Support/OpenNoteBatch/OpenNoteBatchKeychain
```

Deleting that helper causes Keychain to see a new caller and requires another
one-time approval/migration.

For an Apple-signed build, set `OPENNOTE_BATCH_SIGNING_IDENTITY` to an
installed Apple Development or Developer ID Application identity instead.

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
