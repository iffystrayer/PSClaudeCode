function Invoke-PSClaudeCodeAgent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task
    )

    $apiKey = $env:OPENAI_API_KEY
    if (-not $apiKey) {
        throw "OPENAI_API_KEY environment variable is not set. Please set it to your OpenAI API key."
    }

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

    $messages = @(@{ role = "user"; content = $Task })

    while ($true) {
        $body = @{
            model       = "gpt-4o"
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
                
                $allowed = $true
                if ($toolName -eq "Run-Command") {
                    $cmd = $toolInput.command
                    if ($cmd -match "rm|del|Remove-Item|rmdir|rd|Set-Content.*>.*|.*\|.*iex") {
                        Write-Host "⚠️ Potentially dangerous command: $cmd"
                        $userResponse = Read-Host "Allow? (y/n)"
                        $allowed = $userResponse -eq "y"
                    }
                }
                elseif ($toolName -eq "Write-File") {
                    Write-Host "📝 Will write to: $($toolInput.path)"
                    $userResponse = Read-Host "Allow? (y/n)"
                    $allowed = $userResponse -eq "y"
                }
                
                if ($allowed) {
                    if ($toolName -eq "Read-File") {
                        $content = Get-Content $toolInput.path -Raw
                        $result = "Contents of $($toolInput.path):`n$content"
                    }
                    elseif ($toolName -eq "Write-File") {
                        Set-Content $toolInput.path $toolInput.content
                        $result = "Successfully wrote to $($toolInput.path)"
                    }
                    elseif ($toolName -eq "Run-Command") {
                        $output = Invoke-Expression $toolInput.command 2>&1 | Out-String
                        $result = "`$ $($toolInput.command)`n$output"
                    }
                    else {
                        $result = "Unknown tool: $toolName"
                    }
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
}

