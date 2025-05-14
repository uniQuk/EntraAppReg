<#
.SYNOPSIS
    Gets the root path of the EntraAppReg module.

.DESCRIPTION
    The Get-EntraModuleRoot function determines and returns the root path of the EntraAppReg module.
    It is used by other functions in the module to locate configuration files and other resources.

.EXAMPLE
    $moduleRoot = Get-EntraModuleRoot
    Returns the root path of the EntraAppReg module.

.OUTPUTS
    System.String
    Returns the full path to the module root directory.

.NOTES
    This function is used internally by the EntraAppReg module and should not be called directly by users.
#>
function Get-EntraModuleRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        # Try to get the module path from the loaded modules
        $module = Get-Module -Name EntraAppReg -ErrorAction SilentlyContinue
        if ($module) {
            $moduleRoot = Split-Path -Path $module.Path -Parent
            Write-Verbose "Module root path from loaded module: $moduleRoot"
            return $moduleRoot
        }
        
        # If not loaded, try to get from the current script path
        if ($PSScriptRoot) {
            # Navigate up from current script location
            $scriptParent = Split-Path -Path $PSScriptRoot -Parent
            $moduleRoot = Split-Path -Path $scriptParent -Parent
            if (Test-Path -Path (Join-Path -Path $moduleRoot -ChildPath "EntraAppReg.psd1")) {
                Write-Verbose "Module root path from script: $moduleRoot"
                return $moduleRoot
            }
        }
        
        # If both methods fail, try to find the module in the available modules
        $moduleInfo = Get-Module -ListAvailable -Name EntraAppReg | Select-Object -First 1
        if ($moduleInfo) {
            $moduleRoot = Split-Path -Path $moduleInfo.Path -Parent
            Write-Verbose "Module root path from available modules: $moduleRoot"
            return $moduleRoot
        }
        
        # If all methods fail, try to use the current directory
        # Only use this as a last resort in development scenarios
        $currentDir = $PWD.Path
        if ((Test-Path -Path (Join-Path -Path $currentDir -ChildPath "EntraAppReg.psd1")) -or
            (Test-Path -Path (Join-Path -Path (Join-Path -Path $currentDir -ChildPath "EntraAppReg") -ChildPath "EntraAppReg.psd1"))) {
            Write-Verbose "Module root path from current directory: $currentDir"
            if (Test-Path -Path (Join-Path -Path $currentDir -ChildPath "EntraAppReg.psd1")) {
                return $currentDir
            }
            else {
                return Join-Path -Path $currentDir -ChildPath "EntraAppReg"
            }
        }
        
        # If we still can't find it, use a fallback path for development
        $fallbackPath = "/Volumes/Kingston2TB/dev-ps-modules/EntraAppReg/EntraAppReg"
        if (Test-Path -Path $fallbackPath) {
            Write-Warning "Using fallback path for EntraAppReg module: $fallbackPath"
            return $fallbackPath
        }
        
        Write-Error "Could not determine EntraAppReg module root path"
        return $null
    }
    catch {
        Write-Error "Error determining EntraAppReg module root path: $_"
        return $null
    }
}

# Set the module root path when this script is imported
$script:ModuleRootPath = Get-EntraModuleRoot

Export-ModuleMember -Function Get-EntraModuleRoot
