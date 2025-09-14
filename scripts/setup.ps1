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
    Write-Host "  [OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [>] " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [X] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Question {
    param([string]$Message)
    Write-Host "  ? " -ForegroundColor Magenta -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Section {
    param([string]$Title)
    Write-Host "`n" -NoNewline
    Write-Host "--- " -ForegroundColor DarkGray -NoNewline
    Write-Host $Title -ForegroundColor Cyan -NoNewline
    Write-Host " " -NoNewline
    $remaining = 60 - $Title.Length - 4
    if ($remaining -gt 0) {
        Write-Host ("-" * $remaining) -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }
}

function Write-Step {
    param(
        [string]$Step,
        [int]$Current,
        [int]$Total
    )
    $percentage = [math]::Round(($Current / $Total) * 100)
    Write-Host "`r  [" -NoNewline
    Write-Host ("$percentage%").PadLeft(4) -ForegroundColor Yellow -NoNewline
    Write-Host "] " -NoNewline

    # Progress bar
    $barWidth = 20
    $filled = [math]::Floor(($Current / $Total) * $barWidth)
    $empty = $barWidth - $filled

    Write-Host "[" -ForegroundColor DarkGray -NoNewline
    Write-Host ("#" * $filled) -ForegroundColor Green -NoNewline
    Write-Host ("." * $empty) -ForegroundColor DarkGray -NoNewline
    Write-Host "]" -ForegroundColor DarkGray -NoNewline
    Write-Host " $Step" -NoNewline
}

# Clear screen and show header
Clear-Host
Write-Header

# Check for WSL
Write-Section "System Requirements"
Write-Info "Checking WSL installation..."
try {
    wsl --status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "WSL is not installed"
    }
    Write-Success "WSL detected"
} catch {
    Write-Err "WSL is not installed or not accessible."
    Write-Host "    Please install WSL2 first: wsl --install" -ForegroundColor Gray
    if (-not $AutoConfirm) {
        Read-Host "`nPress Enter to exit"
    }
    exit 1
}

# Get WSL distributions
Write-Section "WSL Configuration"
Write-Info "Detecting WSL distributions..."
$distributions = @(wsl --list --quiet 2>$null | Where-Object { $_ -match '\S' } | ForEach-Object {
    $_.Trim() -replace '\0', '' -replace '[^\x20-\x7E]', ''
} | Where-Object { $_ })

if ($distributions.Count -eq 0) {
    Write-Err "No WSL distributions found."
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
        Write-Warn "Specified distribution '$WSLDistribution' not found"
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
        Write-Host ""
        Write-Host "  Available WSL Distributions:" -ForegroundColor White
        Write-Host "  " -NoNewline
        Write-Host ("-" * 40) -ForegroundColor DarkGray

        # Find default (usually Ubuntu or first in list)
        $defaultChoice = 1
        for ($i = 0; $i -lt $distributions.Count; $i++) {
            if ($distributions[$i] -match "Ubuntu") {
                $defaultChoice = $i + 1
            }
            $isDefault = (($i + 1) -eq $defaultChoice)
            if ($isDefault) {
                Write-Host "   >" -ForegroundColor Green -NoNewline
            } else {
                Write-Host "    " -NoNewline
            }
            Write-Host " [$($i + 1)] " -ForegroundColor Yellow -NoNewline
            Write-Host $distributions[$i] -ForegroundColor White -NoNewline
            if ($isDefault) {
                Write-Host " (recommended)" -ForegroundColor Green
            } else {
                Write-Host ""
            }
        }
        Write-Host "  " -NoNewline
        Write-Host ("-" * 40) -ForegroundColor DarkGray
        Write-Host ""

        $choice = Read-Host "  Select distribution [1-$($distributions.Count)] (default: $defaultChoice)"
        if (-not $choice) { $choice = $defaultChoice }
        $choiceNum = $choice -as [int]

        while (-not $choiceNum -or $choiceNum -lt 1 -or $choiceNum -gt $distributions.Count) {
            Write-Warn "Invalid selection. Please enter a number between 1 and $($distributions.Count)"
            $choice = Read-Host "  Select distribution [1-$($distributions.Count)] (default: $defaultChoice)"
            if (-not $choice) { $choice = $defaultChoice }
            $choiceNum = $choice -as [int]
        }

        $selectedDist = $distributions[$choiceNum - 1]
        Write-Success "Selected: $selectedDist"
    }
}

