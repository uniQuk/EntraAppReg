<#
.SYNOPSIS
    Tests if the KnownServices configuration file is outdated.

.DESCRIPTION
    The Test-EntraKnownServicesAge function checks if the KnownServices.json configuration file
    is outdated based on its last updated timestamp and the configured refresh interval.

.PARAMETER Path
    The path to the KnownServices.json configuration file.

.PARAMETER RefreshIntervalDays
    The number of days after which the KnownServices.json file should be considered outdated.
    Default is 30 days.

.EXAMPLE
    Test-EntraKnownServicesAge
    Tests if the default KnownServices.json file is outdated.

.EXAMPLE
    Test-EntraKnownServicesAge -RefreshIntervalDays 7
    Tests if the KnownServices.json file is more than 7 days old.

.EXAMPLE
    if (Test-EntraKnownServicesAge) {
        Update-EntraKnownServices
    }
    Updates the KnownServices.json file only if it is outdated.

.NOTES
    This function is used by the module to determine if the KnownServices.json file
    should be updated automatically.
#>
function Test-EntraKnownServicesAge {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Path = $script:KnownServicesPath,

        [Parameter(Mandatory = $false)]
        [int]$RefreshIntervalDays = 30
    )

    begin {
        Write-Verbose "Testing if KnownServices configuration is outdated..."
    }

    process {
        try {
            # Check if the file exists
            if (-not (Test-Path -Path $Path)) {
                Write-Verbose "KnownServices configuration file does not exist at $Path"
                return $true
            }

            # Load the configuration
            $config = Get-Content -Path $Path -Raw | ConvertFrom-Json

            # Check if the metadata exists
            if (-not $config.Metadata -or -not $config.Metadata.LastUpdated) {
                Write-Verbose "KnownServices configuration file does not have a LastUpdated timestamp"
                return $true
            }

            # Check if auto-refresh is disabled
            if ($config.Metadata.AutoRefreshEnabled -eq $false) {
                Write-Verbose "Auto-refresh is disabled in the KnownServices configuration"
                return $false
            }

            # Get the refresh interval from the configuration if available
            if ($config.Metadata.RefreshIntervalDays -and -not $PSBoundParameters.ContainsKey('RefreshIntervalDays')) {
                $RefreshIntervalDays = $config.Metadata.RefreshIntervalDays
            }

            # Parse the last updated timestamp
            $lastUpdated = [DateTime]::Parse($config.Metadata.LastUpdated)

            # Calculate the age in days
            $age = ([DateTime]::UtcNow - $lastUpdated).TotalDays

            # Check if the configuration is outdated
            $isOutdated = $age -ge $RefreshIntervalDays

            if ($isOutdated) {
                Write-Verbose "KnownServices configuration is outdated (last updated $($age.ToString("F1")) days ago, threshold is $RefreshIntervalDays days)"
            } else {
                Write-Verbose "KnownServices configuration is up to date (last updated $($age.ToString("F1")) days ago, threshold is $RefreshIntervalDays days)"
            }

            return $isOutdated
        }
        catch {
            Write-Warning "Failed to test KnownServices configuration age: $_"
            return $true
        }
    }
}
