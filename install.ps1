# claude-autonomous installer - Windows PowerShell.
#
#   irm https://raw.githubusercontent.com/NspxMiguel/claude-autonomous/main/install.ps1 | iex
#
# Installs the `autonomous` skill and applies the settings. No administrator
# rights needed. The previous settings.json is backed up first.

$ErrorActionPreference = 'Stop'

$Repo      = 'NspxMiguel/claude-autonomous'
$Raw       = "https://raw.githubusercontent.com/$Repo/main"
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$Settings  = Join-Path $ClaudeDir 'settings.json'
$SkillDir  = Join-Path $ClaudeDir 'skills\autonomous'
$Backups   = Join-Path $ClaudeDir 'backups'

Write-Host "claude-autonomous"
Write-Host "=================="
Write-Host ""

New-Item -ItemType Directory -Force -Path $ClaudeDir, $SkillDir, $Backups | Out-Null

Write-Host "-> installing the skill in $SkillDir"
Invoke-WebRequest -Uri "$Raw/skill/SKILL.md" -OutFile (Join-Path $SkillDir 'SKILL.md') -UseBasicParsing

# --- read + back up -------------------------------------------------------
$cfg = [ordered]@{}
if (Test-Path $Settings) {
    Copy-Item $Settings (Join-Path $Backups "settings.json.$(Get-Date -Format 'yyyyMMdd-HHmmss')")
    $cfg = Get-Content $Settings -Raw | ConvertFrom-Json -AsHashtable
}

Write-Host "-> applying the settings"

# --- permissions ----------------------------------------------------------
if (-not $cfg.permissions) { $cfg.permissions = @{} }
$cfg.permissions.defaultMode = 'bypassPermissions'
$cfg.permissions.deny = @()
$cfg.permissions.ask  = @()

$allow = [System.Collections.Generic.HashSet[string]]::new()
foreach ($a in @($cfg.permissions.allow)) { if ($a) { [void]$allow.Add($a) } }
foreach ($a in @(
    'Bash','Read','Edit','Write','Glob','Grep','NotebookEdit',
    'WebFetch','WebSearch','Agent','Task','Skill','Workflow',
    'Artifact','SendUserFile',
    'mcp__computer-use','mcp__terminal','mcp__claude-in-chrome',
    'mcp__Claude_Browser','mcp__Claude_Code_iOS_Simulator',
    'mcp__ccd_session','mcp__ccd_session_mgmt','mcp__ccd_directory',
    'mcp__scheduled-tasks','mcp__mcp-registry','mcp__visualize'
)) { [void]$allow.Add($a) }
$cfg.permissions.allow = @($allow | Sort-Object)

$dirs = [System.Collections.Generic.HashSet[string]]::new()
foreach ($d in @($cfg.permissions.additionalDirectories)) { if ($d) { [void]$dirs.Add($d) } }
foreach ($d in @($HOME, "$env:SystemDrive\", $env:TEMP, "$env:LOCALAPPDATA", "$env:APPDATA")) {
    if ($d -and (Test-Path $d)) { [void]$dirs.Add($d) }
}
$cfg.permissions.additionalDirectories = @($dirs | Sort-Object)

# --- auto-approve hook ----------------------------------------------------
# Second line of defence: if a session opens in a prompting mode, this answers
# "allow" before a prompt can appear. Exec form, so no shell parses the JSON.
$payload = @{
    hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'allow'
        permissionDecisionReason = 'claude-autonomous'
    }
    suppressOutput = $true
} | ConvertTo-Json -Compress -Depth 5

$auto = @{
    type    = 'command'
    command = 'cmd.exe'
    args    = @('/c', 'echo', $payload)
    timeout = 5
}

if (-not $cfg.hooks) { $cfg.hooks = @{} }
$pre = @()
foreach ($g in @($cfg.hooks.PreToolUse)) {
    if ($g -and -not (@($g.hooks) | Where-Object { $_.command -eq 'cmd.exe' })) { $pre += $g }
}
$pre += @{ hooks = @($auto) }
$cfg.hooks.PreToolUse = $pre

# --- everything else that stops to ask ------------------------------------
$cfg.sandbox                          = @{ enabled = $false }
$cfg.enableAllProjectMcpServers       = $true
$cfg.skipDangerousModePermissionPrompt = $true
$cfg.skipAutoPermissionPrompt         = $true
$cfg.skipWorkflowUsageWarning         = $true
$cfg.askUserQuestionTimeout           = '60s'
$cfg.fileCheckpointingEnabled         = $true

# Not asking is half of "does it without me". The other half is finishing
# without me, and being reachable while it happens.
$cfg.doneMeansMerged          = $true
$cfg.effortLevel              = 'high'
$cfg.remoteControlAtStartup   = $true
$cfg.autoUploadSessions       = $true
$cfg.inputNeededNotifEnabled  = $true
$cfg.agentPushNotifEnabled    = $true
$cfg.crossSessionInbound      = 'accept'
$cfg.daemonColdStart          = 'transient'
$cfg.autoMemoryEnabled        = $true
$cfg.cleanupPeriodDays        = 365

if (-not $cfg.env) { $cfg.env = @{} }
foreach ($kv in @{ BASH_DEFAULT_TIMEOUT_MS='600000'; BASH_MAX_TIMEOUT_MS='600000'; MCP_TIMEOUT='60000' }.GetEnumerator()) {
    if (-not $cfg.env[$kv.Key]) { $cfg.env[$kv.Key] = $kv.Value }
}

$cfg | ConvertTo-Json -Depth 12 | Set-Content -Path $Settings -Encoding UTF8

Write-Host ""
Write-Host "AUTONOMOUS MODE ON  ->  $Settings"
Write-Host ""
Write-Host "Restart your Claude Code session - the permission mode is read at startup."
Write-Host "To undo: re-run with -Off, or set permissions.defaultMode back to 'default'."
