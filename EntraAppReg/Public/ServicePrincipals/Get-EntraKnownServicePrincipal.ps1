<#
.SYNOPSIS
    Gets information about well-known service principals from Entra ID.

.DESCRIPTION
    The Get-EntraKnownServicePrincipal function retrieves information about well-known
    service principals from Entra ID, such as Microsoft Graph, Office 365, etc.
    It uses the KnownServices.json configuration file to identify these service principals.

.PARAMETER ServiceName
    The name of the service to retrieve. If not specified, returns all known services.

.PARAMETER RefreshCache
    When specified, forces a refresh of the KnownServices cache before retrieving the service principal.

.PARAMETER IncludeServicePrincipal
    When specified, retrieves the full service principal object from Entra ID.
    By default, only the cached information is returned.

.EXAMPLE
    Get-EntraKnownServicePrincipal
    Gets all known service principals from the local cache.

.EXAMPLE
    Get-EntraKnownServicePrincipal -ServiceName "Microsoft Graph"
    Gets information about the Microsoft Graph service principal from the local cache.

.EXAMPLE
    Get-EntraKnownServicePrincipal -RefreshCache -IncludeServicePrincipal
    Refreshes the KnownServices cache and retrieves all known service principals with their full details.

.NOTES
    This function requires an active connection to the Microsoft Graph API when IncludeServicePrincipal
    or RefreshCache is specified. Use Connect-EntraGraphSession before calling this function.
#>
function Get-EntraKnownServicePrincipal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$ServiceName,

        [Parameter(Mandatory = $false)]
        [switch]$RefreshCache,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeServicePrincipal
    )

    begin {
        Write-Verbose "Getting known service principal information"

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

            # Filter by service name if provided
            if ($ServiceName) {
                # Convert from PSCustomObject to collection of objects with key as a property
                $servicesList = $services.PSObject.Properties | ForEach-Object {
                    [PSCustomObject]@{
                        ServiceName = $_.Name
                        DisplayName = $_.Value.DisplayName
                        AppId = $_.Value.AppId
                        Description = $_.Value.Description
                    }
                }
                
                $servicesList = $servicesList | Where-Object { 
                    $_.DisplayName -like "*$ServiceName*" -or 
                    $_.ServiceName -like "*$ServiceName*" -or 
                    $_.AppId -eq $ServiceName 
                }
                
                if (-not $servicesList) {
                    Write-Verbose "No known services found matching '$ServiceName'."
                    return $null
                }
                $services = $servicesList
            } else {
                # Convert from PSCustomObject to collection of objects with key as a property
                $services = $services.PSObject.Properties | ForEach-Object {
                    [PSCustomObject]@{
                        ServiceName = $_.Name
                        DisplayName = $_.Value.DisplayName
                        AppId = $_.Value.AppId
                        Description = $_.Value.Description
                    }
                }
            }

            # If we need to include full service principal details
            if ($IncludeServicePrincipal) {
                $result = @()
                foreach ($service in $services) {
                    $servicePrincipal = Get-EntraServicePrincipalByAppId -AppId $service.AppId
                    
                    if ($servicePrincipal) {
                        # Create a custom object that combines our cached data with the service principal
                        $combinedInfo = [PSCustomObject]@{
                            ServiceName = $service.ServiceName
                            DisplayName = $service.DisplayName
                            AppId = $service.AppId
                            Description = $service.Description
                            ServicePrincipal = $servicePrincipal
                        }
                        $result += $combinedInfo
                    }
                }
                
                return $result
            }
            else {
                # Return just the cached information
                return $services
            }
        }
        catch {
            Write-Error "Error retrieving known service principals: $_"
            throw $_
        }
    }
}
