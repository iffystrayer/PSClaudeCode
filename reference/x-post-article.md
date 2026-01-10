## Grok Conversation

https://grok.com/c/8d5af9ee-222d-4662-9747-83fa28bff21e?rid=4a4c306a-66f6-4b5d-a794-24be113598a4

## X Post
https://x.com/dabit3/status/2009668398691582315?s=20

## Introduction

What makes Claude Code powerful is surprisingly simple: it's a loop that lets an AI read files, run commands, and iterate until a task is done. 
The complexity comes from handling edge cases, building a good UX, and integrating with real development workflows.

In this post, I'll start from scratch and build up to Claude Code's architecture step by step, showing how you could have invented it yourself from first principles, using nothing but a terminal, an LLM API, and the desire to make AI actually useful.

**End goal:** learn how powerful agents work, so you can build your own.

## The Problem We're Solving

When you use ChatGPT or Claude in a browser, you're doing a lot of manual labor:

- Copy-paste code from the chat into files
- Run commands yourself, then copy errors back
- Provide context by uploading files or pasting content
- Manually iterate through the fix-test-debug cycle

You're essentially acting as the AI's hands. The AI thinks; you execute.

What if the AI could execute too?

Imagine telling an AI: "Fix the bug in auth.py" and walking away. When you come back, the bug is fixed. The AI read the file, understood it, tried a fix, ran the tests, saw them fail, tried another approach, and eventually succeeded.

This is what an agent does. It's an AI that can:

- Take actions in the real world (read files, run commands)
- Observe the results
- Decide what to do next
- Repeat until the task is complete

## Building an Agent from Scratch

### The Simplest Possible Agent

Let's start with the absolute minimum: an AI that can run a single bash command.

```bash
#!/bin/bash
# agent-v0.sh - The simplest possible agent

PROMPT="$1"

# Ask Claude what command to run
RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-opus-4-5-20251101",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "'"$PROMPT"'\n\nRespond with ONLY a bash command. No markdown, no explanation, no code blocks."}]
  }')

# Extract the command from response
COMMAND=$(echo "$RESPONSE" | jq -r '.content[0].text')

echo "AI suggests: $COMMAND"
read -r -p "Run this command? (y/n) " CONFIRM

if [ "$CONFIRM" = "y" ]; then
  eval "$COMMAND"
fi
```
Usage
```bash
bash agent-v0.sh "list all Python files in this directory"
# AI suggests: ls *.py
# Run this command? (y/n)
```
This is... not very useful. The AI can suggest one command, then you're back to doing everything manually.

But here's the key insight: what if we put this in a loop?

### Creating the Agent Loop

The fundamental insight behind all AI agents is the agent loop:

```plaintext
while (task not complete):
    1. AI decides what to do next
    2. Execute that action
    3. Show AI the result
    4. Go back to step 1
```

Let's implement exactly this. The AI needs to tell us:

- What action to take
- Whether it's done

We'll use a simple JSON format:

```bash
#!/bin/bash
# agent-v1.sh - Agent with a loop

SYSTEM_PROMPT='You are a helpful assistant that can run bash commands.

When the user gives you a task, respond with JSON in this exact format:
{"action": "bash", "command": "your command here"}

When the task is complete, respond with:
{"action": "done", "message": "explanation of what was accomplished"}

Only respond with JSON. No other text.'

# We'll build messages as a JSON array (using jq for proper escaping)
MESSAGES="[]"

run_agent() {
    local USER_MSG="$1"
    
    # Add initial user message using jq to handle escaping
    MESSAGES=$(echo "$MESSAGES" | jq --arg msg "$USER_MSG" '. + [{"role": "user", "content": $msg}]')
    
    while true; do
        # Build the request body properly with jq
        REQUEST_BODY=$(jq -n \
            --arg model "claude-opus-4-5-20251101" \
            --arg system "$SYSTEM_PROMPT" \
            --argjson messages "$MESSAGES" \
            '{model: $model, max_tokens: 1024, system: $system, messages: $messages}')
        
        # Call the API
        RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
          -H "x-api-key: $ANTHROPIC_API_KEY" \
          -H "content-type: application/json" \
          -H "anthropic-version: 2023-06-01" \
          -d "$REQUEST_BODY")
        # Echo the response for debugging
        AI_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text')
        
        # Add assistant message to history
        MESSAGES=$(echo "$MESSAGES" | jq --arg msg "$AI_TEXT" '. + [{"role": "assistant", "content": $msg}]')
        
        # Parse the action from the JSON response
        ACTION=$(echo "$AI_TEXT" | jq -r '.action // empty')
        
        if [ -z "$ACTION" ]; then
            echo "❌ Could not parse response: $AI_TEXT"
            break
        elif [ "$ACTION" = "done" ]; then
            echo "✅ $(echo "$AI_TEXT" | jq -r '.message')"
            break
        elif [ "$ACTION" = "bash" ]; then
            COMMAND=$(echo "$AI_TEXT" | jq -r '.command')
            echo "🔧 Running: $COMMAND"
            
            # Execute and capture output
            OUTPUT=$(eval "$COMMAND" 2>&1)
            echo "$OUTPUT"
            
            # Feed result back to AI
            MESSAGES=$(echo "$MESSAGES" | jq --arg msg "Command output: $OUTPUT" '. + [{"role": "user", "content": $msg}]')
        else
            echo "❌ Unknown action: $ACTION"
            break
        fi
    done
}

run_agent "$1"
```

