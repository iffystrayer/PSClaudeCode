---
layout: post
title: "Building a PowerShell AI Agent: From Scratch to Claude Code"
date: 2026-01-10 09:00:00
categories: powershell ai agents psclaudecode claudecode
tags: [PowerShell, AI Agents, Claude Code, OpenAI, Function Calling, Automation, PSAI, API]
description: "Learn how to build your own AI agent from scratch using PowerShell and OpenAI's API. Start with a simple command runner and evolve it into a sophisticated agent with function calling, file operations, and conversational capabilities - inspired by Claude Code."
---

<div
 align="center">
    <img src="PowerShell-Claude-Code.png" alt="alt text" width="400" />
</div>
<br/>
<br/>


<p align="center">
  <a href="https://x.com/dfinke">
    <img src="https://img.shields.io/twitter/follow/dfinke.svg?style=social&label=Follow%20%40dfinke"></a>
  <a href="https://youtube.com/@dougfinke">
    <img src="https://img.shields.io/youtube/channel/subscribers/UCP47ZkO5EDkoI2sr-3P4ShQ"></a>
</p>

# Building a PowerShell AI Agent: From Scratch to Claude Code

The code for this article is available on [GitHub](https://github.com/dfinke/PSClaudeCode).

Inspired by the original article on [building Claude Code](https://x.com/dabit3/status/2009668398691582315?s=20), here's a PowerShell implementation using OpenAI's API.

## Introduction

What makes Claude Code powerful is surprisingly simple: it's a loop that lets an AI read files, run commands, and iterate until a task is done. The complexity comes from handling edge cases, building a good UX, and integrating with real development workflows.

In this post, I'll adapt the approach to PowerShell, using OpenAI (compatible with PSAI), showing how you could build your own agent.

**End goal:** learn how powerful agents work, so you can build your own in PowerShell.

## The Problem We're Solving

Same as original, but with PowerShell commands.

## Building an Agent from Scratch

### The Simplest Possible Agent

Let's start with the absolute minimum: an AI that can run a single PowerShell command.

```powershell
# agent-v0.ps1 - The simplest possible agent
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
    max_tokens = 1024
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
```

Usage
```powershell
.\agent-v0.ps1 "list all PowerShell files in this directory"
# AI suggests: Get-ChildItem *.ps1
# Run this command? (y/n)
```

### Creating the Agent Loop

The agent loop in PowerShell.

```powershell
# agent-v1.ps1 - Agent with a loop
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
        model = "gpt-4.1"
        messages = $messages
        max_tokens = 1024
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type" = "application/json"
    } -Body $body

    $aiText = $response.choices[0].message.content
    $messages += @{ role = "assistant"; content = $aiText }

    try {
        $parsed = $aiText | ConvertFrom-Json
    } catch {
        Write-Host "❌ Could not parse response: $aiText"
        break
    }

    $action = $parsed.action
    if (-not $action) {
        Write-Host "❌ No action in response"
        break
    } elseif ($action -eq "done") {
        Write-Host "✅ $($parsed.message)"
        break
    } elseif ($action -eq "powershell") {
        $command = $parsed.command
        Write-Host "🔧 Running: $command"
        
        # Execute with permission check
        if ($command -match "rm|del|Remove-Item|rmdir|rd|Set-Content.*>.*|.*\|.*iex") {
            Write-Host "⚠️ Potentially dangerous command: $command"
            $allow = Read-Host "Allow? (y/n)"
            if ($allow -ne "y") {
                $output = "DENIED BY USER"
            } else {
                try {
                    $output = Invoke-Expression $command 2>&1 | Out-String
                } catch {
                    $output = "Error: $_"
                }
            }
        } else {
            try {
                $output = Invoke-Expression $command 2>&1 | Out-String
            } catch {
                $output = "Error: $_"
            }
        }
        
        Write-Host $output
        $messages += @{ role = "user"; content = "Command output: $output" }
    } else {
        Write-Host "❌ Unknown action: $action"
        break
    }
}
```

### Beyond Commands: Adding Tools

Using OpenAI's function calling.

```powershell
# agent-v2.ps1 - Agent with structured tools
param([string]$Task)

$apiKey = $env:OPENAI_API_KEY
if (-not $apiKey) { Write-Host "Set OPENAI_API_KEY"; exit }

$tools = @(
    @{
        type = "function"
        function = @{
            name = "Read-File"
            description = "Read the contents of a file"
            parameters = @{
                type = "object"
                properties = @{
                    path = @{ type = "string"; description = "Path to the file" }
                }
                required = @("path")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "Write-File"
            description = "Write content to a file"
            parameters = @{
                type = "object"
                properties = @{
                    path = @{ type = "string"; description = "Path to the file" }
                    content = @{ type = "string"; description = "Content to write" }
                }
                required = @("path", "content")
            }
        }
    }
    @{
        type = "function"
        function = @{
            name = "Run-Command"
            description = "Run a PowerShell command"
            parameters = @{
                type = "object"
                properties = @{
                    command = @{ type = "string"; description = "The command to run" }
                }
                required = @("command")
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
            } catch {
                return "Error: $_"
            }
        }
        "Write-File" {
            try {
                Set-Content $ToolInput.path $ToolInput.content
                return "Successfully wrote to $($ToolInput.path)"
            } catch {
                return "Error: $_"
            }
        }
        "Run-Command" {
            try {
                $output = Invoke-Expression $ToolInput.command 2>&1 | Out-String
                return "`$ $($ToolInput.command)`n$output"
            } catch {
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
    } elseif ($ToolName -eq "Write-File") {
        Write-Host "📝 Will write to: $($ToolInput.path)"
        $response = Read-Host "Allow? (y/n)"
        return $response -eq "y"
    }
    return $true
}

$messages = @(@{ role = "user"; content = $Task })

while ($true) {
    $body = @{
        model = "gpt-4.1"
        messages = $messages
        max_tokens = 4096
        tools = $tools
        tool_choice = "auto"
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type" = "application/json"
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
            } else {
                $result = "Permission denied by user"
                Write-Host "   🚫 $result"
            }
            
            $toolResults += @{
                tool_call_id = $toolCall.id
                role = "tool"
                content = $result
            }
        }
        $messages += $toolResults
    } else {
        Write-Host "✅ $($message.content)"
        break
    }
}
```

## What We've Learned

Adapted to PowerShell, using OpenAI for compatibility with PSAI.

## Resources

- PSAI Module
- OpenAI API Docs