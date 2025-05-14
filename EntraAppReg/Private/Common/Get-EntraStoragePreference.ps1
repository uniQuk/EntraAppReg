<#
.SYNOPSIS
    Gets the preferred storage format for KnownServices.

.DESCRIPTION
    The Get-EntraStoragePreference function determines the preferred storage format for KnownServices.
    It checks for the presence of environment variables, user preferences, and available storage formats.

.PARAMETER ForceCheck
    If specified, bypasses any cached preference and performs a fresh check.

.PARAMETER ConfigPath
    The path to the configuration directory. If not specified, the default configuration path is used.

.EXAMPLE
    Get-EntraStoragePreference
    Returns the preferred storage format based on environment variables, user preferences, and available formats.

.OUTPUTS
    PSObject
    Returns an object with UseNormalizedStorage and Reason properties.

.NOTES
    This function is part of the EntraAppReg module's normalized storage approach introduced
    in v0.2.0 to improve performance and reduce storage requirements.
#>
function Get-EntraStoragePreference {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ForceCheck,

        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    begin {
        Write-Verbose "Getting storage preference for KnownServices"
    }

    process {
        try {
            # Check if preference is cached and no force check requested
            if (-not $ForceCheck -and $script:KnownServicesPreference) {
                Write-Verbose "Using cached storage preference: $($script:KnownServicesPreference.UseNormalizedStorage)"
                return $script:KnownServicesPreference
            }

            # Determine config path
            if (-not $ConfigPath) {
                # Use active configuration path from module variables if available
                if ($script:ConfigPaths -and $script:ConfigPaths.Active) {
                    $ConfigPath = $script:ConfigPaths.Active
                }
                else {
                    # Fallback to the current user configuration path
                    $ConfigPath = Get-EntraConfigurationPath -ConfigType UserDefault -CreateIfNotExists
                }
            }

            # Check for environment variable override
            $envVar = $env:ENTRAAPPREG_USE_NORMALIZED_STORAGE
            if ($envVar -ne $null) {
                $useNormalized = ($envVar -eq "1" -or $envVar -eq "true" -or $envVar -eq "yes" -or $envVar -eq "y")
                $preference = [PSCustomObject]@{
                    UseNormalizedStorage = $useNormalized
                    Reason = "Environment variable"
                }
                
                Write-Verbose "Storage preference set by environment variable: $($preference.UseNormalizedStorage)"
                $script:KnownServicesPreference = $preference
                return $preference
            }

            # Check for user preference in profile
            try {
                # TODO: Implement user preference storage and retrieval when needed
                # This would typically be stored in user profile or settings file
            }
            catch {
                Write-Verbose "No user preference found"
            }

            # Check if normalized storage is available
            $normalizedAvailable = Test-EntraNormalizedStorageAvailable -ConfigPath $ConfigPath
            
            # If only normalized is available, use it
            if ($normalizedAvailable) {
                $legacyPath = Join-Path -Path $ConfigPath -ChildPath "KnownServices.json"
                $legacyAvailable = Test-Path -Path $legacyPath
                
                if (-not $legacyAvailable) {
                    $preference = [PSCustomObject]@{
                        UseNormalizedStorage = $true
                        Reason = "Only normalized format available"
                    }
                    
                    Write-Verbose "Only normalized storage format is available"
                    $script:KnownServicesPreference = $preference
                    return $preference
                }
            }

            # Default to legacy format for now (transition plan stage)
            $preference = [PSCustomObject]@{
                UseNormalizedStorage = $false
                Reason = "Default to legacy format during transition"
            }
            
            # Display warning about future change if normalized format is available
            if ($normalizedAvailable) {
                Write-Warning "Normalized storage format is available but not used by default. In a future version, normalized storage will become the default. Use -UseNormalizedStorage parameter to opt-in now."
            }
            
            Write-Verbose "Using legacy storage format: $($preference.Reason)"
            $script:KnownServicesPreference = $preference
            return $preference
        }
        catch {
            Write-Error "Failed to determine storage preference: $_"
            # Default to legacy format for safety on error
            return [PSCustomObject]@{
                UseNormalizedStorage = $false
                Reason = "Error determining preference, defaulting to legacy format"
            }
        }
    }
}

Export-ModuleMember -Function Get-EntraStoragePreference
