<#
.SYNOPSIS
    Gets the normalized KnownServices configuration.

.DESCRIPTION
    The Get-EntraNormalizedKnownServices function loads the normalized KnownServices
    configuration from disk or cache, based on the specified parameters.

.PARAMETER ConfigPath
    The path where the configuration files are stored. If not specified, the default
    configuration path will be used.

.PARAMETER Force
    Forces a reload from disk even if the cache is valid.

.PARAMETER Component
    The specific component to load. Valid values are 'Index', 'ServicePrincipals',
    'PermissionDefinitions', 'ServicePermissionMappings', 'CommonPermissions', or 'All'.
    Default is 'All'.

.EXAMPLE
    Get-EntraNormalizedKnownServices
    Gets all normalized KnownServices configuration.

.EXAMPLE
    Get-EntraNormalizedKnownServices -Component ServicePrincipals
    Gets only the ServicePrincipals component of the normalized KnownServices configuration.

.EXAMPLE
    Get-EntraNormalizedKnownServices -Force
    Forces a reload of all normalized KnownServices configuration from disk.

.NOTES
    This function is part of the EntraAppReg module's normalized storage approach introduced
    in v3.0 to improve performance and reduce storage requirements.
#>
function Get-EntraNormalizedKnownServices {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Index', 'ServicePrincipals', 'PermissionDefinitions', 'ServicePermissionMappings', 'CommonPermissions', 'All')]
        [string]$Component = 'All'
    )

    begin {
        # Set module paths if not already set
        if (-not $script:ModuleRootPath) {
            $script:ModuleRootPath = Get-EntraModuleRoot
            Write-Verbose "Module root path set to: $script:ModuleRootPath"
            
            $script:ConfigPath = Join-Path -Path $script:ModuleRootPath -ChildPath "Config"
            Write-Verbose "Default config path set to: $script:ConfigPath"
        }
        
        # Use default ConfigPath if not provided
        if (-not $ConfigPath) {
            $ConfigPath = $script:ConfigPath
            Write-Verbose "Using default config path: $ConfigPath"
        }
        Write-Verbose "Loading normalized KnownServices configuration from $ConfigPath"
        
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
        
        # Define file paths
        $indexPath = Join-Path -Path $ConfigPath -ChildPath "KnownServicesIndex.json"
        
        # Check if normalized structure exists
        if (-not (Test-Path -Path $indexPath)) {
            Write-Warning "Normalized KnownServices structure not found at $ConfigPath"
            return $null
        }
    }

    process {
        try {
            # Always load the index file first if needed
            if ($Force -or $null -eq $script:KnownServicesCache.Index) {
                if (Test-Path -Path $indexPath) {
                    $script:KnownServicesCache.Index = Get-Content -Path $indexPath -Raw | ConvertFrom-Json
                    Write-Verbose "Loaded KnownServicesIndex from $indexPath"
                }
                else {
                    Write-Warning "KnownServicesIndex not found at $indexPath"
                    return $null
                }
            }
            
            # Get the index
            $index = $script:KnownServicesCache.Index
            
            # Load the requested component(s)
            if ($Component -eq 'Index' -or $Component -eq 'All') {
                # Already loaded above
                if ($Component -eq 'Index') {
                    return $index
                }
            }
            
            if ($Component -eq 'ServicePrincipals' -or $Component -eq 'All') {
                if ($Force -or $null -eq $script:KnownServicesCache.ServicePrincipals) {
                    $servicePrincipalsPath = Join-Path -Path $ConfigPath -ChildPath $index.Files.ServicePrincipals
                    if (Test-Path -Path $servicePrincipalsPath) {
                        $script:KnownServicesCache.ServicePrincipals = Get-Content -Path $servicePrincipalsPath -Raw | ConvertFrom-Json
                        Write-Verbose "Loaded ServicePrincipals from $servicePrincipalsPath"
                    }
                    else {
                        Write-Warning "ServicePrincipals not found at $servicePrincipalsPath"
                    }
                }
                
                if ($Component -eq 'ServicePrincipals') {
                    return $script:KnownServicesCache.ServicePrincipals
                }
            }
            
            if ($Component -eq 'PermissionDefinitions' -or $Component -eq 'All') {
                if ($Force -or $null -eq $script:KnownServicesCache.PermissionDefinitions) {
                    $permissionDefinitionsPath = Join-Path -Path $ConfigPath -ChildPath $index.Files.PermissionDefinitions
                    if (Test-Path -Path $permissionDefinitionsPath) {
                        $script:KnownServicesCache.PermissionDefinitions = Get-Content -Path $permissionDefinitionsPath -Raw | ConvertFrom-Json
                        Write-Verbose "Loaded PermissionDefinitions from $permissionDefinitionsPath"
                    }
                    else {
                        Write-Warning "PermissionDefinitions not found at $permissionDefinitionsPath"
                    }
                }
                
                if ($Component -eq 'PermissionDefinitions') {
                    return $script:KnownServicesCache.PermissionDefinitions
                }
            }
            
            if ($Component -eq 'ServicePermissionMappings' -or $Component -eq 'All') {
                if ($Force -or $null -eq $script:KnownServicesCache.ServicePermissionMappings) {
                    $servicePermissionMappingsPath = Join-Path -Path $ConfigPath -ChildPath $index.Files.ServicePermissionMappings
                    if (Test-Path -Path $servicePermissionMappingsPath) {
                        $script:KnownServicesCache.ServicePermissionMappings = Get-Content -Path $servicePermissionMappingsPath -Raw | ConvertFrom-Json
                        Write-Verbose "Loaded ServicePermissionMappings from $servicePermissionMappingsPath"
                    }
                    else {
                        Write-Warning "ServicePermissionMappings not found at $servicePermissionMappingsPath"
                    }
                }
                
                if ($Component -eq 'ServicePermissionMappings') {
                    return $script:KnownServicesCache.ServicePermissionMappings
                }
            }
            
            if ($Component -eq 'CommonPermissions' -or $Component -eq 'All') {
                if ($Force -or $null -eq $script:KnownServicesCache.CommonPermissions) {
                    $commonPermissionsPath = Join-Path -Path $ConfigPath -ChildPath $index.Files.LegacyCommonPermissions
                    if (Test-Path -Path $commonPermissionsPath) {
                        $script:KnownServicesCache.CommonPermissions = Get-Content -Path $commonPermissionsPath -Raw | ConvertFrom-Json
                        Write-Verbose "Loaded CommonPermissions from $commonPermissionsPath"
                    }
                    else {
                        Write-Warning "CommonPermissions not found at $commonPermissionsPath"
                    }
                }
                
                if ($Component -eq 'CommonPermissions') {
                    return $script:KnownServicesCache.CommonPermissions
                }
            }
            
            # Update the last refresh timestamp
            $script:KnownServicesCache.LastRefresh = Get-Date
            
            # If we got here and Component is 'All', return a consolidated object
            if ($Component -eq 'All') {
                return [PSCustomObject]@{
                    Index = $script:KnownServicesCache.Index
                    ServicePrincipals = $script:KnownServicesCache.ServicePrincipals
                    PermissionDefinitions = $script:KnownServicesCache.PermissionDefinitions
                    ServicePermissionMappings = $script:KnownServicesCache.ServicePermissionMappings
                    CommonPermissions = $script:KnownServicesCache.CommonPermissions
                }
            }
        }
        catch {
            Write-Error "Failed to load normalized KnownServices configuration: $_"
            return $null
        }
    }
}
