# agent-v1.ps1 - Agent with a loop
# agent-v1.ps1 "List all files in the current directory and count how many there are"

param([string]$Task)

$apiKey = $env:OPENAI_API_KEY
if (-not $apiKey) { Write-Host "Set OPENAI_API_KEY"; exit }

$systemPrompt = @"
You are a helpful assistant that can run PowerShell commands.

When the user gives you a task, respond with JSON in this exact format:
{"action": "powershell", "command": "your command here"}

When the task is complete, respond with:
{"action": "done", "message": "explanation of what was accomplished"}

Only respond with JSON. No other text.
"@

$messages = @(
    @{ role = "system"; content = $systemPrompt }
    @{ role = "user"; content = $Task }
)

while ($true) {
    $body = @{
        model    = "gpt-4.1"
        messages = $messages
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type"  = "application/json"
    } -Body $body

    $aiText = $response.choices[0].message.content
    $messages += @{ role = "assistant"; content = $aiText }

    try {
        $parsed = $aiText | ConvertFrom-Json
    }
    catch {
        Write-Host "❌ Could not parse response: $aiText"
        break
    }

    $action = $parsed.action
    if (-not $action) {
        Write-Host "❌ No action in response"
        break
    }
    elseif ($action -eq "done") {
        Write-Host "✅ $($parsed.message)"
        break
    }
    elseif ($action -eq "powershell") {
        $command = $parsed.command
        Write-Host "🔧 Running: $command"
        
        # Execute with permission check
        if ($command -match "rm|del|Remove-Item|rmdir|rd|Set-Content.*>.*|.*\|.*iex") {
            Write-Host "⚠️ Potentially dangerous command: $command"
            $allow = Read-Host "Allow? (y/n)"
            if ($allow -ne "y") {
                $output = "DENIED BY USER"
            }
            else {
                try {
                    $output = Invoke-Expression $command 2>&1 | Out-String
                }
                catch {
                    $output = "Error: $_"
                }
            }
        }
        else {
            try {
                $output = Invoke-Expression $command 2>&1 | Out-String
            }
            catch {
                $output = "Error: $_"
            }
        }
        
        Write-Host $output
        $messages += @{ role = "user"; content = "Command output: $output" }
    }
    else {
        Write-Host "❌ Unknown action: $action"
        break
    }
}