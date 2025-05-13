Describe "App Registration Functions" {
    BeforeAll {
        # Mock the Test-EntraGraphConnection function to return true
        Mock Test-EntraGraphConnection { return $true }
        # Mock Invoke-EntraGraphRequest
        Mock Invoke-EntraGraphRequest {
            param($Uri, $Method, $Body)
            
            if ($Uri -eq "https://graph.microsoft.com/v1.0/applications" -and $Method -eq "POST") {
                return @{
                    id = "mock-object-id"
                    appId = "mock-app-id"
                    displayName = $Body.displayName
                    signInAudience = $Body.signInAudience
                    notes = $Body.notes
                }
            }
            elseif ($Uri -like "https://graph.microsoft.com/v1.0/applications/mock-object-id*" -and $Method -eq "GET") {
                return @{
                    id = "mock-object-id"
                    appId = "mock-app-id"
                    displayName = "Test App"
                    signInAudience = "AzureADMyOrg"
                    notes = "Test notes"
                }
            }
            elseif ($Uri -like "https://graph.microsoft.com/v1.0/applications?`$filter=appId*" -and $Method -eq "GET") {
                return @{
                    value = @(
                        @{
                            id = "mock-object-id"
                            appId = "mock-app-id"
                            displayName = "Test App"
                        }
                    )
                }
            }
            elseif ($Uri -like "https://graph.microsoft.com/v1.0/applications?`$filter=displayName*" -and $Method -eq "GET") {
                return @{
                    value = @(
                        @{
                            id = "mock-object-id"
                            appId = "mock-app-id"
                            displayName = "Test App"
                        }
                    )
                }
            }
            elseif ($Uri -eq "https://graph.microsoft.com/v1.0/applications" -and $Method -eq "GET") {
                return @{
                    value = @(
                        @{
                            id = "mock-object-id-1"
                            appId = "mock-app-id-1"
                            displayName = "Test App 1"
                        },
                        @{
                            id = "mock-object-id-2"
                            appId = "mock-app-id-2"
                            displayName = "Test App 2"
                        }
                    )
                }
            }
            elseif ($Uri -like "https://graph.microsoft.com/v1.0/applications/mock-object-id*" -and $Method -eq "DELETE") {
                return $null
            }
            else {
                throw "Unexpected call to Invoke-EntraGraphRequest with Uri: $Uri, Method: $Method"
            }
        }

        # Mock Get-EntraServicePrincipalByAppId
        Mock Get-EntraServicePrincipalByAppId {
            return @{
                appId = "00000003-0000-0000-c000-000000000000"
                displayName = "Microsoft Graph"
                appRoles = @(
                    @{
                        id = "mock-role-id-1"
                        value = "User.Read.All"
                        displayName = "Read all users"
                    },
                    @{
                        id = "mock-role-id-2"
                        value = "Directory.Read.All"
                        displayName = "Read directory data"
                    }
                )
            }
        }

        # Mock Get-EntraServicePrincipalByName
        Mock Get-EntraServicePrincipalByName {
            return @{
                appId = "00000012-0000-0000-c000-000000000000"
                displayName = "Azure Rights Management Services"
                appRoles = @(
                    @{
                        id = "mock-rms-role-id"
                        value = "Content.SuperUser"
                        displayName = "Super User"
                    }
                )
            }
        }
    }

    Context "New-EntraAppRegistration" {
        It "Creates a basic app registration" {
            $result = New-EntraAppRegistration -DisplayName "Test App"
            $result | Should -Not -BeNullOrEmpty
            $result.displayName | Should -Be "Test App"
            $result.id | Should -Be "mock-object-id"
            $result.appId | Should -Be "mock-app-id"
        }

        It "Creates an app registration with notes" {
            $result = New-EntraAppRegistration -DisplayName "Test App" -Notes "Test notes"
            $result | Should -Not -BeNullOrEmpty
            $result.notes | Should -Be "Test notes"
        }

        It "Creates an app registration with Graph permissions" {
            # This test verifies that the permission setup logic works
            $result = New-EntraAppRegistration -DisplayName "Test App" -GraphPermissions @("User.Read.All", "Directory.Read.All")
            
            # We should have attempted to get the Microsoft Graph service principal
            Should -Invoke Get-EntraServicePrincipalByAppId -ParameterFilter {
                $AppId -eq "00000003-0000-0000-c000-000000000000"
            }
        }
    }

    Context "Get-EntraAppRegistration" {
        It "Gets an app registration by ObjectId" {
            $result = Get-EntraAppRegistration -ObjectId "mock-object-id"
            $result | Should -Not -BeNullOrEmpty
            $result.id | Should -Be "mock-object-id"
            $result.displayName | Should -Be "Test App"
        }

        It "Gets an app registration by AppId" {
            $result = Get-EntraAppRegistration -AppId "mock-app-id"
            $result | Should -Not -BeNullOrEmpty
            $result.appId | Should -Be "mock-app-id"
        }

        It "Gets app registrations by DisplayName" {
            $result = Get-EntraAppRegistration -DisplayName "Test"
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterOrEqual 1
        }

        It "Gets all app registrations" {
            $result = Get-EntraAppRegistration
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }
    }

    Context "Remove-EntraAppRegistration" {
        It "Removes an app registration by ObjectId" {
            # Use -Force to bypass confirmation
            $result = Remove-EntraAppRegistration -ObjectId "mock-object-id" -Force
            Should -Invoke Invoke-EntraGraphRequest -ParameterFilter {
                $Uri -like "*/applications/mock-object-id" -and $Method -eq "DELETE"
            }
        }

        It "Returns the removed app when -PassThru is specified" {
            $result = Remove-EntraAppRegistration -ObjectId "mock-object-id" -Force -PassThru
            $result | Should -Not -BeNullOrEmpty
            $result.id | Should -Be "mock-object-id"
        }

        It "Fails when no connection is available" {
            Mock Test-EntraGraphConnection { return $false }
            { Remove-EntraAppRegistration -ObjectId "mock-object-id" -Force } | Should -Throw
        }
    }
}
