# Entra App Registration PowerShell Module Implementation Plan

## Overview

This document outlines the implementation plan for creating a new PowerShell module named `EntraAppReg`. The module will provide a comprehensive set of tools for managing app registrations in Microsoft Entra ID (formerly Azure AD), focusing on creating applications, managing credentials, and monitoring credential expiration.

## Module Structure

```
EntraAppReg/
│
├── EntraAppReg.psd1           # Module manifest
├── EntraAppReg.psm1           # Module script file
│
├── Public/                    # Public functions (exported)
│   ├── AppRegistration/       # App registration management functions
│   ├── Credentials/           # Credential management functions
│   ├── Monitoring/            # Monitoring functions
│   └── Permissions/           # Permission management functions
│
├── Private/                   # Private functions (internal use)
│   ├── Authentication/        # Authentication helper functions
│   │   ├── Connect-EntraGraphSession.ps1
│   │   ├── Disconnect-EntraGraphSession.ps1
│   │   └── Test-EntraGraphConnection.ps1
│   ├── Common/                # Common utility functions
│   │   ├── Update-EntraKnownServices.ps1
│   │   ├── Test-EntraKnownServicesAge.ps1
│   │   ├── New-EntraAppOutputFolder.ps1
│   │   └── Write-EntraLog.ps1
│   ├── ServicePrincipals/     # Service principal helper functions
│   └── Validation/            # Input validation functions
│
├── Config/                    # Configuration files
│   └── KnownServices.json     # Known service principals and their well-known App IDs with refresh metadata
│
├── en-US/                     # Localization and help files
│   └── about_EntraAppReg.help.txt
│
└── Tests/                     # Pester tests
    ├── Unit/                  # Unit tests
    └── Integration/           # Integration tests
```

## Function List

### Public Functions

#### AppRegistration

1. `New-EntraAppRegistration` - Create a new app registration with custom API permissions
2. `Get-EntraAppRegistration` - Get app registration details
3. `Remove-EntraAppRegistration` - Delete an app registration
4. `Set-EntraAppRegistration` - Update an app registration's properties
5. `New-EntraAppRegistrationBatch` - Create multiple app registrations at once from a template or CSV

#### Credentials

1. `Add-EntraAppSecret` - Add a client secret to an app registration
2. `Add-EntraAppCertificate` - Add a self-signed certificate to an app registration
3. `Get-EntraAppCredentials` - Get all credentials for an app registration
4. `Remove-EntraAppCredential` - Remove a specific credential from an app
5. `Export-EntraAppCredentials` - Export credentials to secure files

#### Monitoring

1. `Get-EntraAppExpiringCredentials` - Get app registrations with expiring credentials
2. `Test-EntraAppCredential` - Test if a credential is valid
3. `Get-EntraAppCredentialReport` - Generate a detailed report of app registrations and their credentials

#### Permissions

1. `Add-EntraAppPermission` - Add an API permission to an app registration
2. `Remove-EntraAppPermission` - Remove an API permission from an app registration
3. `Get-EntraAppPermissions` - Get all permissions for an app registration
4. `Grant-EntraAppPermission` - Grant admin consent for an app permission

### Private Functions

#### Authentication

1. `Connect-EntraGraphSession` - Handle authentication to Microsoft Graph
2. `Disconnect-EntraGraphSession` - Handle disconnection from Microsoft Graph
3. `Test-EntraGraphConnection` - Check if there's an active Graph connection

#### Common

1. `New-EntraAppOutputFolder` - Create output folder for credentials and reports
2. `Write-EntraLog` - Write log messages with configurable verbosity
3. `Invoke-EntraGraphRequest` - Wrapper for Graph API requests with error handling

#### ServicePrincipals

1. `Get-EntraServicePrincipalByName` - Find a service principal by name
2. `Get-EntraServicePrincipalByAppId` - Find a service principal by App ID
3. `Get-EntraKnownServicePrincipal` - Get well-known service principals

#### Validation

1. `Test-EntraAppName` - Validate app registration name
2. `Test-EntraApiPermission` - Validate API permission format
3. `Test-EntraCredentialParameters` - Validate credential parameters

## Migration Strategy