# Final validation of distribution name
if ($selectedDist -and -not (Test-DistributionName $selectedDist)) {
    Write-Err "Invalid distribution name format: $selectedDist"
    Write-Host "    Distribution names should only contain letters, numbers, hyphens, and underscores" -ForegroundColor Gray
    if (-not $AutoConfirm) {
        Read-Host "`nPress Enter to exit"
    }
    exit 1
}

# Detect architecture
Write-Section "System Architecture"
Write-Step -Step "Detecting architecture" -Current 1 -Total 3
$arch = "amd64"
$osArch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
if ($osArch -match "ARM") {
    $arch = "arm64"
    Write-Success "Windows: ARM64 architecture"
} else {
    Write-Success "Windows: x64/AMD64 architecture"
}

Write-Step -Step "Checking WSL architecture" -Current 2 -Total 3
$wslArch = wsl -d $selectedDist -- uname -m 2>$null
if ($wslArch -eq "x86_64") {
    $arch = "amd64"
    Write-Success "WSL: x64/AMD64 architecture"
} elseif ($wslArch -eq "aarch64") {
    $arch = "arm64"
    Write-Success "WSL: ARM64 architecture"
}

Write-Step -Step "Architecture detection complete" -Current 3 -Total 3
Write-Host "`n"

# GitHub repository setup - skip if using default
$githubRepo = "camjac251/wsl-clip-bridge"
if (-not $AutoConfirm) {
    # Only ask if user might want to customize
    Write-Host ""
    Write-Info "Default repository: $githubRepo"
    $useCustom = Read-Host "  Use custom GitHub repository? (y/N)"
    if ($useCustom -eq "y" -or $useCustom -eq "Y") {
        Write-Question "Enter repository (format: owner/repo)"
        $customRepo = Read-Host "  Repository"
        if ($customRepo) {
            # Validate repository format
            if ($customRepo -notmatch '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$') {
                Write-Err "Invalid repository format. Using default."
            } else {
                $githubRepo = $customRepo
                Write-Success "Using custom repository: $githubRepo"
            }
        }
    }
}

# Installation location
Write-Section "Installation Location"
Write-Host ""
Write-Host "  Choose where to install xclip:" -ForegroundColor White
Write-Host "  " -NoNewline
Write-Host ("-" * 50) -ForegroundColor DarkGray
Write-Host "   >" -ForegroundColor Green -NoNewline
Write-Host " [1] " -ForegroundColor Yellow -NoNewline
Write-Host "User directory " -ForegroundColor White -NoNewline
Write-Host "(~/.local/bin)" -ForegroundColor Gray -NoNewline
Write-Host " [Recommended]" -ForegroundColor Green
Write-Host "        No sudo required, per-user installation" -ForegroundColor Gray
Write-Host ""
Write-Host "     [2] " -ForegroundColor Yellow -NoNewline
Write-Host "System-wide " -ForegroundColor White -NoNewline
Write-Host "(/usr/local/bin)" -ForegroundColor Gray
Write-Host "        Requires sudo, available to all users" -ForegroundColor Gray
Write-Host "  " -NoNewline
Write-Host ("-" * 50) -ForegroundColor DarkGray
Write-Host ""

if (-not $AutoConfirm) {
    $installLocation = Read-Host "  Select location [1-2] (default: 1)"
    if (-not $installLocation) { $installLocation = "1" }
} else {
    $installLocation = "1"
}

$installPath = '$HOME/.local/bin'
$installDirCmd = 'mkdir -p $HOME/.local/bin'
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

# Installation method - default to download
Write-Section "Installation Method"

# Auto-select download method unless explicitly building
$installMethod = "1"
if (-not $AutoConfirm) {
    Write-Host ""
    Write-Host "  Installation will download the latest release." -ForegroundColor White
    Write-Host "  This is the fastest and recommended method." -ForegroundColor Gray
    Write-Host ""
    $customMethod = Read-Host "  Press Enter to continue, or type 'build' to compile from source"
    if ($customMethod -match "build|source|compile") {
        $installMethod = "2"
        Write-Info "Switching to build from source method"
    } else {
        Write-Success "Using quick download method"
    }
} else {
    Write-Success "Using quick download method"
}

