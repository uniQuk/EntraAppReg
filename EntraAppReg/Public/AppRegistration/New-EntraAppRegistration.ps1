<#
.SYNOPSIS
    Creates a new app registration in Microsoft Entra ID.

.DESCRIPTION
    The New-EntraAppRegistration function creates a new app registration in Microsoft Entra ID 
    with customizable properties and API permissions. It supports various permission types
    for common Microsoft services such as Microsoft Graph, Rights Management Services,
    and Exchange Online, as well as custom services.

.PARAMETER DisplayName
    The display name of the app registration.

.PARAMETER GraphPermissions
    An array of Microsoft Graph API permissions to request.

.PARAMETER RmsPermissions
    An array of Rights Management Services API permissions to request.

.PARAMETER ExchangePermissions
    An array of Exchange Online API permissions to request.

.PARAMETER CustomPermissions
    A hashtable of custom permissions where keys are service principal names or IDs
    and values are arrays of permission names.

.PARAMETER SignInAudience
    Specifies which Microsoft accounts are supported for the application.
    Options are: AzureADMyOrg, AzureADMultipleOrgs, AzureADandPersonalMicrosoftAccount, PersonalMicrosoftAccount.
    Default is AzureADMyOrg (single tenant).

.PARAMETER RedirectUris
    An array of URIs to which the OAuth 2.0 authorization server can redirect users
    after authentication.

.PARAMETER IdentifierUris
    An array of URIs that uniquely identify the application within its Azure AD tenant.

.PARAMETER Notes
    Additional notes to be stored with the application.

.EXAMPLE
    New-EntraAppRegistration -DisplayName "My API App" -GraphPermissions @("User.Read.All", "Directory.Read.All")
    Creates a new app registration with Microsoft Graph permissions.

.EXAMPLE
    New-EntraAppRegistration -DisplayName "RMS App" -RmsPermissions @("Content.SuperUser") -Notes "App for RMS operations"
    Creates a new app registration with RMS permissions and notes.

.EXAMPLE
    New-EntraAppRegistration -DisplayName "Multi-API App" -GraphPermissions @("User.Read") -ExchangePermissions @("full_access_as_app")
    Creates a new app registration with both Graph and Exchange Online permissions.

.EXAMPLE
    $customPerms = @{
        "Azure Key Vault" = @("user_impersonation")
        "Microsoft.Storage" = @("Delegated.FullControl")
    }
    New-EntraAppRegistration -DisplayName "Custom API App" -CustomPermissions $customPerms -SignInAudience "AzureADMultipleOrgs"
    Creates a new multi-tenant app registration with custom API permissions.

.NOTES
    This function requires an active connection to the Microsoft Graph API with Application.ReadWrite.All permission.
    Use Connect-EntraGraphSession before calling this function.
