# claude-autonomous — turn permission prompts off in Claude Code, and back on.
#
#   claude-autonomous on | off | status | doctor
#   claude-autonomous secret list | set NAME | import NAME | rm NAME
#   claude-autonomous run NAME[,NAME] -- command [args...]
#
# PowerShell port of bin/claude-autonomous. Same settings, same on-disk shape,
# so a machine can be managed from either script. Needs PowerShell 7+.

#Requires -Version 7.0

# No param() block on purpose. `run NAME -- cmd -flag` passes arguments through
# to another program, and a param block would let PowerShell's binder claim
# anything starting with a dash — turning `-Command` into a parameter of this
# script instead of an argument to the child. Reading $args raw keeps the
# passthrough literal.
# Two PowerShell traps here, both of which silently produce a string where an
# array is meant:
#   - $args is a scalar when there is exactly one argument, so wrap it in @().
#   - `$x = if (...) { @(one item) }` unrolls the array back to a scalar,
#     because the if block emits to the pipeline. Assign directly instead.
$argv = @($args)
$Command = 'status'
if ($argv.Count -gt 0) { $Command = [string]$argv[0] }
$Rest = @()
if ($argv.Count -gt 1) { $Rest = @($argv[1..($argv.Count - 1)]) }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:VERSION = '1.7.0'
$script:MARKER  = 'claude-autonomous'

$script:ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR }
                    else { Join-Path $HOME '.claude' }
$script:Settings  = Join-Path $script:ClaudeDir 'settings.json'
$script:Backups   = Join-Path $script:ClaudeDir 'backups'

function Die([string] $Message) { Write-Error $Message; exit 1 }

# --------------------------------------------------------------------------
# settings file
# --------------------------------------------------------------------------

function Read-Settings {
    if (-not (Test-Path $script:Settings)) { return @{} }
    $raw = Get-Content $script:Settings -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    try { return $raw | ConvertFrom-Json -AsHashtable }
    catch { Die "$($script:Settings) is not valid JSON ($_). Fix it and re-run." }
}

function Write-Settings([hashtable] $Cfg) {
    $dir = Split-Path $script:Settings -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Cfg | ConvertTo-Json -Depth 20 | Set-Content -Path $script:Settings -Encoding utf8NoBOM
}

function Backup-Settings {
    if (-not (Test-Path $script:Settings)) { return }
    if (-not (Test-Path $script:Backups)) { New-Item -ItemType Directory -Force -Path $script:Backups | Out-Null }
    # Timestamp plus pid, so two runs in the same second keep both backups.
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID"
    Copy-Item $script:Settings (Join-Path $script:Backups "settings.json.$stamp")
}

# Our auto-approve hook, however this platform spells `echo`. Matching on the
# marker inside the payload rather than the command keeps the bash and
# PowerShell scripts able to recognise each other's work.
function Test-OurHook($Group) {
    foreach ($h in @($Group.hooks)) {
        if ($null -eq $h) { continue }
        $argText = ''
        if ($h.ContainsKey('args') -and $h.args) { $argText = ($h.args -join '') }
        $cmdText = if ($h.ContainsKey('command')) { [string]$h.command } else { '' }
        if ($argText -like "*$($script:MARKER)*" -or $cmdText -like "*$($script:MARKER)*") { return $true }
    }
    return $false
}

# $Platform lets the test suite exercise the Windows shape from any host. The
# only Windows code left untested by that is the DPAPI call itself.
function New-AutoApproveHook([string] $Platform = '') {
    if (-not $Platform) { $Platform = if ($IsWindows) { 'windows' } else { 'unix' } }
    $payload = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'allow'
            permissionDecisionReason = $script:MARKER
        }
        suppressOutput = $true
    } | ConvertTo-Json -Compress -Depth 5

    # Exec form: no shell parses the JSON payload.
    if ($Platform -eq 'windows') { $cmd = 'cmd.exe';   $cmdArgs = @('/c', 'echo', $payload) }
    else                         { $cmd = '/bin/echo'; $cmdArgs = @($payload) }

    return @{ type = 'command'; command = $cmd; args = $cmdArgs; timeout = 5 }
}