switch ($installMethod) {
    "1" {
        # Download from GitHub releases
        Write-Section "Download & Installation"
        Write-Host ""

        $tempDir = Join-Path $env:TEMP "wsl-clip-bridge-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        $downloadUrl = "https://github.com/$githubRepo/releases/latest/download/xclip-$arch"
        Write-Host "  Source: " -NoNewline
        Write-Host $downloadUrl -ForegroundColor DarkCyan
        Write-Host ""

        $downloadPath = Join-Path $tempDir "xclip"

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            # Download the binary
            Write-Step -Step "Downloading binary" -Current 1 -Total 4
            Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
            Write-Success "Binary downloaded"

            # Try to download and verify checksum if available
            $checksumUrl = "$downloadUrl.sha256"
            $checksumPath = Join-Path $tempDir "xclip.sha256"

            try {
                Write-Step -Step "Downloading checksum" -Current 2 -Total 4
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
                        Write-Step -Step "Verifying checksum" -Current 3 -Total 4
                        Write-Success "Checksum verified successfully"
                    } else {
                        Write-Err "Checksum verification failed!"
                        Write-Host "    Expected: $expectedChecksum" -ForegroundColor Gray
                        Write-Host "    Actual:   $actualChecksum" -ForegroundColor Gray
                        Remove-Item $tempDir -Recurse -Force 2>$null
                        if (-not $AutoConfirm) {
                            Read-Host "`nPress Enter to exit"
                        }
                        exit 1
                    }
                } else {
                    Write-Warn "Checksum file not available, skipping verification"
                }
            } catch {
                Write-Warn "Could not verify checksum: $_"
            }

            Write-Step -Step "Download complete" -Current 4 -Total 4
            Write-Host ""
        } catch {
            Write-Err "Failed to download binary."
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
        # Replace backslashes with forward slashes for WSL compatibility
        $escapedPath = $downloadPath.Replace('\', '/')
        $wslTempPath = wsl -d $selectedDist -- wslpath -u "$escapedPath"
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Failed to convert Windows path to WSL path"
            Remove-Item $tempDir -Recurse -Force 2>$null
            exit 1
        }

        wsl -d $selectedDist -- bash -c "$installDirCmd"
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Failed to create installation directory"
            Remove-Item $tempDir -Recurse -Force 2>$null
            exit 1
        }

        wsl -d $selectedDist -- bash -c "$installCopyCmd '$wslTempPath' '$installPath/xclip'"
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Failed to copy binary to installation directory"
            Remove-Item $tempDir -Recurse -Force 2>$null
            exit 1
        }

        wsl -d $selectedDist -- bash -c "${needsSudo}chmod +x '$installPath/xclip'"
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Failed to set executable permissions"
            Remove-Item $tempDir -Recurse -Force 2>$null
            exit 1
        }

        if ($installLocation -eq "1") {
            Write-Success "Binary installed to ~/.local/bin/xclip"
        } else {
            Write-Success "Binary installed to /usr/local/bin/xclip"
        }

        # Cleanup
        Remove-Item $tempDir -Recurse -Force 2>$null
    }

    "2" {
        # Build from source
        Write-Info "Checking for Rust in WSL..."
        wsl -d $selectedDist -- which cargo 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Rust not found in WSL."
            Write-Host "    Install Rust first: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" -ForegroundColor Gray
            if (-not $AutoConfirm) {
                Read-Host "`nPress Enter to exit"
            }
            exit 1
        }

        Write-Info "Cloning repository..."
        wsl -d $selectedDist -- bash -c "git clone 'https://github.com/$githubRepo' \$HOME/wsl-clip-bridge 2>/dev/null"

        Write-Info "Building from source..."
        wsl -d $selectedDist -- bash -c "cd \$HOME/wsl-clip-bridge; cargo build --release"
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Build failed. Check error messages above."
            exit 1
        }

        Write-Info "Installing binary..."
        if ($installLocation -eq "1") {
            wsl -d $selectedDist -- bash -c "mkdir -p \$HOME/.local/bin; cp \$HOME/wsl-clip-bridge/target/release/xclip \$HOME/.local/bin/"
        } else {
            wsl -d $selectedDist -- bash -c "sudo cp \$HOME/wsl-clip-bridge/target/release/xclip /usr/local/bin/"
        }

        Write-Success "Build and installation complete"
    }

    "3" {
        # Use existing build
        Write-Info "Please ensure xclip is already installed in WSL."
    }

    default {
        Write-Err "Invalid selection."
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

    wsl -d $selectedDist -- bash -c 'echo "$PATH" | grep -q "$HOME/.local/bin"' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "~/.local/bin not found in PATH"

        # Check which shell config files exist
        wsl -d $selectedDist -- bash -c 'test -f $HOME/.bashrc' 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Adding to ~/.bashrc..."
            $pathCommand = "grep -q '/.local/bin' `$HOME/.bashrc; if [ `$? -ne 0 ]; then echo 'export PATH=`"`$HOME/.local/bin:`$PATH`"' >> `$HOME/.bashrc; fi"
            wsl -d $selectedDist -- bash -c $pathCommand
            Write-Success "PATH updated in ~/.bashrc"
        }

        wsl -d $selectedDist -- bash -c 'test -f $HOME/.profile' 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Info "Adding to ~/.profile..."
            $pathCommand = "grep -q '/.local/bin' `$HOME/.profile; if [ `$? -ne 0 ]; then echo 'export PATH=`"`$HOME/.local/bin:`$PATH`"' >> `$HOME/.profile; fi"
            wsl -d $selectedDist -- bash -c $pathCommand
            Write-Success "PATH updated in ~/.profile"
        }

        Write-Warn "Please restart your WSL session or run: source ~/.bashrc"
    } else {
        Write-Success "PATH already includes ~/.local/bin"
    }
} else {
    Write-Success "System-wide installation - PATH not required"
}

