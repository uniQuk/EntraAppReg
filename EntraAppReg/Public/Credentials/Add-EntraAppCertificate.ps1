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

.NOTES
    This function requires an active connection to Microsoft Graph API with Application.ReadWrite.All permission.
    Use Connect-EntraGraphSession before calling this function.
    
    This function requires OpenSSL to be installed and available in the system path.
    On macOS, OpenSSL is typically pre-installed. On Windows, you may need to install it separately.
    
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
        [int]$KeySize = 2048
    )

    begin {
        Write-Verbose "Starting Add-EntraAppCertificate function"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection -RequiredScopes "Application.ReadWrite.All")) {
            throw "No active Microsoft Graph connection with required permissions. Please connect using Connect-EntraGraphSession first."
        }
        
        # Check for OpenSSL
        try {
            $opensslVersion = & openssl version
            Write-Verbose "OpenSSL found: $opensslVersion"
        }
        catch {
            throw "OpenSSL not found in the system path. Please install OpenSSL and ensure it's available in the system path."
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
            
            # Create paths for certificate files
            $privateKeyPath = Join-Path -Path $OutputPath -ChildPath "$certFileStem-private.key"
            $certFilePath = Join-Path -Path $OutputPath -ChildPath "$certFileStem.crt"
            $pfxFilePath = Join-Path -Path $OutputPath -ChildPath "$certFileStem.pfx"
            $publicKeyPath = Join-Path -Path $OutputPath -ChildPath "$certFileStem-public.pem"
            $csrConfPath = Join-Path -Path $OutputPath -ChildPath "$certFileStem-csr.conf"
            
            # Generate a secure password for PFX
            $pfxPassword = [System.Guid]::NewGuid().ToString()
            $pfxPasswordFile = Join-Path -Path $OutputPath -ChildPath "$certFileStem-password.txt"
            
            # Save the PFX password to a file
            $pfxPassword | Out-File -FilePath $pfxPasswordFile -Force
            
            Write-Verbose "Generating self-signed certificate for '$appDisplayName'..."
            
            # Generate private key
            Write-Verbose "Generating $KeySize-bit RSA private key"
            $opensslResult = & openssl genrsa -out $privateKeyPath $KeySize 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to generate private key for '$appDisplayName': $opensslResult"
            }
            
            # Calculate certificate validity period
            $validFrom = (Get-Date).ToString("MMM dd HH:mm:ss yyyy")
            $validTo = (Get-Date).AddDays($validityDaysTotal).ToString("MMM dd HH:mm:ss yyyy")
            
            # Generate certificate signing request (CSR) configuration
            $csrConf = @"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $CommonName

[v3_req]
keyUsage = keyEncipherment, dataEncipherment, digitalSignature
extendedKeyUsage = serverAuth, clientAuth
"@
            
            # Save CSR config to file
            $csrConf | Out-File -FilePath $csrConfPath -Force
            
            # Generate self-signed certificate
            Write-Verbose "Generating self-signed certificate valid for $validityDaysTotal days"
            $opensslResult = & openssl req -new -x509 -key $privateKeyPath -out $certFilePath -days $validityDaysTotal -config $csrConfPath 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to generate certificate for '$appDisplayName': $opensslResult"
            }
            
            # Export public key
            $opensslResult = & openssl x509 -in $certFilePath -pubkey -noout > $publicKeyPath 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to export public key for '$appDisplayName': $opensslResult"
            }
            
            # Create PFX
            Write-Verbose "Creating PFX file with password protection"
            $opensslResult = & openssl pkcs12 -export -out $pfxFilePath -inkey $privateKeyPath -in $certFilePath -password "pass:$pfxPassword" 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create PFX for '$appDisplayName': $opensslResult"
            }
            
            # Calculate certificate thumbprint
            $thumbprintOutput = & openssl x509 -in $certFilePath -fingerprint -noout
            $thumbprint = $thumbprintOutput -replace "SHA1 Fingerprint=", ""
            $thumbprint = $thumbprint -replace ":", ""
            
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
            
            # Get certificate start and end dates
            $certInfo = & openssl x509 -in $certFilePath -noout -startdate -enddate
            $startDate = ($certInfo | Where-Object { $_ -like "notBefore*" }) -replace "notBefore=", ""
            $endDate = ($certInfo | Where-Object { $_ -like "notAfter*" }) -replace "notAfter=", ""
            
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
                ValidFrom = $startDate
                ValidTo = $endDate
                CommonName = $CommonName
                KeySize = $KeySize
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
            Write-Host "Certificate valid until: $endDate" -ForegroundColor Yellow
            
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
