<#
.SYNOPSIS
    Gets information about well-known service principals from the normalized KnownServices configuration.

.DESCRIPTION
    The Get-EntraNormalizedKnownServicePrincipal function retrieves information about well-known
    service principals from the normalized KnownServices configuration, such as Microsoft Graph, 
    Office 365, etc. It uses the normalized storage format that splits data across multiple files
    for better performance and reduced storage requirements.
    
    The function can retrieve basic information about service principals or detailed
    information including their permissions (both application and delegated).

.PARAMETER ServiceName
    The name of the service to retrieve. If not specified, returns all known services.

.PARAMETER RefreshCache
    When specified, forces a refresh of the KnownServices cache before retrieving the service principal.

.PARAMETER IncludeServicePrincipal
    When specified, retrieves the full service principal object from Entra ID.
    By default, only the cached information is returned.
    
.PARAMETER IncludePermissions
    When specified, includes detailed permission information (application and delegated permissions)
    for the service principal(s) in the output.

.PARAMETER ConfigPath
    The path where the configuration files are stored. If not specified, the default
    configuration path will be used.

.EXAMPLE
    Get-EntraNormalizedKnownServicePrincipal
    Gets all known service principals from the local cache.

.EXAMPLE
    Get-EntraNormalizedKnownServicePrincipal -ServiceName "Microsoft Graph"
    Gets information about the Microsoft Graph service principal from the local cache.

.EXAMPLE
    Get-EntraNormalizedKnownServicePrincipal -RefreshCache -IncludeServicePrincipal
    Refreshes the KnownServices cache and retrieves all known service principals with their full details.
    
.EXAMPLE
    Get-EntraNormalizedKnownServicePrincipal -ServiceName "Microsoft Graph" -IncludePermissions
    Gets information about the Microsoft Graph service principal including its application and delegated permissions.

.NOTES
    This function requires an active connection to the Microsoft Graph API when IncludeServicePrincipal
    is specified. Use Connect-EntraGraphSession before calling this function.
