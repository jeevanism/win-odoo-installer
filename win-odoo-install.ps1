#Requires -Version 5.1

function Write-Styled-Host {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$ForegroundColor = "White",

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$BackgroundColor = "Black"
    )
    
    $OriginalForegroundColor = $Host.UI.RawUI.ForegroundColor
    $OriginalBackgroundColor = $Host.UI.RawUI.BackgroundColor
    
    $Host.UI.RawUI.ForegroundColor = $ForegroundColor
    $Host.UI.RawUI.BackgroundColor = $BackgroundColor
    
    Write-Host $Message
    
    $Host.UI.RawUI.ForegroundColor = $OriginalForegroundColor
    $Host.UI.RawUI.BackgroundColor = $OriginalBackgroundColor
}
<#
.SYNOPSIS
    An installer script for setting up a local Odoo development environment on Windows 11.
.DESCRIPTION
    This script handles prerequisites, Git cloning, Python virtual environment creation using 'uv',
    dependency installation with a fallback for compilation errors (like libsass), and configuration file generation.
.NOTES
    Requires Git and PowerShell 5.1+. Assumes 'Write-Styled-Host' function is defined elsewhere
    to provide colored output.
#>

# ==============================================================================
# Global Configuration and Utility (Assuming Write-Styled-Host is defined)
# ==============================================================================

# Map Odoo versions to required Python versions (adjust as needed)
$OdooVersions = @{
    "19.0" = "3.12";
    "18.0" = "3.12";
    "17.0" = "3.11";
    "16.0" = "3.10";
    "15.0" = "3.10"; 
    "14.0" = "3.10"; 
}

$OdooRepoUrl = "https://github.com/odoo/odoo.git"

# Fallback Wheel Configuration for Libsass (to bypass MSVC compiler errors)
$LibsassWheelUrl = "https://raw.githubusercontent.com/jeevanism/win-odoo-installer/main/wheels/libsass/libsass-0.20.1-cp310-cp310-win_amd64.whl"
$LibsassWheelName = 'libsass-0.20.1-cp310-cp310-win_amd64.whl'

function Check-Prerequisites {
    Write-Styled-Host "Step 1: Checking prerequisites (Git, uv)..." -ForegroundColor "Cyan"
    # Check for Git (Simplified check)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Styled-Host "Error: Git is not installed or not in PATH." -ForegroundColor "Red"
        Write-Styled-Host "--------------------------------------------------------------------------------" -ForegroundColor "Red"
        Write-Styled-Host "                       *** ACTION REQUIRED ***" -ForegroundColor "Red"
        Write-Styled-Host "Please install Git manually from the official website:" -ForegroundColor "White"
        Write-Styled-Host "--> https://git-scm.com/" -ForegroundColor "DarkYellow"
        Write-Styled-Host " " -ForegroundColor "Red"
        Write-Styled-Host "TROUBLESHOOTING TIP (If Git is installed but still not found):" -ForegroundColor "Red"
        Write-Styled-Host "1. Close and reopen your PowerShell terminal." -ForegroundColor "White"
        Write-Styled-Host "2. If that fails, manually add 'C:\Program Files\Git\cmd' to your user or system PATH environment variables." -ForegroundColor "White"
        Write-Styled-Host "--------------------------------------------------------------------------------" -ForegroundColor "Red"
        exit 1
    }
    Write-Styled-Host "  [OK] Git is installed." -ForegroundColor "Green"

    # Check for uv
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Styled-Host "Warning: 'uv' is not found. It is a required tool for Python environment management." -ForegroundColor "Yellow"
        $installChoice = Read-Host "Do you want to install it now? (y/n)"
        if ($installChoice -eq 'y') {
            Write-Styled-Host "Installing uv..." -ForegroundColor "Cyan"
            try {
                Invoke-Expression -Command "powershell -ExecutionPolicy ByPass -c 'irm https://astral.sh/uv/install.ps1 | iex'"
                Write-Styled-Host "  [OK] uv installed successfully." -ForegroundColor "Green"
                Write-Styled-Host "Please restart your terminal and run the script again to ensure 'uv' is available in your PATH." -ForegroundColor "Yellow"
                exit 0
            }
            catch {
                Write-Styled-Host "Error: Failed to install uv. Please install it manually from https://github.com/astral-sh/uv" -ForegroundColor "Red"
                exit 1
            }
        }
        else {
            Write-Styled-Host "Installation aborted by user." -ForegroundColor "Red"
            exit 1
        }
    }
    Write-Styled-Host "  [OK] uv is installed." -ForegroundColor "Green"
}