Write-Host ""

# Verify installation
Write-Info "Verifying installation..."
# Just check if xclip is found in PATH and is executable
$testResult = wsl -d $selectedDist -- bash -lc "which xclip" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Success "xclip installed at: $($testResult.Trim())"
} else {
    Write-Warn "xclip not found in PATH. You may need to restart your WSL session."
}

Write-Host ""

# Configure WSL Clip Bridge settings
Write-Section "Configuration"

# Use optimal defaults
$ttl = "300"  # 5 minutes
$maxDim = "1568"  # Optimal for Claude API
$restrictHome = "y"  # Security default

if (-not $AutoConfirm) {
    Write-Host ""
    Write-Host "  Configuration Options:" -ForegroundColor White
    Write-Host ""
    Write-Host "    * Clipboard TTL (Time-to-Live):" -ForegroundColor Cyan
    Write-Host "      How long clipboard data remains available" -ForegroundColor Gray
    Write-Host "      Default: 5 minutes (good for most workflows)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    * Image Optimization:" -ForegroundColor Cyan
    Write-Host "      Automatically downscale large screenshots to save bandwidth" -ForegroundColor Gray
    Write-Host "      Default: 1568px (optimal for Claude API)" -ForegroundColor Gray
    Write-Host "      Set to 0 to disable downscaling" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    * Security - Home Directory Restriction:" -ForegroundColor Cyan
    Write-Host "      Prevent access to files outside your home directory" -ForegroundColor Gray
    Write-Host "      Default: Enabled (recommended for security)" -ForegroundColor Gray
    Write-Host ""
    $customize = Read-Host "  Press Enter to use defaults, or type 'custom' to modify"

    if ($customize -eq "custom") {
        Write-Host ""
        Write-Host "  Custom Configuration" -ForegroundColor Cyan
        Write-Host "  " -NoNewline
        Write-Host ("-" * 20) -ForegroundColor DarkGray
        Write-Host ""

        # TTL
        Write-Host "  Clipboard TTL (1-86400 seconds):" -ForegroundColor White
        Write-Host "    Shorter = Data expires quickly, files cleaned up sooner" -ForegroundColor Gray
        Write-Host "    Longer  = Data stays available longer between copies" -ForegroundColor Gray
        $customTtl = Read-Host "  Enter value in seconds [300]"
        if ($customTtl -and $customTtl -match '^\d+$' -and [int]$customTtl -ge 1 -and [int]$customTtl -le 86400) {
            $ttl = $customTtl
        }
        Write-Host ""

        # Image size
        Write-Host "  Maximum Image Dimension (0-10000 pixels):" -ForegroundColor White
        Write-Host "    0    = No downscaling (keep original size)" -ForegroundColor Gray
        Write-Host "    1568 = Optimal for Claude API (recommended)" -ForegroundColor Gray
        Write-Host "    2048 = Good balance for quality vs size" -ForegroundColor Gray
        $customDim = Read-Host "  Enter max dimension [1568]"
        if ($customDim -and $customDim -match '^\d+$' -and [int]$customDim -ge 0 -and [int]$customDim -le 10000) {
            $maxDim = $customDim
        }
        Write-Host ""

        # Security
        Write-Host "  Security - Restrict File Access:" -ForegroundColor White
        Write-Host "    y = Only allow files from home directory (safer)" -ForegroundColor Gray
        Write-Host "    n = Allow files from anywhere (less secure)" -ForegroundColor Gray
        $customRestrict = Read-Host "  Enable restriction? (y/n) [y]"
        if ($customRestrict -match '^[nN]') {
            $restrictHome = "n"
        }
    }
}

