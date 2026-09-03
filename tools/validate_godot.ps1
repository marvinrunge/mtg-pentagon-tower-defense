[CmdletBinding()]
param(
    [string]$GodotPath = $(if ($env:GODOT_PATH) { $env:GODOT_PATH } elseif (Test-Path "G:\Godot\Godot_v4.7-stable_win64_console.exe") { "G:\Godot\Godot_v4.7-stable_win64_console.exe" } else { "C:\Godot\godot.exe" }),
    [int]$SmokeTestSeconds = 8,
    [switch]$SkipRuntime
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $GodotPath)) {
    $resolvedCommand = Get-Command $GodotPath -ErrorAction SilentlyContinue
    if (-not $resolvedCommand) {
        throw "Godot executable not found. Set GODOT_PATH or pass -GodotPath."
    }
    $GodotPath = $resolvedCommand.Source
}

function Invoke-GodotCheck {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 0
    )

    $stdoutPath = Join-Path $env:TEMP "mtg-godot-$Name-stdout.log"
    $stderrPath = Join-Path $env:TEMP "mtg-godot-$Name-stderr.log"
    Remove-Item $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    $process = Start-Process -FilePath $GodotPath -ArgumentList $Arguments -WorkingDirectory $projectRoot -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $timedOut = $false
    if ($TimeoutSeconds -gt 0) {
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit()
        }
    } else {
        $process.WaitForExit()
    }

    $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { "" }
    $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { "" }
    Remove-Item $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    $combinedOutput = "$stdout`n$stderr"
    $actionableOutput = $combinedOutput
    $knownExitDiagnostics = @(
        '(?im)^ERROR: \d+ RID allocations .* were leaked at exit\.?\s*$',
        '(?im)^ERROR: \d+ resources still in use at exit .*\s*$',
        '(?im)^ERROR: Pages in use exist at exit in PagedAllocator:.*\s*$'
    )
    foreach ($diagnosticPattern in $knownExitDiagnostics) {
        $actionableOutput = $actionableOutput -replace $diagnosticPattern, ""
    }
    # USER ERROR is what push_error() prints. Without it a deliberate, loud failure
    # written by the project itself - "no player was spawned" - passes validation
    # silently, which is exactly the class of bug push_error exists to catch.
    $errorPattern = '(?im)^\s*(USER ERROR|USER SCRIPT ERROR|ERROR|SCRIPT ERROR|Parse Error|Failed loading resource|CrashHandlerException):'
    if ($actionableOutput -match $errorPattern) {
        [Console]::WriteLine($combinedOutput)
        throw "Godot $Name check reported an error."
    }
    $exitCode = $process.ExitCode
    if (-not $timedOut -and $null -ne $exitCode -and $exitCode -ne 0) {
        [Console]::WriteLine($combinedOutput)
        throw "Godot $Name check exited with code $exitCode."
    }

    return [PSCustomObject]@{
        Name = $Name
        TimedOut = $timedOut
        ExitCode = if ($timedOut) { $null } else { $exitCode }
        Output = $combinedOutput.Trim()
    }
}

$version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($GodotPath).ProductVersion
if (-not $version) {
    $version = "unknown"
}
Write-Output "Godot: $version"

$projectSettingsPath = Join-Path $projectRoot "project.godot"
$projectSettingsBytes = [System.IO.File]::ReadAllBytes($projectSettingsPath)
try {
    $importResult = Invoke-GodotCheck -Name "import" -Arguments @("--headless", "--path", $projectRoot, "--editor", "--quit")
} finally {
    [System.IO.File]::WriteAllBytes($projectSettingsPath, $projectSettingsBytes)
}
Write-Output "PASS: project imports and scripts parse."

if (-not $SkipRuntime) {
    $runtimeResult = Invoke-GodotCheck -Name "runtime" -Arguments @("--headless", "--path", $projectRoot) -TimeoutSeconds $SmokeTestSeconds
    if ($runtimeResult.TimedOut) {
        Write-Output "PASS: main scene stayed alive for $SmokeTestSeconds seconds without engine errors."
    } else {
        Write-Output "PASS: main scene exited cleanly with code $($runtimeResult.ExitCode)."
    }

    # Booting without errors is not the same as working. This drives the skill tree the
    # way a player does and asserts that the purchases actually land - the exact thing
    # that was broken for a whole release while every other check passed.
    $skillResult = Invoke-GodotCheck -Name "skill-purchase" -Arguments @("--headless", "--path", $projectRoot, "res://tools/tests/skill_purchase.tscn") -TimeoutSeconds 60
    if ($skillResult.Output -notmatch "TEST RESULT: PASS") {
        [Console]::WriteLine($skillResult.Output)
        throw "Skill tree purchases are broken."
    }
    Write-Output "PASS: skill tree purchases apply (free-debug, paid, out-of-points and centre node)."

    # And that the things you buy DO something. Every one of the twenty-five spells and
    # ten capstones is cast against real enemies with one assertion about an observable
    # consequence - a spell that silently does nothing passes a parse check and a smoke
    # test alike, which is the whole reason this file exists.
    $rosterResult = Invoke-GodotCheck -Name "skill-roster" -Arguments @("--headless", "--path", $projectRoot, "res://tools/tests/skill_roster.tscn") -TimeoutSeconds 90
    if ($rosterResult.Output -notmatch "TEST RESULT: PASS") {
        [Console]::WriteLine($rosterResult.Output)
        throw "One or more skills in the roster do nothing."
    }
    Write-Output "PASS: all 25 spells and 10 capstones have an observable effect."
}
