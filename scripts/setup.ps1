#Requires -Version 5.1
<#
.SYNOPSIS
    WSL Clip Bridge - Interactive Setup for Windows
.DESCRIPTION
    Seamless clipboard sharing between Windows & WSL
    Installs xclip binary and configures ShareX integration
.NOTES
    Run with: powershell -ExecutionPolicy Bypass -File setup.ps1
#>

param(
    [switch]$SkipShareX,
    [switch]$AutoConfirm,
    [ValidatePattern('^$|^[a-zA-Z0-9_-]+$')]
    [string]$WSLDistribution = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Colors and formatting
function Write-Header {
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 64) -ForegroundColor Cyan
    Write-Host "           WSL Clip Bridge - Interactive Setup" -ForegroundColor White
    Write-Host "      Seamless clipboard sharing between Windows & WSL" -ForegroundColor Gray
    Write-Host ("=" * 64) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host "[*] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[!] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error {
    param([string]$Message)
    Write-Host "[X] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Question {
    param([string]$Message)
    Write-Host "[?] " -ForegroundColor Magenta -NoNewline
    Write-Host $Message
}

# Clear screen and show header
Clear-Host
Write-Header

# Check for WSL
Write-Info "Checking WSL installation..."
try {
    $wslStatus = wsl --status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "WSL is not installed"
    }
    Write-Success "WSL detected"
} catch {
    Write-Error "WSL is not installed or not accessible."
    Write-Host "    Please install WSL2 first: wsl --install" -ForegroundColor Gray
    if (-not $AutoConfirm) {
        Read-Host "`nPress Enter to exit"
    }
    exit 1
}

Write-Host ""

# Get WSL distributions
Write-Info "Detecting WSL distributions..."
$distributions = @(wsl --list --quiet 2>$null | Where-Object { $_ -match '\S' } | ForEach-Object {
    $_.Trim() -replace '\0', '' -replace '[^\x20-\x7E]', ''
} | Where-Object { $_ })

if ($distributions.Count -eq 0) {
    Write-Error "No WSL distributions found."
    Write-Host "    Please install a Linux distribution first." -ForegroundColor Gray
    Write-Host "    Run: wsl --install -d Ubuntu" -ForegroundColor Gray
    if (-not $AutoConfirm) {
        Read-Host "`nPress Enter to exit"
    }
    exit 1
}

# Select distribution
$selectedDist = $null
if ($WSLDistribution) {
    if ($distributions -contains $WSLDistribution) {
        $selectedDist = $WSLDistribution
        Write-Success "Using specified distribution: $selectedDist"
    } else {
        Write-Warning "Specified distribution '$WSLDistribution' not found"
    }
}

# Validate selected distribution name for security
function Test-DistributionName {
    param([string]$Name)
    return $Name -match '^[a-zA-Z0-9_-]+$'
}

if (-not $selectedDist) {
    if ($distributions.Count -eq 1) {
        $selectedDist = $distributions[0]
        Write-Success "Found distribution: $selectedDist"
    } else {
        Write-Info "Found $($distributions.Count) distributions:"
        Write-Host ""
        for ($i = 0; $i -lt $distributions.Count; $i++) {
            Write-Host "    $($i + 1). $($distributions[$i])"
        }
        Write-Host ""
        
        do {
            $choice = Read-Host "Select distribution (1-$($distributions.Count))"
            $choiceNum = $choice -as [int]
        } while (-not $choiceNum -or $choiceNum -lt 1 -or $choiceNum -gt $distributions.Count)
        
        $selectedDist = $distributions[$choiceNum - 1]
    }
}

# Final validation of distribution name
if ($selectedDist -and -not (Test-DistributionName $selectedDist)) {
    Write-Error "Invalid distribution name format: $selectedDist"
    Write-Host "    Distribution names should only contain letters, numbers, hyphens, and underscores" -ForegroundColor Gray
    if (-not $AutoConfirm) {
        Read-Host "`nPress Enter to exit"
    }
    exit 1
}

Write-Host ""

# Detect architecture
Write-Info "Detecting system architecture..."
$arch = "amd64"
$osArch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
if ($osArch -match "ARM") {
    $arch = "arm64"
    Write-Success "ARM64 architecture detected"
} else {
    Write-Success "x64/AMD64 architecture detected"
}

Write-Host ""

