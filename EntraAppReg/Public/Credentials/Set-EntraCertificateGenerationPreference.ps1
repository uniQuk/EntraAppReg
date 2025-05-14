<#
.SYNOPSIS
    Sets the preferred certificate generation method for the EntraAppReg module.

.DESCRIPTION
    The Set-EntraCertificateGenerationPreference function allows users to set their preferred
    certificate generation method for the EntraAppReg module. This setting will be used
    by the Add-EntraAppCertificate and other certificate-related functions.
    
    The setting is stored in the user's configuration directory and will persist across
    PowerShell sessions.

.PARAMETER Method
    The preferred certificate generation method:
    - Auto: Automatically select the best method based on the operating system (default)
    - PowerShell: Use PowerShell's New-SelfSignedCertificate cmdlet (Windows only)
    - OpenSSL: Use OpenSSL command line tool (requires OpenSSL to be installed)

.PARAMETER DefaultKeySize
    The default key size to use for certificate generation. Default is 2048 bits.

.PARAMETER DefaultValidityDays
    The default number of days for which certificates will be valid. Default is 365 days.

.EXAMPLE
    Set-EntraCertificateGenerationPreference -Method "PowerShell"
    Sets PowerShell as the preferred certificate generation method.

.EXAMPLE
    Set-EntraCertificateGenerationPreference -Method "OpenSSL" -DefaultKeySize 4096 -DefaultValidityDays 730
    Sets OpenSSL as the preferred method with 4096-bit keys valid for 2 years.

.NOTES
    This function is part of the EntraAppReg module and modifies user-specific settings.
    It does not change behavior for other users or at the system level.
    
    The PowerShell method is only available on Windows systems.
#>
function Set-EntraCertificateGenerationPreference {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet("Auto", "PowerShell", "OpenSSL")]
        [string]$Method = "Auto",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet(1024, 2048, 4096)]
        [int]$DefaultKeySize = 2048,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 1825)]
        [int]$DefaultValidityDays = 365
    )

    begin {
        Write-Verbose "Setting certificate generation preference to $Method"
    }

    process {
        try {
            # Check if PowerShell method is selected on a non-Windows system
            if ($Method -eq "PowerShell" -and
                (-not $IsWindows -and ($IsMacOS -or $IsLinux))) {
                Write-Warning "The PowerShell certificate generation method is only available on Windows systems."
                Write-Warning "Using 'Auto' method instead, which will select OpenSSL on this platform."
                $Method = "Auto"
            }
            
            # Check if OpenSSL is available when it's explicitly selected
            if ($Method -eq "OpenSSL") {
                try {
                    $opensslVersion = & openssl version
                    Write-Verbose "OpenSSL found: $opensslVersion"
                }
                catch {
                    Write-Warning "OpenSSL not found in the system path. Using 'Auto' method instead."
                    $Method = "Auto"
                }
            }
            
            # Get the user configuration path
            $userConfigPath = Get-EntraConfigurationPath -ConfigType UserDefault -CreateIfNotExists
            $userConfigFile = Join-Path -Path $userConfigPath -ChildPath "CertificateSettings.json"
            
            # If user config exists, load it; otherwise get the default
            if (Test-Path -Path $userConfigFile) {
                try {
                    $settingsJson = Get-Content -Path $userConfigFile -Raw
                    $settings = $settingsJson | ConvertFrom-Json
                }
                catch {
                    Write-Verbose "Could not parse existing settings file: $_"
                    $settings = Get-EntraCertificateSettings -ForceRefresh
                }
            }
            else {
                # Get default settings from module
                $settings = Get-EntraCertificateSettings -ForceRefresh
                
                # Convert to editable object if needed
                if ($settings.psobject.TypeNames -contains "System.Management.Automation.PSCustomObject") {
                    $settings = $settings | ConvertTo-Json -Depth 5 | ConvertFrom-Json
                }
            }

            # Update the settings
            if (-not $settings.certificateGeneration) {
                $settings | Add-Member -MemberType NoteProperty -Name "certificateGeneration" -Value ([PSCustomObject]@{})
            }
            
            if ($settings.certificateGeneration.psobject.Properties.Name -contains "preferredMethod") {
                $settings.certificateGeneration.preferredMethod = $Method
            }
            else {
                $settings.certificateGeneration | Add-Member -MemberType NoteProperty -Name "preferredMethod" -Value $Method
            }
            
            if ($settings.certificateGeneration.psobject.Properties.Name -contains "defaultKeySize") {
                $settings.certificateGeneration.defaultKeySize = $DefaultKeySize
            }
            else {
                $settings.certificateGeneration | Add-Member -MemberType NoteProperty -Name "defaultKeySize" -Value $DefaultKeySize
            }
            
            if ($settings.certificateGeneration.psobject.Properties.Name -contains "defaultValidityDays") {
                $settings.certificateGeneration.defaultValidityDays = $DefaultValidityDays
            }
            else {
                $settings.certificateGeneration | Add-Member -MemberType NoteProperty -Name "defaultValidityDays" -Value $DefaultValidityDays
            }
            
            # Save the updated settings back to the file
            $settings | ConvertTo-Json -Depth 5 | Out-File -FilePath $userConfigFile -Force
            
            # Clear the cache to ensure the new settings are loaded next time
            $script:CertificateSettings = $null
            
            Write-Host "Certificate generation preferences updated successfully:" -ForegroundColor Green
            Write-Host "  Preferred Method: $Method" -ForegroundColor Cyan
            Write-Host "  Default Key Size: $DefaultKeySize bits" -ForegroundColor Cyan
            Write-Host "  Default Validity: $DefaultValidityDays days" -ForegroundColor Cyan
            Write-Host "Settings saved to: $userConfigFile" -ForegroundColor Gray
        }
        catch {
            Write-Error "Failed to update certificate generation preferences: $_"
            throw $_
        }
    }
}
