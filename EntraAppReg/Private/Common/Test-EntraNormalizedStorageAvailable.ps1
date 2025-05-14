<#
.SYNOPSIS
    Tests if normalized storage format is available for KnownServices.

.DESCRIPTION
    The Test-EntraNormalizedStorageAvailable function checks if the normalized storage format
    is available for KnownServices. It does this by checking if the KnownServicesIndex.json file exists.

.PARAMETER ConfigPath
    The path to the configuration directory. If not specified, the default configuration path is used.

.EXAMPLE
    Test-EntraNormalizedStorageAvailable
    Returns $true if normalized storage is available in the default configuration directory.

.EXAMPLE
    Test-EntraNormalizedStorageAvailable -ConfigPath "C:\CustomConfig"
    Returns $true if normalized storage is available in the specified configuration directory.

.OUTPUTS
    System.Boolean
    Returns $true if normalized storage is available, $false otherwise.

.NOTES
    This function is part of the EntraAppReg module's normalized storage approach introduced
    in v0.2.0 to improve performance and reduce storage requirements.
#>
function Test-EntraNormalizedStorageAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    begin {
        Write-Verbose "Testing if normalized storage is available"
    }

    process {
        try {
            # Determine config path
            if (-not $ConfigPath) {
                # Use active configuration path from module variables if available
                if ($script:ConfigPaths -and $script:ConfigPaths.Active) {
                    $ConfigPath = $script:ConfigPaths.Active
                }
                else {
                    # Try both user and module paths
                    $userConfigPath = Get-EntraConfigurationPath -ConfigType UserDefault
                    $moduleConfigPath = Get-EntraConfigurationPath -ConfigType ModuleDefault
                    
                    # Check user path first
                    $userIndexPath = Join-Path -Path $userConfigPath -ChildPath "KnownServicesIndex.json"
                    if (Test-Path -Path $userIndexPath) {
                        $ConfigPath = $userConfigPath
                    }
                    else {
                        # Then check module path
                        $moduleIndexPath = Join-Path -Path $moduleConfigPath -ChildPath "KnownServicesIndex.json"
                        if (Test-Path -Path $moduleIndexPath) {
                            $ConfigPath = $moduleConfigPath
                        }
                        else {
                            # Default to user path
                            $ConfigPath = $userConfigPath
                        }
                    }
                }
            }

            # Check if the normalized storage index file exists
            $indexPath = Join-Path -Path $ConfigPath -ChildPath "KnownServicesIndex.json"
            $normalizedAvailable = Test-Path -Path $indexPath

            # Also check if legacy format exists for comparison
            $legacyPath = Join-Path -Path $ConfigPath -ChildPath "KnownServices.json"
            $legacyAvailable = Test-Path -Path $legacyPath

            if ($normalizedAvailable) {
                Write-Verbose "Normalized storage is available"
                
                # Check index file version to ensure compatibility
                try {
                    $indexContent = Get-Content -Path $indexPath -Raw | ConvertFrom-Json
                    $version = [System.Version]::new($indexContent.version)
                    $minVersion = [System.Version]::new("1.0")
                    
                    if ($version -lt $minVersion) {
                        Write-Warning "Normalized storage index version $($indexContent.version) is outdated. Minimum required version is 1.0"
                        return $false
                    }
                }
                catch {
                    Write-Warning "Failed to parse normalized storage index version: $_"
                    return $false
                }
                
                return $true
            }
            else {
                Write-Verbose "Normalized storage is not available"
                return $false
            }
        }
        catch {
            Write-Error "Failed to detect normalized storage availability: $_"
            return $false
        }
    }
}

Export-ModuleMember -Function Test-EntraNormalizedStorageAvailable