# Detect WSL architecture (might differ from Windows)
Write-Info "Checking WSL architecture..."
$wslArch = wsl -d $selectedDist -- uname -m 2>$null
if ($wslArch -eq "x86_64") {
    $arch = "amd64"
    Write-Success "WSL running on x64/AMD64"
} elseif ($wslArch -eq "aarch64") {
    $arch = "arm64"
    Write-Success "WSL running on ARM64"
}

Write-Host ""

# GitHub repository setup
$defaultRepo = "camjac251/wsl-clip-bridge"
Write-Question "GitHub Repository Configuration"
Write-Host "    Default: $defaultRepo" -ForegroundColor Gray

if (-not $AutoConfirm) {
    $customRepo = Read-Host "Enter repository (or press Enter for default)"
    if ($customRepo) {
        # Validate repository format
        if ($customRepo -notmatch '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$') {
            Write-Error "Invalid repository format. Expected: owner/repo"
            if (-not $AutoConfirm) {
                Read-Host "`nPress Enter to exit"
            }
            exit 1
        }
        $githubRepo = $customRepo
    } else {
        $githubRepo = $defaultRepo
    }
} else {
    $githubRepo = $defaultRepo
}

Write-Host ""

# Installation location
Write-Question "Installation Location:"
Write-Host "    1. User directory (~/.local/bin) - Recommended, no sudo required"
Write-Host "    2. System-wide (/usr/local/bin) - Requires sudo"
Write-Host ""

if (-not $AutoConfirm) {
    $installLocation = Read-Host "Select location (1-2) [1]"
    if (-not $installLocation) { $installLocation = "1" }
} else {
    $installLocation = "1"
}

$installPath = "~/.local/bin"
$installDirCmd = "mkdir -p ~/.local/bin"
$installCopyCmd = "cp"
$needsSudo = ""

if ($installLocation -eq "2") {
    $installPath = "/usr/local/bin"
    $installDirCmd = "sudo mkdir -p /usr/local/bin"
    $installCopyCmd = "sudo cp"
    $needsSudo = "sudo "
    Write-Success "Installing system-wide (sudo required)"
} else {
    Write-Success "Installing to user directory (no sudo required)"
}

Write-Host ""

# Installation method
Write-Question "Installation Method:"
Write-Host "    1. Download latest release (recommended)"
Write-Host "    2. Build from source (requires Rust in WSL)"
Write-Host "    3. Use existing local build"
Write-Host ""

if (-not $AutoConfirm) {
    $installMethod = Read-Host "Select method (1-3)"
} else {
    $installMethod = "1"
}

Write-Host ""

