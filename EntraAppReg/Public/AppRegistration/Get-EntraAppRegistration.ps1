<#
.SYNOPSIS
    Gets app registrations from Microsoft Entra ID.

.DESCRIPTION
    The Get-EntraAppRegistration function retrieves app registrations from Microsoft Entra ID.
    It can retrieve a specific app by ID or display name, or return all app registrations
    in the tenant. The function supports filtering by display name pattern and limiting
    the number of results returned.

.PARAMETER ObjectId
    The object ID (GUID) of the app registration to retrieve.

.PARAMETER AppId
    The application ID (client ID) of the app registration to retrieve.

.PARAMETER DisplayName
    The display name of the app registration(s) to retrieve.

.PARAMETER ExactMatch
    When specified with DisplayName, only returns app registrations that exactly match the display name.
    By default, a partial match is performed.

.PARAMETER Filter
    Custom OData filter to apply to the request.

.PARAMETER All
    When specified, returns all app registrations. By default, only the first 100 are returned.

.PARAMETER Top
    The maximum number of results to return. Default is 100.

.EXAMPLE
    Get-EntraAppRegistration -ObjectId "00000000-0000-0000-0000-000000000000"
    Gets the app registration with the specified object ID.

.EXAMPLE
    Get-EntraAppRegistration -AppId "00000000-0000-0000-0000-000000000000"
    Gets the app registration with the specified application (client) ID.

.EXAMPLE
    Get-EntraAppRegistration -DisplayName "My App"
    Gets app registrations with display names containing "My App".

.EXAMPLE
    Get-EntraAppRegistration -DisplayName "My App" -ExactMatch
    Gets app registrations with display name exactly matching "My App".

.EXAMPLE
    Get-EntraAppRegistration -All
    Gets all app registrations in the tenant.

.EXAMPLE
    Get-EntraAppRegistration -Filter "startsWith(displayName,'Test')"
    Gets app registrations with display names starting with 'Test'.

.NOTES
    This function requires an active connection to the Microsoft Graph API with Application.Read.All permission.
    Use Connect-EntraGraphSession before calling this function.
#>
function Get-EntraAppRegistration {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [string]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByAppId')]
        [string]$AppId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByDisplayName')]
        [string]$DisplayName,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByDisplayName')]
        [switch]$ExactMatch,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByFilter')]
        [string]$Filter,

        [Parameter(Mandatory = $false, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory = $false, ParameterSetName = 'All')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByDisplayName')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByFilter')]
        [int]$Top = 100
    )

    begin {
        Write-Verbose "Getting app registration(s)"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection)) {
            throw "No active Microsoft Graph connection. Please connect using Connect-EntraGraphSession first."
        }
    }

    process {
        try {
            $baseUri = "https://graph.microsoft.com/v1.0/applications"

            # Handle different parameter sets
            switch ($PSCmdlet.ParameterSetName) {
                'ById' {
                    $uri = "$baseUri/$ObjectId"
                    Write-Verbose "Getting app registration by object ID: $ObjectId"
                    $response = Invoke-EntraGraphRequest -Uri $uri -Method GET
                    return $response
                }
                'ByAppId' {
                    $uri = "$baseUri?`$filter=appId eq '$AppId'"
                    Write-Verbose "Getting app registration by application ID: $AppId"
                    $response = Invoke-EntraGraphRequest -Uri $uri -Method GET
                    
                    if ($response.value -and $response.value.Count -gt 0) {
                        return $response.value[0]
                    } else {
                        Write-Verbose "No app registration found with application ID: $AppId"
                        return $null
                    }
                }
                'ByDisplayName' {
                    # Construct the filter based on whether exact match is required
                    if ($ExactMatch) {
                        $uri = "$baseUri?`$filter=displayName eq '$DisplayName'"
                    }
                    else {
                        # Use startsWith for partial match since contains isn't widely supported
                        $uri = "$baseUri?`$filter=startswith(displayName, '$DisplayName')"
                    }

                    # Add top parameter if not requesting all results
                    if (-not $All) {
                        $uri += "&`$top=$Top"
                    }

                    Write-Verbose "Getting app registrations by display name: $DisplayName"
                    $response = Invoke-EntraGraphRequest -Uri $uri -Method GET
                    
                    if ($response.value -and $response.value.Count -gt 0) {
                        Write-Verbose "Found $($response.value.Count) app registration(s) matching '$DisplayName'"
                        return $response.value
                    } else {
                        Write-Verbose "No app registrations found matching '$DisplayName'"
                        return $null
                    }
                }
                'ByFilter' {
                    $uri = "$baseUri?`$filter=$Filter"
                    
                    # Add top parameter if not requesting all results
                    if (-not $All) {
                        $uri += "&`$top=$Top"
                    }

                    Write-Verbose "Getting app registrations using filter: $Filter"
                    $response = Invoke-EntraGraphRequest -Uri $uri -Method GET
                    
                    if ($response.value -and $response.value.Count -gt 0) {
                        Write-Verbose "Found $($response.value.Count) app registration(s) using filter"
                        return $response.value
                    } else {
                        Write-Verbose "No app registrations found using filter"
                        return $null
                    }
                }
                'All' {
                    $uri = "$baseUri"
                    
                    # Add top parameter if not requesting all results
                    if (-not $All) {
                        $uri += "?`$top=$Top"
                    }

                    Write-Verbose "Getting all app registrations"
                    $response = Invoke-EntraGraphRequest -Uri $uri -Method GET
                    
                    if ($response.value -and $response.value.Count -gt 0) {
                        Write-Verbose "Found $($response.value.Count) app registration(s)"
                        return $response.value
                    } else {
                        Write-Verbose "No app registrations found"
                        return $null
                    }
                }
            }
        }
        catch {
            Write-Error "Failed to get app registration(s): $_"
            throw $_
        }
    }
}
