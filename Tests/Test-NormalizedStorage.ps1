
<#
.SYNOPSIS
    Tests the normalized storage functionality of the EntraAppReg module.
    
.DESCRIPTION
    This script tests the normalized storage functionality of the EntraAppReg module.
    It validates the conversion from legacy to normalized format, the loading and
    retrieval of data from both formats, and compares results to ensure data integrity.
    
.NOTES
    This script should be run after making changes to the normalized storage implementation
    to ensure backward compatibility and data integrity.
#>

# Import module if not already loaded
if (-not (Get-Module -Name EntraAppReg)) {
    Import-Module -Name "$PSScriptRoot\..\EntraAppReg\EntraAppReg.psd1" -Force
}

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Helper function for test reporting
function Write-TestResult {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TestName,
        
        [Parameter(Mandatory = $true)]
        [bool]$Success,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = ''
    )
    
    $statusEmoji = if ($Success) { "✅" } else { "❌" }
    Write-Host "$statusEmoji $TestName"
    
    if (-not $Success -and $ErrorMessage) {
        Write-Host "   Error: $ErrorMessage" -ForegroundColor Red
    }
}

# Helper function to compare objects for equality
function Test-ObjectsEqual {
    param (
        [Parameter(Mandatory = $true)]
        $Object1,
        
        [Parameter(Mandatory = $true)]
        $Object2,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeProperties = @()
    )
    
    try {
        # Convert objects to JSON and back to normalize them
        $json1 = $Object1 | ConvertTo-Json -Depth 10
        $json2 = $Object2 | ConvertTo-Json -Depth 10
        
        $normalized1 = $json1 | ConvertFrom-Json
        $normalized2 = $json2 | ConvertFrom-Json
        
        # Remove excluded properties if any
        foreach ($property in $ExcludeProperties) {
            $normalized1.PSObject.Properties.Remove($property)
            $normalized2.PSObject.Properties.Remove($property)
        }
        
        # Compare the normalized objects
        $json1 = $normalized1 | ConvertTo-Json -Depth 10 -Compress
        $json2 = $normalized2 | ConvertTo-Json -Depth 10 -Compress
        
        return $json1 -eq $json2
    }
    catch {
        Write-Host "Error comparing objects: $_" -ForegroundColor Red
        return $false
    }
}

# Create test directory if it doesn't exist
$testDir = Join-Path -Path $PSScriptRoot -ChildPath "TestOutput"
if (-not (Test-Path -Path $testDir)) {
    New-Item -Path $testDir -ItemType Directory | Out-Null
}

# Clear test directory
Get-ChildItem -Path $testDir -File | Remove-Item -Force

Write-Host "🧪 STARTING NORMALIZED STORAGE TESTS" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Test 1: Create normalized structure from legacy format
$testName = "Create normalized structure from legacy format"
try {
    # Get a sample of legacy format data
    $legacyData = Get-EntraKnownServicePrincipal | Select-Object -First 5
    
    # Create test config directory
    $testConfigDir = Join-Path -Path $testDir -ChildPath "Config"
    if (-not (Test-Path -Path $testConfigDir)) {
        New-Item -Path $testConfigDir -ItemType Directory | Out-Null
    }
    
    # Save legacy format to test directory
    $legacyData | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path -Path $testConfigDir -ChildPath "KnownServices.json")
    
    # Generate normalized structure
    & "$PSScriptRoot\..\EntraAppReg\EntraAppReg\Private\Common\New-EntraKnownServicesStructure.ps1" -ConfigPath $testConfigDir
    
    # Check if all files were created
    $requiredFiles = @(
        "KnownServicesIndex.json",
        "ServicePrincipals.json",
        "PermissionDefinitions.json",
        "ServicePermissionMappings.json",
        "CommonPermissions.json"
    )
    
    $allFilesExist = $true
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path -Path $testConfigDir -ChildPath $file
        if (-not (Test-Path -Path $filePath)) {
            $allFilesExist = $false
            throw "Required file $file was not created"
        }
    }
    
    Write-TestResult -TestName $testName -Success $allFilesExist
}
catch {
    Write-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
}

# Test 2: Load data from normalized format
$testName = "Load data from normalized format"
try {
    # Clear cache first
    & "$PSScriptRoot\..\EntraAppReg\EntraAppReg\Private\Common\Clear-EntraKnownServicesCache.ps1"
    
    # Get data from normalized format
    $normalizedData = & "$PSScriptRoot\..\EntraAppReg\EntraAppReg\Private\Common\Get-EntraNormalizedKnownServices.ps1" -ConfigPath $testConfigDir
    
    $success = $null -ne $normalizedData -and $normalizedData.Count -gt 0
    Write-TestResult -TestName $testName -Success $success
}
catch {
    Write-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
}

# Test 3: Compare legacy and normalized data retrieval
$testName = "Compare legacy and normalized data retrieval"
try {
    # Get sample service from legacy format
    $sampleServiceId = $legacyData[0].AppId
    $legacyService = Get-EntraKnownServicePrincipal -AppId $sampleServiceId
    
    # Get same service from normalized format
    $normalizedService = Get-EntraNormalizedKnownServicePrincipal -AppId $sampleServiceId -ConfigPath $testConfigDir
    
    # Compare results (excluding metadata fields that might be different)
    $compareResult = Test-ObjectsEqual -Object1 $legacyService -Object2 $normalizedService -ExcludeProperties @('Source', 'LastUpdated')
    
    Write-TestResult -TestName $testName -Success $compareResult
}
catch {
    Write-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
}

