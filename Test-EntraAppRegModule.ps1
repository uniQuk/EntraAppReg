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
        
        # Test service principal helper functions
        Write-Host "`nTesting service principal helper functions..." -ForegroundColor Cyan
        
        # Test Get-EntraKnownServicePrincipal
        Write-Host "Testing Get-EntraKnownServicePrincipal..." -ForegroundColor Cyan
        try {
            $knownServices = Get-EntraKnownServicePrincipal -Verbose
            if ($knownServices) {
                $count = if ($knownServices -is [array]) { $knownServices.Count } else { 1 }
                Write-Host "Retrieved $count known service(s) successfully." -ForegroundColor Green
                
                # Test filtering by name
                Write-Host "Testing Get-EntraKnownServicePrincipal with name filter..." -ForegroundColor Cyan
                $graphService = Get-EntraKnownServicePrincipal -ServiceName "Microsoft Graph" -Verbose
                if ($graphService) {
                    Write-Host "Retrieved Microsoft Graph service successfully." -ForegroundColor Green
                } else {
                    Write-Host "Failed to retrieve Microsoft Graph service." -ForegroundColor Red
                }
            } else {
                Write-Host "No known services found." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Get-EntraKnownServicePrincipal failed: $_" -ForegroundColor Red
        }
        
        # Test Get-EntraServicePrincipalByName
        Write-Host "Testing Get-EntraServicePrincipalByName..." -ForegroundColor Cyan
        try {
            $spByName = Get-EntraServicePrincipalByName -DisplayName "Microsoft Graph" -Verbose
            if ($spByName) {
                Write-Host "Retrieved service principal by name successfully." -ForegroundColor Green
                Write-Host "   Display Name: $($spByName[0].displayName)" -ForegroundColor Green
                Write-Host "   App ID: $($spByName[0].appId)" -ForegroundColor Green
            } else {
                Write-Host "Failed to retrieve service principal by name." -ForegroundColor Red
            }
        } catch {
            Write-Host "Get-EntraServicePrincipalByName failed: $_" -ForegroundColor Red
        }
        
        # Test Get-EntraServicePrincipalByAppId
        if ($spByName -and $spByName[0].appId) {
            Write-Host "Testing Get-EntraServicePrincipalByAppId..." -ForegroundColor Cyan
            try {
                $spByAppId = Get-EntraServicePrincipalByAppId -AppId $spByName[0].appId -Verbose
                if ($spByAppId) {
                    Write-Host "Retrieved service principal by AppId successfully." -ForegroundColor Green
                    Write-Host "   Display Name: $($spByAppId.displayName)" -ForegroundColor Green
                    Write-Host "   App ID: $($spByAppId.appId)" -ForegroundColor Green
                } else {
                    Write-Host "Failed to retrieve service principal by AppId." -ForegroundColor Red
                }
            } catch {
                Write-Host "Get-EntraServicePrincipalByAppId failed: $_" -ForegroundColor Red
            }
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
