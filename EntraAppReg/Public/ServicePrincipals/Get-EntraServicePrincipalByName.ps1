<#
.SYNOPSIS
    Gets a service principal by its display name.

.DESCRIPTION
    The Get-EntraServicePrincipalByName function retrieves a service principal from Entra ID
    by searching for its display name. It can return multiple service principals if there are
    multiple matches for the display name.

.PARAMETER DisplayName
    The display name of the service principal to retrieve.

.PARAMETER ExactMatch
    When specified, only returns service principals that exactly match the display name.
    By default, a partial match is performed.

.PARAMETER All
    When specified, returns all matching service principals. By default, only the first 100 are returned.

.PARAMETER Top
    The maximum number of results to return. Default is 100.

.EXAMPLE
    Get-EntraServicePrincipalByName -DisplayName "Microsoft Graph"
    Gets service principals with display names containing "Microsoft Graph".

.EXAMPLE
    Get-EntraServicePrincipalByName -DisplayName "Microsoft Graph" -ExactMatch
    Gets service principals with display name exactly matching "Microsoft Graph".

.NOTES
    This function requires an active connection to the Microsoft Graph API.
    Use Connect-EntraGraphSession before calling this function.
#>
function Get-EntraServicePrincipalByName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [switch]$ExactMatch,

        [Parameter(Mandatory = $false)]
        [switch]$All,

        [Parameter(Mandatory = $false)]
        [int]$Top = 100
    )

    begin {
        Write-Verbose "Getting service principal by display name: $DisplayName"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection)) {
            throw "No active Microsoft Graph connection. Please connect using Connect-EntraGraphSession first."
        }
    }

    process {
        try {
            # Construct the filter based on whether exact match is required
            if ($ExactMatch) {
                $filter = "displayName eq '$DisplayName'"
            }
            else {
                # Use startsWith operator for partial match - contains isn't supported
                $filter = "startswith(displayName, '$DisplayName')"
            }

            # Construct the URI with filter
            $uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$filter"
            
            # Add top parameter if not requesting all results
            if (-not $All) {
                $uri += "&`$top=$Top"
            }

            # Execute the request
            $response = Invoke-EntraGraphRequest -Uri $uri -Method GET

            # Check if we got any results
            if ($response.value -and $response.value.Count -gt 0) {
                Write-Verbose "Found $($response.value.Count) service principal(s) matching '$DisplayName'"
                return $response.value
            }
            else {
                Write-Verbose "No service principals found matching '$DisplayName'"
                return $null
            }
        }
        catch {
            Write-Error "Error retrieving service principal by name: $_"
            throw $_
        }
    }
}