function Select-Odoo-Version {
    Write-Styled-Host "Step 2: Select the Odoo version to install" -ForegroundColor "Cyan"
    $versionKeys = $OdooVersions.Keys | Sort-Object -Descending
    for ($i = 0; $i -lt $versionKeys.Count; $i++) {
        Write-Host ("[{0}] {1} (Python {2})" -f ($i + 1), $versionKeys[$i], $OdooVersions[$versionKeys[$i]])
    }

    $choice = Read-Host "Enter the number of your choice"
    $index = [int]$choice - 1

    if ($index -ge 0 -and $index -lt $versionKeys.Count) {
        return $versionKeys[$index]
    }
    else {
        Write-Styled-Host "Invalid selection. Please run the script again." -ForegroundColor "Red"
        exit 1
    }
}

function Generate-Odoo-Conf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OdooVersion,
        [Parameter(Mandatory = $true)]
        [string]$BaseInstallPath, # This will be the new parent (e.g., odoo-19)
        [Parameter(Mandatory = $true)]
        [string]$OdooCloneDir # This will be the git clone folder (e.g., odoo-19/odoo-src)
    )

    Write-Styled-Host "Step 6: Generating odoo.conf file..." -ForegroundColor "Cyan"

    # Calculate ports: e.g., 17.0 -> 8017
    $MajorVersion = ($OdooVersion -split '\.')[0]
    $HttpPort = "80" + $MajorVersion
    $LongpollingPort = "8072" # Standard longpolling port is 8072/8073, using fixed 8072 for simplicity
    
    # Paths are relative to BaseInstallPath (the new odoo-XX folder)
    $confFilePath = Join-Path -Path $BaseInstallPath -ChildPath "odoo.conf"
    $dataDir = Join-Path -Path $BaseInstallPath -ChildPath "data"
    $customAddonsDir = Join-Path -Path $BaseInstallPath -ChildPath "custom-addons"
    
    # Core Odoo Addons Paths
    # OdooCloneDir is now the source code directory inside the parent folder
    $OdooCoreInternalAddons = Join-Path -Path $OdooCloneDir -ChildPath "odoo\addons"
    $OdooCoreExternalAddons = Join-Path -Path $OdooCloneDir -ChildPath "addons"
    
    # Create data and custom-addons directories if they don't exist (inside BaseInstallPath)
    if (-not (Test-Path $dataDir)) { New-Item -Path $dataDir -ItemType Directory | Out-Null }
    if (-not (Test-Path $customAddonsDir)) { New-Item -Path $customAddonsDir -ItemType Directory | Out-Null }

    # Generate addons_path using forward slashes (Unix style) for config file reliability
    # ESCAPE FIX: Use '\\' to match literal backslash in a regex pattern
    $addonsPath = "$($customAddonsDir -replace '\\','/'),$($OdooCoreExternalAddons -replace '\\','/'),$($OdooCoreInternalAddons -replace '\\','/')"

    $confContent = @"
[options]
# This is the password that allows database operations:
admin_passwd = admin

# --- Connection Settings ---
http_port = $HttpPort
xmlrpc_port = $HttpPort
longpolling_port = $LongpollingPort

# --- Database Connection (Requires PostgreSQL) ---
db_host = False
db_port = False
db_user = False
db_password = False
db_maxconn = 64

# --- Paths ---
# ESCAPE FIX: Use '\\' to match literal backslash in a regex pattern
data_dir = $($dataDir -replace '\\','/')
addons_path = $addonsPath

# --- Development & Logging ---
log_level = info
list_db = True
proxy_mode = False
debug_mode = False
without_demo = False
workers = 2
server_wide_modules = web,queue_job
"@

    Set-Content -Path $confFilePath -Value $confContent -Encoding UTF8
    Write-Styled-Host "  [OK] odoo.conf generated successfully at '$confFilePath'." -ForegroundColor "Green"
}


