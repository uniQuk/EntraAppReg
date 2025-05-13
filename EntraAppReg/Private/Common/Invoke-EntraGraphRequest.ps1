<#
.SYNOPSIS
    Invokes a Microsoft Graph API request with error handling and retries.

.DESCRIPTION
    The Invoke-EntraGraphRequest function is a wrapper for Invoke-MgGraphRequest that adds
    error handling, automatic retries for transient errors, and optional result processing.
    It is used by other functions in the EntraAppReg module to call the Microsoft Graph API.

.PARAMETER Uri
    The URI of the Microsoft Graph API endpoint to call.

.PARAMETER Method
    The HTTP method to use for the request. Default is GET.

.PARAMETER Body
    The body of the request for POST, PUT, and PATCH methods.

.PARAMETER Headers
    Additional headers to include in the request.

.PARAMETER ContentType
    The content type of the request. Default is "application/json".

.PARAMETER MaxRetries
    The maximum number of retry attempts for transient errors. Default is defined in the module configuration.

.PARAMETER RetryDelaySeconds
    The delay in seconds between retry attempts. Default is defined in the module configuration.

.PARAMETER Raw
    When specified, returns the raw response without processing.

.EXAMPLE
    Invoke-EntraGraphRequest -Uri "https://graph.microsoft.com/v1.0/applications"
    Gets all applications from the Microsoft Graph API.

.EXAMPLE
    Invoke-EntraGraphRequest -Uri "https://graph.microsoft.com/v1.0/applications" -Method POST -Body $bodyObject
    Creates a new application using the Microsoft Graph API.

.NOTES
    This function requires an active connection to the Microsoft Graph API.
    Use Connect-EntraGraphSession before calling this function.
#>
function Invoke-EntraGraphRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateSet("GET", "POST", "PUT", "PATCH", "DELETE")]
        [string]$Method = "GET",

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $false)]
        [string]$ContentType = "application/json",

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = $script:MaxRetryAttempts,

        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = $script:RetryDelaySeconds,

        [Parameter(Mandatory = $false)]
        [switch]$Raw
    )

    begin {
        Write-Verbose "Invoking Graph API request: $Method $Uri"

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection)) {
            throw "No active Microsoft Graph connection. Please connect using Connect-EntraGraphSession first."
        }

        # Initialize variables
        $retryCount = 0
        $success = $false
        $result = $null
        $transientErrors = @(429, 500, 502, 503, 504)
    }

    process {
        # Try the request with retries for transient errors
        while (-not $success -and $retryCount -le $MaxRetries) {
            try {
                # Prepare request parameters
                $requestParams = @{
                    Uri = $Uri
                    Method = $Method
                    ErrorAction = "Stop"
                }

                # Add body if specified
                if ($Body) {
                    $requestParams.Body = $Body
                }

                # Add headers if specified
                if ($Headers) {
                    $requestParams.Headers = $Headers
                }

                # Add content type if specified
                if ($ContentType) {
                    $requestParams.ContentType = $ContentType
                }

                # Invoke the Graph request
                $result = Invoke-MgGraphRequest @requestParams

                # If we get here, the request was successful
                $success = $true
            }
            catch {
                # Increment retry count
                $retryCount++

                # Get the response status code
                $statusCode = 0
                if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }

                # Check if this is a transient error that we should retry
                if ($statusCode -in $transientErrors -and $retryCount -le $MaxRetries) {
                    $delay = $RetryDelaySeconds * [Math]::Pow(2, $retryCount - 1)
                    Write-EntraLog -Message "Transient error ($statusCode) occurred. Retrying in $delay seconds (attempt $retryCount of $MaxRetries)..." -Level Warning
                    Start-Sleep -Seconds $delay
                }
                else {
                    # This is not a transient error or we've reached max retries
                    Write-EntraLog -Message "Error invoking Graph API: $_" -Level Error
                    throw $_
                }
            }
        }

        # Return the raw result if requested
        if ($Raw) {
            return $result
        }

        # Process and return the result
        return $result
    }
}