Now we have something that can actually iterate:

```bash
bash agent-v1.sh "Create a file called hello.py that prints hello world, then run it"

# 🔧 Running: echo 'print("hello world")' > hello.py
# 🔧 Running: python hello.py
# hello world
# ✅ Created hello.py and executed it successfully. It prints "hello world".
```
The AI ran two commands and then told us it was done. We've created an agent loop!

But wait! We're executing arbitrary commands with no safety checks. The AI could `rm -rf /` and we'd blindly execute it.

### Adding Permission Controls

Let's add a human-in-the-loop for dangerous operations. First, we define a function that wraps command execution with a safety check:

```bash
# Add this function BEFORE run_agent() in your script
execute_with_permission() {
    local COMMAND="$1"
    
    # Check if command seems dangerous
    if echo "$COMMAND" | grep -qE 'rm |sudo |chmod |curl.*\|.*sh'; then
        # Use >&2 to print to stderr, so prompts display immediately
        # (stdout gets captured by the $(...) in the agent loop)
        echo "⚠️  Potentially dangerous command: $COMMAND" >&2
        echo "Allow? (y/n)" >&2
        read CONFIRM
        if [ "$CONFIRM" != "y" ]; then
            echo "DENIED BY USER"
            return 1
        fi
    fi
    
    eval "$COMMAND" 2>&1
}
```

Then, inside the agent loop, we replace the direct eval call with our new function:
```bash
        # BEFORE:
        OUTPUT=$(eval "$COMMAND" 2>&1)
        
        # AFTER (with permission check):
        OUTPUT=$(execute_with_permission "$COMMAND")
```

That's it! The function sits between the AI's request and actual execution, giving you a chance to block dangerous commands. When denied, you can feed that back to the AI so it can try a different approach.


Try it out:
```bash
# Create a test file
echo 'print("hello world")' > hello.py

# Ask the agent to delete it
bash agent-v1.sh "delete the file hello.py"

# 🔧 Running: rm hello.py
# ⚠️  Potentially dangerous command: rm hello.py
# Allow? (y/n)
```

Type y to allow the deletion, or n to block it.
This is the beginning of a permission system. Claude Code takes this much further with:

- Tool-specific permissions (file edits vs. bash commands)
- Pattern-based allowlists (Bash(npm test:*) allows any npm test command)
- Session-level "accept all" modes for when you trust the AI

**Key insight:** the human should be able to control what the AI can do, but with enough granularity that it's not annoying.
### Beyond Bash: Adding Tools

Running bash commands is powerful, but it's also:

- Dangerous: unlimited access to the system
- Inefficient: reading a file shouldn't spawn a subprocess
- Imprecise: output parsing is fragile

What if we gave the AI structured tools instead?

