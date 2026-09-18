# UTH SEB for macOS

Native macOS port reconstructed from the supplied Windows .NET 8 application.

Build:

```sh
sh macos/build.sh
```

Open the launcher:

```sh
open dist/UTHSEB.app
```

Open a direct exam link:

```sh
open 'uthseb://open?url=https%3A%2F%2Fcourses.ut.edu.vn%2F'
```

The app starts unlocked in a normal macOS window, so login fields work normally and
the window can be minimized or switched away from. Press `Control + 5` to turn the
locked full-screen mode on; press `Control + 5` again to restore the normal window.
While locked, press `Esc` to display the **Ở lại / Thoát** confirmation. These two
shortcuts are the only keyboard input intercepted; everything else is passed to the
web page. Close the normal window to show the same exit confirmation.

For UI testing without macOS kiosk restrictions, add `--demo` before the URL. Demo
mode is not intended for a real exam session.

This is an ad-hoc signed build. Distribution to other Macs requires signing with an
Apple Developer ID and notarization. macOS WebKit cannot attach a custom header to
every subresource exactly like WebView2; the port attaches the UTH SEB authentication
header to top-level navigation requests.

The supplied Windows build currently has its process-action policy disabled
(`GetAction` returns `None`). The production macOS build mirrors that behavior, so it
can be launched from Chrome without immediately treating the calling browser as a
forbidden process. Screen locking is off by default and is controlled explicitly by
`Control + 5`; clipboard clearing and multiple-display enforcement remain disabled.
The custom user agent and authenticated top-level GET/HEAD navigation remain enabled.
POST requests are deliberately left untouched so Moodle login form bodies are not
lost when WebKit submits them.