# --- Main Script ---
try {
    $originalLocation = Get-Location
    Check-Prerequisites

    $selectedOdooVersion = Select-Odoo-Version
    $requiredPythonVersion = $OdooVersions[$selectedOdooVersion]
    
    # ----------------------------------------------------
    # NEW LOGIC: Define and create the new parent folder
    # ----------------------------------------------------
    $MajorVersion = ($selectedOdooVersion -split '\.')[0]
    $parentInstallFolderName = "odoo-$MajorVersion" # e.g., odoo-19
    $parentInstallDir = Join-Path -Path $originalLocation -ChildPath $parentInstallFolderName
    
    # The git clone directory will be a subfolder named 'odoo-src' inside the parent folder
    $cloneDir = Join-Path -Path $parentInstallDir -ChildPath "odoo-src"
    
    Write-Styled-Host "Step 3: Creating installation structure in '$parentInstallDir'..." -ForegroundColor "Cyan"
    
    # Create the new parent directory
    if (-not (Test-Path $parentInstallDir)) {
        New-Item -Path $parentInstallDir -ItemType Directory | Out-Null
    }
    
    # Check and handle existing clone directory
    if (Test-Path $cloneDir) {
        $overwriteChoice = Read-Host "Odoo source directory '$cloneDir' already exists. Do you want to remove it and clone again? (y/n)"
        if ($overwriteChoice -eq 'y') {
            if ($PSCmdlet.ShouldProcess($cloneDir, "Removing directory")) {
                Remove-Item -Path $cloneDir -Recurse -Force
            }
        }
        else {
            Write-Styled-Host "Operation cancelled by user. Using existing source directory." -ForegroundColor "Yellow"
        }
    }

    # Perform clone if directory does not exist or was just removed
    if (-not (Test-Path $cloneDir)) {
        $gitCommand = "git clone --branch $selectedOdooVersion --single-branch $OdooRepoUrl `"$cloneDir`""
        Write-Host "Executing: $gitCommand"
        Invoke-Expression $gitCommand
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone Odoo repository."
        }
        Write-Styled-Host "  [OK] Odoo $selectedOdooVersion cloned successfully to '$cloneDir'." -ForegroundColor "Green"
    }


    # Change location to the CLONE directory to find requirements.txt and create .venv
    Set-Location $parentInstallDir

    Write-Styled-Host "Step 4: Setting up Python environment..." -ForegroundColor "Cyan"
    
    # Create virtual environment (uv creates it as .venv inside the current location: $cloneDir)
    $venvCommand = "uv venv --python $requiredPythonVersion"
    Write-Host "Executing: $venvCommand"
    Invoke-Expression $venvCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create Python virtual environment. Ensure Python $requiredPythonVersion is available via 'uv'."
    }
    Write-Styled-Host "  [OK] Python virtual environment created with Python $requiredPythonVersion." -ForegroundColor "Green"
    Set-Location $cloneDir

    # ==============================================================================
    # UPDATED STEP 5: Dependency Installation with Libsass Fallback
    # ==============================================================================
    Write-Styled-Host "Step 5: Installing dependencies from requirements.txt..." -ForegroundColor "Cyan"
    $requirementsFile = ".\requirements.txt"
    if (-not (Test-Path $requirementsFile)) {
        throw "Could not find requirements.txt in the cloned repository."
    }
    
    # 1. Attempt the main installation first.
    $initialInstallCommand = "uv pip install -r $requirementsFile"
    Write-Host "Executing initial install: $initialInstallCommand"
    Invoke-Expression $initialInstallCommand
    
    if ($LASTEXITCODE -ne 0) {
        # Installation failed. This is the error we are handling (likely compiler issue with libsass).
        
        Write-Styled-Host "`nWarning: Initial dependency installation failed ($LASTEXITCODE). This often indicates that the required C++ compilers (like MSVC) are missing, preventing packages like 'libsass' from building." -ForegroundColor "Yellow"
        Write-Styled-Host "### COMPILER FALLBACK ACTIVATED ###" -ForegroundColor "Yellow"
        Write-Styled-Host "We are attempting to automatically install the pre-built 'libsass' wheel to bypass the compilation step." -ForegroundColor "Yellow"

        # 2. Download the wheel
        # 2. Download the wheel using the native PowerShell cmdlet
        Write-Styled-Host "Attempting to download pre-built 'libsass' wheel..." -ForegroundColor "Yellow"
        try {
            # Use Invoke-WebRequest directly instead of the 'wget' alias
            Invoke-WebRequest -Uri $LibsassWheelUrl -OutFile $LibsassWheelName
        }
        catch {
            throw "Failed to download the pre-built 'libsass' wheel. Please check your network connection or the URL."
        }

        # Check if the download was successful (file exists and size > 0)
        if (-not (Test-Path $LibsassWheelName) -or (Get-Item $LibsassWheelName).Length -eq 0) {
            throw "Failed to download the pre-built 'libsass' wheel or file is empty. Cannot proceed."
        }

        Write-Styled-Host "  [OK] Libsass wheel downloaded to '$LibsassWheelName'." -ForegroundColor "Green"

        # 3. Install the downloaded wheel (using uv pip install)
        # Use --no-deps because we want the requirements.txt to handle its dependencies later.
        $installWheelCommand = "uv pip install --no-deps --no-build-isolation .\$LibsassWheelName"
        Write-Host "Executing wheel install: $installWheelCommand"
        Invoke-Expression $installWheelCommand

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install the pre-built 'libsass' wheel. Cannot proceed with installation."
        }
        Write-Styled-Host "  [OK] Libsass wheel installed successfully." -ForegroundColor "Green"

        # 4. Re-run the main installation to grab the remaining dependencies.
        Write-Styled-Host "Re-running dependency installation for remaining packages..." -ForegroundColor "Yellow"
        # Use the original command, uv should detect libsass is already satisfied.
        $reinstallCommand = "uv pip install -r $requirementsFile --upgrade" 
        Write-Host "Executing re-install with UTF-8 encoding: $reinstallCommand"
        $env:PYTHONIOENCODING = 'utf-8'
        Invoke-Expression $reinstallCommand
        $env:PYTHONIOENCODING = $null
         
        
        if ($LASTEXITCODE -ne 0) {
            throw "Even after installing libsass, remaining dependencies failed to install. Check the output for further errors."
        }
        
        Write-Styled-Host "  [OK] All dependencies installed successfully via manual intervention." -ForegroundColor "Green"
    
    }
    else {
        # Initial installation succeeded.
        Write-Styled-Host "  [OK] Dependencies installed successfully." -ForegroundColor "Green"
    }
    # ==============================================================================
    # END UPDATED STEP 5
    # ==============================================================================

    # Go back to the new PARENT directory to generate the conf file and other folders (data, custom-addons)
    Set-Location $parentInstallDir
    Generate-Odoo-Conf -OdooVersion $selectedOdooVersion -BaseInstallPath $parentInstallDir -OdooCloneDir $cloneDir

    # --- Summary ---
    Write-Styled-Host "------------------- Odoo Setup Complete -------------------" -ForegroundColor "Magenta"
    Write-Styled-Host "  Installation Directory: $parentInstallDir" -ForegroundColor "White"
    Write-Styled-Host "  Odoo Version:         $selectedOdooVersion" -ForegroundColor "White"
    Write-Styled-Host "  Odoo Source Path:     $cloneDir" -ForegroundColor "White"
    Write-Styled-Host "  Custom Addons Path: $(Join-Path -Path $parentInstallDir -ChildPath 'custom-addons')" -ForegroundColor "White"
    Write-Styled-Host "  Config File:          $(Join-Path -Path $parentInstallDir -ChildPath 'odoo.conf')" -ForegroundColor "White"
    Write-Styled-Host "  HTTP Port:            $HttpPort (Longpolling: $LongpollingPort)" -ForegroundColor "White"
    Write-Styled-Host "-----------------------------------------------------------" -ForegroundColor "Magenta"
    Write-Styled-Host "To start Odoo, run the following command from this new directory ($parentInstallDir):" -ForegroundColor "Yellow"
    
    # Generate the robust startup command
    # Python executable is in the clone directory's .venv folder

    $startCommand = "& '$parentInstallDir\.venv\Scripts\python.exe' '$cloneDir\odoo-bin' -c odoo.conf"
    Write-Styled-Host "  $startCommand" -ForegroundColor "DarkYellow"
    Write-Host "  (NOTE: Remember to set up and configure your PostgreSQL database before starting.)" -ForegroundColor "Red"


}
catch {
    Write-Styled-Host "An error occurred during installation:" -ForegroundColor "Red"
    Write-Styled-Host $_.Exception.Message -ForegroundColor "Red"
    exit 1
}
finally {
    # Ensure we return to the starting directory on exit
    if ($originalLocation -and (Get-Location) -ne $originalLocation) {
        Set-Location $originalLocation
    }
}