We'll switch to Python here since it handles JSON and API calls more cleanly:
```python
# agent-v2.py - Agent with structured tools
import anthropic
import json
import os

client = anthropic.Anthropic()

TOOLS = [
    {
        "name": "read_file",
        "description": "Read the contents of a file",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Path to the file"}
            },
            "required": ["path"]
        }
    },
    {
        "name": "write_file",
        "description": "Write content to a file",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Path to the file"},
                "content": {"type": "string", "description": "Content to write"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "run_bash",
        "description": "Run a bash command",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "The command to run"}
            },
            "required": ["command"]
        }
    }
]

def execute_tool(name, input):
    """Execute a tool and return the result."""
    if name == "read_file":
        try:
            with open(input["path"], "r") as f:
                return f.read()
        except Exception as e:
            return f"Error: {e}"
    
    elif name == "write_file":
        try:
            with open(input["path"], "w") as f:
                f.write(input["content"])
            return f"Successfully wrote to {input['path']}"
        except Exception as e:
            return f"Error: {e}"
    
    elif name == "run_bash":
        import subprocess
        result = subprocess.run(
            input["command"], 
            shell=True, 
            capture_output=True, 
            text=True
        )
        return result.stdout + result.stderr

def run_agent(task):
    """Main agent loop."""
    messages = [{"role": "user", "content": task}]
    
    while True:
        response = client.messages.create(
            model="claude-opus-4-5-20251101",
            max_tokens=4096,
            tools=TOOLS,
            messages=messages
        )
        
        # Check if we're done
        if response.stop_reason == "end_turn":
            # Extract final text response
            for block in response.content:
                if hasattr(block, "text"):
                    print(f"✅ {block.text}")
            break
        
        # Process tool uses
        if response.stop_reason == "tool_use":
            # Add assistant's response to history
            messages.append({"role": "assistant", "content": response.content})
            
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    print(f"🔧 {block.name}: {json.dumps(block.input)}")
                    result = execute_tool(block.name, block.input)
                    print(f"   → {result[:200]}...")  # Truncate for display
                    
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result
                    })
            
            # Add results to conversation
            messages.append({"role": "user", "content": tool_results})

if __name__ == "__main__":
    import sys
    run_agent(sys.argv[1])
```

Now we're using Anthropic's native tool use API. This is much better because:

- Type safety: the AI knows exactly what parameters each tool accepts
- Explicit actions: reading a file is a `read_file` call, not `cat`
- Controlled surface area: we decide what tools exist

Try it out:
```bash
# Create a test file for the agent to work with
cat > main.py << 'EOF'
def calculate(x, y):
    return x + y

def greet(name):
    print(f"Hello, {name}!")
EOF

# Run the agent
uv run --with anthropic python agent-v2.py "Read main.py and add a docstring to the first function"

# 🔧 read_file: {"path": "main.py"}
#    → def calculate(x, y):...
# 🔧 write_file: {"path": "main.py", "content": "def calculate(x, y):\n    \"\"\"Calculate..."}
#    → Successfully wrote to main.py
# ✅ I've added a docstring to the calculate function explaining its purpose.
```
### Making Edits Precise

Our `write_file` tool has a problem: it replaces the entire file. If the AI makes a small change to a 1000-line file, it has to output all 1000 lines. This is:

- Expensive: more output tokens = more cost
- Error-prone: the AI might accidentally drop lines
- Slow: generating that much text takes time

What if we had a tool for surgical edits?
```python
{
    "name": "edit_file",
    "description": "Make a precise edit to a file by replacing a unique string",
    "input_schema": {
        "type": "object",
        "properties": {
            "path": {"type": "string"},
            "old_str": {"type": "string", "description": "Exact string to find (must be unique in file)"},
            "new_str": {"type": "string", "description": "String to replace it with"}
        },
        "required": ["path", "old_str", "new_str"]
    }
}
```

Implementation:
```python
def edit_file(path, old_str, new_str):
    with open(path, "r") as f:
        content = f.read()
    
    # Ensure the string is unique
    count = content.count(old_str)
    if count == 0:
        return f"Error: '{old_str}' not found in file"
    if count > 1:
        return f"Error: '{old_str}' found {count} times. Must be unique."
    
    new_content = content.replace(old_str, new_str)
    with open(path, "w") as f:
        f.write(new_content)
    
    return f"Successfully replaced text in {path}"
```
This is exactly how Claude Code's `str_replace` tool works. The requirement for uniqueness might seem annoying, but it's actually a feature:

- Forces the AI to include enough context to be unambiguous
- Creates a natural diff that's easy for humans to review
- Prevents accidental mass replacements
### Searching the Codebase

So far our agent can read files it knows about. But what about a task like "find where the authentication bug is"?

