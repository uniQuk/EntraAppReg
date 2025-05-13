<#
.SYNOPSIS
    Writes a log message for the EntraAppReg module.

.DESCRIPTION
    The Write-EntraLog function writes a log message to a log file and optionally to the console.
    It supports various log levels (Information, Warning, Error, Verbose) and can format messages
    with timestamps and prefixes.

.PARAMETER Message
    The log message to write.

.PARAMETER Level
    The log level. Can be Information, Warning, Error, or Verbose.

.PARAMETER LogPath
    The path to the log file. If not specified, the default log path will be used.

.PARAMETER NoConsole
    When specified, prevents the message from being written to the console.

.PARAMETER NoTimestamp
    When specified, prevents the timestamp from being included in the log message.

.PARAMETER NoPrefix
    When specified, prevents the log level prefix from being included in the log message.

.EXAMPLE
    Write-EntraLog -Message "Operation completed successfully" -Level Information
    Writes an information message to the log file and console.

.EXAMPLE
    Write-EntraLog -Message "Operation failed" -Level Error -NoConsole
    Writes an error message to the log file only.

.NOTES
    This function is used by other functions in the EntraAppReg module to provide consistent logging.
#>
function Write-EntraLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Information", "Warning", "Error", "Verbose")]
        [string]$Level = "Information",

        [Parameter(Mandatory = $false)]
        [string]$LogPath,

        [Parameter(Mandatory = $false)]
        [switch]$NoConsole,

        [Parameter(Mandatory = $false)]
        [switch]$NoTimestamp,

        [Parameter(Mandatory = $false)]
        [switch]$NoPrefix
    )

    begin {
        # Use default log path if not specified
        if (-not $LogPath) {
            $LogPath = $script:LogPath
        }

        # Create log path if it doesn't exist
        if (-not (Test-Path -Path $LogPath)) {
            try {
                New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
            }
            catch {
                Write-Warning "Failed to create log directory: $_"
            }
        }

        # Create log file path
        $logFileName = "EntraAppReg_$(Get-Date -Format 'yyyyMMdd').log"
        $logFilePath = Join-Path -Path $LogPath -ChildPath $logFileName

        # Prepare timestamp
        $timestamp = if (-not $NoTimestamp) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | " } else { "" }

        # Prepare prefix
        $prefix = if (-not $NoPrefix) {
            switch ($Level) {
                "Information" { "INFO  | " }
                "Warning"     { "WARN  | " }
                "Error"       { "ERROR | " }
                "Verbose"     { "DEBUG | " }
                default       { "      | " }
            }
        } else { "" }

        # Prepare full log message
        $fullMessage = "$timestamp$prefix$Message"
    }

    process {
        try {
            # Add message to log file
            Add-Content -Path $logFilePath -Value $fullMessage -ErrorAction SilentlyContinue

            # Write to console if not suppressed
            if (-not $NoConsole) {
                switch ($Level) {
                    "Information" {
                        Write-Host $fullMessage -ForegroundColor White
                    }
                    "Warning" {
                        Write-Host $fullMessage -ForegroundColor Yellow
                    }
                    "Error" {
                        Write-Host $fullMessage -ForegroundColor Red
                    }
                    "Verbose" {
                        if ($VerbosePreference -eq "Continue" -or $script:VerboseLogging) {
                            Write-Host $fullMessage -ForegroundColor Gray
                        }
                    }
                }
            }
        }
        catch {
            # Fallback to Write-Warning if there's an issue with the log file
            Write-Warning "Failed to write to log file: $_"
            Write-Warning $Message
        }
    }
}
