<#
.SYNOPSIS
    Updates the module configuration paths.

.DESCRIPTION
    The Update-EntraConfigurationPaths function updates the module configuration paths
    based on availability and configured preferences. It ensures that the module uses
    the appropriate paths for reading and writing configuration files.

.PARAMETER Force
    If specified, forces the update of paths regardless of any cached values.

.EXAMPLE
    Update-EntraConfigurationPaths
    Updates the module configuration paths based on availability and preferences.

.OUTPUTS
    None

.NOTES
    This function is called internally when the module is loaded and should not be called directly.
#>
function Update-EntraConfigurationPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    try {
        Write-Verbose "Updating EntraAppReg configuration paths"

        # Module configuration path - always available, read-only when installed from PSGallery
        $moduleConfigPath = Get-EntraConfigurationPath -ConfigType ModuleDefault
        Write-Verbose "Module default configuration path: $moduleConfigPath"

        # User configuration path - writable, persists between module updates
        $userConfigPath = Get-EntraConfigurationPath -ConfigType UserDefault -CreateIfNotExists
        Write-Verbose "User configuration path: $userConfigPath"

        # Check which path to use for KnownServices
        $userKnownServicesPath = Join-Path -Path $userConfigPath -ChildPath "KnownServices.json"
        $userKnownServicesIndexPath = Join-Path -Path $userConfigPath -ChildPath "KnownServicesIndex.json"
        $moduleKnownServicesPath = Join-Path -Path $moduleConfigPath -ChildPath "KnownServices.json"
        
        # Determine which KnownServices path to use - user path takes precedence if it exists
        if (Test-Path -Path $userKnownServicesPath) {
            $script:KnownServicesPath = $userKnownServicesPath
            Write-Verbose "Using user KnownServices path: $userKnownServicesPath"
        }
        elseif (Test-Path -Path $moduleKnownServicesPath) {
            # Module path exists but might be read-only in PSGallery install
            $script:KnownServicesPath = $moduleKnownServicesPath
            Write-Verbose "Using module KnownServices path: $moduleKnownServicesPath"
            
            # Check if we can write to the user path and if the module path might be read-only
            $installLocation = $script:ModuleRootPath
            $isPSGalleryInstall = $installLocation -like "*\PowerShell\Modules\*" -or $installLocation -like "*/PowerShell/Modules/*"
            
            if ($isPSGalleryInstall) {
                # Copy the KnownServices file to user path for future use
                Write-Verbose "Module appears to be installed from PSGallery, copying KnownServices to user path"
                Copy-Item -Path $moduleKnownServicesPath -Destination $userKnownServicesPath -Force
                $script:KnownServicesPath = $userKnownServicesPath
            }
        }
        else {
            # Neither path exists, default to user path (it will be created when needed)
            $script:KnownServicesPath = $userKnownServicesPath
            Write-Verbose "No existing KnownServices path found, defaulting to user path: $userKnownServicesPath"
        }

        # Update the script-level variables
        $script:ConfigPaths = @{
            Module = $moduleConfigPath
            User = $userConfigPath
            Active = if (Test-Path -Path $userKnownServicesPath) { $userConfigPath } else { $moduleConfigPath }
            ReadOnly = $moduleConfigPath
            Writable = $userConfigPath
        }

        # Update normalized storage paths if they exist
        if (Test-Path -Path $userKnownServicesIndexPath) {
            $script:NormalizedStoragePath = $userConfigPath
            Write-Verbose "Using user path for normalized storage: $userConfigPath"
        }
        elseif (Test-Path -Path (Join-Path -Path $moduleConfigPath -ChildPath "KnownServicesIndex.json")) {
            $script:NormalizedStoragePath = $moduleConfigPath
            Write-Verbose "Using module path for normalized storage: $moduleConfigPath"
        }
        else {
            $script:NormalizedStoragePath = $userConfigPath
            Write-Verbose "No existing normalized storage path found, defaulting to user path: $userConfigPath"
        }

        return $true
    }
    catch {
        Write-Error "Failed to update configuration paths: $_"
        return $false
    }
}

Export-ModuleMember -Function Update-EntraConfigurationPaths
