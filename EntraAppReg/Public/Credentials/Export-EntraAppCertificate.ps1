<#
.SYNOPSIS
    Exports a certificate from a PFX file to various formats.

.DESCRIPTION
    The Export-EntraAppCertificate function exports a certificate from a PKCS#12/PFX file
    to various formats, including PEM, DER, and separate key files. This is useful when
    you need to provide the certificate in a specific format for different applications.
    
    The function supports exporting:
    - Public certificate in PEM format (.crt)
    - Public certificate in DER format (.der)
    - Private key in PEM format (.key)
    - Combined certificate and key in PEM format (.pem)
    
    It handles cross-platform differences by using the appropriate tools (OpenSSL).

.PARAMETER PfxPath
    The path to the PFX file to export from.

.PARAMETER PfxPassword
    The password for the PFX file. If not provided, the function will look for a corresponding
    password file in the same directory.

.PARAMETER OutputPath
    The directory where the exported files should be saved.
    If not specified, files will be saved in the same directory as the PFX file.

.PARAMETER ExportPrivateKey
    Switch to include the private key in the export. Default is $true.

.PARAMETER OutputFormats
    Array of formats to export to. Allowed values: PEM, DER, PKCS8, KeyOnly.
    Default is all formats.

.EXAMPLE
    Export-EntraAppCertificate -PfxPath "C:\Certificates\MyApp.pfx" -PfxPassword "Secret123"
    Exports the certificate from MyApp.pfx to all supported formats in the same directory.

.EXAMPLE
    Export-EntraAppCertificate -PfxPath "C:\Certificates\MyApp.pfx" -OutputPath "C:\Exports" -ExportPrivateKey $false
    Exports only the public certificate (no private key) to the specified output directory.

.EXAMPLE
    Export-EntraAppCertificate -PfxPath "C:\Certificates\MyApp.pfx" -OutputFormats @("PEM", "DER")
    Exports the certificate to PEM and DER formats only.

.OUTPUTS
    PSObject
    Returns an object with paths to all exported files.

.NOTES
    This function requires OpenSSL to be installed and available in the system path.
    
    Exporting private keys should be handled with care - the exported files should be
    secured appropriately as they contain sensitive information.
