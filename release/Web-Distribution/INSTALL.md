# Web Browser Installation

## System Requirements
- macOS 14.6 or later
- Apple Silicon (M1/M2/M3) or Intel Mac

## Installation Instructions

### Method 1: Drag and Drop (Recommended)
1. Open this folder and your Applications folder side by side
2. Drag the **Web.app** to your Applications folder
3. Launch Web from Applications or Spotlight

### Method 2: Terminal Installation
```bash
# Copy to Applications folder
cp -R "Web.app" "/Applications/"

# Launch the application
open "/Applications/Web.app"
```

## First Launch
- The app may show a security warning on first launch
- Go to System Preferences > Security & Privacy > General
- Click "Open Anyway" next to the Web app warning
- Or right-click the app and select "Open" from the context menu

## AI Features Setup
The browser includes local AI capabilities:
- **Ollama**: Install from https://ollama.ai for instant AI (recommended)
- **MLX**: Works automatically on Apple Silicon Macs
- **Cloud APIs**: Configure your own API keys in Settings

## Troubleshooting
- If the app won't open, check System Preferences > Security & Privacy
- For AI model issues, see the included documentation
- Report issues at: https://github.com/ddttom/Web/issues

## Version Information
- Version: 0.0.4
- Build Date: Sat Sep  6 16:38:51 BST 2025
- Platform: macOS (Universal)
