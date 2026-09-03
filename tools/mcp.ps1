<#
.SYNOPSIS
  Calls a Godot MCP Native tool over HTTP.

.DESCRIPTION
  The plugin exposes an MCP server at http://localhost:9080/mcp (see docs/AI_WORKSPACE.md).
  This is a thin JSON-RPC client for it, so the editor can be driven from a shell while it
  holds the project lock - which is exactly when tools/validate_godot.ps1 cannot run.

.EXAMPLE
  ./tools/mcp.ps1 get_editor_state
  ./tools/mcp.ps1 run_project
  ./tools/mcp.ps1 get_editor_logs '{"lines":80}'
  ./tools/mcp.ps1 execute_editor_script '{"code":"print(1+1)"}'
#>
param(
    [Parameter(Mandatory = $true)][string]$Tool,
    [string]$Arguments = '{}',
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = "Stop"

$payload = @{
    jsonrpc = "2.0"
    id      = 1
    method  = "tools/call"
    params  = @{
        name      = $Tool
        arguments = ($Arguments | ConvertFrom-Json)
    }
} | ConvertTo-Json -Depth 12

try {
    $response = Invoke-WebRequest -Uri "http://localhost:9080/mcp" -Method POST `
        -Body $payload -ContentType "application/json" -TimeoutSec $TimeoutSec -UseBasicParsing
} catch {
    Write-Output "MCP CALL FAILED: $($_.Exception.Message)"
    exit 1
}

$parsed = $response.Content | ConvertFrom-Json
if ($parsed.error) {
    Write-Output "MCP ERROR: $($parsed.error.message)"
    exit 1
}

# Tool results come back as a content array of typed parts; text is all we ever want.
foreach ($part in $parsed.result.content) {
    if ($part.text) { Write-Output $part.text }
}
if ($parsed.result.isError) { Write-Output "(tool reported an error)" }
