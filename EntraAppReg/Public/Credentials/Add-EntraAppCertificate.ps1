<#
.SYNOPSIS
    Adds a self-signed certificate to an existing app registration.

.DESCRIPTION
    The Add-EntraAppCertificate function creates a self-signed certificate and adds it to an existing
    app registration. The function supports using OpenSSL for certificate generation, which is
    compatible with macOS, Linux, and Windows with OpenSSL installed.
    
    The function creates several certificate-related files:
    - A certificate file (.crt)
    - A private key file (.key)
    - A PKCS#12/PFX file (.pfx) with a generated password
    - A password text file containing the PFX password
    
    All generated files are saved to the specified output path.

.PARAMETER DisplayName
    The display name of the app registration to add the certificate to. This parameter is part of a parameter set
    and is mutually exclusive with ObjectId and AppId.

.PARAMETER ObjectId
    The object ID (guid) of the app registration. This parameter is part of a parameter set and is
    mutually exclusive with DisplayName and AppId.

.PARAMETER AppId
    The application ID (client ID) of the app registration. This parameter is part of a parameter set and is
    mutually exclusive with DisplayName and ObjectId.

.PARAMETER CertificateDisplayName
    The display name for the certificate. This name helps identify the certificate in the Azure portal.

.PARAMETER ValidityYears
    The number of years the certificate should be valid for. Default is 1 year.
    This parameter is mutually exclusive with ValidityMonths and ValidityDays.

.PARAMETER ValidityMonths
    The number of months the certificate should be valid for.
    This parameter is mutually exclusive with ValidityYears and ValidityDays.

.PARAMETER ValidityDays
    The number of days the certificate should be valid for.
    This parameter is mutually exclusive with ValidityYears and ValidityMonths.

.PARAMETER OutputPath
    The directory path where the certificate files should be saved.
    If not specified, the default module output path will be used.

.PARAMETER ExportToFile
    Switch parameter that determines whether the certificate metadata should be exported to a CSV file.
    When set to $true, the certificate details (not including the key) will be exported to the OutputPath.
    Default is $false.

.PARAMETER CommonName
    The Common Name (CN) to use in the certificate. If not specified, the app display name will be used.

.PARAMETER KeySize
    The size of the RSA key to generate. Default is 2048 bits.
    
.PARAMETER CertificateGenerationMethod
    The method to use for certificate generation: "Auto", "PowerShell", or "OpenSSL".
    - Auto: Automatically selects the best method based on the operating system
    - PowerShell: Uses the New-SelfSignedCertificate cmdlet (Windows only)
    - OpenSSL: Uses OpenSSL command line tool (requires OpenSSL to be installed)
    Default is "Auto".

.EXAMPLE
    Add-EntraAppCertificate -DisplayName "MyApp" -CertificateDisplayName "MyCertificate"
    Creates a self-signed certificate named "MyCertificate" and adds it to the app registration named "MyApp"
    with a default validity period of 1 year.

.EXAMPLE
    Add-EntraAppCertificate -AppId "11111111-1111-1111-1111-111111111111" -CertificateDisplayName "ApiCert" -ValidityYears 2 -OutputPath "./Certificates"
    Creates a self-signed certificate named "ApiCert" and adds it to the app registration with the specified
    Application ID, valid for 2 years, and saves the certificate files to the "./Certificates" directory.

.EXAMPLE
    Add-EntraAppCertificate -DisplayName "MyApp" -CertificateDisplayName "ShortCert" -ValidityDays 30 -KeySize 4096
    Creates a self-signed certificate with a 4096-bit key named "ShortCert" and adds it to the app registration
    named "MyApp" with a validity period of 30 days.
    
.EXAMPLE
    Add-EntraAppCertificate -DisplayName "MyApp" -CertificateDisplayName "WinCert" -CertificateGenerationMethod "PowerShell"
    Creates a self-signed certificate using PowerShell's certificate cmdlets and adds it to the app registration.

.NOTES
    This function requires an active connection to Microsoft Graph API with Application.ReadWrite.All permission.
    Use Connect-EntraGraphSession before calling this function.
    
    This function supports cross-platform certificate generation:
    - On Windows, PowerShell's New-SelfSignedCertificate cmdlet is used by default
    - On macOS/Linux, OpenSSL is used by default (requires OpenSSL to be installed)
    - The certificate generation method can be controlled with the CertificateGenerationMethod parameter
    
    The certificate files created by this function contain sensitive information and should be
    handled securely. Store them in a secure location and delete them when no longer needed.