The AI needs to search the codebase. Let's add tools for that.
```python
SEARCH_TOOLS = [
    {
        "name": "glob",
        "description": "Find files matching a pattern",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Glob pattern (e.g., '**/*.py')"}
            },
            "required": ["pattern"]
        }
    },
    {
        "name": "grep",
        "description": "Search for a pattern in files",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Regex pattern to search for"},
                "path": {"type": "string", "description": "Directory or file to search in"}
            },
            "required": ["pattern"]
        }
    }
]
```
Now the AI can:

- `glob("**/*.py")` → Find all Python files
- `grep("def authenticate", "src/")` → Find authentication code
- `read_file("src/auth.py")` → Read the relevant file
- `edit_file(...)` → Fix the bug

This is the pattern: give the AI tools to explore, and it can navigate codebases it's never seen before.
### Context Management

Here's a problem you'll hit quickly: context windows are finite.

If you're working on a large codebase, the conversation might look like:

- User: "Fix the bug in authentication"
- AI: reads 10 files, runs 20 commands, tries 3 approaches
- ...conversation is now 100,000 tokens
- AI: runs out of context and starts forgetting earlier information

How do we handle this?

#### Option 1: Summarization (Compaction)
When context gets too long, summarize what happened:
```python
def compact_conversation(messages):
    """Summarize the conversation to free up context."""
    summary_prompt = """Summarize this conversation concisely, preserving:
    - The original task
    - Key findings and decisions
    - Current state of the work
    - What still needs to be done"""
    
    summary = client.messages.create(
        model="claude-opus-4-5-20251101",
        max_tokens=2000,
        messages=[
            {"role": "user", "content": f"{messages}\n\n{summary_prompt}"}
        ]
    )
    
    return [{"role": "user", "content": f"Previous work summary:\n{summary}"}]
```
#### Option 2: Sub-Agents (Delegation)

For complex tasks, spawn a sub-agent with its own context:

```python
def delegate_to_subagent(task, tools_allowed):
    """Spawn a sub-agent for a focused task."""
    result = run_agent(
        task=task,
        tools=tools_allowed,
        max_turns=10  # Prevent infinite loops
    )
    # Only return the result, not the full conversation
    return result.final_answer
```

This is why Claude Code has the concept of subagents: specialized agents that handle focused tasks in their own context, returning just the results.

### The System Prompt

We've been glossing over something important: how does the AI know how to behave?

The system prompt is where you encode:

- The AI's identity and capabilities
- Guidelines for tool usage
- Project-specific context
- Behavioral rules
Here's a simplified version of what makes Claude Code effective:

```python
SYSTEM_PROMPT = """You are an AI assistant that helps with software development tasks.
You have access to the following tools:
- read_file: Read file contents
- write_file: Create or overwrite files
- edit_file: Make precise edits to existing files
- glob: Find files by pattern
- grep: Search for patterns in files
- bash: Run shell commands

## Guidelines

### Before making changes:
1. Understand the task fully before acting
2. Read relevant files to understand context
3. Plan your approach

### When editing code:
1. Use edit_file for small changes (preferred)
2. Use write_file only for new files or complete rewrites
3. Run tests after changes when possible
4. If tests fail, analyze the error and iterate

### General principles:
- Be concise but thorough
- Explain your reasoning briefly
- Ask for clarification if the task is ambiguous
- If you're stuck, say so instead of guessing

## Current Directory
You are working in: {current_directory}
"""
```

But here's the problem: what if the project has specific conventions? What if the team uses a particular testing framework, or has a non-standard directory structure?

### Project-Specific Context (CLAUDE.md)
Claude Code solves this with CLAUDE.md - a file at the project root that gets automatically included in context:

```markdown
# CLAUDE.md

## Project Overview
This is a FastAPI application for user authentication.

## Key Commands
- `make test`: Run all tests
- `make lint`: Run linting
- `make dev`: Start development server

## Architecture
- `src/api/`: API routes
- `src/models/`: Database models
- `src/services/`: Business logic
- `tests/`: Test files (mirror src/ structure)

## Conventions
- All functions must have type hints
- Use pydantic for request/response models
- Write tests before implementing features (TDD)

## Known Issues
- The /auth/refresh endpoint has a race condition (see issue #142)
```
Now the AI knows:
How to run tests for this project
Where to find things
What conventions to follow
Known gotchas to watch out for
This is one of Claude Code's most powerful features: project knowledge that travels with the code.