#>
function Export-EntraAppCertificate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$PfxPath,
        
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$PfxPassword,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [bool]$ExportPrivateKey = $true,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("PEM", "DER", "PKCS8", "KeyOnly")]
        [string[]]$OutputFormats = @("PEM", "DER", "PKCS8", "KeyOnly")
    )

    begin {
        Write-Verbose "Starting Export-EntraAppCertificate function"

        # If no output path is specified, use the directory containing the PFX
        if (-not $OutputPath) {
            $OutputPath = Split-Path -Path $PfxPath -Parent
        }
        
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
        
        # If no password is provided, try to find a password file
        if (-not $PfxPassword) {
            $pfxDir = Split-Path -Path $PfxPath -Parent
            $pfxBaseName = [System.IO.Path]::GetFileNameWithoutExtension($PfxPath)
            $pfxPasswordFile = Join-Path -Path $pfxDir -ChildPath "$pfxBaseName-password.txt"
            
            if (Test-Path -Path $pfxPasswordFile) {
                $PfxPassword = Get-Content -Path $pfxPasswordFile -Raw
                $PfxPassword = $PfxPassword.Trim()
                Write-Verbose "Using password from file: $pfxPasswordFile"
            }
            else {
                throw "PFX password not provided and no password file found at $pfxPasswordFile"
            }
        }
        
        # Check for OpenSSL
        try {
            $opensslVersion = & openssl version
            Write-Verbose "OpenSSL found: $opensslVersion"
        }
        catch {
            throw "OpenSSL not found in the system path. This function requires OpenSSL for certificate export operations."
        }
        
        # Prepare file paths
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($PfxPath)
        
        # Output file paths
        $pemCertPath = Join-Path -Path $OutputPath -ChildPath "$baseName.crt"
        $derCertPath = Join-Path -Path $OutputPath -ChildPath "$baseName.der"
        $pemKeyPath = Join-Path -Path $OutputPath -ChildPath "$baseName-key.pem"
        $pkcs8KeyPath = Join-Path -Path $OutputPath -ChildPath "$baseName-pkcs8-key.pem"
        $combinedPemPath = Join-Path -Path $OutputPath -ChildPath "$baseName-combined.pem"
    }

    process {
        try {
            $result = [PSCustomObject]@{
                OriginalPfxPath = $PfxPath
                ExportedFiles = @{}
                Success = $false
            }
            
            # Export certificate in PEM format (public cert only)
            if ($OutputFormats -contains "PEM") {
                Write-Verbose "Exporting certificate to PEM format: $pemCertPath"
                $opensslResult = & openssl pkcs12 -in $PfxPath -clcerts -nokeys -out $pemCertPath -password "pass:$PfxPassword" 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to export certificate to PEM: $opensslResult"
                }
                else {
                    $result.ExportedFiles["PEM_Certificate"] = $pemCertPath
                }
            }
            
            # Export certificate in DER format (public cert only)
            if ($OutputFormats -contains "DER") {
                Write-Verbose "Exporting certificate to DER format: $derCertPath"
                
                if ($result.ExportedFiles.ContainsKey("PEM_Certificate")) {
                    # Convert from PEM to DER
                    $opensslResult = & openssl x509 -in $pemCertPath -outform DER -out $derCertPath 2>&1
                }
                else {
                    # Direct from PFX to DER
                    $opensslResult = & openssl pkcs12 -in $PfxPath -clcerts -nokeys -out $derCertPath -outform DER -password "pass:$PfxPassword" 2>&1
                }
                
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to export certificate to DER: $opensslResult"
                }
                else {
                    $result.ExportedFiles["DER_Certificate"] = $derCertPath
                }
            }
            
            # Export the private key if requested
            if ($ExportPrivateKey) {
                # Export private key in PEM format
                if ($OutputFormats -contains "KeyOnly") {
                    Write-Verbose "Exporting private key to PEM format: $pemKeyPath"
                    $opensslResult = & openssl pkcs12 -in $PfxPath -nocerts -out $pemKeyPath -password "pass:$PfxPassword" -passout "pass:$PfxPassword" 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Failed to export private key to PEM: $opensslResult"
                    }
                    else {
                        # Remove the passphrase from the key
                        $tempKeyPath = Join-Path -Path $OutputPath -ChildPath "$baseName-temp-key.pem"
                        $opensslResult = & openssl rsa -in $pemKeyPath -out $tempKeyPath -passin "pass:$PfxPassword" 2>&1
                        
                        if ($LASTEXITCODE -eq 0) {
                            # Replace the original file with the unencrypted one
                            Move-Item -Path $tempKeyPath -Destination $pemKeyPath -Force
                            $result.ExportedFiles["PEM_PrivateKey"] = $pemKeyPath
                        }
                        else {
                            Write-Error "Failed to remove passphrase from private key: $opensslResult"
                        }
                    }
                }
                
                # Export private key in PKCS8 format
                if ($OutputFormats -contains "PKCS8" -and $result.ExportedFiles.ContainsKey("PEM_PrivateKey")) {
                    Write-Verbose "Converting private key to PKCS8 format: $pkcs8KeyPath"
                    $opensslResult = & openssl pkcs8 -topk8 -inform PEM -outform PEM -in $pemKeyPath -out $pkcs8KeyPath -nocrypt 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error "Failed to convert private key to PKCS8 format: $opensslResult"
                    }
                    else {
                        $result.ExportedFiles["PKCS8_PrivateKey"] = $pkcs8KeyPath
                    }
                }
                
                # Create a combined PEM file with both certificate and key
                if ($OutputFormats -contains "PEM" -and 
                    $result.ExportedFiles.ContainsKey("PEM_Certificate") -and 
                    $result.ExportedFiles.ContainsKey("PEM_PrivateKey")) {
                    Write-Verbose "Creating combined PEM file: $combinedPemPath"
                    
                    try {
                        $certContent = Get-Content -Path $pemCertPath -Raw
                        $keyContent = Get-Content -Path $pemKeyPath -Raw
                        "$keyContent`n$certContent" | Out-File -FilePath $combinedPemPath -Encoding ASCII
                        $result.ExportedFiles["PEM_Combined"] = $combinedPemPath
                    }
                    catch {
                        Write-Error "Failed to create combined PEM file: $_"
                    }
                }
            }
            
            $result.Success = $result.ExportedFiles.Count -gt 0
            
            if ($result.Success) {
                Write-Host "Certificate exported successfully to the following formats:" -ForegroundColor Green
                foreach ($format in $result.ExportedFiles.Keys) {
                    Write-Host "  $format`: $($result.ExportedFiles[$format])" -ForegroundColor Cyan
                }
                
                if ($ExportPrivateKey) {
                    Write-Warning "Exported files contain private key material. Store them securely."
                }
            }
            else {
                Write-Warning "No certificate formats were successfully exported."
            }
            
            return $result
        }
        catch {
            Write-Error "Failed to export certificate: $_"
            throw $_
        }
    }
}
