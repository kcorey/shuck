# shuck

A macOS command-line tool that extracts text from documents and images and displays it in a native scrollable window. Supports PDFs, images (via OCR), rich documents, and plain text. Comes with an Automator Quick Action for Finder right-click integration.

## Requirements

- macOS (uses Apple frameworks: AppKit, Vision, PDFKit)
- Swift compiler — either Xcode or the Command Line Tools package:
  ```
  xcode-select --install
  ```

No third-party dependencies.

## Compilation

```bash
./build.sh
```

This runs `swiftc -O -o shuck Shuck.swift` and produces the `shuck` binary in the project directory.

## Installation (Finder Quick Action)

```bash
./install.sh
```

This builds the binary, copies it to `/usr/local/bin/shuck` (requires `sudo`), and installs the Automator workflow to `~/Library/Services/Shuck Text.workflow`, making it available as a Quick Action in Finder.

If "Shuck Text" doesn't appear in the right-click menu after installation:

- Open **System Settings → Privacy & Security → Extensions → Finder Extensions** and ensure "Shuck Text" is enabled
- Or log out and log back in

## Usage

### Command line

```bash
./shuck file1.pdf
./shuck image.png document.docx notes.txt
```

Pass one or more files. When multiple files are given, they are combined into a single view separated by `--- filename ---` headers.

The extracted text opens in a native macOS window sized to fit the widest line of text (plus 5%), capped at two-thirds of the screen width, 80% tall. Text is selectable but not editable. Press **Escape** or close the window to quit.

At the top-right of the window are two checkboxes:

| Checkbox | Default | Shortcut | Behaviour |
|---|---|---|---|
| **Numbered** | off | Cmd-N | Shows grey 6-digit line numbers to the left of each line |
| **Wrap** | off | Cmd-W | Wraps lines at the window edge; continuation lines are indented by one character |

When **Wrap** is off, a horizontal scrollbar appears at the bottom whenever the text is wider than the window. You can also scroll left/right with the **←** / **→** arrow keys (4 characters per keypress).

### Selecting and copying text

| Action | Result |
|---|---|
| **Cmd-A** | Select all text |
| **Cmd-C** | Copy selection to clipboard |
| **Mouse drag** | Selects text, then automatically copies it to the clipboard and shows a brief "Copied!" toast |

### Finder Quick Action

After running `./install.sh`:

1. Select one or more files in Finder
2. Right-click → **Quick Actions → Shuck Text**

## Supported Formats

| Category | Extensions | Method |
|---|---|---|
| PDF | `.pdf` | PDFKit text layer |
| Images | `.png` `.jpg` `.jpeg` `.tiff` `.tif` `.heic` `.heics` `.webp` `.gif` `.bmp` `.jp2` `.jxl` | Vision OCR |
| Rich documents | `.docx` `.doc` `.odt` `.rtf` `.rtfd` | NSAttributedString |
| Plain text | everything else | UTF-8 → macOS Roman → ISO Latin-1 |

Unrecognised extensions are treated as plain text.

## Gotchas & Warnings

**Scanned / image-only PDFs**

PDF extraction uses PDFKit's embedded text layer. A PDF that is purely a scanned image with no text layer will return `[No text found in PDF]`. To extract text from a scanned PDF, save each page as an image first and pass those image files instead.

**OCR accuracy**

Image OCR uses the Vision framework at `.accurate` recognition level with language correction enabled. Quality depends on image resolution and clarity; low-resolution or heavily stylised text may produce poor results.

**Gatekeeper**

The compiled binary is not code-signed. On first run via the Finder Quick Action, macOS may block it. If this happens, go to **System Settings → Privacy & Security** and allow it to run, or clear the quarantine attribute:

```bash
xattr -d com.apple.quarantine shuck
```

**No Dock icon**

The app uses the `.accessory` activation policy, so it does not appear in the Dock or Command-Tab switcher. It will appear briefly in the menu bar when active.

**GIF and WebP OCR**

Animated GIFs and WebP files are decoded as static images (first frame). The Vision framework will attempt OCR on whatever pixel data it receives, which may produce nonsense for non-document images.

## Project Structure

```
Shuck.swift                Source code
build.sh                   Compiles the binary
install.sh                 Builds and installs the Automator workflow
Shuck Text.workflow/       Automator Quick Action package
shuck                      Compiled binary (not in git)
```
