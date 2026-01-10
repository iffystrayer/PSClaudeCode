@{
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'  # Generate a unique GUID if needed
    Author            = 'Douglas Finke'
    CompanyName       = 'dfinke'
    Copyright         = '(c) 2026 Douglas Finke. All rights reserved.'
    Description       = 'A PowerShell module for building AI agents using OpenAI API, with reference implementations for tool-based interactions.'
    PowerShellVersion = '5.1'
    ModuleToProcess   = 'PSClaudeCode.psm1'
    FunctionsToExport = @('Invoke-PSClaudeCodeAgent')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('AI', 'Agent', 'OpenAI', 'PowerShell', 'Automation')
            LicenseUri   = 'https://github.com/dfinke/PSClaudeCode/blob/main/LICENSE'  # Add a LICENSE file if needed
            ProjectUri   = 'https://github.com/dfinke/PSClaudeCode'
            ReleaseNotes = 'Initial release with Invoke-PSClaudeCodeAgent cmdlet.'
        }
    }
}