<#
.SYNOPSIS
    Removes a credential from an existing app registration.

.DESCRIPTION
    The Remove-EntraAppCredential function removes a client secret (password credential) or
    certificate (key credential) from an existing app registration. The credential to remove
    can be identified by its ID, thumbprint (for certificates), or display name.
    
    By default, the function prompts for confirmation before removing the credential.

.PARAMETER DisplayName
    The display name of the app registration. This parameter is part of a parameter set
    and is mutually exclusive with ObjectId and AppId.

.PARAMETER ObjectId
    The object ID (guid) of the app registration. This parameter is part of a parameter set and is
    mutually exclusive with DisplayName and AppId.

.PARAMETER AppId
    The application ID (client ID) of the app registration. This parameter is part of a parameter set and is
    mutually exclusive with DisplayName and ObjectId.

.PARAMETER CredentialId
    The ID of the credential to remove. This is the KeyId value returned by Get-EntraAppCredentials.
    This parameter is mutually exclusive with Thumbprint and CredentialDisplayName.

.PARAMETER Thumbprint
    The thumbprint of the certificate to remove. This parameter is only applicable for certificates
    and is mutually exclusive with CredentialId and CredentialDisplayName.

.PARAMETER CredentialDisplayName
    The display name of the credential to remove. If multiple credentials have the same display name,
    the function will prompt for selection unless -Force is used, which will remove all matching credentials.
    This parameter is mutually exclusive with CredentialId and Thumbprint.

.PARAMETER CredentialType
    The type of credential to remove: "Secret", "Certificate", or "All". Default is "All".
    Use this parameter to limit the removal to a specific type of credential.

.PARAMETER Force
    Switch parameter that bypasses confirmation prompts. Use with caution.
    When used with CredentialDisplayName, all matching credentials will be removed.

.EXAMPLE
    Remove-EntraAppCredential -DisplayName "MyApp" -CredentialId "abcdef-12345-67890"
    Removes the credential with the specified ID from the app registration named "MyApp".

.EXAMPLE
    Remove-EntraAppCredential -AppId "11111111-1111-1111-1111-111111111111" -Thumbprint "1234567890ABCDEF1234567890ABCDEF12345678"
    Removes the certificate with the specified thumbprint from the app registration with the specified Application ID.

.EXAMPLE
    Remove-EntraAppCredential -DisplayName "MyApp" -CredentialDisplayName "BackupSecret" -CredentialType Secret -Force
    Removes all client secrets named "BackupSecret" from the app registration named "MyApp" without prompting for confirmation.

.NOTES
    This function requires an active connection to Microsoft Graph API with Application.ReadWrite.All permission.
    Use Connect-EntraGraphSession before calling this function.
    
    Be extremely careful when using the -Force parameter, as it can remove credentials without confirmation,
    potentially causing service disruptions if active credentials are removed.