#>
function Add-EntraAppCertificate {
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
        [string]$CertificateDisplayName = "AppCertificate",

        [Parameter(Mandatory = $false, ParameterSetName = 'Years')]
        [int]$ValidityYears = 1,

        [Parameter(Mandatory = $true, ParameterSetName = 'Months')]
        [int]$ValidityMonths,

        [Parameter(Mandatory = $true, ParameterSetName = 'Days')]
        [int]$ValidityDays,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [switch]$ExportToFile = $false,

        [Parameter(Mandatory = $false)]
        [string]$CommonName,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1024, 2048, 4096)]
        [int]$KeySize = 2048,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Auto", "PowerShell", "OpenSSL")]
        [string]$CertificateGenerationMethod = "Auto"
    )

    begin {
        Write-Verbose "Starting Add-EntraAppCertificate function"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection -RequiredScopes "Application.ReadWrite.All")) {
            throw "No active Microsoft Graph connection with required permissions. Please connect using Connect-EntraGraphSession first."
        }
        
        # Get certificate settings
        $certSettings = Get-EntraCertificateSettings
        
        # If no explicit generation method was provided, use the one from settings
        if (-not $PSBoundParameters.ContainsKey('CertificateGenerationMethod') -and 
            $certSettings.certificateGeneration.preferredMethod) {
            $CertificateGenerationMethod = $certSettings.certificateGeneration.preferredMethod
            Write-Verbose "Using certificate generation method from settings: $CertificateGenerationMethod"
        }
        
        # Create output path if specified or use default module output path
        if (-not $OutputPath) {
            $OutputPath = New-EntraAppOutputFolder -FolderName "Certificates" -LogOutput
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
        
        # Calculate the validity period in days
        $validityDaysTotal = 0
        switch ($PSCmdlet.ParameterSetName) {
            'Years' { $validityDaysTotal = $ValidityYears * 365 }
            'Months' { $validityDaysTotal = $ValidityMonths * 30 }  # Approximation
            'Days' { $validityDaysTotal = $ValidityDays }
            default { $validityDaysTotal = $ValidityYears * 365 }
        }
        Write-Verbose "Certificate validity: $validityDaysTotal days"
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
            
            # Use app display name for Common Name if not specified
            if (-not $CommonName) {
                $CommonName = $appDisplayName
            }
            
            # Generate safe file name
            $certName = $appDisplayName -replace '[^\w\d]', '_'
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $certFileStem = "$certName-$timestamp"
            
            # The file paths will be generated by the helper function
            # Just need the file stem for use in the helper function
            Write-Verbose "Using certificate file name base: $certFileStem"
            
            Write-Verbose "Generating self-signed certificate for '$appDisplayName'..."
            
            # Use the helper function to generate the certificate with cross-platform compatibility
            Write-Verbose "Generating certificate for '$appDisplayName' using $CertificateGenerationMethod method"
            
            $certProperties = New-EntraAppSelfSignedCertificate `
                -Subject $CommonName `
                -OutputPath $OutputPath `
                -CertificateFileName $certFileStem `
                -ValidityDays $validityDaysTotal `
                -KeySize $KeySize `
                -PreferredMethod $CertificateGenerationMethod
            
            # Extract values from the returned properties
            $certFilePath = $certProperties.CertificatePath
            $privateKeyPath = $certProperties.PrivateKeyPath
            $publicKeyPath = $certProperties.PublicKeyPath
            $pfxFilePath = $certProperties.PfxPath
            $pfxPassword = $certProperties.PfxPassword
            $pfxPasswordFile = $certProperties.PfxPasswordFile
            $thumbprint = $certProperties.Thumbprint
            
            Write-Verbose "Certificate generated with thumbprint: $thumbprint"
            
            # Read the certificate file
            $certBytes = [System.IO.File]::ReadAllBytes($certFilePath)
            $certBase64 = [System.Convert]::ToBase64String($certBytes)
            
            # Create the key credential
            $keyCredential = @{
                type = "AsymmetricX509Cert"
                usage = "Verify"
                key = [System.Convert]::FromBase64String($certBase64)
                displayName = $CertificateDisplayName
            }
            
            # Update the application with the key credential
            Write-Verbose "Adding certificate to app registration in Entra ID"
            Update-MgApplication -ApplicationId $application.Id -KeyCredential $keyCredential
            
            # Create a result object with all relevant details
            $result = [PSCustomObject]@{
                AppId = $application.AppId
                AppName = $appDisplayName
                ObjectId = $application.Id
                CertificateDisplayName = $CertificateDisplayName
                CertificatePath = $certFilePath
                PrivateKeyPath = $privateKeyPath
                PublicKeyPath = $publicKeyPath
                PfxPath = $pfxFilePath
                PfxPasswordFile = $pfxPasswordFile
                PfxPassword = $pfxPassword
                Thumbprint = $thumbprint
                ValidFrom = $certProperties.ValidFrom
                ValidTo = $certProperties.ValidTo
                CommonName = $CommonName
                KeySize = $KeySize
                GeneratedBy = $certProperties.GeneratedBy
            }
            
            # Export the certificate metadata to a CSV file if requested
            if ($ExportToFile) {
                $metadataFilePath = Join-Path -Path $OutputPath -ChildPath "$certFileStem-metadata.csv"
                
                try {
                    # Create a copy without the sensitive password
                    $exportResult = $result | Select-Object -Property * -ExcludeProperty PfxPassword
                    $exportResult | Export-Csv -Path $metadataFilePath -NoTypeInformation
                    $result | Add-Member -MemberType NoteProperty -Name "MetadataFilePath" -Value $metadataFilePath
                    
                    Write-Verbose "Exported certificate metadata to file: $metadataFilePath"
                    Write-EntraLog -Message "Certificate metadata for app '$appDisplayName' exported to file: $metadataFilePath" -Level Info
                }
                catch {
                    Write-Warning "Failed to export certificate metadata to file: $_"
                }
            }
            
            Write-Host "Successfully added self-signed certificate to app registration '$appDisplayName'." -ForegroundColor Green
            Write-Host "Certificate files saved in $OutputPath directory." -ForegroundColor Green
            Write-Host "Certificate thumbprint: $thumbprint" -ForegroundColor Yellow
            Write-Host "Certificate valid until: $($certProperties.ValidTo)" -ForegroundColor Yellow
            
            # Provide security reminder
            Write-Warning "The PFX password has been saved to '$pfxPasswordFile'. This file contains sensitive information and should be secured."
            
            return $result
        }
        catch {
            Write-Error "Failed to add certificate: $_"
            throw $_
        }
    }
}