switch ($installMethod) {
    "1" {
        # Download from GitHub releases
        Write-Info "Downloading latest release for $arch..."
        
        $tempDir = Join-Path $env:TEMP "wsl-clip-bridge-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        $downloadUrl = "https://github.com/$githubRepo/releases/latest/download/xclip-$arch"
        Write-Host "    URL: $downloadUrl" -ForegroundColor Gray
        Write-Host ""
        
        $downloadPath = Join-Path $tempDir "xclip"
        
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            # Download the binary
            Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
            
            # Try to download and verify checksum if available
            $checksumUrl = "$downloadUrl.sha256"
            $checksumPath = Join-Path $tempDir "xclip.sha256"
            
            try {
                Write-Info "Downloading checksum for verification..."
                Invoke-WebRequest -Uri $checksumUrl -OutFile $checksumPath -UseBasicParsing -ErrorAction SilentlyContinue
                
                if (Test-Path $checksumPath) {
                    # Parse checksum file (format: "filename  hash" or just "hash")
                    $checksumContent = (Get-Content $checksumPath -Raw).Trim()
                    if ($checksumContent -match '^([a-fA-F0-9]{64})') {
                        $expectedChecksum = $matches[1].ToUpper()
                    } else {
                        $expectedChecksum = $checksumContent.Split(' ')[-1].ToUpper()
                    }
                    $actualChecksum = (Get-FileHash $downloadPath -Algorithm SHA256).Hash.ToUpper()
                    
                    if ($expectedChecksum -eq $actualChecksum) {
                        Write-Success "Checksum verified successfully"
                    } else {
                        Write-Error "Checksum verification failed!"
                        Write-Host "    Expected: $expectedChecksum" -ForegroundColor Gray
                        Write-Host "    Actual:   $actualChecksum" -ForegroundColor Gray
                        Remove-Item $tempDir -Recurse -Force 2>$null
                        if (-not $AutoConfirm) {
                            Read-Host "`nPress Enter to exit"
                        }
                        exit 1
                    }
                } else {
                    Write-Warning "Checksum file not available, skipping verification"
                }
            } catch {
                Write-Warning "Could not verify checksum: $_"
            }
            
            Write-Success "Download complete"
        } catch {
            Write-Error "Failed to download binary."
            Write-Host "    Please check your internet connection and repository settings." -ForegroundColor Gray
            Remove-Item $tempDir -Recurse -Force 2>$null
            if (-not $AutoConfirm) {
                Read-Host "`nPress Enter to exit"
            }
            exit 1
        }
        
        Write-Host ""
        Write-Info "Installing to WSL distribution: $selectedDist..."
        
        # Convert Windows path to WSL path and copy
        $wslTempPath = wsl -d $selectedDist -- wslpath -u "$downloadPath"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to convert Windows path to WSL path"
            Remove-Item $tempDir -Recurse -Force 2>$null
            exit 1
        }
        
        wsl -d $selectedDist -- $installDirCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create installation directory"
            Remove-Item $tempDir -Recurse -Force 2>$null
            exit 1
        }
        
        wsl -d $selectedDist -- $installCopyCmd "$wslTempPath" "$installPath/xclip"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to copy binary to installation directory"
            Remove-Item $tempDir -Recurse -Force 2>$null
            exit 1
        }
        
        wsl -d $selectedDist -- ${needsSudo}chmod +x "$installPath/xclip"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to set executable permissions"
            Remove-Item $tempDir -Recurse -Force 2>$null
            exit 1
        }
        
        Write-Success "Binary installed to $installPath/xclip"
        
        # Cleanup
        Remove-Item $tempDir -Recurse -Force 2>$null
    }
    
    "2" {
        # Build from source
        Write-Info "Checking for Rust in WSL..."
        $cargoCheck = wsl -d $selectedDist -- which cargo 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Rust not found in WSL."
            Write-Host "    Install Rust first: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" -ForegroundColor Gray
            if (-not $AutoConfirm) {
                Read-Host "`nPress Enter to exit"
            }
            exit 1
        }
        
        Write-Info "Cloning repository..."
        wsl -d $selectedDist -- git clone "https://github.com/$githubRepo" ~/wsl-clip-bridge 2>$null
        
        Write-Info "Building from source..."
        wsl -d $selectedDist -- bash -c "cd ~/wsl-clip-bridge && cargo build --release"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Build failed. Check error messages above."
            exit 1
        }
        
        Write-Info "Installing binary..."
        if ($installLocation -eq "1") {
            wsl -d $selectedDist -- bash -c "mkdir -p ~/.local/bin && cp ~/wsl-clip-bridge/target/release/xclip ~/.local/bin/"
        } else {
            wsl -d $selectedDist -- bash -c "sudo cp ~/wsl-clip-bridge/target/release/xclip /usr/local/bin/"
        }
        
        Write-Success "Build and installation complete"
    }
    
    "3" {
        # Use existing build
        Write-Info "Please ensure xclip is already installed in WSL."
    }
    
    default {
        Write-Error "Invalid selection."
        if (-not $AutoConfirm) {
            Read-Host "`nPress Enter to exit"
        }
        exit 1
    }
}

Write-Host ""

# Configure PATH (only for user installation)
if ($installLocation -eq "1") {
    Write-Info "Checking PATH configuration..."
    
    $pathCheck = wsl -d $selectedDist -- bash -c 'echo $PATH | grep -q ~/.local/bin'
    if ($LASTEXITCODE -ne 0) {
        Write-Info "~/.local/bin not found in PATH"
        
        # Check which shell config files exist
        $bashrcExists = wsl -d $selectedDist -- test -f ~/.bashrc
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Adding to ~/.bashrc..."
            $pathCommand = 'grep -q "/.local/bin" ~/.bashrc || echo ''export PATH="$HOME/.local/bin:$PATH"'' >> ~/.bashrc'
            wsl -d $selectedDist -- bash -c $pathCommand
            Write-Success "PATH updated in ~/.bashrc"
        }

        $profileExists = wsl -d $selectedDist -- test -f ~/.profile
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Adding to ~/.profile..."
            $pathCommand = 'grep -q "/.local/bin" ~/.profile || echo ''export PATH="$HOME/.local/bin:$PATH"'' >> ~/.profile'
            wsl -d $selectedDist -- bash -c $pathCommand
            Write-Success "PATH updated in ~/.profile"
        }
        
        Write-Warning "Please restart your WSL session or run: source ~/.bashrc"
    } else {
        Write-Success "PATH already includes ~/.local/bin"
    }
} else {
    Write-Success "System-wide installation - PATH not required"
}

