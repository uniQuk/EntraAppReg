<#
.SYNOPSIS
    Gets information about well-known service principals from Entra ID.

.DESCRIPTION
    The Get-EntraKnownServicePrincipal function retrieves information about well-known
    service principals from Entra ID, such as Microsoft Graph, Office 365, etc.
    It uses the KnownServices configuration files to identify these service principals.
    
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
    
.PARAMETER UseNormalizedStorage
    When specified, uses the normalized KnownServices configuration files instead of the legacy format.
    The normalized format splits data across multiple files for better performance and reduced storage requirements.

.EXAMPLE
    Get-EntraKnownServicePrincipal
    Gets all known service principals from the local cache.

.EXAMPLE
    Get-EntraKnownServicePrincipal -ServiceName "Microsoft Graph"
    Gets information about the Microsoft Graph service principal from the local cache.

.EXAMPLE
    Get-EntraKnownServicePrincipal -RefreshCache -IncludeServicePrincipal
    Refreshes the KnownServices cache and retrieves all known service principals with their full details.
    
.EXAMPLE
    Get-EntraKnownServicePrincipal -ServiceName "Microsoft Graph" -IncludePermissions
    Gets information about the Microsoft Graph service principal including its application and delegated permissions.
    
.EXAMPLE
    Get-EntraKnownServicePrincipal -UseNormalizedStorage -ServiceName "Microsoft Graph" -IncludePermissions
    Gets information about the Microsoft Graph service principal using the normalized storage format.

.NOTES
    This function requires an active connection to the Microsoft Graph API when IncludeServicePrincipal
    or RefreshCache is specified. Use Connect-EntraGraphSession before calling this function.
    
    Starting from v3.0, this function can use a normalized storage format that splits data across
    multiple files for better performance and reduced storage requirements. Use the -UseNormalizedStorage
    parameter to enable this feature. In a future version, the normalized format will become the default.
