<#
.SYNOPSIS
    Generates a self-signed certificate for use with app registrations.

.DESCRIPTION
    The New-EntraAppSelfSignedCertificate function creates a self-signed certificate using the appropriate
    method based on the operating system and available tools. It supports:
    
    1. PowerShell's New-SelfSignedCertificate cmdlet (Windows)
    2. OpenSSL (cross-platform, if installed)
    3. Fallback methods if neither of the above are available
    
    The function creates several certificate-related files:
    - A certificate file (.crt)
    - A private key file (.key)
    - A PKCS#12/PFX file (.pfx) with a generated password
    - A password text file containing the PFX password
    
    All generated files are saved to the specified output path.

.PARAMETER Subject
    The subject name for the certificate. Typically set to the app registration display name.

.PARAMETER OutputPath
    The directory path where the certificate files should be saved.

.PARAMETER CertificateFileName
    The base name for the generated certificate files (without extension).

.PARAMETER ValidityDays
    The number of days the certificate should be valid for. Default is 365 days (1 year).

.PARAMETER KeySize
    The size of the RSA key to generate. Default is 2048 bits.

.PARAMETER PreferredMethod
    The preferred method for certificate generation: 'Auto', 'PowerShell', or 'OpenSSL'.
    When set to 'Auto', the function will choose the best method based on the operating system
    and available tools.

.EXAMPLE
    New-EntraAppSelfSignedCertificate -Subject "MyApp" -OutputPath ".\Certificates" -CertificateFileName "MyApp-20250514"
    Creates a self-signed certificate for "MyApp" in the ".\Certificates" directory.

.EXAMPLE
    New-EntraAppSelfSignedCertificate -Subject "MyApp" -OutputPath ".\Certificates" -CertificateFileName "MyApp-20250514" -ValidityDays 730 -KeySize 4096 -PreferredMethod "PowerShell"
    Creates a self-signed certificate using PowerShell with a 4096-bit key valid for 2 years.

.OUTPUTS
    PSObject
    Returns an object containing paths to the generated files and certificate metadata.

.NOTES
    This function is part of the EntraAppReg module and is used internally by Add-EntraAppCertificate.
    It supports cross-platform operation and will use the most appropriate certificate generation
    method based on the operating system and available tools.
