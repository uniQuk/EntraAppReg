<#
.SYNOPSIS
    Updates the KnownServices configuration file with the latest service principals and permissions from the tenant.

.DESCRIPTION
    The Update-EntraKnownServices function queries the Microsoft Graph API to get the latest 
    service principals and their permissions from the tenant. It then updates the KnownServices.json
    configuration file with this information. The function can be used to keep the module's knowledge
    of available APIs and permissions up to date.
    
    The function captures both application permissions (appRoles) and delegated permissions
    (oauth2PermissionScopes) for each service principal. It stores detailed information about
    each permission including its ID, display name, description, and other relevant metadata.

.PARAMETER Force
    Forces an update even if the file is not outdated.

.PARAMETER IncludeMicrosoftGraph
    Includes Microsoft Graph permissions in the update. This can add a significant number of permissions.
    Microsoft Graph has hundreds of permissions, so including it can make the configuration file much larger.

.PARAMETER IncludeCustomApis
    Includes custom APIs (those created within the tenant) in the update.
    These are APIs that are not published by Microsoft.

.PARAMETER OutputPath
    The path where the updated KnownServices.json file will be saved. If not specified, the default
    configuration path will be used.

.PARAMETER RefreshIntervalDays
    The number of days after which the KnownServices.json file should be considered outdated.
    Default is 30 days.

.EXAMPLE
    Update-EntraKnownServices
    Updates the KnownServices.json file if it is outdated.

.EXAMPLE
    Update-EntraKnownServices -Force
    Updates the KnownServices.json file regardless of its age.

.EXAMPLE
    Update-EntraKnownServices -IncludeMicrosoftGraph -IncludeCustomApis
    Updates the KnownServices.json file with all available APIs and permissions.

.NOTES
    This function requires an active connection to the Microsoft Graph API with sufficient permissions.
    Use Connect-EntraGraphSession before calling this function.
