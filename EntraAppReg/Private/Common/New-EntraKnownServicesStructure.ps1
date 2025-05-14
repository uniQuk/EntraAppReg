<#
.SYNOPSIS
    Creates a new normalized structure for KnownServices configuration.

.DESCRIPTION
    The New-EntraKnownServicesStructure function creates a new normalized structure for
    KnownServices configuration, splitting the monolithic KnownServices.json file into
    multiple smaller files for better performance and maintainability.

.PARAMETER ConfigPath
    The path where the configuration files will be created. If not specified, the default
    configuration path will be used.

.PARAMETER Force
    Forces the creation of the structure even if it already exists.

.EXAMPLE
    New-EntraKnownServicesStructure
    Creates a new normalized structure for KnownServices configuration in the default location.

.EXAMPLE
    New-EntraKnownServicesStructure -ConfigPath "C:\Config" -Force
    Creates a new normalized structure for KnownServices configuration in the specified location,
    overwriting any existing files.

.NOTES
    This function is part of the EntraAppReg module's normalized storage approach introduced
    in v3.0 to improve performance and reduce storage requirements.
#>
function New-EntraKnownServicesStructure {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force
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
        
        Write-Verbose "Creating new EntraKnownServices normalized structure in $ConfigPath"
        
        # Ensure the config path exists
        if (-not (Test-Path -Path $ConfigPath)) {
            try {
                New-Item -Path $ConfigPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created config directory at $ConfigPath"
            }
            catch {
                Write-Error "Failed to create config directory at ${ConfigPath}: $_"
                return $false
            }
        }
        
        # Define file paths
        $indexPath = Join-Path -Path $ConfigPath -ChildPath "KnownServicesIndex.json"
        $servicePrincipalsPath = Join-Path -Path $ConfigPath -ChildPath "ServicePrincipals.json"
        $permissionDefinitionsPath = Join-Path -Path $ConfigPath -ChildPath "PermissionDefinitions.json"
        $servicePermissionMappingsPath = Join-Path -Path $ConfigPath -ChildPath "ServicePermissionMappings.json"
        $commonPermissionsPath = Join-Path -Path $ConfigPath -ChildPath "CommonPermissions.json"
    }

    process {
        try {
            # Check if files already exist and exit if not forcing
            $existingFiles = @(
                $indexPath,
                $servicePrincipalsPath,
                $permissionDefinitionsPath,
                $servicePermissionMappingsPath,
                $commonPermissionsPath
            ) | Where-Object { Test-Path -Path $_ }
            
            if ($existingFiles.Count -gt 0 -and -not $Force) {
                Write-Warning "The following files already exist: $($existingFiles -join ', ')"
                Write-Warning "Use -Force to overwrite existing files."
                return $false
            }
            
            # Create index file
            $knownServicesIndex = @{
                Metadata = @{
                    LastUpdated = [DateTime]::UtcNow.ToString("o")
                    RefreshIntervalDays = 30
                    AutoRefreshEnabled = $true
                    Version = "3.0"
                }
                Configuration = @{
                    IncludeMicrosoftGraph = $false
                    IncludeCustomApis = $false
                }
                Files = @{
                    ServicePrincipals = "ServicePrincipals.json"
                    PermissionDefinitions = "PermissionDefinitions.json"
                    ServicePermissionMappings = "ServicePermissionMappings.json"
                    LegacyCommonPermissions = "CommonPermissions.json"
                }
            }
            
            # Create service principals file
            $servicePrincipals = @{}
            
            # Create permission definitions file
            $permissionDefinitions = @{
                Application = @{}
                Delegated = @{}
            }
            
            # Create service permission mappings file
            $servicePermissionMappings = @{}
            
            # Create common permissions file (legacy format)
            $commonPermissions = @{}
            
            # Save files
            ConvertTo-Json -InputObject $knownServicesIndex -Depth 4 | Out-File -FilePath $indexPath -Force
            ConvertTo-Json -InputObject $servicePrincipals -Depth 4 | Out-File -FilePath $servicePrincipalsPath -Force
            ConvertTo-Json -InputObject $permissionDefinitions -Depth 4 | Out-File -FilePath $permissionDefinitionsPath -Force
            ConvertTo-Json -InputObject $servicePermissionMappings -Depth 4 | Out-File -FilePath $servicePermissionMappingsPath -Force
            ConvertTo-Json -InputObject $commonPermissions -Depth 4 | Out-File -FilePath $commonPermissionsPath -Force
            
            Write-Verbose "Created normalized KnownServices structure at $ConfigPath"
            Write-Verbose "Created $indexPath"
            Write-Verbose "Created $servicePrincipalsPath"
            Write-Verbose "Created $permissionDefinitionsPath"
            Write-Verbose "Created $servicePermissionMappingsPath"
            Write-Verbose "Created $commonPermissionsPath"
            
            return $true
        }
        catch {
            Write-Error "Failed to create normalized KnownServices structure: $_"
            return $false
        }
    }
}
