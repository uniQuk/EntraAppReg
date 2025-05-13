<#
.SYNOPSIS
    Disconnects from the active Microsoft Graph API session.

.DESCRIPTION
    The Disconnect-EntraGraphSession function terminates the active connection to the Microsoft Graph API.
    It clears any cached tokens and session state.

.EXAMPLE
    Disconnect-EntraGraphSession
    Disconnects from the active Microsoft Graph API session.

.NOTES
    This function requires the Microsoft.Graph.Authentication module.
#>
function Disconnect-EntraGraphSession {
    [CmdletBinding()]
    param ()

    begin {
        Write-Verbose "Disconnecting from Microsoft Graph API..."
    }

    process {
        try {
            # Disconnect from Microsoft Graph
            Disconnect-MgGraph

            # Clear the module variable
            $script:GraphConnection = $null
            
            # Return success
            Write-Verbose "Successfully disconnected from Microsoft Graph API"
            Write-Host "Disconnected from Microsoft Graph API" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to disconnect from Microsoft Graph: $_"
            return $false
        }
    }
}