function Get-ScopeDirectories([string] $Platform = '') {
    if (-not $Platform) { $Platform = if ($IsWindows) { 'windows' } else { 'unix' } }
    $dirs = [System.Collections.Generic.List[string]]::new()
    $dirs.Add($HOME)
    $candidates = if ($Platform -eq 'windows') {
        @("$env:SystemDrive\", $env:TEMP, $env:LOCALAPPDATA, $env:APPDATA, $env:ProgramData)
    } else {
        @('/Applications', '/Volumes', '/opt', '/usr/local', '/private/tmp', '/tmp', '/srv', '/mnt')
    }
    foreach ($d in $candidates) {
        # A path is kept when it exists, or when we are shaping the list for a
        # platform we are not running on (the test suite's case).
        $hostPlatform = if ($IsWindows) { 'windows' } else { 'unix' }
        $onHost = ($Platform -eq $hostPlatform)
        if ($d -and (-not $onHost -or (Test-Path $d)) -and -not $dirs.Contains($d)) { $dirs.Add($d) }
    }
    return ($dirs | Sort-Object -Unique)
}

function Invoke-On {
    Backup-Settings
    $cfg = Read-Settings

    if (-not $cfg.ContainsKey('permissions')) { $cfg['permissions'] = @{} }
    $p = $cfg['permissions']
    $p['defaultMode'] = 'bypassPermissions'
    $p['deny'] = @()
    $p['ask']  = @()

    $allow = [System.Collections.Generic.HashSet[string]]::new()
    if ($p.ContainsKey('allow')) { foreach ($a in @($p['allow'])) { if ($a) { [void]$allow.Add([string]$a) } } }
    foreach ($a in @(
        'Bash','Read','Edit','Write','Glob','Grep','NotebookEdit',
        'WebFetch','WebSearch','Agent','Task','Skill','Workflow',
        'Artifact','SendUserFile',
        'mcp__computer-use','mcp__terminal','mcp__claude-in-chrome',
        'mcp__Claude_Browser','mcp__Claude_Code_iOS_Simulator',
        'mcp__ccd_session','mcp__ccd_session_mgmt','mcp__ccd_directory',
        'mcp__scheduled-tasks','mcp__mcp-registry','mcp__visualize'
    )) { [void]$allow.Add($a) }
    $p['allow'] = @($allow | Sort-Object)
    $p['additionalDirectories'] = @(Get-ScopeDirectories)

    if (-not $cfg.ContainsKey('hooks')) { $cfg['hooks'] = @{} }
    $hooks = $cfg['hooks']
    $pre = @()
    if ($hooks.ContainsKey('PreToolUse')) {
        foreach ($g in @($hooks['PreToolUse'])) { if ($g -and -not (Test-OurHook $g)) { $pre += $g } }
    }
    $pre += @{ hooks = @(New-AutoApproveHook) }
    $hooks['PreToolUse'] = @($pre)

    $cfg['sandbox']                          = @{ enabled = $false }
    $cfg['enableAllProjectMcpServers']       = $true
    $cfg['skipDangerousModePermissionPrompt']= $true
    $cfg['skipAutoPermissionPrompt']         = $true
    $cfg['skipWorkflowUsageWarning']         = $true
    $cfg['askUserQuestionTimeout']           = '60s'
    $cfg['fileCheckpointingEnabled']         = $true

    # Not asking is half of "does it without me". The other half is finishing
    # without me, and staying reachable while it happens.
    $cfg['doneMeansMerged']         = $true
    $cfg['effortLevel']             = 'high'
    $cfg['remoteControlAtStartup']  = $true
    $cfg['autoUploadSessions']      = $true
    $cfg['inputNeededNotifEnabled'] = $true
    $cfg['agentPushNotifEnabled']   = $true
    $cfg['crossSessionInbound']     = 'accept'
    $cfg['daemonColdStart']         = 'transient'
    $cfg['autoMemoryEnabled']       = $true
    $cfg['cleanupPeriodDays']       = 365

    if (-not $cfg.ContainsKey('env')) { $cfg['env'] = @{} }
    foreach ($kv in @{ BASH_DEFAULT_TIMEOUT_MS='600000'
                       BASH_MAX_TIMEOUT_MS='600000'
                       MCP_TIMEOUT='60000' }.GetEnumerator()) {
        if (-not $cfg['env'].ContainsKey($kv.Key)) { $cfg['env'][$kv.Key] = $kv.Value }
    }

    Write-Settings $cfg
    Write-Host "autonomous mode ON  ->  $($script:Settings)"
    Write-Host ''
    Write-Host 'Restart your Claude Code session — the permission mode is read at startup.'
}

function Invoke-Off {
    if (-not (Test-Path $script:Settings)) { Die "nothing to turn off: $($script:Settings) does not exist" }
    Backup-Settings
    $cfg = Read-Settings

    if (-not $cfg.ContainsKey('permissions')) { $cfg['permissions'] = @{} }
    $cfg['permissions']['defaultMode'] = 'default'
    $cfg['permissions'].Remove('additionalDirectories')

    if ($cfg.ContainsKey('hooks')) {
        $hooks = $cfg['hooks']
        if ($hooks.ContainsKey('PreToolUse')) {
            $pre = @()
            foreach ($g in @($hooks['PreToolUse'])) { if ($g -and -not (Test-OurHook $g)) { $pre += $g } }
            if ($pre.Count -gt 0) { $hooks['PreToolUse'] = @($pre) } else { $hooks.Remove('PreToolUse') }
        }
        if ($hooks.Count -eq 0) { $cfg.Remove('hooks') }
    }

    $cfg['askUserQuestionTimeout'] = 'never'
    foreach ($k in @('doneMeansMerged','remoteControlAtStartup','autoUploadSessions',
                     'crossSessionInbound','agentPushNotifEnabled',
                     'inputNeededNotifEnabled','daemonColdStart','effortLevel')) {
        $cfg.Remove($k)
    }

    Write-Settings $cfg
    Write-Host "autonomous mode OFF  ->  $($script:Settings)"
    Write-Host 'the allow list is left in place — it only avoids repeat prompts, it does not grant anything on its own'
}

function Invoke-Status {
    if (-not (Test-Path $script:Settings)) { Die "no settings file at $($script:Settings) — run: claude-autonomous on" }
    $cfg = Read-Settings
    $p = if ($cfg.ContainsKey('permissions')) { $cfg['permissions'] } else { @{} }

    $hook = $false
    if ($cfg.ContainsKey('hooks') -and $cfg['hooks'].ContainsKey('PreToolUse')) {
        foreach ($g in @($cfg['hooks']['PreToolUse'])) { if ($g -and (Test-OurHook $g)) { $hook = $true } }
    }
    function Val($h, $k) { if ($h.ContainsKey($k)) { $h[$k] } else { $null } }

    $sandbox = if ($cfg.ContainsKey('sandbox') -and $cfg['sandbox'].ContainsKey('enabled')) {
        $cfg['sandbox']['enabled'] } else { $false }

    $checks = @(
        @{ n='permission mode';       got=(Val $p 'defaultMode');                     want='bypassPermissions' }
        @{ n='auto-approve hook';     got=$(if ($hook) {'yes'} else {'no'});           want='yes' }
        @{ n='deny rules';            got=@(Val $p 'deny').Count;                      want=0 }
        @{ n='ask rules';             got=@(Val $p 'ask').Count;                       want=0 }
        @{ n='dangerous-mode dialog'; got=(Val $cfg 'skipDangerousModePermissionPrompt'); want=$true }
        @{ n='sandbox';               got=$sandbox;                                    want=$false }
        @{ n='file checkpointing';    got=(Val $cfg 'fileCheckpointingEnabled');       want=$true }
        @{ n="finish, don't report";  got=(Val $cfg 'doneMeansMerged');                want=$true }
        @{ n='effort';                got=(Val $cfg 'effortLevel');                    want='high' }
        @{ n='remote control';        got=(Val $cfg 'remoteControlAtStartup');         want=$true }
        @{ n='push notifications';    got=(Val $cfg 'agentPushNotifEnabled');          want=$true }
        @{ n='inbound from sessions'; got=(Val $cfg 'crossSessionInbound');            want='accept' }
    )

    $w = ($checks | ForEach-Object { $_.n.Length } | Measure-Object -Maximum).Maximum
    $bad = 0
    foreach ($c in $checks) {
        $ok = ($c.got -eq $c.want)
        if (-not $ok) { $bad++ }
        $tag = if ($ok) { 'OK ' } else { '-- ' }
        Write-Host ("{0} {1}  {2}" -f $tag, $c.n.PadRight($w), $c.got)
    }

    $dirs = @(Val $p 'additionalDirectories')
    $dirText = if ($dirs.Count) { $dirs -join ', ' } else { 'project only' }
    Write-Host ''
    Write-Host "directories in scope ($($dirs.Count)): $dirText"
    Write-Host "allow rules: $(@(Val $p 'allow').Count)"
    Write-Host ''
    if ($bad -eq 0) { Write-Host 'AUTONOMOUS MODE ON'; exit 0 }
    else { Write-Host "INCOMPLETE — $bad item(s) off; run: claude-autonomous on"; exit 1 }
}

# --------------------------------------------------------------------------
# secrets
#
# The value goes to the command, never through a transcript. On Windows it is
# encrypted with DPAPI, which ties it to this Windows user account — no key
# file exists to be copied elsewhere. On macOS and Linux it goes to the same
# keychain the bash script uses, so both scripts see the same secrets.
# --------------------------------------------------------------------------

$script:SecretDir = if ($IsWindows) {
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'claude-autonomous\secrets'
} else { $null }

function Set-Secret([string] $Name, [string] $Value) {
    if ($IsWindows) {
        if (-not (Test-Path $script:SecretDir)) { New-Item -ItemType Directory -Force -Path $script:SecretDir | Out-Null }
        $enc = ConvertTo-SecureString -String $Value -AsPlainText -Force | ConvertFrom-SecureString
        Set-Content -Path (Join-Path $script:SecretDir "$Name.cred") -Value $enc -Encoding ascii
    } elseif ($IsMacOS) {
        & security add-generic-password -U -a $env:USER -s "$($script:MARKER):$Name" `
            -w $Value -D 'claude-autonomous secret' 2>&1 | Out-Null
    } else {
        $Value | & secret-tool store --label="$($script:MARKER):$Name" service $script:MARKER key $Name 2>&1 | Out-Null
    }

    # Read back. A backend can fail without a clean exit code, and reporting
    # success for a value that is not there is the worst outcome.
    if ((Get-Secret $Name) -ne $Value) {
        Die "could not store $Name — the keychain read back empty or different."
    }
}

function Get-Secret([string] $Name) {
    try {
        if ($IsWindows) {
            $f = Join-Path $script:SecretDir "$Name.cred"
            if (-not (Test-Path $f)) { return $null }
            $sec = Get-Content $f -Raw | ConvertTo-SecureString
            return [System.Net.NetworkCredential]::new('', $sec).Password
        } elseif ($IsMacOS) {
            $v = & security find-generic-password -a $env:USER -s "$($script:MARKER):$Name" -w 2>$null
            if ($LASTEXITCODE -ne 0) { return $null }
            return $v
        } else {
            $v = & secret-tool lookup service $script:MARKER key $Name 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($v)) { return $null }
            return $v
        }
    } catch { return $null }
}

function Get-SecretNames {
    if ($IsWindows) {
        if (-not (Test-Path $script:SecretDir)) { return @() }
        return @(Get-ChildItem $script:SecretDir -Filter '*.cred' | ForEach-Object { $_.BaseName } | Sort-Object)
    } elseif ($IsMacOS) {
        $dump = & security dump-keychain 2>$null | Out-String
        $rx = [regex]::new('"svce"<blob>="' + [regex]::Escape($script:MARKER) + ':([^"]*)"')
        return @($rx.Matches($dump) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    } else {
        # Only attribute.key lines. secret-tool also prints `secret = ...`
        # with the value itself, so this pattern must stay exact.
        $out = & secret-tool search --all service $script:MARKER 2>&1 | Out-String
        return @([regex]::Matches($out, '(?m)^attribute\.key = (.+)$') |
                 ForEach-Object { $_.Groups[1].Value.Trim() } | Sort-Object -Unique)
    }
}

function Remove-Secret([string] $Name) {
    if ($IsWindows) {
        $f = Join-Path $script:SecretDir "$Name.cred"
        if (Test-Path $f) { Remove-Item $f -Force }
    } elseif ($IsMacOS) {
        & security delete-generic-password -a $env:USER -s "$($script:MARKER):$Name" 2>&1 | Out-Null
    } else {
        & secret-tool clear service $script:MARKER key $Name 2>&1 | Out-Null
    }
}

function Assert-ValidName([string] $Name) {
    if (-not $Name) { Die 'usage: claude-autonomous secret <set|import|rm> NAME' }
    if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        Die 'NAME must be a valid environment variable name'
    }
}

# NOTE: the parameter cannot be named $Args — that is a reserved automatic
# variable inside every function, and it silently shadows what is passed in.
function Invoke-Secret([string[]] $Arguments) {
    $sub = if ($Arguments.Count -gt 0) { $Arguments[0] } else { 'list' }
    switch ($sub) {
        'set' {
            $name = if ($Arguments.Count -gt 1) { $Arguments[1] } else { '' }
            Assert-ValidName $name
            $sec = Read-Host -AsSecureString -Prompt "value for $name (input hidden)"
            $v = [System.Net.NetworkCredential]::new('', $sec).Password
            if (-not $v) { Die 'empty, nothing stored' }
            Set-Secret $name $v
            Write-Host "stored $name"
        }
        'import' {
            $name = if ($Arguments.Count -gt 1) { $Arguments[1] } else { '' }
            Assert-ValidName $name
            # Without this guard ReadToEnd blocks forever on an interactive
            # console, which reads as a hang rather than a mistake.
            if (-not [Console]::IsInputRedirected) {
                Die 'secret import expects a pipe. To type one in, use: secret set NAME'
            }
            # Read stdin directly. $input is only populated for a function in a
            # pipeline, which this is not when invoked via -File.
            $v = [Console]::In.ReadToEnd()
            if ($null -eq $v) { $v = '' }
            $v = $v.Trim()
            if (-not $v) { Die 'nothing on stdin, nothing stored' }
            Set-Secret $name $v
            Write-Host "stored $name ($($v.Length) characters)"
        }
        { $_ -in 'rm', 'remove', 'delete' } {
            $name = if ($Arguments.Count -gt 1) { $Arguments[1] } else { '' }
            Assert-ValidName $name
            Remove-Secret $name
            Write-Host "removed $name"
        }
        default {
            $names = Get-SecretNames
            $names = @($names)
            if ($names.Count -eq 0) {
                Write-Host 'no secrets stored. add one with: claude-autonomous secret set NAME'
            } else {
                Write-Host 'stored secrets (names only):'
                $names | ForEach-Object { Write-Host "  $_" }
            }
        }
    }
}

function Invoke-Run([string[]] $Arguments) {
    if ($Arguments.Count -lt 1) { Die 'usage: claude-autonomous run NAME[,NAME] -- command [args...]' }
    $names = $Arguments[0] -split ','
    $rest  = @($Arguments[1..($Arguments.Count - 1)])
    if ($rest.Count -gt 0 -and $rest[0] -eq '--') { $rest = @($rest[1..($rest.Count - 1)]) }
    if ($rest.Count -lt 1) { Die 'usage: claude-autonomous run NAME[,NAME] -- command [args...]' }

    $missing = @()
    foreach ($n in $names) {
        $n = $n.Trim()
        if (-not $n) { continue }
        $v = Get-Secret $n
        # Set into this process's environment, which the child inherits. Never
        # onto the command line, where any user could read it out of the
        # process list.
        if ($v) { Set-Item -Path "Env:$n" -Value $v } else { $missing += $n }
    }
    if ($missing.Count -gt 0) {
        Die "not stored: $($missing -join ', ')  (add with: claude-autonomous secret set NAME)"
    }

    $exe = $rest[0]
    $rest2 = if ($rest.Count -gt 1) { @($rest[1..($rest.Count - 1)]) } else { @() }
    & $exe @rest2
    exit $LASTEXITCODE
}

# harvest and vault are one Python implementation shared by both CLIs, so a
# machine managed from either script behaves identically.
function Invoke-Helper([string] $Script, [string[]] $Arguments) {
    $here = Split-Path -Parent $PSCommandPath
    $path = Join-Path $here $Script
    if (-not (Test-Path $path)) { Die "$Script is not next to the CLI (expected $path)" }
    $py = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $py) { Die "$Script needs Python 3 on PATH" }
    $env:CLAUDE_AUTONOMOUS_CLI = $PSCommandPath
    & $py.Source $path @Arguments
    exit $LASTEXITCODE
}

function Invoke-Doctor {
    Write-Host 'toolchain'
    foreach ($t in @('python3','git','gh','curl','node','claude','pwsh')) {
        $c = Get-Command $t -ErrorAction SilentlyContinue
        if ($c) { Write-Host ("  OK  {0} {1}" -f $t.PadRight(8), $c.Source) }
        else    { Write-Host ("  --  {0} not found" -f $t.PadRight(8)) }
    }

    Write-Host ''
    Write-Host 'authenticated CLIs (these do the work without the secret being read)'
    foreach ($pair in @(@('gh','auth','status'), @('vercel','whoami'),
                        @('supabase','projects','list'), @('firebase','projects:list'),
                        @('pass-cli','info'))) {
        $bin = $pair[0]
        if (-not (Get-Command $bin -ErrorAction SilentlyContinue)) {
            Write-Host ("      {0} not installed" -f $bin.PadRight(10)); continue
        }
        & $bin @($pair[1..($pair.Count - 1)]) *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host ("  OK  {0} signed in" -f $bin.PadRight(10)) }
        else { Write-Host ("  --  {0} installed, not signed in" -f $bin.PadRight(10)) }
    }

    Write-Host ''
    Write-Host 'stored secrets'
    $names = @(Get-SecretNames)
    if ($names.Count -gt 0) { $names | ForEach-Object { Write-Host "  OK  $_" } }
    else { Write-Host '  --  none (claude-autonomous secret set NAME)' }

    if ($IsWindows) {
        Write-Host ''
        Write-Host 'Windows'
        Write-Host "  secrets are DPAPI-encrypted under $($script:SecretDir)"
        Write-Host '  they are readable only by this Windows user on this machine'
        Write-Host '  UAC still gates anything needing elevation; no settings file changes that'
    }

    Write-Host ''
    Invoke-Status
}

function Show-Usage {
    @'
claude-autonomous — turn permission prompts off in Claude Code, and back on.

  on                              apply the autonomous settings
  off                             restore prompting
  status                          show what is actually set right now
  doctor                          settings + toolchain + secrets

  secret list                     stored secret names (never values)
  secret set NAME                 store one, typed in, hidden
  secret import NAME              store one from stdin, never echoed
  secret rm NAME                  remove one
  harvest [--apply]               find keys already on this machine, store them
  import-csv FILE [--apply]       import a password-manager CSV export
  proton-seed FILE [--apply]      copy a CSV export into a Proton Pass vault
  vault                           open a local page to paste keys into
  run NAME[,NAME] -- cmd ...      run cmd with those secrets in its environment

`run` is the point: the command receives the credential, the agent that wrote
the command does not, and the value never enters a transcript.
'@ | Write-Host
}

switch ($Command) {
    '__shape' {
        # Internal, for tests: print the platform-specific shapes as JSON so the
        # Windows branches can be asserted from a macOS or Linux host.
        $plat = if ($Rest.Count -gt 0) { $Rest[0] } else { 'unix' }
        @{ hook = (New-AutoApproveHook $plat)
           dirs = @(Get-ScopeDirectories $plat) } | ConvertTo-Json -Depth 8 -Compress | Write-Host
    }
    { $_ -in 'on','enable' }   { Invoke-On }
    { $_ -in 'off','disable' } { Invoke-Off }
    { $_ -in 'status','' }     { Invoke-Status }
    'doctor'                   { Invoke-Doctor }
    'harvest'                  { Invoke-Helper 'harvest.py' $Rest }
    'import-csv'               { Invoke-Helper 'import_csv.py' $Rest }
    'proton-seed'              { Invoke-Helper 'csv_to_proton.py' $Rest }
    'vault'                    { Invoke-Helper 'vault.py'   $Rest }
    { $_ -in 'secret','secrets' } { Invoke-Secret $Rest }
    'run'                      { Invoke-Run $Rest }
    { $_ -in '-v','--version' }{ Write-Host "claude-autonomous $($script:VERSION)" }
    { $_ -in '-h','--help' }   { Show-Usage }
    default { Show-Usage; Die "unknown command: $Command" }
}
