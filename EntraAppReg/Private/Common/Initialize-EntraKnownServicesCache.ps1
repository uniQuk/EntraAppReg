<#
.SYNOPSIS
    Initializes the KnownServices cache.

.DESCRIPTION
    The Initialize-EntraKnownServicesCache function initializes the in-memory cache for KnownServices
    configuration. This function is called automatically when the module is loaded.

.EXAMPLE
    Initialize-EntraKnownServicesCache
    Initializes the KnownServices cache.

.NOTES
    This function is part of the EntraAppReg module's normalized storage approach introduced
    in v0.2.0 to improve performance and reduce storage requirements.
#>
function Initialize-EntraKnownServicesCache {
    [CmdletBinding()]
    param ()

    begin {
        Write-Verbose "Initializing KnownServices cache"
    }

    process {
        try {
            # Initialize module paths if not already set
            if (-not $script:ModuleRootPath) {
                $script:ModuleRootPath = Get-EntraModuleRoot
                Write-Verbose "Module root path set to: $script:ModuleRootPath"
                
                if ($script:ModuleRootPath) {
                    $script:ConfigPath = Join-Path -Path $script:ModuleRootPath -ChildPath "Config"
                    $script:KnownServicesPath = Join-Path -Path $script:ConfigPath -ChildPath "KnownServices.json"
                    
                    Write-Verbose "Config path set to: $script:ConfigPath"
                    Write-Verbose "KnownServices path set to: $script:KnownServicesPath"
                }
                else {
                    Write-Error "Failed to determine module root path"
                    return $false
                }
            }
            
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
                
                Write-Verbose "KnownServices cache initialized"
            }
            else {
                Write-Verbose "KnownServices cache already initialized"
            }
            
            # Initialize storage preference cache
            if (-not $script:KnownServicesPreference) {
                $script:KnownServicesPreference = $null
                Write-Verbose "KnownServices preference cache initialized"
            }
            
            return $true
        }
        catch {
            Write-Error "Failed to initialize KnownServices cache: $_"
            return $false
        }
    }
}

# Initialize cache when module is loaded
Initialize-EntraKnownServicesCache
