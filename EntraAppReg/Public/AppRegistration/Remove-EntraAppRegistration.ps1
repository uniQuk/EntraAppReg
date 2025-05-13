<#
.SYNOPSIS
    Removes an app registration from Microsoft Entra ID.

.DESCRIPTION
    The Remove-EntraAppRegistration function deletes an app registration from Microsoft Entra ID.
    It can remove an app by its object ID, application ID (client ID), or display name.
    When removing by display name, an exact match is required to prevent accidental deletion.

.PARAMETER ObjectId
    The object ID (GUID) of the app registration to remove.

.PARAMETER AppId
    The application ID (client ID) of the app registration to remove.

.PARAMETER DisplayName
    The display name of the app registration to remove. Must be an exact match.

.PARAMETER Force
    When specified, suppresses confirmation prompts.

.PARAMETER PassThru
    When specified, returns the app registration that was removed.

.EXAMPLE
    Remove-EntraAppRegistration -ObjectId "00000000-0000-0000-0000-000000000000"
    Removes the app registration with the specified object ID after confirmation.

.EXAMPLE
    Remove-EntraAppRegistration -AppId "00000000-0000-0000-0000-000000000000" -Force
    Removes the app registration with the specified application ID without confirmation.

.EXAMPLE
    Remove-EntraAppRegistration -DisplayName "My Test App" -Force
    Removes the app registration with the exact display name "My Test App" without confirmation.

.EXAMPLE
    Get-EntraAppRegistration -DisplayName "Test" | Remove-EntraAppRegistration
    Pipes multiple app registrations to Remove-EntraAppRegistration and prompts for each.

.NOTES
    This function requires an active connection to the Microsoft Graph API with Application.ReadWrite.All permission.
    Use Connect-EntraGraphSession before calling this function.
#>
function Remove-EntraAppRegistration {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'ById', ValueFromPipelineByPropertyName = $true)]
        [Alias('id')]
        [string]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByAppId')]
        [string]$AppId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByDisplayName')]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    begin {
        Write-Verbose "Preparing to remove app registration(s)"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection -RequiredScopes "Application.ReadWrite.All")) {
            throw "No active Microsoft Graph connection with required permissions. Please connect using Connect-EntraGraphSession first."
        }
    }

    process {
        try {
            $appToRemove = $null

            # Get app registration based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'ById' {
                    Write-Verbose "Finding app registration by object ID: $ObjectId"
                    $appToRemove = Get-EntraAppRegistration -ObjectId $ObjectId
                }
                'ByAppId' {
                    Write-Verbose "Finding app registration by application ID: $AppId"
                    $appToRemove = Get-EntraAppRegistration -AppId $AppId
                }
                'ByDisplayName' {
                    Write-Verbose "Finding app registration by display name: $DisplayName"
                    $apps = Get-EntraAppRegistration -DisplayName $DisplayName -ExactMatch
                    
                    if ($apps -and $apps.Count -gt 1) {
                        Write-Error "Multiple app registrations found with display name '$DisplayName'. Please use ObjectId or AppId to specify a single app."
                        return
                    }
                    elseif ($apps) {
                        $appToRemove = $apps[0]
                    }
                    else {
                        Write-Error "No app registration found with display name: $DisplayName"
                        return
                    }
                }
            }

            # If app was found, remove it
            if ($appToRemove) {
                $appDisplayName = $appToRemove.displayName
                $appObjectId = $appToRemove.id
                
                $confirmMessage = "Are you sure you want to remove app registration '$appDisplayName' (ID: $appObjectId)?"
                if ($Force -or $PSCmdlet.ShouldProcess($appDisplayName, "Remove app registration")) {
                    Write-Verbose "Removing app registration: $appDisplayName (ID: $appObjectId)"
                    
                    $uri = "https://graph.microsoft.com/v1.0/applications/$appObjectId"
                    Invoke-EntraGraphRequest -Uri $uri -Method DELETE | Out-Null
                    
                    Write-Verbose "Successfully removed app registration: $appDisplayName"
                    
                    if ($PassThru) {
                        return $appToRemove
                    }
                }
            }
            else {
                Write-Error "App registration not found."
            }
        }
        catch {
            Write-Error "Failed to remove app registration: $_"
            throw $_
        }
    }
}
