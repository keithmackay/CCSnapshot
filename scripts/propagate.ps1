# ABOUTME: Restores Claude Code personalizations from a snapshot directory.
# ABOUTME: Windows PowerShell port of propagate.sh — mechanical copy with backups.

[CmdletBinding()]
param(
    [switch]$MechanicalOnly
)

$ErrorActionPreference = "Stop"

$InputDir = if ($env:CCSNAPSHOT_INPUT_DIR) { $env:CCSNAPSHOT_INPUT_DIR } else { ".\snapshot" }
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"

# --- Validation ---

$manifestPath = Join-Path $InputDir "manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Error "manifest.json not found in $InputDir. Run collect.ps1 first to create a snapshot."
    exit 1
}

# --- Backup helper ---

function Safe-Copy {
    param($Source, $Destination)

    $destDir = Split-Path $Destination -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }

    if (Test-Path $Destination) {
        Copy-Item $Destination "${Destination}.bak" -Force
    }

    Copy-Item $Source $Destination -Force
}

# --- Restore functions ---

function Restore-GlobalConfig {
    $globalDir = Join-Path $InputDir "global"
    if (-not (Test-Path $globalDir)) { return }

    $claudeMd = Join-Path $globalDir "CLAUDE.md"
    if (Test-Path $claudeMd) {
        Safe-Copy $claudeMd (Join-Path $ClaudeDir "CLAUDE.md")
    }

    $settings = Join-Path $globalDir "settings.json"
    if (Test-Path $settings) {
        Safe-Copy $settings (Join-Path $ClaudeDir "settings.json")
    }

    $claudeJson = Join-Path $globalDir "claude.json"
    if (Test-Path $claudeJson) {
        Safe-Copy $claudeJson (Join-Path $env:USERPROFILE ".claude.json")
    }
}

function Restore-Commands {
    $commandsDir = Join-Path $InputDir "commands"
    if ((Test-Path $commandsDir) -and (Get-ChildItem $commandsDir -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $ClaudeDir "commands"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -Recurse -Force "$commandsDir\*" $dest
    }
}

function Restore-Skills {
    $skillsDir = Join-Path $InputDir "skills"
    if ((Test-Path $skillsDir) -and (Get-ChildItem $skillsDir -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $ClaudeDir "skills"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -Recurse -Force "$skillsDir\*" $dest
    }
}

function Restore-Plugins {
    $pluginsDir = Join-Path $InputDir "plugins"
    if ((Test-Path $pluginsDir) -and (Get-ChildItem $pluginsDir -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $ClaudeDir "plugins"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -Recurse -Force "$pluginsDir\*" $dest
    }
}

# --- Shell fragment display ---

function Display-ShellFragments {
    $fragmentsDir = Join-Path $InputDir "shell-fragments"
    if (-not (Test-Path $fragmentsDir)) { return }

    $fragments = Get-ChildItem $fragmentsDir -Filter "*.fragment" -ErrorAction SilentlyContinue
    if (-not $fragments) { return }

    Write-Host ""
    Write-Host "Shell fragments to merge (review before adding to your shell config):"
    Write-Host "----------------------------------------------------------------------"

    foreach ($fragment in $fragments) {
        $name = $fragment.BaseName
        Write-Host ""
        Write-Host "  From: $name"
        foreach ($line in (Get-Content $fragment.FullName)) {
            Write-Host "    $line"
        }
    }

    Write-Host "----------------------------------------------------------------------"
    Write-Host ""
}

# --- Summary ---

function Print-Summary {
    $globalCount = if (Test-Path (Join-Path $InputDir "global")) { (Get-ChildItem (Join-Path $InputDir "global")).Count } else { 0 }
    $cmdCount = if (Test-Path (Join-Path $InputDir "commands")) { (Get-ChildItem (Join-Path $InputDir "commands")).Count } else { 0 }
    $skillCount = if (Test-Path (Join-Path $InputDir "skills")) { (Get-ChildItem (Join-Path $InputDir "skills")).Count } else { 0 }
    $pluginStatus = if (Test-Path (Join-Path $InputDir "plugins")) { "restored" } else { "-" }

    Write-Host ""
    Write-Host "CCSnapshot: Propagation complete (mechanical)"
    Write-Host "  Global config:   $globalCount files restored"
    Write-Host "  Commands:        $cmdCount files restored"
    Write-Host "  Skills:          $skillCount directories restored"
    Write-Host "  Plugins:         $pluginStatus"

    if (Test-Path (Join-Path $InputDir "shell-fragments")) {
        Write-Host "  Shell fragments: displayed above (manual merge needed)"
    }
}

# --- Claude agent invocation ---

function Invoke-ClaudeAgent {
    if ($MechanicalOnly) { return }

    $scriptDir = Split-Path $MyInvocation.ScriptName -Parent
    $promptFile = Join-Path $scriptDir "..\prompts\propagate.md"

    if (-not (Test-Path $promptFile)) {
        Write-Warning "Claude agent prompt not found at $promptFile"
        Write-Warning "Skipping intelligent adaptation phase."
        return
    }

    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Write-Host ""
        Write-Host "Claude Code is not available on this machine."
        Write-Host "Install it to run the intelligent adaptation phase:"
        Write-Host "  npm install -g @anthropic-ai/claude-code"
        Write-Host ""
        Write-Host "Then re-run without -MechanicalOnly:"
        Write-Host "  .\scripts\propagate.ps1"
        return
    }

    Write-Host ""
    Write-Host "Launching Claude agent for intelligent adaptation..."
    $prompt = Get-Content $promptFile -Raw
    & claude --print $prompt
}

# --- Main ---

Restore-GlobalConfig
Restore-Commands
Restore-Skills
Restore-Plugins
Display-ShellFragments
Print-Summary
Invoke-ClaudeAgent