#>
function Update-EntraKnownServices {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMicrosoftGraph,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeCustomApis,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath = $script:KnownServicesPath,

        [Parameter(Mandatory = $false)]
        [int]$RefreshIntervalDays = 30
    )

    begin {
        Write-Verbose "Checking if KnownServices configuration needs updating..."

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection)) {
            Write-Error "No active Microsoft Graph connection. Please connect using Connect-EntraGraphSession first."
            return $false
        }
        
        # Create base structure for the KnownServices configuration
        $knownServicesConfig = @{
            Metadata = @{
                LastUpdated = [DateTime]::UtcNow.ToString("o")
                RefreshIntervalDays = $RefreshIntervalDays
                AutoRefreshEnabled = $true
                Version = "2.0"  # Increment version for the new schema
            }
            ServicePrincipals = @{}  # Basic service principal info
            Permissions = @{}        # Detailed permission structure (application and delegated)
            CommonPermissions = @{}  # For backward compatibility
            Configuration = @{
                IncludeMicrosoftGraph = $IncludeMicrosoftGraph.IsPresent
                IncludeCustomApis = $IncludeCustomApis.IsPresent
            }
        }

        # If the file exists, load it to preserve existing data
        if (Test-Path -Path $OutputPath) {
            try {
                $existingConfig = Get-Content -Path $OutputPath -Raw | ConvertFrom-Json -AsHashtable

                # Merge existing data if available
                if ($existingConfig.ServicePrincipals) {
                    $knownServicesConfig.ServicePrincipals = $existingConfig.ServicePrincipals
                }
                if ($existingConfig.CommonPermissions) {
                    $knownServicesConfig.CommonPermissions = $existingConfig.CommonPermissions
                }
                if ($existingConfig.Configuration) {
                    # Keep existing configuration but update specific settings
                    $knownServicesConfig.Configuration = $existingConfig.Configuration
                    $knownServicesConfig.Configuration.IncludeMicrosoftGraph = $IncludeMicrosoftGraph.IsPresent
                    $knownServicesConfig.Configuration.IncludeCustomApis = $IncludeCustomApis.IsPresent
                }
                if ($existingConfig.Metadata) {
                    # Keep the refresh interval from existing config if not explicitly specified
                    if (-not $PSBoundParameters.ContainsKey('RefreshIntervalDays') -and $existingConfig.Metadata.RefreshIntervalDays) {
                        $knownServicesConfig.Metadata.RefreshIntervalDays = $existingConfig.Metadata.RefreshIntervalDays
                    }
                    # Keep the auto-refresh setting
                    if ($existingConfig.Metadata.AutoRefreshEnabled -is [bool]) {
                        $knownServicesConfig.Metadata.AutoRefreshEnabled = $existingConfig.Metadata.AutoRefreshEnabled
                    }
                }

                Write-Verbose "Loaded existing KnownServices configuration"
            }
            catch {
                Write-Warning "Failed to load existing KnownServices configuration: $_"
            }
        }
    }

    process {
        try {
            Write-Host "Fetching service principals from Microsoft Graph API..." -ForegroundColor Cyan
            
            # Initialize counters
            $totalServicePrincipals = 0
            $totalPermissions = 0
            $processedServicePrincipals = 0
            
            # Build filter - keep it simple due to Graph API limitations
            $filter = "servicePrincipalType eq 'Application'"
            
            # Query for service principals - use paging because there could be many
            $serviceprincipals = @()
            $uri = "/v1.0/servicePrincipals?`$filter=$filter&`$select=id,appId,displayName,appRoles,publisherName,oauth2PermissionScopes&`$top=100"
            
            do {
                $response = Invoke-MgGraphRequest -Uri $uri -Method Get
                if ($response.value) {
                    $serviceprincipals += $response.value
                    $totalServicePrincipals += $response.value.Count
                }
                $uri = $response.'@odata.nextLink'
            } while ($uri)
            
            Write-Host "Found $totalServicePrincipals service principals" -ForegroundColor Green
            
            # Process each service principal
            foreach ($servicePrincipal in $serviceprincipals) {
                $processedServicePrincipals++
                Write-Progress -Activity "Processing service principals" -Status "$processedServicePrincipals of $totalServicePrincipals" -PercentComplete (($processedServicePrincipals / $totalServicePrincipals) * 100)
                
                # Initialize counters for this service principal
                $appRoleCount = 0
                $delegatedPermissionCount = 0
                
                # Handle Microsoft Graph permissions properly
                if ($servicePrincipal.appId -eq "00000003-0000-0000-c000-000000000000") {
                    # Only skip Microsoft Graph if explicitly not requested
                    if (-not $IncludeMicrosoftGraph) {
                        Write-Verbose "Skipping Microsoft Graph permissions as requested"
                        continue
                    }
                    else {
                        Write-Verbose "Including Microsoft Graph permissions as requested"
                    }
                }
                
                # Filter out non-Microsoft APIs if requested
                if (-not $IncludeCustomApis -and -not ($servicePrincipal.appId -like "0000*") -and -not ($servicePrincipal.publisherName -like "*Microsoft*")) {
                    continue
                }
                
                # Generate service principal key
                $spKey = $servicePrincipal.displayName -replace '[^\w\d]', ''
                if ($spKey -eq '') {
                    $spKey = "SP_$($servicePrincipal.id)"
                }
                
                # Add service principal to our configuration
                $knownServicesConfig.ServicePrincipals[$spKey] = @{
                    AppId = $servicePrincipal.appId
                    DisplayName = $servicePrincipal.displayName
                    Description = if ($servicePrincipal.publisherName) { "API published by $($servicePrincipal.publisherName)" } else { "API with ID $($servicePrincipal.appId)" }
                    ServicePrincipalId = $servicePrincipal.id
                    Publisher = $servicePrincipal.publisherName
                }
                
                # Initialize the permissions structure for this service principal if needed
                if (-not $knownServicesConfig.ContainsKey("Permissions")) {
                    $knownServicesConfig.Permissions = @{}
                }
                
                # Initialize the permissions for this service principal
                $knownServicesConfig.Permissions[$spKey] = @{
                    "Application" = @{}
                    "Delegated" = @{}
                }
                
                # Process application permissions (appRoles)
                if ($servicePrincipal.appRoles -and $servicePrincipal.appRoles.Count -gt 0) {
                    foreach ($appRole in $servicePrincipal.appRoles) {
                        if ($appRole.isEnabled) {
                            # Store detailed permission info for app roles
                            try {
                                $appRoleName = $appRole.value
                                if ([string]::IsNullOrEmpty($appRoleName)) {
                                    # Handle empty role names by using ID instead
                                    $appRoleName = "role_$($appRole.id)"
                                }
                                
                                $knownServicesConfig.Permissions[$spKey]["Application"][$appRoleName] = @{
                                    Id = $appRole.id
                                    DisplayName = $appRole.displayName
                                    Description = $appRole.description
                                    AllowedMemberTypes = $appRole.allowedMemberTypes
                                }
                                
                                # Add to simple CommonPermissions for backwards compatibility
                                if (-not $knownServicesConfig.CommonPermissions.ContainsKey($spKey)) {
                                    $knownServicesConfig.CommonPermissions[$spKey] = @()
                                }
                                $knownServicesConfig.CommonPermissions[$spKey] += $appRoleName
                            }
                            catch {
                                Write-Verbose "Failed to add app role $($appRole.value) to permissions: $_"
                            }
                            
                            $appRoleCount++
                            $totalPermissions++
                        }
                    }
                }
                
                # Process delegated permissions (oauth2PermissionScopes)
                if ($servicePrincipal.oauth2PermissionScopes -and $servicePrincipal.oauth2PermissionScopes.Count -gt 0) {
                    foreach ($scope in $servicePrincipal.oauth2PermissionScopes) {
                        if ($scope.isEnabled) {
                            # Store detailed permission info for delegated permissions
                            try {
                                $scopeName = $scope.value
                                if ([string]::IsNullOrEmpty($scopeName)) {
                                    # Handle empty scope names by using ID instead
                                    $scopeName = "scope_$($scope.id)"
                                }
                                
                                $knownServicesConfig.Permissions[$spKey]["Delegated"][$scopeName] = @{
                                    Id = $scope.id
                                    DisplayName = $scope.adminConsentDisplayName
                                    Description = $scope.adminConsentDescription
                                    UserConsentDisplayName = $scope.userConsentDisplayName
                                    UserConsentDescription = $scope.userConsentDescription
                                    Type = $scope.type
                                }
                                
                                # Don't add delegated scopes to CommonPermissions to avoid confusion
                            }
                            catch {
                                Write-Verbose "Failed to add delegated permission $($scope.value) to permissions: $_"
                            }
                            
                            $delegatedPermissionCount++
                            $totalPermissions++
                        }
                    }
                }
                
                # If no permissions were found for this service principal, remove it from the permissions collection
                if ($appRoleCount -eq 0 -and $delegatedPermissionCount -eq 0) {
                    if ($knownServicesConfig.Permissions.ContainsKey($spKey)) {
                        $knownServicesConfig.Permissions.Remove($spKey)
                    }
                }
                else {
                    Write-Verbose "Found $appRoleCount application and $delegatedPermissionCount delegated permissions for $($servicePrincipal.displayName)"
                }
            }
            
            Write-Progress -Activity "Processing service principals" -Completed
            
            # Calculate permission stats
            $appPermissionCount = 0
            $delegatedPermissionCount = 0
            $servicePrincipalsWithPermissions = 0
            
            if ($knownServicesConfig.Permissions) {
                foreach ($key in $knownServicesConfig.Permissions.Keys) {
                    try {
                        $spPerms = $knownServicesConfig.Permissions[$key]
                        
                        $appCount = if ($spPerms.Application) { $spPerms.Application.Count } else { 0 }
                        $delegatedCount = if ($spPerms.Delegated) { $spPerms.Delegated.Count } else { 0 }
                        
                        if ($appCount -gt 0 -or $delegatedCount -gt 0) {
                            $servicePrincipalsWithPermissions++
                            $appPermissionCount += $appCount
                            $delegatedPermissionCount += $delegatedCount
                        }
                    }
                    catch {
                        Write-Verbose "Error calculating stats for $key`: $_"
                    }
                }
            }
            
            $totalPermissionCount = $appPermissionCount + $delegatedPermissionCount
            
            Write-Host "Service Principal Statistics" -ForegroundColor Cyan
            Write-Host "  Total service principals found: $totalServicePrincipals" -ForegroundColor Green
            Write-Host "  Service principals with permissions: $servicePrincipalsWithPermissions" -ForegroundColor Green
            Write-Host "Permission Statistics" -ForegroundColor Cyan  
            Write-Host "  Application permissions: $appPermissionCount" -ForegroundColor Green
            Write-Host "  Delegated permissions: $delegatedPermissionCount" -ForegroundColor Green
            Write-Host "  Total permissions: $totalPermissionCount" -ForegroundColor Green
            
            # Save the updated configuration
            $outputFolder = Split-Path -Path $OutputPath -Parent
            if (-not (Test-Path -Path $outputFolder)) {
                New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
            }
            
            $knownServicesJson = ConvertTo-Json -InputObject $knownServicesConfig -Depth 6
            $knownServicesJson | Out-File -FilePath $OutputPath -Force
            
            Write-Host "KnownServices configuration updated successfully at $OutputPath" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to update KnownServices configuration: $_"
            return $false
        }
    }
}
