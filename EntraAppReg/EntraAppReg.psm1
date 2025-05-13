# EntraAppReg.psm1
# Module script for EntraAppReg - Entra App Registration Management Module

#Region Module Variables
# Script variables
$script:ModuleRoot = $PSScriptRoot
$script:ModuleName = (Get-Item $PSCommandPath).BaseName
$script:ConfigPath = Join-Path -Path $script:ModuleRoot -ChildPath "Config"
$script:KnownServicesPath = Join-Path -Path $script:ConfigPath -ChildPath "KnownServices.json"
$script:PublicFunctionsPath = Join-Path -Path $script:ModuleRoot -ChildPath "Public"
$script:PrivateFunctionsPath = Join-Path -Path $script:ModuleRoot -ChildPath "Private"

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
# Import all private functions
$privateFunctions = Get-ChildItem -Path "$script:PrivateFunctionsPath" -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue
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
#EndRegion Module Initialization

# Export public functions
Export-ModuleMember -Function $functionsToExport