#>
function Remove-EntraAppCredential {
    [CmdletBinding(DefaultParameterSetName = 'DisplayName', SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'DisplayNameId', Position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = 'DisplayNameThumb', Position = 0)]
        [Parameter(Mandatory = $true, ParameterSetName = 'DisplayNameDisplay', Position = 0)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectIdId')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectIdThumb')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectIdDisplay')]
        [guid]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'AppIdId')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AppIdThumb')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AppIdDisplay')]
        [guid]$AppId,

        [Parameter(Mandatory = $true, ParameterSetName = 'DisplayNameId')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectIdId')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AppIdId')]
        [string]$CredentialId,

        [Parameter(Mandatory = $true, ParameterSetName = 'DisplayNameThumb')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectIdThumb')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AppIdThumb')]
        [string]$Thumbprint,

        [Parameter(Mandatory = $true, ParameterSetName = 'DisplayNameDisplay')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectIdDisplay')]
        [Parameter(Mandatory = $true, ParameterSetName = 'AppIdDisplay')]
        [string]$CredentialDisplayName,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Secret", "Certificate", "All")]
        [string]$CredentialType = "All",

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {
        Write-Verbose "Starting Remove-EntraAppCredential function"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection -RequiredScopes "Application.ReadWrite.All")) {
            throw "No active Microsoft Graph connection with required permissions. Please connect using Connect-EntraGraphSession first."
        }
    }

    process {
        try {
            # Get the application based on provided identity parameter
            $application = $null
            $appDisplayName = $null
            
            # Determine which identity parameter was used
            $identityParamSet = $PSCmdlet.ParameterSetName
            if ($identityParamSet -like 'DisplayName*') {
                Write-Verbose "Finding app registration by display name: $DisplayName"
                $application = Get-MgApplication -Filter "displayName eq '$DisplayName'"
                $appDisplayName = $DisplayName
            }
            elseif ($identityParamSet -like 'ObjectId*') {
                Write-Verbose "Finding app registration by object ID: $ObjectId"
                $application = Get-MgApplication -ApplicationId $ObjectId.Guid
                $appDisplayName = $application.DisplayName
            }
            elseif ($identityParamSet -like 'AppId*') {
                Write-Verbose "Finding app registration by app ID (client ID): $AppId"
                $application = Get-MgApplication -Filter "appId eq '$($AppId.Guid)'"
                $appDisplayName = $application.DisplayName
            }

            if (-not $application) {
                $identityValue = if ($identityParamSet -like 'DisplayName*') { $DisplayName }
                               elseif ($identityParamSet -like 'ObjectId*') { $ObjectId.ToString() }
                               elseif ($identityParamSet -like 'AppId*') { $AppId.ToString() }
                               else { "Unknown" }
                throw "Application not found using identity '$identityValue'"
            }

            if ($application -is [array]) {
                # If multiple apps found with same display name, throw error
                if ($identityParamSet -like 'DisplayName*' -and $application.Count -gt 1) {
                    throw "Multiple app registrations found with display name '$DisplayName'. Please use ObjectId or AppId parameter for a unique match."
                }
                # Use the first result otherwise
                $application = $application[0]
            }

            Write-Verbose "Found app registration: $($application.DisplayName) (ID: $($application.Id), AppId: $($application.AppId))"
            
            # Get all credentials of the app based on the specified CredentialType
            $secretsToRemove = @()
            $certificatesToRemove = @()
            
            # Determine which credentials to consider for removal
            if ($CredentialType -eq "All" -or $CredentialType -eq "Secret") {
                if ($application.PasswordCredentials) {
                    Write-Verbose "Found $($application.PasswordCredentials.Count) password credential(s) (secrets) in the app registration"
                    $secretsToRemove = $application.PasswordCredentials
                }
                else {
                    Write-Verbose "No password credentials (secrets) found in the app registration"
                }
            }
            
            if ($CredentialType -eq "All" -or $CredentialType -eq "Certificate") {
                if ($application.KeyCredentials) {
                    Write-Verbose "Found $($application.KeyCredentials.Count) key credential(s) (certificates) in the app registration"
                    $certificatesToRemove = $application.KeyCredentials
                }
                else {
                    Write-Verbose "No key credentials (certificates) found in the app registration"
                }
            }
            
            # Filter credentials based on the provided parameters
            if ($identityParamSet -like '*Id') {
                # Filter by credential ID
                Write-Verbose "Filtering credentials by ID: $CredentialId"
                $secretsToRemove = $secretsToRemove | Where-Object { $_.KeyId -eq $CredentialId }
                $certificatesToRemove = $certificatesToRemove | Where-Object { $_.KeyId -eq $CredentialId }
            }
            elseif ($identityParamSet -like '*Thumb') {
                # Filter by thumbprint (applicable only for certificates)
                Write-Verbose "Filtering certificates by thumbprint: $Thumbprint"
                $normalizedThumbprint = $Thumbprint.ToUpper() -replace ':', ''
                
                $certificatesToRemove = $certificatesToRemove | Where-Object {
                    # Try to extract thumbprint from CustomKeyIdentifier
                    if ($_.CustomKeyIdentifier) {
                        try {
                            $thumbprintFromCert = [System.BitConverter]::ToString([System.Convert]::FromBase64String($_.CustomKeyIdentifier)) -replace '-', ''
                            $thumbprintFromCert -eq $normalizedThumbprint
                        }
                        catch {
                            $false
                        }
                    }
                    else {
                        $false
                    }
                }
                
                # Clear secrets since thumbprint is not applicable for them
                $secretsToRemove = @()
            }
            elseif ($identityParamSet -like '*Display') {
                # Filter by display name
                Write-Verbose "Filtering credentials by display name: $CredentialDisplayName"
                $secretsToRemove = $secretsToRemove | Where-Object { $_.DisplayName -eq $CredentialDisplayName }
                $certificatesToRemove = $certificatesToRemove | Where-Object { $_.DisplayName -eq $CredentialDisplayName }
            }
            
            # Combine all credentials to remove
            $credentialsToRemove = @()
            
            foreach ($secret in $secretsToRemove) {
                $credentialsToRemove += [PSCustomObject]@{
                    Type = "Secret"
                    KeyId = $secret.KeyId
                    DisplayName = $secret.DisplayName
                    StartDateTime = $secret.StartDateTime
                    EndDateTime = $secret.EndDateTime
                    Thumbprint = $null
                    Original = $secret
                }
            }
            
            foreach ($cert in $certificatesToRemove) {
                # Try to extract thumbprint
                $thumbprint = $null
                if ($cert.CustomKeyIdentifier) {
                    try {
                        $thumbprint = [System.BitConverter]::ToString([System.Convert]::FromBase64String($cert.CustomKeyIdentifier)) -replace '-', ''
                    }
                    catch {
                        Write-Verbose "Could not parse CustomKeyIdentifier for certificate with ID $($cert.KeyId)"
                    }
                }
                
                $credentialsToRemove += [PSCustomObject]@{
                    Type = "Certificate"
                    KeyId = $cert.KeyId
                    DisplayName = $cert.DisplayName
                    StartDateTime = $cert.StartDateTime
                    EndDateTime = $cert.EndDateTime
                    Thumbprint = $thumbprint
                    Original = $cert
                }
            }
            
            # Check if any credentials were found to remove
            if ($credentialsToRemove.Count -eq 0) {
                $filterDesc = if ($identityParamSet -like '*Id') { "ID '$CredentialId'" }
                          elseif ($identityParamSet -like '*Thumb') { "thumbprint '$Thumbprint'" }
                          elseif ($identityParamSet -like '*Display') { "display name '$CredentialDisplayName'" }
                          else { "the provided criteria" }
                
                Write-Warning "No credentials found matching $filterDesc for app registration '$appDisplayName'"
                return $null
            }
            
            # If there are multiple credentials and we're not forcing, prompt for selection
            $selectedCredentials = $credentialsToRemove
            
            if ($credentialsToRemove.Count -gt 1 -and -not $Force) {
                Write-Host "`nMultiple credentials found matching your criteria for app '$appDisplayName':" -ForegroundColor Yellow
                for ($i = 0; $i -lt $credentialsToRemove.Count; $i++) {
                    $cred = $credentialsToRemove[$i]
                    $thumbprintInfo = if ($cred.Thumbprint) { ", Thumbprint: $($cred.Thumbprint)" } else { "" }
                    $expiryDate = [datetime]$cred.EndDateTime
                    $expiryInfo = if ($expiryDate -lt (Get-Date)) { " (EXPIRED)" } else { "" }
                    
                    Write-Host "[$($i+1)] $($cred.Type): $($cred.DisplayName) (ID: $($cred.KeyId)$thumbprintInfo, Expires: $($expiryDate.ToString('yyyy-MM-dd'))$expiryInfo)" -ForegroundColor Cyan
                }
                
                $selectedIndices = Read-Host "`nEnter the number(s) of the credential(s) to remove (e.g., '1,3' or '2') or 'A' for all"
                
                if ($selectedIndices -eq "A" -or $selectedIndices -eq "a") {
                    # Keep all credentials
                    $selectedCredentials = $credentialsToRemove
                }
                else {
                    try {
                        $indices = $selectedIndices -split ',' | ForEach-Object { [int]$_.Trim() - 1 }
                        $selectedCredentials = $indices | ForEach-Object { $credentialsToRemove[$_] }
                    }
                    catch {
                        Write-Error "Invalid selection. Please enter numbers separated by commas or 'A' for all."
                        return $null
                    }
                }
            }
            
            # Process the removal of each selected credential
            $removedCredentials = @()
            
            foreach ($credential in $selectedCredentials) {
                $credentialDesc = "$($credential.Type) credential '$($credential.DisplayName)' (ID: $($credential.KeyId))"
                
                if ($Force -or $PSCmdlet.ShouldProcess($credentialDesc, "Remove")) {
                    try {
                        if ($credential.Type -eq "Secret") {
                            Write-Verbose "Removing password credential (secret) with ID $($credential.KeyId) from app registration"
                            
                            # Remove the password credential
                            Remove-MgApplicationPassword -ApplicationId $application.Id -KeyId $credential.KeyId
                            
                            Write-Host "Successfully removed $credentialDesc from app registration '$appDisplayName'" -ForegroundColor Green
                            $removedCredentials += $credential
                        }
                        elseif ($credential.Type -eq "Certificate") {
                            Write-Verbose "Removing key credential (certificate) with ID $($credential.KeyId) from app registration"
                            
                            # Remove the key credential
                            Remove-MgApplicationKey -ApplicationId $application.Id -KeyId $credential.KeyId
                            
                            Write-Host "Successfully removed $credentialDesc from app registration '$appDisplayName'" -ForegroundColor Green
                            $removedCredentials += $credential
                        }
                    }
                    catch {
                        Write-Error "Failed to remove $credentialDesc from app registration '$appDisplayName': $_"
                    }
                }
            }
            
            # Return information about the removed credentials
            $result = [PSCustomObject]@{
                AppId = $application.AppId
                AppObjectId = $application.Id
                AppDisplayName = $appDisplayName
                RemovedCredentials = $removedCredentials
            }
            
            return $result
        }
        catch {
            Write-Error "Failed to remove app credential: $_"
            throw $_
        }
    }
}
