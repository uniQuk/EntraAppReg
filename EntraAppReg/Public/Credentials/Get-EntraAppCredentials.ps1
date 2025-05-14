<#
.SYNOPSIS
    Gets all credentials for an existing app registration.

.DESCRIPTION
    The Get-EntraAppCredentials function retrieves all credentials (client secrets and certificates)
    from an existing app registration. It provides additional information such as expiration dates,
    credential type, and status.

    The function allows filtering credentials by type (secret/certificate) and expiry status
    (expired, expiring soon, active). It also calculates the days remaining until expiration.

.PARAMETER DisplayName
    The display name of the app registration. This parameter is part of a parameter set
    and is mutually exclusive with ObjectId and AppId.

.PARAMETER ObjectId
    The object ID (guid) of the app registration. This parameter is part of a parameter set and is
    mutually exclusive with DisplayName and AppId.

.PARAMETER AppId
    The application ID (client ID) of the app registration. This parameter is part of a parameter set and is
    mutually exclusive with DisplayName and ObjectId.

.PARAMETER IncludeSecrets
    Switch parameter that determines whether to include client secrets (password credentials) in the results.
    Default is $true.

.PARAMETER IncludeCertificates
    Switch parameter that determines whether to include certificates (key credentials) in the results.
    Default is $true.

.PARAMETER ShowExpired
    Switch parameter that determines whether to include expired credentials in the results.
    Default is $true.

.PARAMETER ExpiringInDays
    Integer parameter that filters credentials expiring within the specified number of days.
    If specified, only credentials expiring within this timeframe will be included.

.PARAMETER IncludeDetails
    Switch parameter that determines whether to include additional details like credential flags and hint.
    Default is $false.

.EXAMPLE
    Get-EntraAppCredentials -DisplayName "MyApp"
    Retrieves all credentials (both secrets and certificates) for the app registration named "MyApp",
    including those that have already expired.

.EXAMPLE
    Get-EntraAppCredentials -AppId "11111111-1111-1111-1111-111111111111" -IncludeSecrets -ShowExpired:$false
    Retrieves only active client secrets for the app registration with the specified Application ID.

.EXAMPLE
    Get-EntraAppCredentials -DisplayName "MyApp" -IncludeCertificates -ExpiringInDays 30
    Retrieves only certificates that are expiring within 30 days for the app registration named "MyApp".

.NOTES
    This function requires an active connection to Microsoft Graph API with Application.Read.All permission.
    Use Connect-EntraGraphSession before calling this function.
