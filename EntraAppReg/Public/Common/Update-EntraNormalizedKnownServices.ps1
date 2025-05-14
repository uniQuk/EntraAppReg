<#
.SYNOPSIS
    Updates the normalized KnownServices configuration with the latest service principals and permissions from the tenant.

.DESCRIPTION
    The Update-EntraNormalizedKnownServices function queries the Microsoft Graph API to get the latest 
    service principals and their permissions from the tenant. It then updates the normalized 
    KnownServices configuration files with this information. 
    
    The function uses a normalized storage format that splits data across multiple files:
    - KnownServicesIndex.json: Contains metadata and file references
    - ServicePrincipals.json: Basic info about service principals
    - PermissionDefinitions.json: Unique definitions of all permissions
    - ServicePermissionMappings.json: Maps services to permissions
    - CommonPermissions.json: Legacy format for backward compatibility
    
    This approach significantly reduces storage requirements by eliminating duplication
    of permission definitions across multiple service principals.

.PARAMETER ConfigPath
    The path where the configuration files will be created or updated. If not specified, the default
    configuration path will be used.

.PARAMETER Force
    Forces an update even if the structure does not exist or files are not outdated.

.PARAMETER IncludeMicrosoftGraph
    Includes Microsoft Graph permissions in the update. This can add a significant number of permissions.
    Microsoft Graph has hundreds of permissions, so including it can make the configuration files larger.

.PARAMETER IncludeCustomApis
    Includes custom APIs (those created within the tenant) in the update.
    These are APIs that are not published by Microsoft.

.PARAMETER RefreshIntervalDays
    The number of days after which the KnownServices configuration should be considered outdated.
    Default is 30 days.

.PARAMETER UpdateLegacyFormat
    When specified, also updates the legacy KnownServices.json file for backward compatibility.

.EXAMPLE
    Update-EntraNormalizedKnownServices
    Updates the normalized KnownServices configuration if it is outdated.

.EXAMPLE
    Update-EntraNormalizedKnownServices -Force
    Updates the normalized KnownServices configuration regardless of its age.

.EXAMPLE
    Update-EntraNormalizedKnownServices -IncludeMicrosoftGraph -IncludeCustomApis
    Updates the normalized KnownServices configuration with all available APIs and permissions.

.NOTES
    This function requires an active connection to the Microsoft Graph API with sufficient permissions.
    Use Connect-EntraGraphSession before calling this function.