#>
function Get-EntraNormalizedKnownServicePrincipal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$ServiceName,

        [Parameter(Mandatory = $false)]
        [switch]$RefreshCache,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeServicePrincipal,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludePermissions,
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    begin {
        Write-Verbose "Getting normalized known service principal information"
        
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

        # Define file paths
        $indexPath = Join-Path -Path $ConfigPath -ChildPath "KnownServicesIndex.json"
        
        # Check if normalized structure exists
        if (-not (Test-Path -Path $indexPath)) {
            Write-Warning "Normalized KnownServices structure not found at $ConfigPath"
            Write-Warning "KnownServicesIndex not found at $indexPath"
            Write-Error "Normalized KnownServices structure not found at $ConfigPath. Run Update-EntraNormalizedKnownServices first."
            return $null
        }
        
        # Check if we need to connect to Graph for service principal details
        if ($IncludeServicePrincipal -and -not (Test-EntraGraphConnection)) {
            throw "No active Microsoft Graph connection for retrieving service principal details. Please connect using Connect-EntraGraphSession first."
        }
    }

    process {
        try {
            # Load the normalized configuration
            $normalizedConfig = Get-EntraNormalizedKnownServices -ConfigPath $ConfigPath -Force:$RefreshCache -Component All
            
            if (-not $normalizedConfig) {
                Write-Error "Failed to load normalized KnownServices configuration."
                return $null
            }
            
            # Extract components
            $servicePrincipals = $normalizedConfig.ServicePrincipals
            $permissionDefinitions = $normalizedConfig.PermissionDefinitions
            $servicePermissionMappings = $normalizedConfig.ServicePermissionMappings
            
            if (-not $servicePrincipals) {
                Write-Warning "No service principals found in normalized KnownServices configuration."
                return $null
            }
            
            # Convert from PSCustomObject to collection of objects with key as a property
            $servicesList = $servicePrincipals.PSObject.Properties | ForEach-Object {
                [PSCustomObject]@{
                    ServiceName = $_.Name
                    DisplayName = $_.Value.DisplayName
                    AppId = $_.Value.AppId
                    Description = $_.Value.Description
                    ServicePrincipalId = $_.Value.ServicePrincipalId
                    Publisher = $_.Value.Publisher
                }
            }
            
            # Filter by service name if provided
            if ($ServiceName) {
                # Try different matching approaches (normalized, case-insensitive, etc.)
                $servicesList = $servicesList | Where-Object { 
                    $_.DisplayName -like "*$ServiceName*" -or 
                    $_.ServiceName -like "*$ServiceName*" -or 
                    $_.AppId -eq $ServiceName -or
                    ($_.DisplayName -replace '[^a-zA-Z0-9]', '') -like "*$($ServiceName -replace '[^a-zA-Z0-9]', '')*" -or
                    ($_.ServiceName -replace '[^a-zA-Z0-9]', '') -like "*$($ServiceName -replace '[^a-zA-Z0-9]', '')*"
                }
                
                if (-not $servicesList) {
                    Write-Verbose "No known services found matching '$ServiceName'."
                    return $null
                }
                
                Write-Verbose "Found $($servicesList.Count) service(s) matching '$ServiceName'"
                foreach ($svc in $servicesList) {
                    Write-Verbose "  - $($svc.DisplayName) (ServiceName: $($svc.ServiceName), AppId: $($svc.AppId))"
                }
            }
            
            # Build result based on requested information
            $result = @()
            foreach ($service in $servicesList) {
                # Create a combined info object with basic service information
                $combinedInfo = [PSCustomObject]@{
                    ServiceName = $service.ServiceName
                    DisplayName = $service.DisplayName
                    AppId = $service.AppId
                    Description = $service.Description
                    Publisher = $service.Publisher
                }
                
                Write-Verbose "Processing service: $($service.DisplayName) (ServiceName: $($service.ServiceName))"
                
                # Add permissions if requested
                if ($IncludePermissions) {
                    $applicationPermissions = @()
                    $delegatedPermissions = @()
                    
                    # Check if we have permissions data for this service
                    if ($servicePermissionMappings.PSObject.Properties.Name -contains $service.ServiceName) {
                        $serviceMappings = $servicePermissionMappings.($service.ServiceName)
                        Write-Verbose "Found permission mappings for $($service.ServiceName)"
                        
                        # Process application permissions
                        if ($serviceMappings.PSObject.Properties.Name -contains "Application" -and 
                            $serviceMappings.Application -and 
                            $serviceMappings.Application.Count -gt 0) {
                            
                            Write-Verbose "Processing application permissions for $($service.ServiceName)"
                            foreach ($permName in $serviceMappings.Application) {
                                if ($permissionDefinitions.Application.PSObject.Properties.Name -contains $permName) {
                                    $perm = $permissionDefinitions.Application.$permName
                                    $applicationPermissions += [PSCustomObject]@{
                                        Name = $permName
                                        Id = $perm.Id
                                        DisplayName = $perm.DisplayName
                                        Description = $perm.Description
                                        AllowedMemberTypes = $perm.AllowedMemberTypes
                                    }
                                }
                            }
                        }
                        
                        # Process delegated permissions
                        if ($serviceMappings.PSObject.Properties.Name -contains "Delegated" -and 
                            $serviceMappings.Delegated -and 
                            $serviceMappings.Delegated.Count -gt 0) {
                            
                            Write-Verbose "Processing delegated permissions for $($service.ServiceName)"
                            foreach ($permName in $serviceMappings.Delegated) {
                                if ($permissionDefinitions.Delegated.PSObject.Properties.Name -contains $permName) {
                                    $perm = $permissionDefinitions.Delegated.$permName
                                    $delegatedPermissions += [PSCustomObject]@{
                                        Name = $permName
                                        Id = $perm.Id
                                        DisplayName = $perm.DisplayName
                                        Description = $perm.Description
                                        UserConsentDisplayName = $perm.UserConsentDisplayName
                                        UserConsentDescription = $perm.UserConsentDescription
                                        Type = $perm.Type
                                    }
                                }
                            }
                        }
                        
                        $combinedInfo | Add-Member -MemberType NoteProperty -Name "ApplicationPermissions" -Value $applicationPermissions -Force
                        $combinedInfo | Add-Member -MemberType NoteProperty -Name "DelegatedPermissions" -Value $delegatedPermissions -Force
                    }
                    else {
                        Write-Verbose "No permission mappings found for $($service.ServiceName)"
                        $combinedInfo | Add-Member -MemberType NoteProperty -Name "ApplicationPermissions" -Value @() -Force
                        $combinedInfo | Add-Member -MemberType NoteProperty -Name "DelegatedPermissions" -Value @() -Force
                    }
                }
                
                # Add service principal if requested
                if ($IncludeServicePrincipal) {
                    $servicePrincipal = Get-EntraServicePrincipalByAppId -AppId $service.AppId
                    if ($servicePrincipal) {
                        $combinedInfo | Add-Member -MemberType NoteProperty -Name "ServicePrincipal" -Value $servicePrincipal
                    }
                }
                
                $result += $combinedInfo
            }
            
            return $result
        }
        catch {
            Write-Error "Error retrieving normalized known service principals: $_"
            throw $_
        }
    }
}
