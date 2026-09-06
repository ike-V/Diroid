# Diroid

<img src="Screenshots/icon.png" width="128" height="128" alt="Diroid app icon">

A native macOS app for browsing your Android phone's storage over USB — no MTP, no kernel extension, no background daemon.

![Diroid listing a phone's internal storage](Screenshots/list-view.jpg)

## What is this?

- macOS has no built-in way to see an Android phone's files when you plug it in over USB. 
Every existing solution wraps `libmtp` in a FUSE filesystem, which means a kernel extension, kernel-level trust, and (in practice) a lot of flakiness getting it to actually mount.
- Diroid speaks Android's own USB debugging protocol (ADB) directly over a socket to the local `adb` server (the same mechanism Android Studio's "Device File Explorer" uses), reimplemented from scratch in Swift.
- No `adb` binary shelled out to, no third-party libraries, no elevated privileges, no daemons running in the background.

## Features

- Browse your phone's storage like a Finder window — List and Grid view, groupable by Name, Size, or Date Modified
- Double-click a file to pull it and open it in whatever app macOS would normally use for that file type
- Right-click → **Save to…** to copy a file to a folder you choose, without opening it
- Right-click → **Rename…** to rename or move a file or folder
- Right-click → **Delete** to remove a file, or a folder and everything in it (with a confirmation prompt first)
- **New Folder** (➕📁) button to create a folder in the current directory
- **Upload** (↑) button to push local files onto the phone
- Click any segment of the path breadcrumb to jump straight to that folder, including the root `/` itself — the whole filesystem is browsable, not just your phone's storage (permission-restricted system folders show a clear error instead of a blank screen)
- **Refresh** (↻) button to reconnect after unplugging/replugging your phone — no need to relaunch

### Screenshots

| Grid view | Group By: Date Modified | New Folder |
| --- | --- | --- |
| ![Grid/Icon view of a phone's internal storage](Screenshots/grid-view.jpg) | ![Camera roll grouped by Date Modified into Previous 7 Days / Previous 30 Days](Screenshots/Sort-by-date.jpg) | ![Creating a new folder from the toolbar](Screenshots/new-folder.jpg) |

The toolbar adapts to a narrower window rather than clipping — everything that doesn't fit collapses into a "»" overflow menu:

![Toolbar overflow menu showing every control still reachable in a narrow window](Screenshots/overflow-menu.jpg)

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (for the Swift compiler — full Xcode isn't required): `xcode-select --install`
- An Android phone with **USB debugging** enabled: Settings → About phone → tap "Build number" 7 times to unlock Developer options → Developer options → USB debugging
- The `adb` server running on your Mac — easiest way is Homebrew: `brew install android-platform-tools`. Diroid talks to this same background server; it just doesn't shell out to the `adb` binary itself.

## Getting started

```bash
git clone https://github.com/ike-V/Diroid.git
cd Diroid
./build.sh
open Diroid.app
```

- Plug in your phone before or after launching 
- The first time, you'll get a prompt on the phone itself asking to authorize this computer for USB debugging; accept it (check "always allow" to skip this next time).
- If you unplug/replug while the app is already open, hit the refresh (↻) button.



## License

[MIT](LICENSE)
