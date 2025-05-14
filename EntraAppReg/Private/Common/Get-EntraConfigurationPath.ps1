<#
.SYNOPSIS
    Gets the appropriate path for EntraAppReg configuration storage.

.DESCRIPTION
    The Get-EntraConfigurationPath function determines the appropriate path for storing
    EntraAppReg configuration files like KnownServices.json. It handles different scenarios
    including module installation from PSGallery and local development.

.PARAMETER ConfigType
    The type of configuration path to retrieve. Available options:
    - ModuleDefault: The path within the module directory (default)
    - UserDefault: The path in user's AppData or platform equivalent
    - Custom: A custom path specified by the CustomPath parameter

.PARAMETER CustomPath
    The custom path to use when ConfigType is set to 'Custom'.

.PARAMETER CreateIfNotExists
    If specified, creates the directory if it does not exist.

.EXAMPLE
    Get-EntraConfigurationPath
    Returns the default configuration path based on the module location.

.EXAMPLE
    Get-EntraConfigurationPath -ConfigType UserDefault -CreateIfNotExists
    Returns the user-specific configuration path and creates it if it doesn't exist.

.EXAMPLE
    Get-EntraConfigurationPath -ConfigType Custom -CustomPath "C:\MyConfigs\EntraAppReg"
    Returns the specified custom path.

.OUTPUTS
    System.String
    Returns the full path to the configuration directory.

.NOTES
    This function supports module usage when installed from PSGallery and prevents
    writing to the module installation directory which may require elevation.
#>
function Get-EntraConfigurationPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("ModuleDefault", "UserDefault", "Custom")]
        [string]$ConfigType = "ModuleDefault",
        
        [Parameter(Mandatory = $false)]
        [string]$CustomPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$CreateIfNotExists
    )

    begin {
        Write-Verbose "Getting configuration path for EntraAppReg ($ConfigType)"
    }

    process {
        try {
            $configPath = $null
            
            switch ($ConfigType) {
                "ModuleDefault" {
                    # Use the module path - this might be read-only when installed from PSGallery
                    $moduleRoot = Get-EntraModuleRoot
                    $configPath = Join-Path -Path $moduleRoot -ChildPath "Config"
                    Write-Verbose "Using module default configuration path: $configPath"
                }
                
                "UserDefault" {
                    # Use platform-appropriate user config path
                    if ($IsWindows -or (-not $IsWindows -and -not $IsMacOS -and -not $IsLinux)) {
                        # Windows or PowerShell 5.1 on Windows
                        $configBase = Join-Path -Path $env:APPDATA -ChildPath "EntraAppReg"
                    }
                    elseif ($IsMacOS) {
                        # macOS
                        $configBase = Join-Path -Path $HOME -ChildPath ".config/EntraAppReg"
                    }
                    elseif ($IsLinux) {
                        # Linux
                        $configBase = Join-Path -Path $HOME -ChildPath ".config/EntraAppReg"
                    }
                    else {
                        # Fallback
                        $configBase = Join-Path -Path $HOME -ChildPath ".EntraAppReg"
                    }
                    
                    $configPath = Join-Path -Path $configBase -ChildPath "Config"
                    Write-Verbose "Using user default configuration path: $configPath"
                }
                
                "Custom" {
                    if (-not $CustomPath) {
                        throw "CustomPath parameter is required when ConfigType is Custom"
                    }
                    
                    $configPath = $CustomPath
                    Write-Verbose "Using custom configuration path: $configPath"
                }
            }
            
            # Create the directory if it doesn't exist and CreateIfNotExists is specified
            if ($CreateIfNotExists -and -not (Test-Path -Path $configPath)) {
                Write-Verbose "Creating configuration directory: $configPath"
                New-Item -Path $configPath -ItemType Directory -Force | Out-Null
            }
            
            return $configPath
        }
        catch {
            Write-Error "Failed to determine configuration path: $_"
            
            # Return the module config path as fallback
            $moduleRoot = $PSScriptRoot
            if ($moduleRoot) {
                $moduleParent = Split-Path -Path $moduleRoot -Parent
                $moduleGrandParent = Split-Path -Path $moduleParent -Parent
                return Join-Path -Path $moduleGrandParent -ChildPath "Config"
            }
            else {
                return Join-Path -Path $PWD.Path -ChildPath "Config"
            }
        }
    }
}

Export-ModuleMember -Function Get-EntraConfigurationPath
