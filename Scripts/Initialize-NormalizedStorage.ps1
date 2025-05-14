<#
.SYNOPSIS
    Initializes the normalized storage format for the EntraAppReg module.

.DESCRIPTION
    This script initializes the normalized storage format for the EntraAppReg module by 
    creating the necessary directory structure and files. It's useful for first-time setup
    or for testing the normalized storage features.

.EXAMPLE
    ./Initialize-NormalizedStorage.ps1
    Initializes the normalized storage format in the default location.

.NOTES
    This script requires the EntraAppReg module to be imported.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Import module if not already loaded
if (-not (Get-Module -Name EntraAppReg)) {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $moduleRoot -ChildPath "EntraAppReg"
    
    if (Test-Path -Path (Join-Path -Path $modulePath -ChildPath "EntraAppReg.psd1")) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath "EntraAppReg.psd1") -Force
        Write-Host "Imported EntraAppReg module from $modulePath" -ForegroundColor Green
    }
    else {
        Write-Error "EntraAppReg module not found at $modulePath"
        return
    }
}

# Step 1: Set up the module root path correctly
try {
    Write-Host "Setting up module root path..." -ForegroundColor Cyan
    $moduleRoot = Get-EntraModuleRoot
    
    if (-not $moduleRoot) {
        Write-Host "Module root path not found. Creating script variables..." -ForegroundColor Yellow
        $script:ModuleRootPath = Split-Path -Path (Get-Module -Name EntraAppReg).Path -Parent
        $script:ConfigPath = Join-Path -Path $script:ModuleRootPath -ChildPath "Config"
        Write-Host "Set script:ModuleRootPath to $script:ModuleRootPath" -ForegroundColor Green
        Write-Host "Set script:ConfigPath to $script:ConfigPath" -ForegroundColor Green
    }
    else {
        Write-Host "Module root path found: $moduleRoot" -ForegroundColor Green
    }
}
catch {
    Write-Error "Failed to set up module root path: $_"
    return
}

# Step 2: Initialize the KnownServices cache
try {
    Write-Host "Initializing KnownServices cache..." -ForegroundColor Cyan
    Initialize-EntraKnownServicesCache
    Write-Host "KnownServices cache initialized." -ForegroundColor Green
}
catch {
    Write-Error "Failed to initialize KnownServices cache: $_"
    return
}

# Step 3: Check for existing legacy KnownServices.json
try {
    Write-Host "Checking for legacy KnownServices.json..." -ForegroundColor Cyan
    
    $configPath = $script:ConfigPath
    $legacyPath = Join-Path -Path $configPath -ChildPath "KnownServices.json"
    
    if (Test-Path -Path $legacyPath) {
        Write-Host "Found legacy KnownServices.json at $legacyPath" -ForegroundColor Green
        
        # Get file size to show user
        $fileInfo = Get-Item -Path $legacyPath
        $fileSizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
        Write-Host "Legacy file size: $fileSizeKB KB" -ForegroundColor Cyan
        
        # Check if it has content
        $content = Get-Content -Path $legacyPath -Raw
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-Warning "Legacy KnownServices.json exists but is empty."
        }
        else {
            try {
                $jsonContent = $content | ConvertFrom-Json
                Write-Host "Legacy file contains valid JSON with $($jsonContent.Count) entries" -ForegroundColor Green
            }
            catch {
                Write-Warning "Legacy KnownServices.json contains invalid JSON: $_"
            }
        }
    }
    else {
        Write-Warning "Legacy KnownServices.json not found at $legacyPath"
    }
}
catch {
    Write-Error "Failed to check for legacy KnownServices.json: $_"
}

# Step 4: Create the normalized structure
try {
    Write-Host "Creating normalized structure..." -ForegroundColor Cyan
    
    $result = New-EntraKnownServicesStructure -Force
    
    if ($result) {
        Write-Host "Normalized structure created successfully." -ForegroundColor Green
        
        # List the created files
        $normalizedFiles = @(
            "KnownServicesIndex.json",
            "ServicePrincipals.json",
            "PermissionDefinitions.json",
            "ServicePermissionMappings.json",
            "CommonPermissions.json"
        )
        
        foreach ($file in $normalizedFiles) {
            $filePath = Join-Path -Path $configPath -ChildPath $file
            if (Test-Path -Path $filePath) {
                $fileInfo = Get-Item -Path $filePath
                $fileSizeKB = [math]::Round($fileInfo.Length / 1KB, 2)
                Write-Host "Created $file ($fileSizeKB KB)" -ForegroundColor Green
            }
            else {
                Write-Warning "File not created: $file"
            }
        }
    }
    else {
        Write-Error "Failed to create normalized structure."
    }
}
catch {
    Write-Error "Failed to create normalized structure: $_"
}

# Step 5: Test if normalized structure can be read
try {
    Write-Host "Testing if normalized structure can be read..." -ForegroundColor Cyan
    
    # Clear the cache first
    Clear-EntraKnownServicesCache
    
    # Attempt to load the normalized structure
    $normalizedConfig = Get-EntraNormalizedKnownServices -Force
    
    if ($normalizedConfig) {
        Write-Host "Normalized structure can be read successfully." -ForegroundColor Green
        
        # Display statistics
        $spCount = $normalizedConfig.ServicePrincipals.PSObject.Properties.Count
        $pdCount = $normalizedConfig.PermissionDefinitions.PSObject.Properties.Count
        $spmCount = $normalizedConfig.ServicePermissionMappings.PSObject.Properties.Count
        
        Write-Host "Statistics:" -ForegroundColor Cyan
        Write-Host "  Service Principals: $spCount" -ForegroundColor Green
        Write-Host "  Permission Definitions: $pdCount" -ForegroundColor Green
        Write-Host "  Service Permission Mappings: $spmCount" -ForegroundColor Green
    }
    else {
        Write-Warning "Could not read normalized structure."
    }
}
catch {
    Write-Error "Failed to test normalized structure: $_"
}

Write-Host "`nNormalized storage initialization complete." -ForegroundColor Cyan