#>
function Get-EntraAppCredentials {
    [CmdletBinding(DefaultParameterSetName = 'DisplayName')]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'DisplayName', Position = 0)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectId')]
        [guid]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'AppId')]
        [guid]$AppId,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeSecrets = $true,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeCertificates = $true,

        [Parameter(Mandatory = $false)]
        [switch]$ShowExpired = $true,

        [Parameter(Mandatory = $false)]
        [int]$ExpiringInDays,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDetails = $false
    )

    begin {
        Write-Verbose "Starting Get-EntraAppCredentials function"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection -RequiredScopes "Application.Read.All")) {
            throw "No active Microsoft Graph connection with required permissions. Please connect using Connect-EntraGraphSession first."
        }
        
        # Define credential status types
        $STATUS_ACTIVE = "Active"
        $STATUS_EXPIRING = "Expiring Soon"
        $STATUS_EXPIRED = "Expired"
        
        # Current date/time for expiration checks
        $now = Get-Date
    }

    process {
        try {
            # Get the application based on provided identity parameter
            $application = $null
            $appDisplayName = $null
            
            switch ($PSCmdlet.ParameterSetName) {
                'DisplayName' {
                    Write-Verbose "Finding app registration by display name: $DisplayName"
                    $application = Get-MgApplication -Filter "displayName eq '$DisplayName'"
                    $appDisplayName = $DisplayName
                }
                'ObjectId' {
                    Write-Verbose "Finding app registration by object ID: $ObjectId"
                    $application = Get-MgApplication -ApplicationId $ObjectId.Guid
                    $appDisplayName = $application.DisplayName
                }
                'AppId' {
                    Write-Verbose "Finding app registration by app ID (client ID): $AppId"
                    $application = Get-MgApplication -Filter "appId eq '$($AppId.Guid)'"
                    $appDisplayName = $application.DisplayName
                }
            }

            if (-not $application) {
                $identityValue = switch ($PSCmdlet.ParameterSetName) {
                    'DisplayName' { $DisplayName }
                    'ObjectId' { $ObjectId.ToString() }
                    'AppId' { $AppId.ToString() }
                    default { "Unknown" }
                }
                throw "Application not found using identity '$identityValue'"
            }

            if ($application -is [array]) {
                # If multiple apps found with same display name, throw error
                if ($PSCmdlet.ParameterSetName -eq 'DisplayName' -and $application.Count -gt 1) {
                    throw "Multiple app registrations found with display name '$DisplayName'. Please use ObjectId or AppId parameter for a unique match."
                }
                # Use the first result otherwise
                $application = $application[0]
            }

            Write-Verbose "Found app registration: $($application.DisplayName) (ID: $($application.Id), AppId: $($application.AppId))"
            
            # Initialize results array
            $credentialResults = @()
            
            # Process password credentials (secrets) if requested
            if ($IncludeSecrets) {
                Write-Verbose "Processing password credentials (client secrets) for app '$($application.DisplayName)'"
                
                if ($application.PasswordCredentials) {
                    foreach ($secret in $application.PasswordCredentials) {
                        $startDate = [datetime]$secret.StartDateTime
                        $endDate = [datetime]$secret.EndDateTime
                        $daysRemaining = ($endDate - $now).Days
                        
                        # Determine credential status
                        $status = $STATUS_ACTIVE
                        if ($daysRemaining -lt 0) {
                            $status = $STATUS_EXPIRED
                        }
                        elseif ($ExpiringInDays -and $daysRemaining -le $ExpiringInDays) {
                            $status = $STATUS_EXPIRING
                        }
                        
                        # Skip expired credentials if ShowExpired is false
                        if (-not $ShowExpired -and $status -eq $STATUS_EXPIRED) {
                            continue
                        }
                        
                        # Skip credentials that don't match the expiring filter
                        if ($ExpiringInDays -and $status -eq $STATUS_ACTIVE) {
                            continue
                        }
                        
                        # Create credential object
                        $credObj = [PSCustomObject]@{
                            AppId = $application.AppId
                            AppObjectId = $application.Id
                            AppDisplayName = $application.DisplayName
                            CredentialId = $secret.KeyId
                            DisplayName = $secret.DisplayName
                            Type = "Secret"
                            Created = $startDate
                            Expires = $endDate
                            DaysRemaining = $daysRemaining
                            Status = $status
                        }
                        
                        # Add additional details if requested
                        if ($IncludeDetails) {
                            $credObj | Add-Member -MemberType NoteProperty -Name "CustomKeyIdentifier" -Value $secret.CustomKeyIdentifier
                            $credObj | Add-Member -MemberType NoteProperty -Name "Hint" -Value $secret.Hint
                        }
                        
                        $credentialResults += $credObj
                    }
                }
                else {
                    Write-Verbose "No password credentials (client secrets) found for app '$($application.DisplayName)'"
                }
            }
            
            # Process key credentials (certificates) if requested
            if ($IncludeCertificates) {
                Write-Verbose "Processing key credentials (certificates) for app '$($application.DisplayName)'"
                
                if ($application.KeyCredentials) {
                    foreach ($cert in $application.KeyCredentials) {
                        $startDate = [datetime]$cert.StartDateTime
                        $endDate = [datetime]$cert.EndDateTime
                        $daysRemaining = ($endDate - $now).Days
                        
                        # Determine credential status
                        $status = $STATUS_ACTIVE
                        if ($daysRemaining -lt 0) {
                            $status = $STATUS_EXPIRED
                        }
                        elseif ($ExpiringInDays -and $daysRemaining -le $ExpiringInDays) {
                            $status = $STATUS_EXPIRING
                        }
                        
                        # Skip expired credentials if ShowExpired is false
                        if (-not $ShowExpired -and $status -eq $STATUS_EXPIRED) {
                            continue
                        }
                        
                        # Skip credentials that don't match the expiring filter
                        if ($ExpiringInDays -and $status -eq $STATUS_ACTIVE) {
                            continue
                        }
                        
                        # Extract thumbprint from CustomKeyIdentifier if available
                        $thumbprint = ""
                        if ($cert.CustomKeyIdentifier) {
                            try {
                                $thumbprint = [System.BitConverter]::ToString($cert.CustomKeyIdentifier).Replace("-", "")
                            } 
                            catch {
                                Write-Verbose "Could not parse CustomKeyIdentifier for certificate: $_"
                            }
                        }
                        
                        # Create credential object
                        $credObj = [PSCustomObject]@{
                            AppId = $application.AppId
                            AppObjectId = $application.Id
                            AppDisplayName = $application.DisplayName
                            CredentialId = $cert.KeyId
                            DisplayName = $cert.DisplayName
                            Type = "Certificate"
                            Created = $startDate
                            Expires = $endDate
                            DaysRemaining = $daysRemaining
                            Status = $status
                            Thumbprint = $thumbprint
                        }
                        
                        # Add additional details if requested
                        if ($IncludeDetails) {
                            $credObj | Add-Member -MemberType NoteProperty -Name "Usage" -Value $cert.Usage
                            $credObj | Add-Member -MemberType NoteProperty -Name "Type" -Value $cert.Type
                        }
                        
                        $credentialResults += $credObj
                    }
                }
                else {
                    Write-Verbose "No key credentials (certificates) found for app '$($application.DisplayName)'"
                }
            }
            
            # Sort credentials by expiration date (ascending)
            $credentialResults = $credentialResults | Sort-Object -Property Expires
            
            # Return results
            if ($credentialResults.Count -eq 0) {
                Write-Host "No credentials found for app registration '$($application.DisplayName)' matching the specified criteria." -ForegroundColor Yellow
            }
            else {
                Write-Verbose "Found $($credentialResults.Count) credentials for app registration '$($application.DisplayName)'"
            }
            
            return $credentialResults
        }
        catch {
            Write-Error "Failed to get app credentials: $_"
            throw $_
        }
    }
}