$configureSettings = "y"
if ($configureSettings -eq "y") {

    # Create config file
    Write-Info "Creating configuration file..."

    wsl -d $selectedDist -- bash -c 'mkdir -p $HOME/.config/wsl-clip-bridge'
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to create config directory"
        exit 1
    }

    # Store ShareX config flag for later
    $script:shareXConfigured = $false

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
    # Write config as UTF-8 without BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $configBytes = $utf8NoBom.GetBytes(($configContent -replace "`r`n", "`n"))
    [System.IO.File]::WriteAllBytes($tempConfigPath, $configBytes)

    # Copy config to WSL
    # Replace backslashes with forward slashes for WSL compatibility
    $escapedConfigPath = $tempConfigPath.Replace('\', '/')
    $wslConfigPath = wsl -d $selectedDist -- wslpath -u "$escapedConfigPath"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to convert config path"
        Remove-Item $tempConfigPath -Force 2>$null
        exit 1
    }

    wsl -d $selectedDist -- bash -c "cp '$wslConfigPath' ~/.config/wsl-clip-bridge/config.toml"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to copy config file"
        Remove-Item $tempConfigPath -Force 2>$null
        exit 1
    }
    Remove-Item $tempConfigPath -Force 2>$null

    Write-Success "Configuration saved to ~/.config/wsl-clip-bridge/config.toml"
    Write-Host ""
    Write-Host "  Settings applied:" -ForegroundColor Gray
    Write-Host "    - Clipboard TTL: $ttl seconds" -ForegroundColor Gray
    Write-Host "    - Max image size: $(if ($maxDim -eq '0') { 'Disabled (original size)' } else { "$maxDim pixels" })" -ForegroundColor Gray
    Write-Host "    - Home restriction: $(if ($restrictHome -eq 'y') { 'Enabled (secure)' } else { 'Disabled' })" -ForegroundColor Gray
    Write-Host "    - ShareX dirs: Will be added if ShareX is configured" -ForegroundColor DarkGray
}

Write-Host ""