Write-Host ""

# Test installation
Write-Info "Testing installation..."
$testResult = wsl -d $selectedDist -- bash -lc "xclip -version" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Success "xclip is working"
} else {
    Write-Warning "xclip test failed. You may need to restart your WSL session."
}

Write-Host ""

# Configure WSL Clip Bridge settings
Write-Question "Configure WSL Clip Bridge Settings?"
if (-not $AutoConfirm) {
    $configureSettings = Read-Host "Configure settings now? (y/n)"
} else {
    $configureSettings = "y"
}

if ($configureSettings -eq "y") {
    Write-Host ""
    Write-Info "Configuration Options:"
    Write-Host ""
    
    # TTL Configuration
    Write-Question "Clipboard TTL (Time To Live)"
    Write-Host "    How long should clipboard data persist?" -ForegroundColor Gray
    Write-Host "    Default: 300 seconds (5 minutes)" -ForegroundColor Gray
    
    if (-not $AutoConfirm) {
        $ttl = Read-Host "Enter TTL in seconds (or press Enter for default)"
        if (-not $ttl) { 
            $ttl = "300" 
        } elseif ($ttl -notmatch '^\d+$' -or [int]$ttl -lt 1 -or [int]$ttl -gt 86400) {
            Write-Warning "Invalid TTL value. Using default (300 seconds)"
            $ttl = "300"
        }
    } else {
        $ttl = "300"
    }
    
    # Image downscaling
    Write-Host ""
    Write-Question "Image Downscaling"
    Write-Host "    Automatically downscale large images for Claude API?" -ForegroundColor Gray
    Write-Host "    Recommended: 1568 pixels" -ForegroundColor Gray
    Write-Host "    Enter 0 to disable downscaling" -ForegroundColor Gray
    
    if (-not $AutoConfirm) {
        $maxDim = Read-Host "Maximum dimension in pixels (or press Enter for 1568)"
        if (-not $maxDim) { 
            $maxDim = "1568" 
        } elseif ($maxDim -notmatch '^\d+$' -or [int]$maxDim -lt 0 -or [int]$maxDim -gt 10000) {
            Write-Warning "Invalid dimension value. Using default (1568 pixels)"
            $maxDim = "1568"
        }
    } else {
        $maxDim = "1568"
    }
    
    # Security settings
    Write-Host ""
    Write-Question "Security Settings"
    Write-Host "    Restrict file access to home directory only?" -ForegroundColor Gray
    
    if (-not $AutoConfirm) {
        $restrictHome = Read-Host "Enable home restriction? (y/n) [y]"
        if (-not $restrictHome) { $restrictHome = "y" }
    } else {
        $restrictHome = "y"
    }
    
    # Create config file
    Write-Host ""
    Write-Info "Creating configuration file..."
    
    wsl -d $selectedDist -- mkdir -p ~/.config/wsl-clip-bridge
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create config directory"
        exit 1
    }
    
    $configContent = @"
# WSL Clip Bridge Configuration

# Clipboard TTL in seconds
ttl_secs = $ttl

# Maximum image dimension (0 = no downscaling)
max_image_dimension = $maxDim

# Security settings
max_file_size_mb = 100
restrict_to_home = $(if ($restrictHome -eq 'y') { 'true' } else { 'false' })
"@
    
    $tempConfigPath = Join-Path $env:TEMP "wsl-clip-config.toml"
    # Use Unix line endings for config file
    $configContent -replace "`r`n", "`n" | Out-File -FilePath $tempConfigPath -Encoding UTF8 -NoNewline
    
    # Copy config to WSL
    $wslConfigPath = wsl -d $selectedDist -- wslpath -u "$tempConfigPath"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to convert config path"
        Remove-Item $tempConfigPath -Force 2>$null
        exit 1
    }
    
    wsl -d $selectedDist -- cp "$wslConfigPath" ~/.config/wsl-clip-bridge/config.toml
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to copy config file"
        Remove-Item $tempConfigPath -Force 2>$null
        exit 1
    }
    Remove-Item $tempConfigPath -Force 2>$null
    
    Write-Success "Configuration saved"
}