### Putting It All Together

Let's see what we've built. The core of an AI coding agent is this loop:

1. **Setup (runs once)**
   - Load the system prompt with tool descriptions, behavioral guidelines, and project context (CLAUDE.md)
   - Initialize an empty conversation history

2. **Agent Loop (repeats until done)**
   - Send conversation history to the LLM
   - LLM decides: use a tool or respond to user
   - If tool use:
     1. Check permissions (prompt user if dangerous)
     2. Execute the tool (read_file, edit_file, bash, glob, grep, etc.)
     3. Add the result to conversation history
     4. Loop back to step 2
   - If final answer:
     1. Display response to user
     2. Done

That's it. Every AI coding agent, from our 50-line bash script to Claude Code, follows this pattern.

### Building a Complete Mini-Claude Code

Now let's build a complete, working mini-Claude Code that you can actually use. It combines everything we've learned: the agent loop, structured tools, permission checks, and an interactive REPL.
```bash
#!/usr/bin/env python3
# mini-claude-code.py - A minimal Claude Code clone

import anthropic
import subprocess
import os
import json

client = anthropic.Anthropic()

TOOLS = [
    {
        "name": "read_file",
        "description": "Read the contents of a file",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Path to the file"}
            },
            "required": ["path"]
        }
    },
    {
        "name": "write_file",
        "description": "Write content to a file (creates or overwrites)",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Path to the file"},
                "content": {"type": "string", "description": "Content to write"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "list_files",
        "description": "List files in a directory",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Directory path (default: current directory)"}
            }
        }
    },
    {
        "name": "run_command",
        "description": "Run a shell command",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "The command to run"}
            },
            "required": ["command"]
        }
    }
]

DANGEROUS_PATTERNS = ["rm ", "sudo ", "chmod ", "mv ", "cp ", "> ", ">>"]

def check_permission(tool_name, tool_input):
    """Check if an action requires user permission."""
    if tool_name == "run_command":
        cmd = tool_input.get("command", "")
        if any(p in cmd for p in DANGEROUS_PATTERNS):
            print(f"\n⚠️  Potentially dangerous command: {cmd}")
            response = input("Allow? (y/n): ").strip().lower()
            return response == "y"
    elif tool_name == "write_file":
        path = tool_input.get("path", "")
        print(f"\n📝 Will write to: {path}")
        response = input("Allow? (y/n): ").strip().lower()
        return response == "y"
    return True

def execute_tool(name, tool_input):
    """Execute a tool and return the result."""
    if name == "read_file":
        path = tool_input["path"]
        try:
            with open(path, "r") as f:
                content = f.read()
            return f"Contents of {path}:\n{content}"
        except Exception as e:
            return f"Error reading file: {e}"

    elif name == "write_file":
        path = tool_input["path"]
        content = tool_input["content"]
        try:
            with open(path, "w") as f:
                f.write(content)
            return f"✅ Successfully wrote to {path}"
        except Exception as e:
            return f"Error writing file: {e}"

    elif name == "list_files":
        path = tool_input.get("path", ".")
        try:
            files = os.listdir(path)
            return f"Files in {path}:\n" + "\n".join(f"  {f}" for f in sorted(files))
        except Exception as e:
            return f"Error listing files: {e}"

    elif name == "run_command":
        cmd = tool_input["command"]
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            return f"$ {cmd}\n{output}" if output else f"$ {cmd}\n(no output)"
        except subprocess.TimeoutExpired:
            return f"Command timed out after 30 seconds"
        except Exception as e:
            return f"Error running command: {e}"

    return f"Unknown tool: {name}"

def agent_loop(user_message, conversation_history):
    """Run the agent loop until the task is complete."""
    conversation_history.append({"role": "user", "content": user_message})

    while True:
        # Call Claude
        response = client.messages.create(
            model="claude-opus-4-5-20251101",
            max_tokens=4096,
            system=f"You are a helpful coding assistant. Working directory: {os.getcwd()}",
            tools=TOOLS,
            messages=conversation_history
        )

        # Add assistant response to history
        conversation_history.append({"role": "assistant", "content": response.content})

        # Check if we're done (no tool use)
        if response.stop_reason == "end_turn":
            # Print the final text response
            for block in response.content:
                if hasattr(block, "text"):
                    print(f"\n🤖 {block.text}")
            break

        # Process tool calls
        tool_results = []
        for block in response.content:
            if block.type == "tool_use":
                tool_name = block.name
                tool_input = block.input

                print(f"\n🔧 {tool_name}: {json.dumps(tool_input)}")

                # Check permissions
                if not check_permission(tool_name, tool_input):
                    result = "Permission denied by user"
                    print(f"   🚫 {result}")
                else:
                    result = execute_tool(tool_name, tool_input)
                    # Truncate long output for display
                    display = result[:200] + "..." if len(result) > 200 else result
                    print(f"   → {display}")

                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result
                })

        # Add tool results to conversation
        conversation_history.append({"role": "user", "content": tool_results})

    return conversation_history

def main():
    print("Mini Claude Code")
    print(" Type your requests, or 'quit' to exit.\n")

    conversation_history = []

    while True:
        try:
            user_input = input("You: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nGoodbye!")
            break

        if not user_input:
            continue
        if user_input.lower() in ["quit", "exit", "q"]:
            print("Goodbye!")
            break

        conversation_history = agent_loop(user_input, conversation_history)

if __name__ == "__main__":
    main()
```

