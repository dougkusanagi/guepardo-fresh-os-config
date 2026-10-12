package assets

import "embed"

// WindowsFiles keeps the Jellyfin module and stylesheet available when the
// Windows executable is run without a repository checkout beside it.
//
//go:embed modules/jellyfin.ps1 jellyfin/polish.css
var WindowsFiles embed.FS
