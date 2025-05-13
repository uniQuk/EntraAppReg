# Test-EntraAppRegModule.ps1
# This script tests the basic functionality of the EntraAppReg module

# Import the module
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath "EntraAppReg"
Import-Module -Name $modulePath -Force -Verbose

Write-Host "Module imported successfully." -ForegroundColor Green

# Test core authentication helpers
Write-Host "Testing authentication helpers..." -ForegroundColor Cyan

# Connect to Microsoft Graph
try {
    Connect-EntraGraphSession -Verbose
    Write-Host "Connection successful!" -ForegroundColor Green
    
    # Test if connection is active
    if (Test-EntraGraphConnection) {
        Write-Host "Connection is active." -ForegroundColor Green
        
        # Try to update KnownServices
        Write-Host "Updating KnownServices configuration..." -ForegroundColor Cyan
        if (Update-EntraKnownServices -Force -Verbose) {
            Write-Host "KnownServices configuration updated successfully." -ForegroundColor Green
        } else {
            Write-Host "Failed to update KnownServices configuration." -ForegroundColor Red
        }
        
        # Try to disconnect
        Disconnect-EntraGraphSession
        if (-not (Test-EntraGraphConnection)) {
            Write-Host "Disconnected successfully." -ForegroundColor Green
        } else {
            Write-Host "Failed to disconnect." -ForegroundColor Red
        }
    } else {
        Write-Host "Connection is not active." -ForegroundColor Red
    }
}
catch {
    Write-Host "Connection failed: $_" -ForegroundColor Red
}

# Test common utility functions
Write-Host "`nTesting common utility functions..." -ForegroundColor Cyan

# Test output folder creation
try {
    $outputFolder = New-EntraAppOutputFolder -CreateSubfolders -Verbose
    if (Test-Path -Path $outputFolder) {
        Write-Host "Output folder created successfully: $outputFolder" -ForegroundColor Green
    } else {
        Write-Host "Failed to create output folder." -ForegroundColor Red
    }
}
catch {
    Write-Host "Output folder creation failed: $_" -ForegroundColor Red
}

# Test logging
try {
    Write-EntraLog -Message "This is an information message" -Level Information -Verbose
    Write-EntraLog -Message "This is a warning message" -Level Warning -Verbose
    Write-EntraLog -Message "This is an error message" -Level Error -Verbose
    Write-EntraLog -Message "This is a verbose message" -Level Verbose -Verbose
    Write-Host "Log messages written successfully." -ForegroundColor Green
}
catch {
    Write-Host "Logging failed: $_" -ForegroundColor Red
}

Write-Host "`nBasic testing completed." -ForegroundColor Cyan