1. **Phase 1: Core Functions**
   - Migrate the essential functionality from the existing scripts
   - Implement the basic app registration and credential management functions
   - Create the module structure and manifest

2. **Phase 2: Enhanced Features**
   - Add monitoring functions for credential expiration
   - Implement batch operations for creating multiple apps
   - Add credential testing functionality

3. **Phase 3: Polish and Extensions**
   - Implement detailed logging and error handling
   - Add report generation features
   - Create comprehensive help documentation

## Improvements Over Existing Scripts

1. **Modular Design**
   - Functions are organized logically and follow PowerShell best practices
   - Separation of concerns between public and private functions
   - Reusable components to avoid code duplication

2. **Enhanced Error Handling**
   - Consistent error messages and handling
   - Proper use of PowerShell error streams
   - Detailed logging for troubleshooting

3. **Expanded Functionality**
   - Support for more credential types and authentication methods
   - Built-in reporting and monitoring capabilities
   - Batch operations for efficiency

4. **Platform Compatibility**
   - Cross-platform support (Windows, macOS, Linux)
   - Alternative methods for certificate generation when openssl isn't available
   - Consistent experience across environments

5. **Testing and Validation**
   - Comprehensive Pester tests
   - Parameter validation to prevent errors
   - Mock Graph API responses for unit testing

6. **Interactive Features**
   - Progress bars for long-running operations
   - Colorized output for better readability
   - Confirmation prompts for destructive actions

7. **Integration with Microsoft Graph SDK**
   - Use of the latest Microsoft Graph PowerShell SDK
   - Support for Microsoft.Graph.Beta module for advanced features
   - Fallback to REST API when needed

## New Features

1. **Credential Management**
   - Support for managed identities
   - Support for federated credentials
   - Automated credential rotation

2. **Permission Management**
   - Permission templates for common scenarios
   - Least privilege permission recommendations
   - Comparison between requested and granted permissions

3. **Monitoring and Reporting**
   - Customizable expiration thresholds
   - Email notifications for expiring credentials
   - HTML and CSV report generation

4. **Security Features**
   - Secret storage options (Azure Key Vault, encrypted files)
   - Credential usage auditing
   - Security best practice checks

5. **Integration Options**
   - Azure Automation runbook templates
   - CI/CD pipeline integration examples
   - Scheduled task templates

## Testing Strategy

1. **Unit Tests**
   - Test each function in isolation
   - Mock external dependencies
   - Cover error conditions and edge cases

2. **Integration Tests**
   - Test with actual Graph API (using test tenant)
   - Verify end-to-end workflows
   - Test cross-platform functionality

3. **Security Testing**
   - Verify credential handling security
   - Test permission boundaries
   - Validate authentication mechanisms

## Documentation

1. **In-Module Help**
   - Comprehensive comment-based help
   - Example-driven documentation
   - Parameter descriptions and types

2. **External Documentation**
   - README.md with quickstart guide
   - Detailed wiki with advanced scenarios
   - Troubleshooting guide

3. **Example Scripts**
   - Common use case examples
   - Automation script templates
   - Integration examples

## Development Roadmap

### Phase 1 (Core Implementation)
- Set up module structure
- Implement core app registration functions
- Implement basic credential management
- Create initial tests

### Phase 2 (Feature Enhancement)
- Implement monitoring functions
- Add batch operations
- Enhance error handling and logging
- Expand test coverage

### Phase 3 (Polish and Documentation)
- Refine user experience
- Complete documentation
- Add advanced features
- Publish to PowerShell Gallery

## API Integration

We will use the `ac2_askEntra` tool to query Microsoft Graph API endpoints for accurate data about Entra (Azure AD) resources. This will allow us to:

1. Test API endpoints during development
2. Verify permissions and access requirements
3. Build more robust functionality based on actual API responses
4. Create mock responses for testing

## Conclusion

The EntraAppReg PowerShell module will provide a comprehensive solution for managing app registrations in Microsoft Entra ID. By leveraging the existing scripts as a foundation and applying proper PowerShell module design principles, we will create a robust, extensible, and user-friendly tool that addresses the needs of administrators and developers working with Entra ID applications.
