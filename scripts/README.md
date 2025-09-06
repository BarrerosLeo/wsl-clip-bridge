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
- Locates ShareX configuration
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
8. **Configuration** - Sets up TTL, image scaling, security
9. **ShareX Integration** - Optional automatic setup
10. **Testing** - Validates the installation

## ShareX Integration

The script can automatically:
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

## Requirements

- Windows 10/11 with WSL2
- PowerShell 5.1 or higher (included in Windows)
- A WSL distribution (Ubuntu recommended)
- ShareX (optional, for screenshot integration)

## Security

The script uses `ExecutionPolicy Bypass` only for itself and doesn't change system-wide PowerShell policies. All operations are performed with user permissions unless you explicitly choose system-wide installation.