Write-Host ""

# ShareX Integration
if (-not $SkipShareX) {
    Write-Question "Configure ShareX Integration?"
    if (-not $AutoConfirm) {
        $configureShareX = Read-Host "Setup ShareX integration? (y/n)"
    } else {
        $configureShareX = "n"
    }
    
    if ($configureShareX -eq "y") {
        Write-Host ""
        
        # Check if ShareX is installed and find config
        $shareXDir = Join-Path $env:USERPROFILE "Documents\ShareX"
        $configFile = Join-Path $shareXDir "ApplicationConfig.json"
        
        if (-not (Test-Path $shareXDir)) {
            Write-Question "ShareX directory not found at default location."
            $customDir = Read-Host "Enter ShareX documents directory path"
            if ($customDir) {
                $shareXDir = $customDir
                $configFile = Join-Path $shareXDir "ApplicationConfig.json"
            }
        }
        
        if (-not (Test-Path $configFile)) {
            Write-Question "ShareX config not found at: $configFile"
            $customConfig = Read-Host "Enter full path to ApplicationConfig.json"
            if ($customConfig) {
                $configFile = $customConfig
                $shareXDir = Split-Path $configFile -Parent
            }
        }
        
        if (-not (Test-Path $configFile)) {
            Write-Error "ShareX configuration file not found. Cannot continue with automatic setup."
            Write-Host "    Please ensure ShareX is installed and has been run at least once." -ForegroundColor Gray
            if (-not $AutoConfirm) {
                Read-Host "`nPress Enter to continue"
            }
        } else {
            Write-Success "Found ShareX config: $configFile"
            Write-Host ""
            
            # Check if ShareX is running BEFORE we do anything
            $shareXProcess = Get-Process "ShareX" -ErrorAction SilentlyContinue
            if ($shareXProcess) {
                Write-Warning "ShareX is currently running."
                Write-Host "    ShareX MUST be closed before configuration files can be edited." -ForegroundColor Gray
                Write-Host ""
                
                if (-not $AutoConfirm) {
                    $closeShareX = Read-Host "Close ShareX now? (y/n)"
                } else {
                    $closeShareX = "y"
                }
                
                if ($closeShareX -eq "y") {
                    Write-Info "Closing ShareX..."
                    Stop-Process -Name "ShareX" -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                    Write-Success "ShareX closed"
                } else {
                    Write-Error "Cannot proceed with setup while ShareX is running."
                    Write-Host "    Please close ShareX manually and run setup again." -ForegroundColor Gray
                    if (-not $AutoConfirm) {
                        Read-Host "`nPress Enter to continue"
                    }
                }
            }
            
            if (-not (Get-Process "ShareX" -ErrorAction SilentlyContinue)) {
                $toolsDir = Join-Path $shareXDir "Tools"
                
                # Create Tools directory
                Write-Info "Creating Tools directory..."
                New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
                
                # Create the action script
                Write-Info "Creating ShareX action script..."
                $scriptPath = Join-Path $toolsDir "copy-image-to-wsl-clipboard.bat"
                
                # Validate distribution name one more time for safety
                if (-not (Test-DistributionName $selectedDist)) {
                    Write-Error "Cannot create ShareX script with invalid distribution name"
                    return
                }
                
                # Use a safer approach with escaped distribution name
                $safeDistName = $selectedDist -replace '[^a-zA-Z0-9_-]', ''
                
                $scriptContent = @"
@echo off
rem WSL Clip Bridge - ShareX Action Script
rem Auto-generated by setup.ps1

if "%~1"=="" (
    echo Error: No file path provided
    exit /b 1
)

rem Convert Windows path to WSL path and copy to clipboard
for /f "usebackq tokens=*" %%i in (`wsl -d $safeDistName wslpath -u "%~1"`) do set WSLPATH=%%i
wsl -d $safeDistName bash -lc "xclip -selection clipboard -t image/png -i \"%WSLPATH%\""

if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to copy image to WSL clipboard
    exit /b %ERRORLEVEL%
)
"@
                
                $scriptContent | Out-File -FilePath $scriptPath -Encoding ASCII -NoNewline
                Write-Success "Action script created: $scriptPath"
                Write-Host ""
                
                # Setup method choice
                Write-Question "ShareX Configuration Method:"
                Write-Host "    1. Automatic - I'll update your ShareX config (recommended)"
                Write-Host "    2. Manual - I'll show you the steps to do it yourself"
                Write-Host ""
                
                if (-not $AutoConfirm) {
                    $setupMethod = Read-Host "Select method (1-2) [1]"
                    if (-not $setupMethod) { $setupMethod = "1" }
                } else {
                    $setupMethod = "1"
                }
                
                if ($setupMethod -eq "1") {
                    # Automatic setup
                    Write-Host ""
                    Write-Info "Preparing automatic configuration..."
                    
                    # Backup existing config
                    Write-Info "Creating backup of ApplicationConfig.json..."
                    $backupPath = "$configFile.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
                    Copy-Item $configFile $backupPath -Force
                    Write-Success "Backup created"
                    
                    # Update ShareX configuration
                    Write-Info "Updating ShareX configuration..."
                    
                    try {
                        $json = Get-Content $configFile -Raw | ConvertFrom-Json
                        
                        # Check if action already exists
                        $actionName = "Copy Image to WSL Clipboard"
                        $existingAction = $json.DefaultTaskSettings.ExternalPrograms | Where-Object { $_.Name -eq $actionName }
                        
                        if ($existingAction) {
                            Write-Warning "Action '$actionName' already exists. Updating..."
                            $existingAction.Path = $scriptPath
                            $existingAction.Args = '"%input"'
                            $existingAction.IsActive = $true
                            $existingAction.HiddenWindow = $true
                        } else {
                            Write-Info "Adding new action: $actionName"
                            $newAction = [PSCustomObject]@{
                                IsActive = $true
                                Name = $actionName
                                Path = $scriptPath
                                Args = '"%input"'
                                OutputExtension = ""
                                Extensions = ""
                                HiddenWindow = $true
                                DeleteInputFile = $false
                            }
                            $json.DefaultTaskSettings.ExternalPrograms += $newAction
                        }
                        
                        # Update AfterCaptureJob to include PerformActions
                        $afterCapture = $json.DefaultTaskSettings.AfterCaptureJob
                        if ($afterCapture -notmatch "PerformActions") {
                            $json.DefaultTaskSettings.AfterCaptureJob = $afterCapture + ", PerformActions"
                            Write-Info "Added PerformActions to After Capture tasks"
                        }
                        
                        # Save the updated config
                        $json | ConvertTo-Json -Depth 100 | Set-Content $configFile -Encoding UTF8
                        Write-Success "ShareX configuration updated successfully"
                        
                        Write-Host ""
                        Write-Success "ShareX has been configured automatically!"
                        Write-Host ""
                        Write-Host "    The following has been set up:" -ForegroundColor Gray
                        Write-Host "    - Custom action: `"Copy Image to WSL Clipboard`"" -ForegroundColor Gray
                        Write-Host "    - Action script: $scriptPath" -ForegroundColor Gray
                        Write-Host "    - After capture tasks updated to include the action" -ForegroundColor Gray
                        Write-Host ""
                        Write-Host "    To use:" -ForegroundColor Gray
                        Write-Host "    1. Start ShareX" -ForegroundColor Gray
                        Write-Host "    2. Take a screenshot (it will auto-copy to WSL)" -ForegroundColor Gray
                        Write-Host "    3. Press Ctrl+V in Claude Code to paste" -ForegroundColor Gray
                        Write-Host ""
                        
                        if (-not $AutoConfirm) {
                            $startShareX = Read-Host "Start ShareX now? (y/n)"
                            if ($startShareX -eq "y") {
                                Write-Info "Starting ShareX..."
                                $shareXPath = "${env:ProgramFiles}\ShareX\ShareX.exe"
                                if (-not (Test-Path $shareXPath)) {
                                    $shareXPath = "${env:ProgramFiles(x86)}\ShareX\ShareX.exe"
                                }
                                if (Test-Path $shareXPath) {
                                    Start-Process $shareXPath
                                } else {
                                    Write-Warning "Could not find ShareX executable"
                                }
                            }
                        }
                        
                    } catch {
                        Write-Error "Failed to update ShareX configuration automatically."
                        Write-Host "    Error: $_" -ForegroundColor Gray
                        Write-Host "    Please use manual setup instead." -ForegroundColor Gray
                    }
                    
                } else {
                    # Manual setup
                    Write-Host ""
                    Write-Info "Manual ShareX Configuration Instructions:"
                    Write-Host ""
                    Write-Host "    1. Open ShareX" -ForegroundColor Gray
                    Write-Host "    2. Go to: Task Settings -> Actions" -ForegroundColor Gray
                    Write-Host "    3. Click `"Add`" to create new action:" -ForegroundColor Gray
                    Write-Host "       Name: Copy Image to WSL Clipboard" -ForegroundColor Gray
                    Write-Host "       File: $scriptPath" -ForegroundColor Gray
                    Write-Host '       Arguments: "%input"' -ForegroundColor Gray
                    Write-Host "       [x] Hidden window" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "    4. Go to: Task Settings -> After capture tasks" -ForegroundColor Gray
                    Write-Host "    5. Enable:" -ForegroundColor Gray
                    Write-Host "       [x] Save image to file" -ForegroundColor Gray
                    Write-Host '       [x] Perform actions -> "Copy Image to WSL Clipboard"' -ForegroundColor Gray
                    Write-Host ""
                    
                    if (-not $AutoConfirm) {
                        Read-Host "Press Enter when you've completed ShareX setup"
                    }
                }
            }
        }
    }
}