# ShareX Integration
if (-not $SkipShareX) {
    Write-Section "ShareX Integration"

    # Check if ShareX is installed first
    $shareXDir = Join-Path $env:USERPROFILE "Documents\ShareX"
    $configFile = Join-Path $shareXDir "ApplicationConfig.json"

    if (Test-Path $configFile) {
        Write-Host ""
        Write-Host "  [OK] ShareX detected!" -ForegroundColor Green
        Write-Host "  This will enable direct screenshot pasting into Claude Code." -ForegroundColor Gray
        Write-Host ""

        if (-not $AutoConfirm) {
            $configureShareX = Read-Host "  Configure ShareX integration? (Y/n)"
            if (-not $configureShareX) { $configureShareX = "y" }
        } else {
            $configureShareX = "y"  # Default to yes when ShareX is found
        }
    } else {
        # ShareX not found - skip silently unless user wants to set it up
        if (-not $AutoConfirm) {
            Write-Host ""
            Write-Host "  ShareX not detected. Skip for now? (Y/n)" -ForegroundColor Gray
            $skip = Read-Host "  "
            if ($skip -eq "n" -or $skip -eq "N") {
                Write-Question "Enter ShareX documents directory path"
                $customDir = Read-Host "  Path"
                if ($customDir) {
                    $shareXDir = $customDir
                    $configFile = Join-Path $shareXDir "ApplicationConfig.json"
                }
                $configureShareX = "y"
            } else {
                $configureShareX = "n"
            }
        } else {
            $configureShareX = "n"
        }
    }

    if ($configureShareX -eq "y") {

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
            Write-Err "ShareX configuration file not found. Cannot continue with automatic setup."
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
                Write-Warn "ShareX is currently running."
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
                    Write-Err "Cannot proceed with setup while ShareX is running."
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
                    Write-Err "Cannot create ShareX script with invalid distribution name"
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
for /f "usebackq tokens=*" %%i in (``wsl -d $safeDistName wslpath -u "%~1"``) do set WSLPATH=%%i
wsl -d $safeDistName bash -lc "xclip -selection clipboard -t image/png -i '%WSLPATH%'"

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
                            Write-Warn "Action '$actionName' already exists. Updating..."
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

                        # Update WSL config to allow ShareX directories
                        Write-Info "Updating WSL config to allow ShareX directories..."

                        # Get actual screenshot directory from ShareX config
                        $screenshotsFolder = $json.DefaultTaskSettings.ScreenshotsFolder
                        if ([string]::IsNullOrEmpty($screenshotsFolder)) {
                            # Use default ShareX location
                            $screenshotsFolder = Join-Path $shareXDir "Screenshots"
                        }

                        # Convert Windows paths to WSL paths
                        $shareXDirEscaped = $shareXDir.Replace('\', '/')
                        $screenshotsDirEscaped = $screenshotsFolder.Replace('\', '/')
                        $wslShareXPath = wsl -d $selectedDist -- wslpath -u "$shareXDirEscaped" 2>$null
                        $wslScreenshotsPath = wsl -d $selectedDist -- wslpath -u "$screenshotsDirEscaped" 2>$null

                        # Read current config
                        $configPath = "~/.config/wsl-clip-bridge/config.toml"
                        $currentConfig = wsl -d $selectedDist -- bash -c "cat $configPath 2>/dev/null"

                        # Check if allowed_directories already exists
                        if ($currentConfig -notmatch "allowed_directories") {
                            # Build the allowed directories list
                            $allowedDirs = @"

# ShareX Integration - Allow access to ShareX directories
allowed_directories = [
"@

                            if ($wslShareXPath) {
                                $allowedDirs += "`n  `"$wslShareXPath`","
                            }
                            if ($wslScreenshotsPath -and ($wslScreenshotsPath -ne $wslShareXPath)) {
                                $allowedDirs += "`n  `"$wslScreenshotsPath`","
                            }
                            $allowedDirs += @"

  "/tmp"
]
"@

                            # Append directories to config
                            $tempConfigUpdate = Join-Path $env:TEMP "wsl-clip-config-update.txt"
                            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                            $updateBytes = $utf8NoBom.GetBytes(($allowedDirs -replace "`r`n", "`n"))
                            [System.IO.File]::WriteAllBytes($tempConfigUpdate, $updateBytes)

                            # Convert path and append to config
                            $escapedUpdatePath = $tempConfigUpdate.Replace('\', '/')
                            $wslUpdatePath = wsl -d $selectedDist -- wslpath -u "$escapedUpdatePath" 2>$null

                            if ($wslUpdatePath) {
                                wsl -d $selectedDist -- bash -c "cat '$wslUpdatePath' >> $configPath"
                                if ($LASTEXITCODE -eq 0) {
                                    Write-Success "Config updated to allow ShareX directories:"
                                    if ($wslShareXPath) {
                                        Write-Host "    - $wslShareXPath" -ForegroundColor Gray
                                    }
                                    if ($wslScreenshotsPath -and ($wslScreenshotsPath -ne $wslShareXPath)) {
                                        Write-Host "    - $wslScreenshotsPath" -ForegroundColor Gray
                                    }
                                    Write-Host "    - /tmp" -ForegroundColor Gray
                                    $script:shareXConfigured = $true
                                } else {
                                    Write-Warn "Could not update config for ShareX directories"
                                    Write-Host "    You may need to manually add ShareX paths to allowed_directories" -ForegroundColor Gray
                                }
                            }
                            Remove-Item $tempConfigUpdate -Force -ErrorAction SilentlyContinue 2>$null
                        } else {
                            Write-Info "Config already has allowed_directories configured"
                            $script:shareXConfigured = $true
                        }

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
                                    Write-Warn "Could not find ShareX executable"
                                }
                            }
                        }

                    } catch {
                        Write-Err "Failed to update ShareX configuration automatically."
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
                    Write-Host "    6. IMPORTANT: Add ShareX directories to WSL config:" -ForegroundColor Yellow
                    Write-Host "       Edit: ~/.config/wsl-clip-bridge/config.toml" -ForegroundColor Gray
                    Write-Host "       Add at the end:" -ForegroundColor Gray
                    Write-Host "       allowed_directories = [" -ForegroundColor DarkGray
                    # Convert ShareX paths for manual instructions
                    $shareXDirForWSL = $shareXDir.Replace('\', '/').Replace('C:', '/mnt/c')
                    Write-Host "         `"$shareXDirForWSL`"," -ForegroundColor DarkGray
                    Write-Host "         `"$shareXDirForWSL/Screenshots`"," -ForegroundColor DarkGray
                    Write-Host "         `"/tmp`"" -ForegroundColor DarkGray
                    Write-Host "       ]" -ForegroundColor DarkGray
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

# Quick test - do it automatically
Write-Section "Quick Test"
Write-Host ""
Write-Info "Running quick clipboard test..."
$testFile = Join-Path $env:TEMP "test-clipboard.txt"
"WSL Clip Bridge Test" | Out-File -FilePath $testFile -Encoding ASCII -NoNewline

# Replace backslashes with forward slashes for WSL compatibility
$escapedTestPath = $testFile.Replace('\', '/')
$wslTestPath = wsl -d $selectedDist -- wslpath -u "$escapedTestPath" 2>$null

if ($wslTestPath) {
    wsl -d $selectedDist -- bash -lc "cat '$wslTestPath' | xclip -selection clipboard -i -t text/plain" 2>$null
    $clipContent = wsl -d $selectedDist -- bash -lc "xclip -selection clipboard -o -t text/plain" 2>$null

    if ($clipContent -eq "WSL Clip Bridge Test") {
        Write-Success "Clipboard test passed successfully"
    } else {
        Write-Warn "Clipboard test inconclusive - may need to restart WSL session"
    }
} else {
    Write-Warn "Test skipped - restart WSL session to test"
}

Remove-Item $testFile -Force -ErrorAction SilentlyContinue 2>$null

Write-Host ""

# Summary
Write-Host "`n"
Write-Host ("=" * 64) -ForegroundColor Green
Write-Host "              Installation Complete!" -ForegroundColor Green
Write-Host ("=" * 64) -ForegroundColor Green

Write-Host ""
Write-Host "  Installation Details:" -ForegroundColor Cyan
Write-Host "  " -NoNewline
Write-Host ("-" * 20) -ForegroundColor DarkGray
Write-Host "  Distribution: " -NoNewline
Write-Host $selectedDist -ForegroundColor Yellow
Write-Host "  Architecture: " -NoNewline
Write-Host $arch -ForegroundColor Yellow

if ($installLocation -eq "1") {
    Write-Host "  Binary Path:  " -NoNewline
    Write-Host "~/.local/bin/xclip" -ForegroundColor Yellow
} else {
    Write-Host "  Binary Path:  " -NoNewline
    Write-Host "/usr/local/bin/xclip" -ForegroundColor Yellow
}

Write-Host "  Config Path:  " -NoNewline
Write-Host "~/.config/wsl-clip-bridge/config.toml" -ForegroundColor Yellow

if ($configureShareX -eq "y" -and $scriptPath) {
    Write-Host ""
    Write-Host "  ShareX Integration:" -ForegroundColor Cyan
    Write-Host "  " -NoNewline
    Write-Host ("-" * 18) -ForegroundColor DarkGray
    Write-Host "  [OK] Configured and ready" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Quick Start:" -ForegroundColor Cyan
Write-Host "  " -NoNewline
Write-Host ("-" * 11) -ForegroundColor DarkGray

if ($configureShareX -eq "y") {
    Write-Host "  1. Take a screenshot with ShareX" -ForegroundColor White
    Write-Host "  2. Open Claude Code (claude.ai/code)" -ForegroundColor White
    Write-Host "  3. Press " -NoNewline
    Write-Host "Ctrl+V" -ForegroundColor Yellow -NoNewline
    Write-Host " to paste the image" -ForegroundColor White
} else {
    Write-Host "  Copy text:  " -NoNewline
    Write-Host "echo 'Hello' | xclip -i" -ForegroundColor Yellow
    Write-Host "  Paste text: " -NoNewline
    Write-Host "xclip -o" -ForegroundColor Yellow
    Write-Host "  Copy image: " -NoNewline
    Write-Host "xclip -t image/png -i file.png" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Enjoy seamless clipboard sharing!" -ForegroundColor Green
Write-Host ""

if (-not $AutoConfirm) {
    Read-Host "Press Enter to exit"
}