#>
function Get-EntraKnownServicePrincipal {
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
        [switch]$UseNormalizedStorage
    )

    begin {
        Write-Verbose "Getting known service principal information"

        # Determine which storage format to use
        $configPath = Split-Path -Path $script:KnownServicesPath -Parent
        
        # If UseNormalizedStorage is explicitly specified, use it
        # Otherwise, check for auto-detection if no parameter is specified
        if ($UseNormalizedStorage -or 
            ((-not $PSBoundParameters.ContainsKey('UseNormalizedStorage')) -and 
             (Get-EntraStoragePreference).UseNormalizedStorage)) {
                 
            Write-Verbose "Using normalized storage format"
            
            $result = Get-EntraNormalizedKnownServicePrincipal `
                -ServiceName $ServiceName `
                -RefreshCache:$RefreshCache `
                -IncludeServicePrincipal:$IncludeServicePrincipal `
                -IncludePermissions:$IncludePermissions `
                -ConfigPath $configPath
            
            return $result
        }
        
        # Continue with legacy format
        Write-Verbose "Using legacy storage format"
        
        # Check if KnownServices.json exists and refresh if needed or requested
        if ($RefreshCache -or -not (Test-Path -Path $script:KnownServicesPath) -or (Test-EntraKnownServicesAge)) {
            Write-Verbose "KnownServices cache needs to be refreshed"
            
            # Ensure we have an active Graph connection for refresh
            if (-not (Test-EntraGraphConnection)) {
                throw "No active Microsoft Graph connection for cache refresh. Please connect using Connect-EntraGraphSession first."
            }
            
            # Update the KnownServices configuration
            if (-not (Update-EntraKnownServices -Force)) {
                throw "Failed to update KnownServices configuration."
            }
        }

        # Ensure KnownServices is loaded
        if (-not $script:KnownServices) {
            try {
                $script:KnownServices = Get-Content -Path $script:KnownServicesPath -Raw | ConvertFrom-Json
                Write-Verbose "Loaded KnownServices configuration from $script:KnownServicesPath"
            }
            catch {
                throw "Failed to load KnownServices configuration: $_"
            }
        }

        # Check if we need to connect to Graph for service principal details
        if ($IncludeServicePrincipal -and -not (Test-EntraGraphConnection)) {
            throw "No active Microsoft Graph connection for retrieving service principal details. Please connect using Connect-EntraGraphSession first."
        }
    }

    process {
        try {
            # Get the services collection from the KnownServices
            $services = $script:KnownServices.ServicePrincipals
            
            if (-not $services) {
                Write-Warning "No service principals found in KnownServices configuration."
                return $null
            }

            # Convert from PSCustomObject to collection of objects with key as a property
            $servicesList = $services.PSObject.Properties | ForEach-Object {
                [PSCustomObject]@{
                    ServiceName = $_.Name
                    DisplayName = $_.Value.DisplayName
                    AppId = $_.Value.AppId
                    Description = $_.Value.Description
                }
            }
            
            # Filter by service name if provided
            if ($ServiceName) {
                # Try different matching approaches (normalized, case-insensitive)
                $servicesList = $servicesList | Where-Object { 
                    $_.DisplayName -like "*$ServiceName*" -or 
                    $_.ServiceName -like "*$ServiceName*" -or 
                    $_.AppId -eq $ServiceName -or
                    $_.DisplayName -replace '\s', '' -like "*$($ServiceName -replace '\s', '')*" -or
                    $_.ServiceName -replace '\s', '' -like "*$($ServiceName -replace '\s', '')*"
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
            
            # Services list is now prepared

            # Build result based on requested information
            $result = @()
            foreach ($service in $servicesList) {
                # Create a combined info object with basic service information
                $combinedInfo = [PSCustomObject]@{
                    ServiceName = $service.ServiceName
                    DisplayName = $service.DisplayName
                    AppId = $service.AppId
                    Description = $service.Description
                }
                
                Write-Verbose "Processing service: $($service.DisplayName) (ServiceName: $($service.ServiceName))"
                
                # Add permissions if requested
                if ($IncludePermissions) {
                    try {
                        $applicationPermissions = @()
                        $delegatedPermissions = @() 
                        $hasPermissionsV2 = $false

                        # Try to get permissions from the new schema (v2.0)
                        if ($script:KnownServices.Permissions) {
                            # Get the correct service name key for accessing permissions
                            $permServiceName = $service.ServiceName
                            
                            # Check if this service has permissions data
                            if ($script:KnownServices.Permissions.PSObject.Properties.Name -contains $permServiceName) {
                                $hasPermissionsV2 = $true
                                Write-Verbose "Found v2.0 permissions data for $permServiceName"
                                
                                $permissionsData = $script:KnownServices.Permissions.$permServiceName
                                
                                # Process application permissions if they exist
                                if ($permissionsData.PSObject.Properties.Name -contains "Application" -and $permissionsData.Application.PSObject.Properties.Count -gt 0) {
                                    Write-Verbose "Processing application permissions for $permServiceName"
                                    $appPerms = $permissionsData.Application
                                    
                                    foreach ($permName in $appPerms.PSObject.Properties.Name) {
                                        $perm = $appPerms.$permName
                                        $applicationPermissions += [PSCustomObject]@{
                                            Name = $permName
                                            Id = $perm.Id
                                            DisplayName = $perm.DisplayName
                                            Description = $perm.Description
                                            AllowedMemberTypes = $perm.AllowedMemberTypes
                                        }
                                    }
                                }
                                
                                # Process delegated permissions if they exist
                                if ($permissionsData.PSObject.Properties.Name -contains "Delegated" -and $permissionsData.Delegated.PSObject.Properties.Count -gt 0) {
                                    Write-Verbose "Processing delegated permissions for $permServiceName"
                                    $delPerms = $permissionsData.Delegated
                                    
                                    foreach ($permName in $delPerms.PSObject.Properties.Name) {
                                        $perm = $delPerms.$permName
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
                                
                                # Add these as separate properties
                                $combinedInfo | Add-Member -MemberType NoteProperty -Name "ApplicationPermissions" -Value $applicationPermissions -Force
                                $combinedInfo | Add-Member -MemberType NoteProperty -Name "DelegatedPermissions" -Value $delegatedPermissions -Force
                            }
                        }
                        
                        # Fall back to legacy CommonPermissions if new schema not available
                        if (-not $hasPermissionsV2) {
                            if ($script:KnownServices.CommonPermissions -and 
                                $script:KnownServices.CommonPermissions.PSObject.Properties.Name -contains $service.ServiceName) {
                                Write-Verbose "Using legacy CommonPermissions for $($service.ServiceName)"
                                $permissionNames = $script:KnownServices.CommonPermissions.$($service.ServiceName)
                                $combinedInfo | Add-Member -MemberType NoteProperty -Name "Permissions" -Value $permissionNames -Force
                            } 
                            else {
                                $combinedInfo | Add-Member -MemberType NoteProperty -Name "Permissions" -Value @() -Force
                                Write-Verbose "No permissions found for $($service.ServiceName)"
                            }
                        }
                    }
                    catch {
                        Write-Error "Error retrieving permissions for $($service.ServiceName): $_"
                        $combinedInfo | Add-Member -MemberType NoteProperty -Name "Permissions" -Value @() -Force
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
            Write-Error "Error retrieving known service principals: $_"
            throw $_
        }
    }
}
