# claude-autonomous installer — Windows (and any host with PowerShell 7).
#
#   irm https://raw.githubusercontent.com/NspxMiguel/claude-autonomous/main/install.ps1 | iex
#
# Installs the claude-autonomous command and the autonomous skill, then turns
# the mode on. No administrator rights needed. The previous settings.json is
# backed up before anything is written.

$ErrorActionPreference = 'Stop'

# ConvertFrom-Json -AsHashtable arrived in PowerShell 6, and Windows still
# ships 5.1 as "Windows PowerShell". Stop before touching anything.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    Write-Error @"
This installer needs PowerShell 7 or newer (you are on $($PSVersionTable.PSVersion)).

Install it, then re-run in the new "PowerShell" (not "Windows PowerShell"):
    winget install --id Microsoft.PowerShell --source winget
"@
    exit 1
}

$Repo      = 'NspxMiguel/claude-autonomous'
$Raw       = "https://raw.githubusercontent.com/$Repo/main"
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$SkillDir  = Join-Path $ClaudeDir 'skills/autonomous'
$BinDir    = if ($IsWindows) { Join-Path $env:LOCALAPPDATA 'Programs\claude-autonomous' }
             else            { Join-Path $HOME '.local/bin' }

Write-Host 'claude-autonomous'
Write-Host '=================='
Write-Host ''

New-Item -ItemType Directory -Force -Path $ClaudeDir, $SkillDir, $BinDir | Out-Null

# Run from a clone when there is one, otherwise fetch.
$src = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'bin/claude-autonomous.ps1'))) { $PSScriptRoot } else { $null }
function Fetch([string] $RelPath, [string] $Dest) {
    if ($src) { Copy-Item (Join-Path $src $RelPath) $Dest -Force }
    else { Invoke-WebRequest -Uri "$Raw/$RelPath" -OutFile $Dest -UseBasicParsing }
}

$cli = Join-Path $BinDir 'claude-autonomous.ps1'
Write-Host "-> installing the command in $BinDir"
Fetch 'bin/claude-autonomous.ps1' $cli
# harvest and vault are Python and shared across platforms; the CLI finds them
# next to itself.
Fetch 'bin/harvest.py' (Join-Path $BinDir 'harvest.py')
Fetch 'bin/vault.py'   (Join-Path $BinDir 'vault.py')

if ($IsWindows) {
    # A .cmd shim so `claude-autonomous` works from cmd.exe and from anything
    # that resolves commands through PATHEXT, not just from PowerShell.
    $shim = Join-Path $BinDir 'claude-autonomous.cmd'
    @"
@echo off
pwsh -NoLogo -NoProfile -File "%~dp0claude-autonomous.ps1" %*
"@ | Set-Content -Path $shim -Encoding ascii

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$BinDir*") {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
        Write-Host "   added $BinDir to your user PATH (new terminals will see it)"
    }
} else {
    if (":$env:PATH:" -notlike "*:$BinDir`:*") {
        Write-Host "   note: $BinDir is not on your PATH. Add it to your shell profile."
    }
}

Write-Host "-> installing the skill in $SkillDir"
Fetch 'skill/SKILL.md' (Join-Path $SkillDir 'SKILL.md')

Write-Host ''
Write-Host '-> applying the settings'
& pwsh -NoLogo -NoProfile -File $cli on

Write-Host ''
& pwsh -NoLogo -NoProfile -File $cli status

Write-Host @'

Two things the installer cannot do for you:

  1. Restart your Claude Code session. The permission mode is read at startup.

  2. Grant the OS permissions the first time each is used.
     Windows: UAC still gates anything needing elevation.
     macOS:   System Settings -> Privacy & Security -> Screen Recording,
              Accessibility, Automation, Files and Folders.

To undo everything:  claude-autonomous off
'@
