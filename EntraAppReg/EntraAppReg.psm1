# EntraAppReg.psm1
# Module script for EntraAppReg - Entra App Registration Management Module

#Region Module Variables
# Script variables
$script:ModuleRootPath = $PSScriptRoot
$script:ModuleName = (Get-Item $PSCommandPath).BaseName
# Default module configuration paths (these will be updated after functions are loaded)
$script:ConfigPath = Join-Path -Path $script:ModuleRootPath -ChildPath "Config"
$script:KnownServicesPath = Join-Path -Path $script:ConfigPath -ChildPath "KnownServices.json"
$script:PublicFunctionsPath = Join-Path -Path $script:ModuleRootPath -ChildPath "Public"
$script:PrivateFunctionsPath = Join-Path -Path $script:ModuleRootPath -ChildPath "Private"

# Initialize KnownServices cache
$script:KnownServicesCache = @{
    Index = $null
    ServicePrincipals = $null
    PermissionDefinitions = $null
    ServicePermissionMappings = $null
    CommonPermissions = $null
    LegacyFormat = $null
    LastRefresh = $null
}

# Initialize storage preference
$script:KnownServicesPreference = $null

# Module preference variables - can be overridden by user
$script:LogPath = [System.IO.Path]::Combine($env:TEMP, "EntraAppReg")
$script:DefaultOutputPath = Join-Path -Path (Get-Location) -ChildPath "EntraAppReg_Output"
$script:VerboseLogging = $false
$script:MaxRetryAttempts = 3
$script:RetryDelaySeconds = 2

# GraphAPI related variables
$script:GraphConnection = $null
$script:GraphScopes = @("Application.ReadWrite.All")
#EndRegion Module Variables

#Region Import Functions
# First import core functions that others might depend on
$coreFunctions = @(
    "Get-EntraModuleRoot.ps1",
    "Get-EntraConfigurationPath.ps1"
)

foreach ($coreFunction in $coreFunctions) {
    $functionPath = Join-Path -Path "$script:PrivateFunctionsPath" -ChildPath "Common"
    $functionPath = Join-Path -Path $functionPath -ChildPath $coreFunction
    if (Test-Path -Path $functionPath) {
        try {
            . $functionPath
            Write-Verbose "Imported core function: $coreFunction"
        }
        catch {
            Write-Error "Failed to import core function ${functionPath}: $_"
        }
    }
    else {
        Write-Warning "Core function file not found: $functionPath"
    }
}

# Import all other private functions
$privateFunctions = Get-ChildItem -Path "$script:PrivateFunctionsPath" -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue |
                    Where-Object { $coreFunctions -notcontains $_.Name }

foreach ($function in $privateFunctions) {
    try {
        . $function.FullName
        Write-Verbose "Imported private function: $($function.BaseName)"
    }
    catch {
        Write-Error "Failed to import private function $($function.FullName): $_"
    }
}

# Import all public functions
$publicFunctions = Get-ChildItem -Path "$script:PublicFunctionsPath" -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue
$functionsToExport = @()
foreach ($function in $publicFunctions) {
    try {
        . $function.FullName
        $functionsToExport += $function.BaseName
        Write-Verbose "Imported public function: $($function.BaseName)"
    }
    catch {
        Write-Error "Failed to import public function $($function.FullName): $_"
    }
}
#EndRegion Import Functions

#Region Module Initialization
# Update configuration paths
if (Get-Command -Name 'Update-EntraConfigurationPaths' -ErrorAction SilentlyContinue) {
    try {
        Update-EntraConfigurationPaths
        Write-Verbose "Updated configuration paths"
    }
    catch {
        Write-Warning "Failed to update configuration paths: $_"
    }
}

# Load configuration if exists
if (Test-Path -Path $script:KnownServicesPath) {
    try {
        $script:KnownServices = Get-Content -Path $script:KnownServicesPath -Raw | ConvertFrom-Json
        Write-Verbose "Loaded KnownServices configuration from $script:KnownServicesPath"
    }
    catch {
        Write-Warning "Failed to load KnownServices configuration: $_"
    }
}

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $script:LogPath)) {
    try {
        New-Item -Path $script:LogPath -ItemType Directory -Force | Out-Null
        Write-Verbose "Created log directory: $script:LogPath"
    }
    catch {
        Write-Warning "Failed to create log directory: $_"
    }
}

# Check if KnownServices configuration needs to be updated
if (Test-Path -Path $script:KnownServicesPath) {
    try {
        # Only check if Test-EntraKnownServicesAge function is available
        if (Get-Command -Name 'Test-EntraKnownServicesAge' -ErrorAction SilentlyContinue) {
            if (Test-EntraKnownServicesAge) {
                Write-Host "The KnownServices configuration is outdated or missing." -ForegroundColor Yellow
                Write-Host "You can update it using Update-EntraKnownServices function." -ForegroundColor Yellow
                
                # Prompt to update if we're in an interactive session
                if ([System.Environment]::UserInteractive) {
                    $updateNow = Read-Host "Would you like to update now? (Y/N)"
                    if ($updateNow -eq "Y" -or $updateNow -eq "y") {
                        # Only try to update if we have the necessary function and Graph connection
                        if (Get-Command -Name 'Update-EntraKnownServices' -ErrorAction SilentlyContinue) {
                            # Try to connect to Graph if not already connected
                            if (Get-Command -Name 'Connect-EntraGraphSession' -ErrorAction SilentlyContinue) {
                                if (-not (Get-Command -Name 'Test-EntraGraphConnection' -ErrorAction SilentlyContinue) -or 
                                    -not (Test-EntraGraphConnection)) {
                                    Connect-EntraGraphSession
                                }
                                # Now try to update
                                Update-EntraKnownServices
                            } else {
                                Write-Warning "Cannot update KnownServices configuration: Connect-EntraGraphSession function not available"
                            }
                        } else {
                            Write-Warning "Cannot update KnownServices configuration: Update-EntraKnownServices function not available"
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Failed to check KnownServices configuration age: $_"
    }
}
#Region Normalized Storage Initialization
# Initialize the KnownServices cache and module paths
if (Get-Command -Name 'Initialize-EntraKnownServicesCache' -ErrorAction SilentlyContinue) {
    try {
        Write-Verbose "Initializing EntraKnownServices cache on module load"
        Initialize-EntraKnownServicesCache
        
        # Check if normalized storage is available
        if (Get-Command -Name 'Test-EntraNormalizedStorageAvailable' -ErrorAction SilentlyContinue) {
            $normalizedAvailable = Test-EntraNormalizedStorageAvailable
            if ($normalizedAvailable) {
                Write-Verbose "Normalized storage format is available"
            }
            else {
                Write-Verbose "Normalized storage format is not available"
            }
        }
    }
    catch {
        Write-Warning "Failed to initialize EntraKnownServices cache: $_"
    }
}
#EndRegion Normalized Storage Initialization
#EndRegion Module Initialization

# Export public functions
Export-ModuleMember -Function $functionsToExport
