# WSL Clip Bridge Setup Scripts

## Quick Start

Run from PowerShell:

```powershell
# Download the script
Invoke-WebRequest -Uri https://raw.githubusercontent.com/camjac251/wsl-clip-bridge/main/scripts/setup.ps1 -OutFile setup.ps1

# Run the installer
powershell -ExecutionPolicy Bypass -File setup.ps1
```

## Files

- **`setup.ps1`** - Main PowerShell setup script with all logic

## Features

### 🚀 Full PowerShell Implementation
- Native JSON handling (no embedded scripts)
- Better error handling with try/catch
- Colored output for clarity
- Progress indicators
- Clean code structure

### 🎯 Smart Detection
- Automatically finds WSL distributions
- Detects system architecture (x64/ARM64)
- Checks for wl-clipboard support (WSLg)
- Locates ShareX configuration (optional)
- Checks for running processes

### 🛡️ Safety Features
- Creates timestamped backups before changes
- Validates all paths before operations
- Graceful error handling
- Process safety checks

### ⚙️ Configuration Options
- User or system-wide installation
- Download releases or build from source
- Automatic or manual ShareX setup
- Customizable clipboard TTL and image scaling
- wl-clipboard integration modes

### 📋 Windows Clipboard Integration
- Auto-configures wl-clipboard when WSLg detected
- Works with any Windows application
- Automatic BMP→PNG conversion for efficiency
- Backward compatible with ShareX workflows

## Usage

### Interactive Mode (Default)
```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

### Command Line Options
```powershell
# Run directly with PowerShell
powershell -ExecutionPolicy Bypass -File setup.ps1

# Skip ShareX configuration
powershell -ExecutionPolicy Bypass -File setup.ps1 -SkipShareX

# Auto-confirm all prompts (uses defaults)
powershell -ExecutionPolicy Bypass -File setup.ps1 -AutoConfirm

# Specify WSL distribution
powershell -ExecutionPolicy Bypass -File setup.ps1 -WSLDistribution "Ubuntu"

# Combine options
powershell -ExecutionPolicy Bypass -File setup.ps1 -AutoConfirm -WSLDistribution "Ubuntu"
```

## Installation Flow

1. **WSL Check** - Verifies WSL is installed
2. **Distribution Selection** - Auto-detects or lets you choose
3. **Architecture Detection** - Determines x64 or ARM64
4. **GitHub Repo** - Configure source repository
5. **Install Location** - User (~/.local/bin) or system (/usr/local/bin)
6. **Install Method** - Download, build from source, or use existing
7. **PATH Setup** - Updates .bashrc/.profile if needed
8. **Configuration** - Sets up TTL, image scaling, clipboard mode, security
9. **ShareX Integration** - Optional automatic setup
10. **Testing** - Validates the installation

## Configuration Options

The installer sets up these configuration options:

### Clipboard Integration Modes
- **`auto`** (default) - Checks wl-clipboard first for latest Windows clipboard, falls back to files
- **`file_only`** - Only uses file-based clipboard (ShareX mode or if WSLg unavailable)

### Image Processing
- **BMP→PNG Conversion** - Automatic conversion of Windows BMPs for 15-20x size reduction
- **Image Caching** - Option to cache converted images for faster subsequent access
- **Downscaling** - Configurable max dimension (1568px optimal for Claude API)

## ShareX Integration (Optional)

ShareX provides advanced screenshot features like annotations and uploads. The script can automatically:
- Create the action script (`copy-image-to-wsl-clipboard.bat`)
- Update ShareX's `ApplicationConfig.json`
- Add "Copy Image to WSL Clipboard" action
- Enable it in after-capture tasks

### Manual ShareX Setup

If you prefer manual configuration:
1. Open ShareX → Task Settings → Actions
2. Add new action:
   - Name: `Copy Image to WSL Clipboard`
   - File: `C:\Users\[You]\Documents\ShareX\Tools\copy-image-to-wsl-clipboard.bat`
   - Arguments: `"%input"`
   - ✓ Hidden window
3. Enable in After capture tasks:
   - ✓ Save image to file
   - ✓ Perform actions → "Copy Image to WSL Clipboard"

## Troubleshooting

### "WSL not found"
- Install WSL2: `wsl --install`
- Restart your computer after installation

### "No distributions found"
- Install Ubuntu: `wsl --install -d Ubuntu`

### "ShareX must be closed"
- The script will offer to close it automatically
- Or close ShareX manually before running setup

### "xclip not working"
- Restart your WSL session: `wsl --shutdown`
- Check PATH: `echo $PATH` in WSL
- Try running directly: `~/.local/bin/xclip -version`

### "Images from browser not pasting"
- Ensure WSLg is available (Windows 11 or Windows 10 with WSLg)
- Check clipboard mode is set to `auto` in config
- Test with: `wl-paste --list-types` after copying an image

## Requirements

- Windows 10/11 with WSL2
- PowerShell 5.1 or higher (included in Windows)
- A WSL distribution (Ubuntu recommended)
- WSLg (for wl-clipboard integration, Windows 11 or Windows 10 with WSLg)
- ShareX (optional, for advanced screenshot workflows)

## Security

The script uses `ExecutionPolicy Bypass` only for itself and doesn't change system-wide PowerShell policies. All operations are performed with user permissions unless you explicitly choose system-wide installation.

## How Clipboard Integration Works

The tool supports automatic Windows clipboard integration via WSLg's wl-clipboard:

1. **Copy from Any Windows App** - Browser images, Paint, Photoshop, ShareX, etc.
2. **Automatic Format Conversion** - BMP→PNG for significant size reduction
3. **Smart Priority System** - Always uses latest clipboard content
4. **Zero Configuration** - Works out of the box with WSLg
5. **Backward Compatible** - ShareX workflows continue to work

### Data Flow
```
Windows App → Copy Image → Windows Clipboard (BMP)
                                    ↓
                            WSLg/wl-clipboard
                                    ↓
                        WSL Clip Bridge (converts BMP→PNG)
                                    ↓
                            Ctrl+V in Claude Code
```

The installer automatically configures this integration when WSLg is detected, providing seamless clipboard sharing between Windows and WSL.