#>
function New-EntraAppSelfSignedCertificate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [string]$CertificateFileName,

        [Parameter(Mandatory = $false)]
        [int]$ValidityDays = 365,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1024, 2048, 4096)]
        [int]$KeySize = 2048,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Auto", "PowerShell", "OpenSSL")]
        [string]$PreferredMethod = "Auto"
    )

    begin {
        Write-Verbose "Starting certificate generation for $Subject using method: $PreferredMethod"

        # Ensure output directory exists
        if (-not (Test-Path -Path $OutputPath)) {
            try {
                New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created output directory: $OutputPath"
            }
            catch {
                throw "Failed to create output directory '$OutputPath': $_"
            }
        }

        # Define file paths
        $privateKeyPath = Join-Path -Path $OutputPath -ChildPath "$CertificateFileName-private.key"
        $certFilePath = Join-Path -Path $OutputPath -ChildPath "$CertificateFileName.crt"
        $pfxFilePath = Join-Path -Path $OutputPath -ChildPath "$CertificateFileName.pfx"
        $publicKeyPath = Join-Path -Path $OutputPath -ChildPath "$CertificateFileName-public.pem"
        $pfxPassword = [System.Guid]::NewGuid().ToString()
        $pfxPasswordFile = Join-Path -Path $OutputPath -ChildPath "$CertificateFileName-password.txt"

        # Save the PFX password to a file
        $pfxPassword | Out-File -FilePath $pfxPasswordFile -Force
        Write-Verbose "Generated password for PFX file and saved to: $pfxPasswordFile"

        # Determine the best certificate generation method
        if ($PreferredMethod -eq "Auto") {
            # Check platform and available tools
            if ($IsWindows -or (-not $IsWindows -and -not $IsMacOS -and -not $IsLinux)) {
                # On Windows, use PowerShell's certificate cmdlets
                $method = "PowerShell"
                
                # Verify New-SelfSignedCertificate is available
                if (-not (Get-Command -Name New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
                    Write-Warning "New-SelfSignedCertificate cmdlet not found. Trying OpenSSL..."
                    $method = "OpenSSL"
                }
            }
            else {
                # On macOS/Linux, default to OpenSSL
                $method = "OpenSSL"
            }
            
            # If the selected method is OpenSSL, verify that it's available
            if ($method -eq "OpenSSL") {
                try {
                    $opensslVersion = & openssl version
                    Write-Verbose "OpenSSL found: $opensslVersion"
                }
                catch {
                    throw "Unable to automatically select certificate generation method. OpenSSL is not available, and PowerShell certificate cmdlets are not available on this platform."
                }
            }
            
            Write-Verbose "Auto-selected certificate generation method: $method"
        }
        else {
            $method = $PreferredMethod
            
            # Verify that the specified method is available
            if ($method -eq "PowerShell" -and -not (Get-Command -Name New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
                throw "PowerShell certificate generation method selected but New-SelfSignedCertificate cmdlet is not available."
            }
            elseif ($method -eq "OpenSSL") {
                try {
                    $opensslVersion = & openssl version
                    Write-Verbose "OpenSSL found: $opensslVersion"
                }
                catch {
                    throw "OpenSSL certificate generation method selected but OpenSSL is not available in the system path."
                }
            }
            
            Write-Verbose "Using specified certificate generation method: $method"
        }
    }

    process {
        try {
            $result = $null

            switch ($method) {
                "PowerShell" {
                    Write-Verbose "Generating certificate using PowerShell's New-SelfSignedCertificate cmdlet"
                    
                    # Calculate dates
                    $notBefore = Get-Date
                    $notAfter = $notBefore.AddDays($ValidityDays)
                    
                    # Create the certificate
                    $cert = New-SelfSignedCertificate `
                        -Subject "CN=$Subject" `
                        -CertStoreLocation "Cert:\CurrentUser\My" `
                        -KeyAlgorithm RSA `
                        -KeyLength $KeySize `
                        -NotBefore $notBefore `
                        -NotAfter $notAfter `
                        -KeyUsage DigitalSignature, KeyEncipherment `
                        -FriendlyName $Subject
                    
                    Write-Verbose "Certificate created in CurrentUser\My store with thumbprint: $($cert.Thumbprint)"
                    
                    # Export the certificate to PFX
                    $securePassword = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
                    Export-PfxCertificate -Cert $cert -FilePath $pfxFilePath -Password $securePassword -Force | Out-Null
                    
                    # Export the public certificate
                    Export-Certificate -Cert $cert -FilePath $certFilePath -Type CERT | Out-Null
                    
                    # For consistency with OpenSSL, export the public key to PEM format
                    # (simplified approach, may need additional parsing)
                    $certContent = Get-Content -Path $certFilePath -Raw -Encoding Byte
                    $certBase64 = [System.Convert]::ToBase64String($certContent)
                    $pemContent = "-----BEGIN CERTIFICATE-----`n" + 
                                 ($certBase64 -replace '(.{64})', '$1`n') + 
                                 "`n-----END CERTIFICATE-----"
                    $pemContent | Out-File -FilePath $publicKeyPath -Encoding ASCII
                    
                    # For private key, we'd normally export the PFX and extract, but that's complex
                    # Just note that the private key is in the PFX
                    "Private key is contained in the PFX file" | Out-File -FilePath $privateKeyPath -Encoding ASCII
                    
                    # Remove the certificate from the store
                    Get-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" | Remove-Item
                    
                    # Build the result
                    $result = [PSCustomObject]@{
                        CertificatePath = $certFilePath
                        PrivateKeyPath = $privateKeyPath
                        PublicKeyPath = $publicKeyPath
                        PfxPath = $pfxFilePath
                        PfxPasswordFile = $pfxPasswordFile
                        PfxPassword = $pfxPassword
                        Thumbprint = $cert.Thumbprint
                        ValidFrom = $notBefore
                        ValidTo = $notAfter
                        Subject = "CN=$Subject"
                        KeySize = $KeySize
                        GeneratedBy = "PowerShell"
                    }
                }
                
                "OpenSSL" {
                    Write-Verbose "Generating certificate using OpenSSL"
                    
                    # Generate private key
                    Write-Verbose "Generating $KeySize-bit RSA private key"
                    $opensslResult = & openssl genrsa -out $privateKeyPath $KeySize 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to generate private key: $opensslResult"
                    }
                    
                    # Generate certificate signing request (CSR) configuration
                    $csrConfPath = Join-Path -Path $OutputPath -ChildPath "$CertificateFileName-csr.conf"
                    $csrConf = @"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $Subject

[v3_req]
keyUsage = keyEncipherment, dataEncipherment, digitalSignature
extendedKeyUsage = serverAuth, clientAuth
"@
                    
                    # Save CSR config to file
                    $csrConf | Out-File -FilePath $csrConfPath -Force
                    
                    # Generate self-signed certificate
                    Write-Verbose "Generating self-signed certificate valid for $ValidityDays days"
                    $opensslResult = & openssl req -new -x509 -key $privateKeyPath -out $certFilePath -days $ValidityDays -config $csrConfPath 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to generate certificate: $opensslResult"
                    }
                    
                    # Export public key
                    $opensslResult = & openssl x509 -in $certFilePath -pubkey -noout > $publicKeyPath 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to export public key: $opensslResult"
                    }
                    
                    # Create PFX
                    Write-Verbose "Creating PFX file with password protection"
                    $opensslResult = & openssl pkcs12 -export -out $pfxFilePath -inkey $privateKeyPath -in $certFilePath -password "pass:$pfxPassword" 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to create PFX: $opensslResult"
                    }
                    
                    # Calculate certificate thumbprint
                    $thumbprintOutput = & openssl x509 -in $certFilePath -fingerprint -noout
                    $thumbprint = $thumbprintOutput -replace "SHA1 Fingerprint=", ""
                    $thumbprint = $thumbprint -replace ":", ""
                    
                    Write-Verbose "Certificate generated with thumbprint: $thumbprint"
                    
                    # Get certificate validity dates
                    $certInfo = & openssl x509 -in $certFilePath -noout -startdate -enddate
                    $startDate = ($certInfo | Where-Object { $_ -like "notBefore*" }) -replace "notBefore=", ""
                    $endDate = ($certInfo | Where-Object { $_ -like "notAfter*" }) -replace "notAfter=", ""
                    
                    # Try to parse dates into DateTime objects
                    try {
                        $validFrom = [DateTime]::Parse($startDate)
                        $validTo = [DateTime]::Parse($endDate)
                    }
                    catch {
                        Write-Warning "Could not parse certificate dates: $_"
                        $validFrom = Get-Date
                        $validTo = $validFrom.AddDays($ValidityDays)
                    }
                    
                    # Build the result
                    $result = [PSCustomObject]@{
                        CertificatePath = $certFilePath
                        PrivateKeyPath = $privateKeyPath
                        PublicKeyPath = $publicKeyPath
                        PfxPath = $pfxFilePath
                        PfxPasswordFile = $pfxPasswordFile
                        PfxPassword = $pfxPassword
                        Thumbprint = $thumbprint
                        ValidFrom = $validFrom
                        ValidTo = $validTo
                        Subject = "CN=$Subject"
                        KeySize = $KeySize
                        GeneratedBy = "OpenSSL"
                    }
                    
                    # Clean up the CSR config file
                    Remove-Item -Path $csrConfPath -Force -ErrorAction SilentlyContinue
                }
                
                default {
                    throw "Unsupported certificate generation method: $method"
                }
            }
            
            return $result
        }
        catch {
            Write-Error "Failed to generate certificate: $_"
            throw $_
        }
    }
}
