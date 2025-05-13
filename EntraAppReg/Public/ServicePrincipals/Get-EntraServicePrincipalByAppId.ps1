<#
.SYNOPSIS
    Gets a service principal by its AppId (application ID).

.DESCRIPTION
    The Get-EntraServicePrincipalByAppId function retrieves a service principal from Entra ID
    using its application ID (client ID). This is a unique identifier for the application
    that the service principal represents.

.PARAMETER AppId
    The application ID (client ID) of the service principal to retrieve.

.EXAMPLE
    Get-EntraServicePrincipalByAppId -AppId "00000000-0000-0000-0000-000000000000"
    Gets the service principal with the specified application ID.

.NOTES
    This function requires an active connection to the Microsoft Graph API.
    Use Connect-EntraGraphSession before calling this function.
#>
function Get-EntraServicePrincipalByAppId {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$AppId
    )

    begin {
        Write-Verbose "Getting service principal by application ID: $AppId"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection)) {
            throw "No active Microsoft Graph connection. Please connect using Connect-EntraGraphSession first."
        }

        # Validate the AppId format (simple validation)
        if ($AppId -notmatch "^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$") {
            Write-Warning "The provided AppId '$AppId' does not appear to be a valid GUID format."
        }
    }

    process {
        try {
            # Construct the URI with filter for appId
            $filter = "appId eq '$AppId'"
            $uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$filter"

            # Execute the request
            $response = Invoke-EntraGraphRequest -Uri $uri -Method GET

            # Check if we got any results
            if ($response.value -and $response.value.Count -gt 0) {
                Write-Verbose "Found service principal with AppId '$AppId'"
                # Since appId should be unique, return the first (and likely only) result
                return $response.value[0]
            }
            else {
                Write-Verbose "No service principal found with AppId '$AppId'"
                return $null
            }
        }
        catch {
            Write-Error "Error retrieving service principal by AppId: $_"
            throw $_
        }
    }
}