# Test 4: Test performance comparison
$testName = "Performance comparison: legacy vs. normalized"
try {
    $iterations = 10
    
    # Test legacy format performance
    $legacyTime = Measure-Command {
        for ($i = 0; $i -lt $iterations; $i++) {
            $legacyServices = Get-EntraKnownServicePrincipal
        }
    }
    
    # Clear cache
    & "$PSScriptRoot\..\EntraAppReg\EntraAppReg\Private\Common\Clear-EntraKnownServicesCache.ps1"
    
    # Test normalized format performance
    $normalizedTime = Measure-Command {
        for ($i = 0; $i -lt $iterations; $i++) {
            $normalizedServices = Get-EntraNormalizedKnownServicePrincipal -ConfigPath $testConfigDir
        }
    }
    
    $legacyMs = $legacyTime.TotalMilliseconds
    $normalizedMs = $normalizedTime.TotalMilliseconds
    $improvement = [math]::Round(($legacyMs - $normalizedMs) / $legacyMs * 100, 2)
    
    Write-Host "Legacy: $([math]::Round($legacyMs, 2)) ms, Normalized: $([math]::Round($normalizedMs, 2)) ms, Improvement: $improvement%"
    
    # Success if normalized is at least as fast as legacy
    $success = $normalizedMs -le $legacyMs
    Write-TestResult -TestName $testName -Success $success
}
catch {
    Write-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
}

# Test 5: Test automatic format detection
$testName = "Automatic format detection"
try {
    # Create a function to test auto-detection
    function Test-AutoDetection {
        param (
            [Parameter(Mandatory = $true)]
            [string]$ConfigPath,
            
            [Parameter(Mandatory = $true)]
            [bool]$ExpectNormalized
        )
        
        # Clear cache
        & "$PSScriptRoot\..\EntraAppReg\EntraAppReg\Private\Common\Clear-EntraKnownServicesCache.ps1"
        
        # Get index file path
        $indexPath = Join-Path -Path $ConfigPath -ChildPath "KnownServicesIndex.json"
        $legacyPath = Join-Path -Path $ConfigPath -ChildPath "KnownServices.json"
        
        # Create test scenario
        if ($ExpectNormalized) {
            # Ensure index exists and legacy is missing
            if (-not (Test-Path -Path $indexPath)) {
                '{"version":"1.0","created":"2023-01-01T00:00:00Z"}' | Out-File -FilePath $indexPath
            }
            if (Test-Path -Path $legacyPath) {
                Remove-Item -Path $legacyPath -Force
            }
        }
        else {
            # Ensure legacy exists and index is missing
            if (-not (Test-Path -Path $legacyPath)) {
                '[]' | Out-File -FilePath $legacyPath
            }
            if (Test-Path -Path $indexPath) {
                Remove-Item -Path $indexPath -Force
            }
        }
        
        # Now detect format
        $normalizedAvailable = Test-Path -Path $indexPath
        $legacyAvailable = Test-Path -Path $legacyPath
        
        # Logic to determine which format to use
        $useNormalized = $normalizedAvailable -and (-not $legacyAvailable -or $ExpectNormalized)
        
        return $useNormalized -eq $ExpectNormalized
    }
    
    # Test both scenarios
    $test1 = Test-AutoDetection -ConfigPath $testConfigDir -ExpectNormalized $true
    $test2 = Test-AutoDetection -ConfigPath $testConfigDir -ExpectNormalized $false
    
    Write-TestResult -TestName $testName -Success ($test1 -and $test2)
}
catch {
    Write-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
}

# Test 6: Test updating normalized structure
$testName = "Update normalized structure"
try {
    # Create modified data
    $originalData = Get-EntraKnownServicePrincipal | Select-Object -First 5
    $modifiedData = $originalData.Clone()
    
    # Modify something in the data
    $modifiedData[0].DisplayName = "Modified Test Service"
    
    # Save modified legacy format
    $modifiedData | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path -Path $testConfigDir -ChildPath "KnownServices.json")
    
    # Update normalized structure
    & "$PSScriptRoot\..\EntraAppReg\EntraAppReg\Public\Common\Update-EntraNormalizedKnownServices.ps1" -ConfigPath $testConfigDir
    
    # Verify change was applied
    & "$PSScriptRoot\..\EntraAppReg\EntraAppReg\Private\Common\Clear-EntraKnownServicesCache.ps1"
    $updatedData = & "$PSScriptRoot\..\EntraAppReg\EntraAppReg\Public\ServicePrincipals\Get-EntraNormalizedKnownServicePrincipal.ps1" -ConfigPath $testConfigDir -AppId $modifiedData[0].AppId
    
    $success = $updatedData.DisplayName -eq "Modified Test Service"
    Write-TestResult -TestName $testName -Success $success
}
catch {
    Write-TestResult -TestName $testName -Success $false -ErrorMessage $_.Exception.Message
}

Write-Host "`n📊 TEST SUMMARY" -ForegroundColor Cyan
Write-Host "=============" -ForegroundColor Cyan
