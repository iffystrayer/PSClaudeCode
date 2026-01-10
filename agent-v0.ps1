# agent-v0.ps1 - The simplest possible agent
# ./agent-v0.ps1 "List all PowerShell script files in the current directory"
# ./agent-v0.ps1 "List all markdown files"
param(
    [string]$Prompt
)

# Assume $env:OPENAI_API_KEY is set
$apiKey = $env:OPENAI_API_KEY
if (-not $apiKey) { Write-Host "Set OPENAI_API_KEY"; exit }

# Call OpenAI
$body = @{
    model    = "gpt-4.1"
    messages = @(
        @{ 
            role    = "user"
            content = @"
$Prompt

Respond with ONLY a PowerShell command. No markdown, no explanation, no code blocks.
"@
        }
    )
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type"  = "application/json"
} -Body $body

$command = $response.choices[0].message.content.Trim()

Write-Host "AI suggests: $command" -ForegroundColor Yellow
$confirm = Read-Host "Run this command? (y/n)"
if ($confirm -eq "y") {
    try {
        Invoke-Expression $command
    }
    catch {
        Write-Host "Error: $_"
    }
}