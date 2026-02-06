# ABOUTME: Collects Claude Code personalizations into a portable snapshot directory.
# ABOUTME: Windows PowerShell port of collect.sh — deterministic, no LLM.

[CmdletBinding()]
param(
    [string[]]$Project
)

$ErrorActionPreference = "Stop"

$OutputDir = if ($env:CCSNAPSHOT_OUTPUT_DIR) { $env:CCSNAPSHOT_OUTPUT_DIR } else { ".\snapshot" }
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$ClaudeJson = Join-Path $env:USERPROFILE ".claude.json"

# --- Clean previous snapshot ---

if (Test-Path $OutputDir) {
    Remove-Item -Recurse -Force $OutputDir
}

# --- Global config collection ---

function Collect-GlobalConfig {
    $globalOut = Join-Path $OutputDir "global"

    if (-not (Test-Path $ClaudeDir) -and -not (Test-Path $ClaudeJson)) {
        return
    }

    New-Item -ItemType Directory -Force -Path $globalOut | Out-Null

    $claudeMd = Join-Path $ClaudeDir "CLAUDE.md"
    if (Test-Path $claudeMd) {
        Copy-Item $claudeMd (Join-Path $globalOut "CLAUDE.md")
    }

    $settings = Join-Path $ClaudeDir "settings.json"
    if (Test-Path $settings) {
        Copy-Item $settings (Join-Path $globalOut "settings.json")
    }

    if (Test-Path $ClaudeJson) {
        Copy-Item $ClaudeJson (Join-Path $globalOut "claude.json")
    }
}

# --- Commands and skills collection ---