Save this as mini-claude-code.py and run it:
```bash
uv run --with anthropic python mini-claude-code.py
```

Here's what a session looks like:
```bash
Mini Claude Code
 Type your requests, or 'quit' to exit.

You: create a python file that prints the fibonacci sequence up to n

🔧 write_file: {"path": "fibonacci.py", "content": "def fibonacci(n):\n    ..."}

📝 Will write to: fibonacci.py
Allow? (y/n): y
   → ✅ Successfully wrote to fibonacci.py

🤖 I've created fibonacci.py with a function that prints the Fibonacci sequence.
   Would you like me to run it to test it?

You: yes, run it with n=10

🔧 run_command: {"command": "python fibonacci.py 10"}
   → $ python fibonacci.py 10
     0 1 1 2 3 5 8 13 21 34

🤖 The script works correctly! It printed the first 10 Fibonacci numbers.

You: quit
Goodbye!
```
That's a working mini Claude Code clone in ~150 lines. It has:

- Interactive REPL: keeps conversation context between prompts
- Multiple tools: read, write, list files, run commands
- Permission checks: asks before writing files or running dangerous commands
- Conversation memory: each follow-up builds on previous context

This is essentially what Claude Code does, plus:

- A polished terminal UI
- Sophisticated permission system
- Context compaction when conversations get long
- Subagent delegation for complex tasks
- Hooks for custom automation
- Integration with git and other dev tools
### The Claude Agent SDK

If you want to build on this foundation without reinventing the wheel, Anthropic offers the Claude Agent SDK. It's the same engine that powers Claude Code, exposed as a library.

The SDK handles:

- The agent loop (so you don't have to)
- All the built-in tools (Read, Write, Edit, Bash, Glob, Grep, etc.)
- Permission management
- Context tracking
- Sub-agent coordination
### What We've Learned

Starting from a simple bash script, we discovered:

- **The agent loop:** AI decides → execute → observe → repeat
- **Structured tools:** better than raw bash for safety and precision
- **Surgical edits:** str_replace beats full file rewrites
- **Search tools:** let the AI explore codebases
- **Context management:** compaction and delegation handle long tasks
- **Project knowledge:** CLAUDE.md gives project-specific context

Each of these emerged from a practical problem:

- "How do I make the AI do more than one thing?" → agent loop
- "How do I prevent it from destroying my system?" → permission system
- "How do I make edits efficient?" → str_replace tool
- "How does it find code it doesn't know about?" → search tools
- "What happens when context runs out?" → compaction
- "How does it know my project's conventions?" → CLAUDE.md

This is how you could have invented Claude Code. The core ideas are simple.
Again - the complexity comes from handling edge cases, building a good UX, and integrating with real development workflows.

### Next Steps
If you want to build your own agents:
Start simple: a basic agent loop with 2-3 tools
Add tools incrementally: each new capability should solve a real problem
Handle errors gracefully: tools fail; your agent should recover

Test on real tasks: the edge cases will teach you what's missing
Consider using the Claude Agent SDK: why reinvent the wheel?
The future of software development is agents that can actually do things. Now we know how they work!

### Resources

- Claude Agent SDK Documentation
- Claude Code Documentation
- Anthropic API Reference
If you're interested in building verifiable