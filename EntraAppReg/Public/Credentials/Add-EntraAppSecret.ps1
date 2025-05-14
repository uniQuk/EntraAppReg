<#
.SYNOPSIS
    Adds a client secret to an existing app registration.

.DESCRIPTION
    The Add-EntraAppSecret function adds a client secret (password) to an existing app registration.
    The function accepts parameters for the app identity, secret display name, and validity period.
    The created secret details can be optionally exported to a CSV file in the specified output folder.

.PARAMETER DisplayName
    The display name of the app registration to add the secret to. This parameter is part of a parameter set
    and is mutually exclusive with ObjectId and AppId.

.PARAMETER ObjectId
    The object ID (guid) of the app registration. This parameter is part of a parameter set and is
    mutually exclusive with DisplayName and AppId.

.PARAMETER AppId
    The application ID (client ID) of the app registration. This parameter is part of a parameter set and is
    mutually exclusive with DisplayName and ObjectId.

.PARAMETER SecretDisplayName
    The display name for the client secret. This name helps identify the secret in the Azure portal.

.PARAMETER ValidityYears
    The number of years the client secret should be valid for. Default is 1 year.
    This parameter is mutually exclusive with ValidityMonths and ValidityDays.

.PARAMETER ValidityMonths
    The number of months the client secret should be valid for.
    This parameter is mutually exclusive with ValidityYears and ValidityDays.

.PARAMETER ValidityDays
    The number of days the client secret should be valid for.
    This parameter is mutually exclusive with ValidityYears and ValidityMonths.

.PARAMETER ExportSecretToFile
    Switch parameter that determines whether the secret should be exported to a CSV file.
    When set to $true, the secret will be exported to the path specified by OutputPath.
    Default is $false.

.PARAMETER OutputPath
    The directory path where the client secret CSV file should be saved.
    If not specified, the default module output path will be used.

.EXAMPLE
    Add-EntraAppSecret -DisplayName "MyApp" -SecretDisplayName "MySecret"
    Adds a client secret named "MySecret" to the app registration named "MyApp" with a default validity period of 1 year.

.EXAMPLE
    Add-EntraAppSecret -AppId "11111111-1111-1111-1111-111111111111" -SecretDisplayName "ApiSecret" -ValidityYears 2 -ExportSecretToFile
    Adds a client secret named "ApiSecret" to the app registration with the specified Application ID,
    valid for 2 years, and exports the secret to a CSV file.

.EXAMPLE
    Add-EntraAppSecret -DisplayName "MyApp" -SecretDisplayName "ShortSecret" -ValidityDays 30
    Adds a client secret named "ShortSecret" to the app registration named "MyApp" with a validity period of 30 days.

.NOTES
    This function requires an active connection to Microsoft Graph API with Application.ReadWrite.All permission.
    Use Connect-EntraGraphSession before calling this function.
    
    WARNING: Client secrets are sensitive and should be handled securely. When exported to a file,
    ensure the file is stored in a secure location and deleted when no longer needed.
#>
function Add-EntraAppSecret {
    [CmdletBinding(DefaultParameterSetName = 'DisplayName')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'DisplayName', Position = 0)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true, ParameterSetName = 'ObjectId')]
        [guid]$ObjectId,

        [Parameter(Mandatory = $true, ParameterSetName = 'AppId')]
        [guid]$AppId,

        [Parameter(Mandatory = $false)]
        [string]$SecretDisplayName = "ClientSecret",

        [Parameter(Mandatory = $false, ParameterSetName = 'Years')]
        [int]$ValidityYears = 1,

        [Parameter(Mandatory = $true, ParameterSetName = 'Months')]
        [int]$ValidityMonths,

        [Parameter(Mandatory = $true, ParameterSetName = 'Days')]
        [int]$ValidityDays,

        [Parameter(Mandatory = $false)]
        [switch]$ExportSecretToFile = $false,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )

    begin {
        Write-Verbose "Starting Add-EntraAppSecret function"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection -RequiredScopes "Application.ReadWrite.All")) {
            throw "No active Microsoft Graph connection with required permissions. Please connect using Connect-EntraGraphSession first."
        }
        
        # Create output path if specified or use default module output path
        if ($ExportSecretToFile) {
            if (-not $OutputPath) {
                $OutputPath = New-EntraAppOutputFolder -FolderName "Credentials" -LogOutput
            }
            elseif (-not (Test-Path -Path $OutputPath)) {
                try {
                    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
                    Write-Verbose "Created output directory: $OutputPath"
                }
                catch {
                    Write-Error "Failed to create output directory '$OutputPath': $_"
                    throw
                }
            }
        }
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

            # Calculate the expiration date based on the provided validity parameters
            $endDateTime = $null
            switch ($PSCmdlet.ParameterSetName) {
                'Years' { $endDateTime = (Get-Date).AddYears($ValidityYears) }
                'Months' { $endDateTime = (Get-Date).AddMonths($ValidityMonths) }
                'Days' { $endDateTime = (Get-Date).AddDays($ValidityDays) }
                default { $endDateTime = (Get-Date).AddYears($ValidityYears) }
            }
            
            # Format expiry information for the verbose message
            $expiryInfo = switch ($PSCmdlet.ParameterSetName) {
                'Years' { "$ValidityYears year(s)" }
                'Months' { "$ValidityMonths month(s)" }
                'Days' { "$ValidityDays day(s)" }
                default { "$ValidityYears year(s)" }
            }
            
            Write-Verbose "Adding client secret '$SecretDisplayName' to app registration, valid for $expiryInfo (expires on $($endDateTime.ToString('yyyy-MM-dd')))"

            # Add the secret
            $passwordCredential = @{
                displayName = $SecretDisplayName
                endDateTime = $endDateTime
            }
            
            # Create the password credential
            $secret = Add-MgApplicationPassword -ApplicationId $application.Id -PasswordCredential $passwordCredential
            
            # Create a result object with all relevant details
            $result = [PSCustomObject]@{
                AppId = $application.AppId
                AppName = $appDisplayName
                ObjectId = $application.Id
                SecretId = $secret.KeyId
                ClientSecret = $secret.SecretText
                DisplayName = $SecretDisplayName
                CreatedDateTime = Get-Date
                ExpiryDateTime = $secret.EndDateTime
            }
            
            # Export the secret to a CSV file if requested
            if ($ExportSecretToFile) {
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $appNameSafe = $appDisplayName -replace '[^\w\d]', '_'
                $secretFileName = "$appNameSafe-secret-$timestamp.csv"
                $secretFilePath = Join-Path -Path $OutputPath -ChildPath $secretFileName
                
                try {
                    $result | Export-Csv -Path $secretFilePath -NoTypeInformation
                    $result | Add-Member -MemberType NoteProperty -Name "ExportedFilePath" -Value $secretFilePath
                    
                    Write-Verbose "Exported client secret details to file: $secretFilePath"
                    Write-EntraLog -Message "Client secret details for app '$appDisplayName' exported to file: $secretFilePath" -Level Info
                }
                catch {
                    Write-Warning "Failed to export client secret details to file: $_"
                }
            }
            
            Write-Host "Successfully added client secret to app registration '$appDisplayName'." -ForegroundColor Green
            Write-Host "Secret expires on: $($secret.EndDateTime)" -ForegroundColor Yellow
            
            return $result
        }
        catch {
            Write-Error "Failed to add client secret: $_"
            throw $_
        }
    }
}