function Collect-Commands {
    $commandsDir = Join-Path $ClaudeDir "commands"
    if ((Test-Path $commandsDir) -and (Get-ChildItem $commandsDir -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $OutputDir "commands"
        Copy-Item -Recurse -Force $commandsDir $dest
    }
}

function Collect-Skills {
    $skillsDir = Join-Path $ClaudeDir "skills"
    if ((Test-Path $skillsDir) -and (Get-ChildItem $skillsDir -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $OutputDir "skills"
        Copy-Item -Recurse -Force $skillsDir $dest
    }
}

# --- Plugin collection ---

function Collect-Plugins {
    $pluginsDir = Join-Path $ClaudeDir "plugins"
    if ((Test-Path $pluginsDir) -and (Get-ChildItem $pluginsDir -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $OutputDir "plugins"
        Copy-Item -Recurse -Force $pluginsDir $dest
    }
}

# --- Shell fragment extraction ---

function Collect-ShellFragments {
    $profilePath = $PROFILE
    if (-not $profilePath -or -not (Test-Path $profilePath)) {
        return
    }

    $fragmentDir = Join-Path $OutputDir "shell-fragments"
    $fragmentFile = Join-Path $fragmentDir "powershell_profile.fragment"
    $foundMatch = $false
    $lineNum = 0

    foreach ($line in (Get-Content $profilePath)) {
        $lineNum++
        if ($line -match "(?i)claude|anthropic") {
            if (-not $foundMatch) {
                New-Item -ItemType Directory -Force -Path $fragmentDir | Out-Null
                $foundMatch = $true
            }
            "# source: ${profilePath}:${lineNum}" | Out-File -Append -FilePath $fragmentFile -Encoding UTF8
            $line | Out-File -Append -FilePath $fragmentFile -Encoding UTF8
        }
    }
}

# --- Secrets detection ---

function Detect-Secrets {
    $secrets = @()

    # Scan shell fragments for secret-like patterns
    $fragmentDir = Join-Path $OutputDir "shell-fragments"
    if (Test-Path $fragmentDir) {
        foreach ($fragment in (Get-ChildItem $fragmentDir -Filter "*.fragment")) {
            foreach ($line in (Get-Content $fragment.FullName)) {
                if ($line -match "^# source:") { continue }
                if ($line -match "\w*(API_KEY|TOKEN|SECRET)\w*") {
                    $varName = $Matches[0]
                    $secrets += @{ name = $varName; location = "shell_config" }
                }
            }
        }
    }

    return $secrets | Sort-Object -Property name -Unique
}

# --- Project collection ---

function Collect-Projects {
    $collectedProjects = @()

    foreach ($projectPath in $Project) {
        if (-not (Test-Path $projectPath)) {
            Write-Warning "Project path does not exist, skipping: $projectPath"
            continue
        }

        $projectName = Split-Path $projectPath -Leaf
        $dest = Join-Path $OutputDir "projects" $projectName
        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        $claudeMd = Join-Path $projectPath "CLAUDE.md"
        if (Test-Path $claudeMd) {
            Copy-Item $claudeMd (Join-Path $dest "CLAUDE.md")
        }

        $dotClaude = Join-Path $projectPath ".claude"
        if (Test-Path $dotClaude) {
            Copy-Item -Recurse -Force $dotClaude (Join-Path $dest ".claude")
        }

        $collectedProjects += @{ name = $projectName; sourcePath = $projectPath }
    }

    return $collectedProjects
}

# --- Manifest generation ---

function Generate-Manifest {
    param($CollectedProjects, $Secrets)

    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $artifacts = @{}

    $globalOut = Join-Path $OutputDir "global"
    if (Test-Path $globalOut) {
        $artifacts.global = @(Get-ChildItem $globalOut | Select-Object -ExpandProperty Name)
    }

    $commandsOut = Join-Path $OutputDir "commands"
    if (Test-Path $commandsOut) {
        $artifacts.commands = @(Get-ChildItem $commandsOut | Select-Object -ExpandProperty Name)
    }

    $skillsOut = Join-Path $OutputDir "skills"
    if (Test-Path $skillsOut) {
        $artifacts.skills = @(Get-ChildItem $skillsOut | Select-Object -ExpandProperty Name)
    }

    $pluginsOut = Join-Path $OutputDir "plugins"
    if (Test-Path $pluginsOut) {
        $artifacts.plugins = $true
    }

    $fragmentsOut = Join-Path $OutputDir "shell-fragments"
    if (Test-Path $fragmentsOut) {
        $artifacts.shellFragments = @(Get-ChildItem $fragmentsOut | Select-Object -ExpandProperty Name)
    }

    if ($CollectedProjects -and $CollectedProjects.Count -gt 0) {
        $artifacts.projects = $CollectedProjects
    }

    $claudePath = (Get-Command claude -ErrorAction SilentlyContinue).Source
    if (-not $claudePath) { $claudePath = "not found" }

    $manifest = @{
        version          = "1.0"
        sourceOS         = "win32"
        sourceShell      = "powershell"
        claudeInstallPath = $claudePath
        collectedAt      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        artifacts        = $artifacts
        secretsNeeded    = @($Secrets)
    }

    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $OutputDir "manifest.json") -Encoding UTF8
}

# --- Summary ---

function Print-Summary {
    $globalCount = if (Test-Path (Join-Path $OutputDir "global")) { (Get-ChildItem (Join-Path $OutputDir "global")).Count } else { 0 }
    $cmdCount = if (Test-Path (Join-Path $OutputDir "commands")) { (Get-ChildItem (Join-Path $OutputDir "commands")).Count } else { 0 }
    $skillCount = if (Test-Path (Join-Path $OutputDir "skills")) { (Get-ChildItem (Join-Path $OutputDir "skills")).Count } else { 0 }
    $pluginStatus = if (Test-Path (Join-Path $OutputDir "plugins")) { "collected" } else { "-" }
    $fragCount = if (Test-Path (Join-Path $OutputDir "shell-fragments")) { (Get-ChildItem (Join-Path $OutputDir "shell-fragments")).Count } else { 0 }

    Write-Host ""
    Write-Host "CCSnapshot: Collection complete"
    Write-Host "  Global config:   $globalCount files"
    Write-Host "  Commands:        $cmdCount files"
    Write-Host "  Skills:          $skillCount directories"
    Write-Host "  Plugins:         $pluginStatus"
    Write-Host "  Shell fragments: $fragCount files"
    Write-Host "  Manifest:        $OutputDir\manifest.json"
}

# --- Main ---

Collect-GlobalConfig
Collect-Commands
Collect-Skills
Collect-Plugins
Collect-ShellFragments
$projects = Collect-Projects
$secrets = Detect-Secrets
Generate-Manifest -CollectedProjects $projects -Secrets $secrets
Print-Summary