Write-Host ""

# Test the full pipeline
Write-Question "Test Installation?"
if (-not $AutoConfirm) {
    $testInstall = Read-Host "Would you like to test the clipboard? (y/n)"
} else {
    $testInstall = "n"
}

if ($testInstall -eq "y") {
    Write-Host ""
    Write-Info "Creating test file..."
    $testFile = Join-Path $env:TEMP "test-clipboard.txt"
    "Test content from Windows" | Out-File -FilePath $testFile -Encoding UTF8 -NoNewline
    
    Write-Info "Copying to WSL clipboard..."
    $wslTestPath = wsl -d $selectedDist -- wslpath -u "$testFile"
    wsl -d $selectedDist -- bash -lc "cat '$wslTestPath' | xclip -selection clipboard -i"
    
    Write-Info "Reading from WSL clipboard..."
    $clipContent = wsl -d $selectedDist -- bash -lc "xclip -selection clipboard -o"
    Write-Host $clipContent
    
    Remove-Item $testFile -Force 2>$null
    Write-Host ""
    Write-Success "If you saw `"Test content from Windows`" above, the installation is working!"
}

Write-Host ""

# Summary
Write-Host ("=" * 64) -ForegroundColor Cyan
Write-Host "                    Installation Complete!" -ForegroundColor Green
Write-Host ("=" * 64) -ForegroundColor Cyan
Write-Host ""
Write-Host " Summary:" -ForegroundColor White
Write-Host " --------" -ForegroundColor Gray
Write-Host "   WSL Distribution: $selectedDist"
Write-Host "   Architecture: $arch"
Write-Host "   Binary Location: $installPath/xclip"
Write-Host "   Config Location: ~/.config/wsl-clip-bridge/config.toml"
Write-Host ""

if ($configureShareX -eq "y" -and $scriptPath) {
    Write-Host "   ShareX Action: $scriptPath"
    Write-Host ""
}

Write-Host " Usage Examples:" -ForegroundColor White
Write-Host " --------------" -ForegroundColor Gray
Write-Host '   Copy text:    echo "Hello" | xclip -i'
Write-Host "   Paste text:   xclip -o"
Write-Host "   Copy image:   xclip -t image/png -i screenshot.png"
Write-Host ""
Write-Host " For Claude Code:" -ForegroundColor White
Write-Host " ---------------" -ForegroundColor Gray
Write-Host "   1. Copy image with ShareX (if configured)"
Write-Host "   2. Press Ctrl+V in Claude Code to paste"
Write-Host ""
Write-Host " Thank you for using WSL Clip Bridge!" -ForegroundColor Green
Write-Host ""

if (-not $AutoConfirm) {
    Read-Host "Press Enter to exit"
}