#>
function New-EntraAppRegistration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [string[]]$GraphPermissions = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$RmsPermissions = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$ExchangePermissions = @(),

        [Parameter(Mandatory = $false)]
        [hashtable]$CustomPermissions = @{},

        [Parameter(Mandatory = $false)]
        [ValidateSet("AzureADMyOrg", "AzureADMultipleOrgs", "AzureADandPersonalMicrosoftAccount", "PersonalMicrosoftAccount")]
        [string]$SignInAudience = "AzureADMyOrg",

        [Parameter(Mandatory = $false)]
        [string[]]$RedirectUris = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$IdentifierUris = @(),

        [Parameter(Mandatory = $false)]
        [string]$Notes
    )

    begin {
        Write-Verbose "Creating new app registration: $DisplayName"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection -RequiredScopes "Application.ReadWrite.All")) {
            throw "No active Microsoft Graph connection with required permissions. Please connect using Connect-EntraGraphSession first."
        }
    }

    process {
        try {
            # Prepare app registration properties
            $appProperties = @{
                displayName = $DisplayName
                signInAudience = $SignInAudience
            }

            # Add optional properties if specified
            if ($Notes) {
                $appProperties.notes = $Notes
            }

            # Add web properties if redirect URIs are specified
            if ($RedirectUris.Count -gt 0) {
                $appProperties.web = @{
                    redirectUris = $RedirectUris
                }
            }

            # Add identifier URIs if specified
            if ($IdentifierUris.Count -gt 0) {
                $appProperties.identifierUris = $IdentifierUris
            }

            # Create the app registration
            $uri = "https://graph.microsoft.com/v1.0/applications"
            $app = Invoke-EntraGraphRequest -Uri $uri -Method POST -Body $appProperties

            # Process API permissions if any were specified
            $requiresUpdate = $false
            $requiredResourceAccess = @()

            # Process Microsoft Graph permissions
            if ($GraphPermissions.Count -gt 0) {
                $graphSp = Get-EntraServicePrincipalByAppId -AppId "00000003-0000-0000-c000-000000000000"
                if ($graphSp) {
                    $graphResourceAccess = @{
                        resourceAppId = $graphSp.appId
                        resourceAccess = @()
                    }

                    foreach ($permission in $GraphPermissions) {
                        $appRole = $graphSp.appRoles | Where-Object { $_.value -eq $permission }
                        if ($appRole) {
                            $graphResourceAccess.resourceAccess += @{
                                id = $appRole.id
                                type = "Role"
                            }
                        }
                        else {
                            Write-Warning "Permission '$permission' not found in Microsoft Graph API"
                        }
                    }

                    if ($graphResourceAccess.resourceAccess.Count -gt 0) {
                        $requiredResourceAccess += $graphResourceAccess
                        $requiresUpdate = $true
                    }
                }
                else {
                    Write-Warning "Microsoft Graph service principal not found. Cannot add Graph permissions."
                }
            }

            # Process Rights Management Service permissions
            if ($RmsPermissions.Count -gt 0) {
                $rmsSp = Get-EntraServicePrincipalByName -DisplayName "Azure Rights Management Services" -ExactMatch
                if (-not $rmsSp) {
                    # Try alternate names
                    $rmsSp = Get-EntraServicePrincipalByName -DisplayName "Microsoft Rights Management Services" -ExactMatch
                }
                if (-not $rmsSp) {
                    $rmsSp = Get-EntraServicePrincipalByName -DisplayName "Rights Management Services" -ExactMatch
                }
                
                if ($rmsSp) {
                    $rmsResourceAccess = @{
                        resourceAppId = $rmsSp.appId
                        resourceAccess = @()
                    }

                    foreach ($permission in $RmsPermissions) {
                        $appRole = $rmsSp.appRoles | Where-Object { $_.value -eq $permission }
                        if ($appRole) {
                            $rmsResourceAccess.resourceAccess += @{
                                id = $appRole.id
                                type = "Role"
                            }
                        }
                        else {
                            Write-Warning "Permission '$permission' not found in Rights Management Services API"
                        }
                    }

                    if ($rmsResourceAccess.resourceAccess.Count -gt 0) {
                        $requiredResourceAccess += $rmsResourceAccess
                        $requiresUpdate = $true
                    }
                }
                else {
                    Write-Warning "Rights Management Services service principal not found. Cannot add RMS permissions."
                }
            }

            # Process Exchange Online permissions
            if ($ExchangePermissions.Count -gt 0) {
                $exchangeSp = Get-EntraServicePrincipalByAppId -AppId "00000002-0000-0ff1-ce00-000000000000"
                if ($exchangeSp) {
                    $exchangeResourceAccess = @{
                        resourceAppId = $exchangeSp.appId
                        resourceAccess = @()
                    }

                    foreach ($permission in $ExchangePermissions) {
                        $appRole = $exchangeSp.appRoles | Where-Object { $_.value -eq $permission }
                        if ($appRole) {
                            $exchangeResourceAccess.resourceAccess += @{
                                id = $appRole.id
                                type = "Role"
                            }
                        }
                        else {
                            Write-Warning "Permission '$permission' not found in Exchange Online API"
                        }
                    }

                    if ($exchangeResourceAccess.resourceAccess.Count -gt 0) {
                        $requiredResourceAccess += $exchangeResourceAccess
                        $requiresUpdate = $true
                    }
                }
                else {
                    Write-Warning "Exchange Online service principal not found. Cannot add Exchange permissions."
                }
            }

            # Process custom permissions
            if ($CustomPermissions.Count -gt 0) {
                foreach ($service in $CustomPermissions.Keys) {
                    $permissions = $CustomPermissions[$service]
                    
                    # Try to find service principal by name or app ID
                    $servicePrincipal = $null
                    if ($service -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                        # It's a UUID format, treat as App ID
                        $servicePrincipal = Get-EntraServicePrincipalByAppId -AppId $service
                    }
                    else {
                        # Treat as display name
                        $servicePrincipal = Get-EntraServicePrincipalByName -DisplayName $service -ExactMatch
                    }

                    if ($servicePrincipal) {
                        $customResourceAccess = @{
                            resourceAppId = $servicePrincipal.appId
                            resourceAccess = @()
                        }

                        foreach ($permission in $permissions) {
                            $appRole = $servicePrincipal.appRoles | Where-Object { $_.value -eq $permission }
                            if ($appRole) {
                                $customResourceAccess.resourceAccess += @{
                                    id = $appRole.id
                                    type = "Role"
                                }
                            }
                            else {
                                Write-Warning "Permission '$permission' not found in service '$service'"
                            }
                        }

                        if ($customResourceAccess.resourceAccess.Count -gt 0) {
                            $requiredResourceAccess += $customResourceAccess
                            $requiresUpdate = $true
                        }
                    }
                    else {
                        Write-Warning "Service principal '$service' not found. Cannot add custom permissions."
                    }
                }
            }

            # Update required resource access if needed
            if ($requiresUpdate) {
                $updateUri = "https://graph.microsoft.com/v1.0/applications/$($app.id)"
                $updateBody = @{
                    requiredResourceAccess = $requiredResourceAccess
                }
                
                Invoke-EntraGraphRequest -Uri $updateUri -Method PATCH -Body $updateBody | Out-Null
                
                # Get the updated app
                $app = Invoke-EntraGraphRequest -Uri $updateUri -Method GET
            }

            # Return the created app registration
            Write-Verbose "Successfully created app registration: $DisplayName (ID: $($app.id))"
            return $app
        }
        catch {
            Write-Error "Failed to create app registration: $_"
            throw $_
        }
    }
}
