<#
.SYNOPSIS
    Connects to the Microsoft Graph API for Entra ID operations.

.DESCRIPTION
    The Connect-EntraGraphSession function establishes a connection to the Microsoft Graph API
    using the Microsoft.Graph.Authentication module. It supports various authentication methods
    including interactive, client credentials, and certificate-based authentication.

.PARAMETER Scopes
    The Microsoft Graph scopes (permissions) to request. Default is "Application.ReadWrite.All".

.PARAMETER TenantId
    The Azure AD tenant ID or domain name. If not provided, the connection will use the home tenant.

.PARAMETER ClientId
    The client ID (application ID) for app-only authentication.

.PARAMETER ClientSecret
    The client secret for app-only authentication with client credentials.

.PARAMETER CertificatePath
    The path to a certificate file for certificate-based authentication.

.PARAMETER CertificateThumbprint
    The thumbprint of a certificate in the certificate store for certificate-based authentication.

.PARAMETER Force
    Forces a new connection even if one already exists.

.EXAMPLE
    Connect-EntraGraphSession
    Connects to Microsoft Graph API using interactive authentication.

.EXAMPLE
    Connect-EntraGraphSession -Scopes "Application.ReadWrite.All", "Directory.Read.All"
    Connects to Microsoft Graph API with multiple scopes.

.EXAMPLE
    Connect-EntraGraphSession -ClientId "00000000-0000-0000-0000-000000000000" -ClientSecret "App_Secret"
    Connects using application authentication with client credentials.

.EXAMPLE
    Connect-EntraGraphSession -ClientId "00000000-0000-0000-0000-000000000000" -CertificateThumbprint "1234567890ABCDEF1234567890ABCDEF12345678"
    Connects using application authentication with a certificate.

.NOTES
    This function requires the Microsoft.Graph.Authentication module.
    For app-only authentication, the application must have the appropriate permissions.
#>
function Connect-EntraGraphSession {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$Scopes = $script:GraphScopes,

        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Certificate')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredential')]
        [string]$ClientSecret,

        [Parameter(Mandatory = $true, ParameterSetName = 'CertificateFile')]
        [string]$CertificatePath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Certificate')]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    begin {
        # Check if Microsoft.Graph.Authentication module is available
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
            throw "The Microsoft.Graph.Authentication module is required. Please install it using: Install-Module -Name Microsoft.Graph.Authentication"
        }

        # Check if there's already an active connection
        if (Test-EntraGraphConnection) {
            if ($Force) {
                Write-Verbose "Force parameter specified. Disconnecting existing Graph session."
                Disconnect-EntraGraphSession
            } else {
                Write-Verbose "Already connected to Microsoft Graph. Use -Force to reconnect."
                return $true
            }
        }

        # Write verbose information
        Write-Verbose "Connecting to Microsoft Graph API..."
        if ($TenantId) {
            Write-Verbose "Using tenant: $TenantId"
        }

        Write-Verbose "Using scopes: $($Scopes -join ', ')"
    }

    process {
        try {
            # Create connection parameters
            $connectParams = @{
                Scopes = $Scopes
            }

            # Add tenant ID if specified
            if ($TenantId) {
                $connectParams.TenantId = $TenantId
            }

            # Use appropriate authentication method based on parameter set
            switch ($PSCmdlet.ParameterSetName) {
                'Interactive' {
                    Write-Verbose "Using interactive authentication"
                }
                'ClientCredential' {
                    Write-Verbose "Using client credential authentication"
                    $secureClientSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
                    $connectParams.ClientId = $ClientId
                    $connectParams.ClientSecret = $secureClientSecret
                }
                'Certificate' {
                    Write-Verbose "Using certificate authentication with thumbprint"
                    $connectParams.ClientId = $ClientId
                    $connectParams.CertificateThumbprint = $CertificateThumbprint
                }
                'CertificateFile' {
                    Write-Verbose "Using certificate authentication with file"
                    $connectParams.ClientId = $ClientId
                    $connectParams.Certificate = Get-Item -Path $CertificatePath
                }
            }

            # Connect to Microsoft Graph
            $connection = Connect-MgGraph @connectParams
            
            # Store connection in module variable
            $script:GraphConnection = $connection
            
            # Return success
            Write-Verbose "Successfully connected to Microsoft Graph API"
            Write-Host "Connected to Microsoft Graph API" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to connect to Microsoft Graph: $_"
            return $false
        }
    }
}
