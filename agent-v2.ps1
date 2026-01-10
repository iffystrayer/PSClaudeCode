# agent-v2.ps1 - Agent with structured tools
# agent-v2.ps1 "Create a new file called 'test.txt' with the content 'Hello, World!', then read it back and display the contents."
param(
    [string]$Task
)

$apiKey = $env:OPENAI_API_KEY
if (-not $apiKey) { Write-Host "Set OPENAI_API_KEY"; exit }

$tools = @(
    @{
        type     = "function"
        function = @{
            name        = "Read-File"
            description = "Read the contents of a file"
            parameters  = @{
                type       = "object"
                properties = @{
                    path = @{ type = "string"; description = "Path to the file" }
                }
                required   = @("path")
            }
        }
    }
    @{
        type     = "function"
        function = @{
            name        = "Write-File"
            description = "Write content to a file"
            parameters  = @{
                type       = "object"
                properties = @{
                    path    = @{ type = "string"; description = "Path to the file" }
                    content = @{ type = "string"; description = "Content to write" }
                }
                required   = @("path", "content")
            }
        }
    }
    @{
        type     = "function"
        function = @{
            name        = "Run-Command"
            description = "Run a PowerShell command"
            parameters  = @{
                type       = "object"
                properties = @{
                    command = @{ type = "string"; description = "The command to run" }
                }
                required   = @("command")
            }
        }
    }
)

function Execute-Tool {
    param([string]$Name, $ToolInput)
    
    switch ($Name) {
        "Read-File" {
            try {
                $content = Get-Content $ToolInput.path -Raw
                return "Contents of $($ToolInput.path):`n$content"
            }
            catch {
                return "Error: $_"
            }
        }
        "Write-File" {
            try {
                Set-Content $ToolInput.path $ToolInput.content
                return "Successfully wrote to $($ToolInput.path)"
            }
            catch {
                return "Error: $_"
            }
        }
        "Run-Command" {
            try {
                $output = Invoke-Expression $ToolInput.command 2>&1 | Out-String
                return "`$ $($ToolInput.command)`n$output"
            }
            catch {
                return "Error: $_"
            }
        }
        default { return "Unknown tool: $Name" }
    }
}

function Check-Permission {
    param([string]$ToolName, $ToolInput)
    
    if ($ToolName -eq "Run-Command") {
        $cmd = $ToolInput.command
        if ($cmd -match "rm|del|Remove-Item|rmdir|rd|Set-Content.*>.*|.*\|.*iex") {
            Write-Host "⚠️ Potentially dangerous command: $cmd"
            $response = Read-Host "Allow? (y/n)"
            return $response -eq "y"
        }
    }
    elseif ($ToolName -eq "Write-File") {
        Write-Host "📝 Will write to: $($ToolInput.path)"
        $response = Read-Host "Allow? (y/n)"
        return $response -eq "y"
    }
    return $true
}

$messages = @(@{ role = "user"; content = $Task })

while ($true) {
    $body = @{
        model       = "gpt-4.1"
        messages    = $messages
        max_tokens  = 4096
        tools       = $tools
        tool_choice = "auto"
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type"  = "application/json"
    } -Body $body

    $message = $response.choices[0].message
    $messages += $message

    if ($message.tool_calls) {
        $toolResults = @()
        foreach ($toolCall in $message.tool_calls) {
            $toolName = $toolCall.function.name
            $toolInput = $toolCall.function.arguments | ConvertFrom-Json
            
            Write-Host "🔧 $toolName`: $($toolInput | ConvertTo-Json -Compress)"
            
            if (Check-Permission $toolName $toolInput) {
                $result = Execute-Tool $toolName $toolInput
                Write-Host "   → $($result.Substring(0, [Math]::Min(200, $result.Length)))..."
            }
            else {
                $result = "Permission denied by user"
                Write-Host "   🚫 $result"
            }
            
            $toolResults += @{
                tool_call_id = $toolCall.id
                role         = "tool"
                content      = $result
            }
        }
        $messages += $toolResults
    }
    else {
        Write-Host "✅ $($message.content)"
        break
    }
}