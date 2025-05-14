<#
.SYNOPSIS
    Clears the cache for KnownServices configuration.

.DESCRIPTION
    The Clear-EntraKnownServicesCache function clears the in-memory cache for KnownServices
    configuration, forcing the module to reload configuration from disk on the next request.

.EXAMPLE
    Clear-EntraKnownServicesCache
    Clears the KnownServices cache.

.NOTES
    This function is part of the EntraAppReg module's normalized storage approach introduced
    in v3.0 to improve performance and reduce storage requirements.
#>
function Clear-EntraKnownServicesCache {
    [CmdletBinding()]
    param ()

    begin {
        Write-Verbose "Clearing KnownServices cache"
    }

    process {
        try {
            # Initialize cache if it doesn't exist
            if (-not $script:KnownServicesCache) {
                $script:KnownServicesCache = @{
                    Index = $null
                    ServicePrincipals = $null
                    PermissionDefinitions = $null
                    ServicePermissionMappings = $null
                    CommonPermissions = $null
                    LegacyFormat = $null
                    LastRefresh = $null
                }
            }
            
            # Clear all cache entries
            $script:KnownServicesCache.Index = $null
            $script:KnownServicesCache.ServicePrincipals = $null
            $script:KnownServicesCache.PermissionDefinitions = $null
            $script:KnownServicesCache.ServicePermissionMappings = $null
            $script:KnownServicesCache.CommonPermissions = $null
            $script:KnownServicesCache.LegacyFormat = $null
            $script:KnownServicesCache.LastRefresh = $null
            
            Write-Verbose "KnownServices cache cleared"
            return $true
        }
        catch {
            Write-Error "Failed to clear KnownServices cache: $_"
            return $false
        }
    }
}