#>
function Update-EntraNormalizedKnownServices {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMicrosoftGraph,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeCustomApis,

        [Parameter(Mandatory = $false)]
        [int]$RefreshIntervalDays = 30,
        
        [Parameter(Mandatory = $false)]
        [switch]$UpdateLegacyFormat
    )

    begin {
        Write-Verbose "Checking if normalized KnownServices configuration needs updating..."

        # Ensure we have an active Graph connection
        if (-not (Test-EntraGraphConnection)) {
            Write-Error "No active Microsoft Graph connection. Please connect using Connect-EntraGraphSession first."
            return $false
        }
        
        # Set module paths if not already set
        if (-not $script:ModuleRootPath) {
            $script:ModuleRootPath = Get-EntraModuleRoot
            Write-Verbose "Module root path set to: $script:ModuleRootPath"
            
            $script:ConfigPath = Join-Path -Path $script:ModuleRootPath -ChildPath "Config"
            Write-Verbose "Default config path set to: $script:ConfigPath"
        }
        
        # Use default ConfigPath if not provided
        if (-not $ConfigPath) {
            $ConfigPath = $script:ConfigPath
            Write-Verbose "Using default config path: $ConfigPath"
        }
        
        # Ensure ConfigPath exists
        if (-not (Test-Path -Path $ConfigPath -PathType Container)) {
            try {
                New-Item -Path $ConfigPath -ItemType Directory -Force | Out-Null
                Write-Verbose "Created config directory: $ConfigPath"
            }
            catch {
                Write-Error "Failed to create config directory at $ConfigPath`: $_"
                return $false
            }
        }
        
        # Define file paths
        $indexPath = Join-Path -Path $ConfigPath -ChildPath "KnownServicesIndex.json"
        $legacyPath = Join-Path -Path $ConfigPath -ChildPath "KnownServices.json"
        
        # Check if normalized structure exists, create it if it doesn't
        if (-not (Test-Path -Path $indexPath) -or $Force) {
            if (-not (New-EntraKnownServicesStructure -ConfigPath $ConfigPath -Force:$Force)) {
                Write-Error "Failed to create normalized KnownServices structure."
                return $false
            }
        }
        
        # Get the index
        try {
            $index = Get-Content -Path $indexPath -Raw | ConvertFrom-Json
            
            # Check if file is outdated
            $lastUpdated = $null
            if ([DateTime]::TryParse($index.Metadata.LastUpdated, [ref]$lastUpdated)) {
                $daysSinceUpdate = ([DateTime]::UtcNow - $lastUpdated).Days
                $refreshInterval = if ($index.Metadata.RefreshIntervalDays -gt 0) { $index.Metadata.RefreshIntervalDays } else { $RefreshIntervalDays }
                
                if ($daysSinceUpdate -lt $refreshInterval -and -not $Force) {
                    Write-Verbose "Normalized KnownServices configuration is up to date (last updated $daysSinceUpdate days ago, threshold is $refreshInterval days)"
                    return $true
                }
            }
        }
        catch {
            Write-Warning "Failed to read KnownServicesIndex: $_"
            # Continue anyway since we're updating
        }
        
        # Clear the cache
        Clear-EntraKnownServicesCache
    }

    process {
        try {
            Write-Host "Fetching service principals from Microsoft Graph API..." -ForegroundColor Cyan
            
            # Initialize counters
            $totalServicePrincipals = 0
            $totalPermissions = 0
            $appPermissionCount = 0
            $delegatedPermissionCount = 0
            $servicePrincipalsWithPermissions = 0
            $processedServicePrincipals = 0
            
            # Initialize data structures
            $servicePrincipals = @{}
            $permissionDefinitions = @{
                Application = @{}
                Delegated = @{}
            }
            $servicePermissionMappings = @{}
            $commonPermissions = @{}
            
            # Build filter - keep it simple due to Graph API limitations
            $filter = "servicePrincipalType eq 'Application'"
            
            # Query for service principals - use paging because there could be many
            $graphServicePrincipals = @()
            $uri = "/v1.0/servicePrincipals?`$filter=$filter&`$select=id,appId,displayName,appRoles,publisherName,oauth2PermissionScopes&`$top=100"
            
            do {
                $response = Invoke-MgGraphRequest -Uri $uri -Method Get
                if ($response.value) {
                    $graphServicePrincipals += $response.value
                    $totalServicePrincipals += $response.value.Count
                }
                $uri = $response.'@odata.nextLink'
            } while ($uri)
            
            Write-Host "Found $totalServicePrincipals service principals" -ForegroundColor Green
            
            # Process each service principal
            foreach ($servicePrincipal in $graphServicePrincipals) {
                $processedServicePrincipals++
                Write-Progress -Activity "Processing service principals" -Status "$processedServicePrincipals of $totalServicePrincipals" -PercentComplete (($processedServicePrincipals / $totalServicePrincipals) * 100)
                
                # Handle Microsoft Graph permissions
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
                
                # Generate service principal key (normalized name)
                $spKey = $servicePrincipal.displayName -replace '[^\w\d]', ''
                if ([string]::IsNullOrEmpty($spKey)) {
                    $spKey = "SP_$($servicePrincipal.id)"
                }
                
                # Add service principal to our configuration
                $servicePrincipals[$spKey] = @{
                    AppId = $servicePrincipal.appId
                    DisplayName = $servicePrincipal.displayName
                    Description = if ($servicePrincipal.publisherName) { "API published by $($servicePrincipal.publisherName)" } else { "API with ID $($servicePrincipal.appId)" }
                    ServicePrincipalId = $servicePrincipal.id
                    Publisher = $servicePrincipal.publisherName
                }
                
                # Initialize service permission mappings for this service principal
                $servicePermissionMappings[$spKey] = @{
                    Application = @()
                    Delegated = @()
                }
                
                # Initialize legacy common permissions for this service principal
                $commonPermissions[$spKey] = @()
                
                # Track if this service principal has any permissions
                $hasPermissions = $false
                $spAppPermissionCount = 0
                $spDelegatedPermissionCount = 0
                
                # Process application permissions (appRoles)
                if ($servicePrincipal.appRoles -and $servicePrincipal.appRoles.Count -gt 0) {
                    foreach ($appRole in $servicePrincipal.appRoles) {
                        if ($appRole.isEnabled) {
                            # Get or create a unique permission key
                            $permKey = $appRole.value
                            if ([string]::IsNullOrEmpty($permKey)) {
                                # Handle empty permission names by using ID instead
                                $permKey = "role_$($appRole.id)"
                            }
                            
                            # Add to permission definitions if it doesn't exist
                            if (-not $permissionDefinitions.Application.ContainsKey($permKey)) {
                                $permissionDefinitions.Application[$permKey] = @{
                                    Id = $appRole.id
                                    DisplayName = $appRole.displayName
                                    Description = $appRole.description
                                    AllowedMemberTypes = $appRole.allowedMemberTypes
                                }
                            }
                            
                            # Add to service permission mappings
                            if (-not $servicePermissionMappings[$spKey].Application.Contains($permKey)) {
                                $servicePermissionMappings[$spKey].Application += $permKey
                            }
                            
                            # Add to legacy common permissions
                            if (-not $commonPermissions[$spKey].Contains($permKey)) {
                                $commonPermissions[$spKey] += $permKey
                            }
                            
                            $hasPermissions = $true
                            $spAppPermissionCount++
                            $appPermissionCount++
                            $totalPermissions++
                        }
                    }
                }
                
                # Process delegated permissions (oauth2PermissionScopes)
                if ($servicePrincipal.oauth2PermissionScopes -and $servicePrincipal.oauth2PermissionScopes.Count -gt 0) {
                    foreach ($scope in $servicePrincipal.oauth2PermissionScopes) {
                        if ($scope.isEnabled) {
                            # Get or create a unique permission key
                            $permKey = $scope.value
                            if ([string]::IsNullOrEmpty($permKey)) {
                                # Handle empty permission names by using ID instead
                                $permKey = "scope_$($scope.id)"
                            }
                            
                            # Add to permission definitions if it doesn't exist
                            if (-not $permissionDefinitions.Delegated.ContainsKey($permKey)) {
                                $permissionDefinitions.Delegated[$permKey] = @{
                                    Id = $scope.id
                                    DisplayName = $scope.adminConsentDisplayName
                                    Description = $scope.adminConsentDescription
                                    UserConsentDisplayName = $scope.userConsentDisplayName
                                    UserConsentDescription = $scope.userConsentDescription
                                    Type = $scope.type
                                }
                            }
                            
                            # Add to service permission mappings
                            if (-not $servicePermissionMappings[$spKey].Delegated.Contains($permKey)) {
                                $servicePermissionMappings[$spKey].Delegated += $permKey
                            }
                            
                            # Don't add delegated permissions to CommonPermissions for backward compatibility
                            
                            $hasPermissions = $true
                            $spDelegatedPermissionCount++
                            $delegatedPermissionCount++
                            $totalPermissions++
                        }
                    }
                }
                
                # Update count of service principals with permissions
                if ($hasPermissions) {
                    $servicePrincipalsWithPermissions++
                    Write-Verbose "Found $spAppPermissionCount application and $spDelegatedPermissionCount delegated permissions for $($servicePrincipal.displayName)"
                }
                else {
                    # Remove empty entries
                    $servicePermissionMappings.Remove($spKey)
                    $commonPermissions.Remove($spKey)
                }
            }
            
            Write-Progress -Activity "Processing service principals" -Completed
            
            # Update the index metadata
            $index = @{
                Metadata = @{
                    LastUpdated = [DateTime]::UtcNow.ToString("o")
                    RefreshIntervalDays = $RefreshIntervalDays
                    AutoRefreshEnabled = $true
                    Version = "3.0"
                }
                Configuration = @{
                    IncludeMicrosoftGraph = $IncludeMicrosoftGraph.IsPresent
                    IncludeCustomApis = $IncludeCustomApis.IsPresent
                }
                Files = @{
                    ServicePrincipals = "ServicePrincipals.json"
                    PermissionDefinitions = "PermissionDefinitions.json"
                    ServicePermissionMappings = "ServicePermissionMappings.json"
                    LegacyCommonPermissions = "CommonPermissions.json"
                }
            }
            
            # Display statistics
            Write-Host "Service Principal Statistics" -ForegroundColor Cyan
            Write-Host "  Total service principals found: $totalServicePrincipals" -ForegroundColor Green
            Write-Host "  Service principals with permissions: $servicePrincipalsWithPermissions" -ForegroundColor Green
            Write-Host "Permission Statistics" -ForegroundColor Cyan  
            Write-Host "  Application permissions: $appPermissionCount" -ForegroundColor Green
            Write-Host "  Delegated permissions: $delegatedPermissionCount" -ForegroundColor Green
            Write-Host "  Total permissions: $totalPermissions" -ForegroundColor Green
            Write-Host "  Unique application permissions: $($permissionDefinitions.Application.Count)" -ForegroundColor Green
            Write-Host "  Unique delegated permissions: $($permissionDefinitions.Delegated.Count)" -ForegroundColor Green
            Write-Host "  Total unique permissions: $($permissionDefinitions.Application.Count + $permissionDefinitions.Delegated.Count)" -ForegroundColor Green
            
            # Save all files
            $indexPath = Join-Path -Path $ConfigPath -ChildPath "KnownServicesIndex.json"
            $servicePrincipalsPath = Join-Path -Path $ConfigPath -ChildPath $index.Files.ServicePrincipals
            $permissionDefinitionsPath = Join-Path -Path $ConfigPath -ChildPath $index.Files.PermissionDefinitions
            $servicePermissionMappingsPath = Join-Path -Path $ConfigPath -ChildPath $index.Files.ServicePermissionMappings
            $commonPermissionsPath = Join-Path -Path $ConfigPath -ChildPath $index.Files.LegacyCommonPermissions
            
            ConvertTo-Json -InputObject $index -Depth 4 | Out-File -FilePath $indexPath -Force
            ConvertTo-Json -InputObject $servicePrincipals -Depth 4 | Out-File -FilePath $servicePrincipalsPath -Force
            ConvertTo-Json -InputObject $permissionDefinitions -Depth 6 | Out-File -FilePath $permissionDefinitionsPath -Force
            ConvertTo-Json -InputObject $servicePermissionMappings -Depth 4 | Out-File -FilePath $servicePermissionMappingsPath -Force
            ConvertTo-Json -InputObject $commonPermissions -Depth 4 | Out-File -FilePath $commonPermissionsPath -Force
            
            Write-Host "Normalized KnownServices configuration updated successfully at $ConfigPath" -ForegroundColor Green
            
            # Update the legacy format if requested
            if ($UpdateLegacyFormat) {
                Write-Verbose "Updating legacy KnownServices.json for backward compatibility"
                
                # Create the legacy structure
                $legacyConfig = @{
                    Metadata = $index.Metadata
                    Configuration = $index.Configuration
                    ServicePrincipals = $servicePrincipals
                    CommonPermissions = $commonPermissions
                    Permissions = @{}
                }
                
                # Build the legacy Permissions section
                foreach ($spKey in $servicePermissionMappings.Keys) {
                    $legacyConfig.Permissions[$spKey] = @{
                        Application = @{}
                        Delegated = @{}
                    }
                    
                    # Add application permissions
                    foreach ($permKey in $servicePermissionMappings[$spKey].Application) {
                        if ($permissionDefinitions.Application.ContainsKey($permKey)) {
                            $legacyConfig.Permissions[$spKey].Application[$permKey] = $permissionDefinitions.Application[$permKey]
                        }
                    }
                    
                    # Add delegated permissions
                    foreach ($permKey in $servicePermissionMappings[$spKey].Delegated) {
                        if ($permissionDefinitions.Delegated.ContainsKey($permKey)) {
                            $legacyConfig.Permissions[$spKey].Delegated[$permKey] = $permissionDefinitions.Delegated[$permKey]
                        }
                    }
                }
                
                # Save the legacy file
                ConvertTo-Json -InputObject $legacyConfig -Depth 6 | Out-File -FilePath $legacyPath -Force
                Write-Host "Legacy KnownServices.json updated successfully at $legacyPath" -ForegroundColor Green
            }
            
            # Clear the cache to force reload
            Clear-EntraKnownServicesCache
            
            return $true
        }
        catch {
            Write-Error "Failed to update normalized KnownServices configuration: $_"
            return $false
        }
    }
}
