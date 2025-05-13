<#
.SYNOPSIS
    Tests if there is an active connection to the Microsoft Graph API.

.DESCRIPTION
    The Test-EntraGraphConnection function checks if there is an active connection to the Microsoft Graph API
    and optionally verifies that the connection has the required scopes (permissions).

.PARAMETER RequiredScopes
    The scopes (permissions) that the connection should have. If specified, the function will verify
    that the connection has these scopes.

.EXAMPLE
    Test-EntraGraphConnection
    Tests if there is an active connection to the Microsoft Graph API.

.EXAMPLE
    Test-EntraGraphConnection -RequiredScopes "Application.ReadWrite.All"
    Tests if there is an active connection with the specified scope.

.EXAMPLE
    if (-not (Test-EntraGraphConnection)) {
        Connect-EntraGraphSession
    }
    Connects to Microsoft Graph API only if there's no active connection.

.NOTES
    This function requires the Microsoft.Graph.Authentication module.
#>
function Test-EntraGraphConnection {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredScopes
    )

    begin {
        Write-Verbose "Testing Microsoft Graph API connection..."
    }

    process {
        try {
            # Get current connection context
            $context = Get-MgContext

            # Check if we have a context
            if (-not $context) {
                Write-Verbose "No active Microsoft Graph connection found"
                return $false
            }

            # Check if we have the required scopes
            if ($RequiredScopes) {
                $missingScopes = @()
                foreach ($scope in $RequiredScopes) {
                    if ($context.Scopes -notcontains $scope) {
                        $missingScopes += $scope
                    }
                }

                if ($missingScopes.Count -gt 0) {
                    Write-Verbose "Connection is missing required scopes: $($missingScopes -join ', ')"
                    return $false
                }
            }

            # Connection is valid
            Write-Verbose "Active Microsoft Graph connection confirmed"
            return $true
        }
        catch {
            Write-Verbose "Error checking Microsoft Graph connection: $_"
            return $false
        }
    }
}
