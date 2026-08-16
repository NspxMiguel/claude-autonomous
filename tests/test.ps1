# Exercises bin/claude-autonomous.ps1 against a throwaway CLAUDE_CONFIG_DIR.
# Runs on any platform PowerShell 7 supports; the secret tests are skipped
# where no keychain backend exists.
#
#   pwsh tests/test.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$CA   = Join-Path $PSScriptRoot '..' 'bin' 'claude-autonomous.ps1'
$Work = Join-Path ([System.IO.Path]::GetTempPath()) "ca-test-$PID"
$env:CLAUDE_CONFIG_DIR = $Work
New-Item -ItemType Directory -Force -Path $Work | Out-Null

$script:pass = 0; $script:fail = 0
function Ok([string]$m)  { $script:pass++; Write-Host "  OK     $m" }
function Bad([string]$m) { $script:fail++; Write-Host "  FALHOU $m" }
function Check([string]$m, [bool]$cond) { if ($cond) { Ok $m } else { Bad $m } }
function Cfg { Get-Content (Join-Path $Work 'settings.json') -Raw | ConvertFrom-Json -AsHashtable }
# Native-command call, not a wrapper function: a PowerShell function strips a
# bare `--` from its arguments and does not forward pipeline input to a child
# process, so both the passthrough and `secret import` tests need the real
# invocation shape a user would type.
$PW = (Get-Command pwsh).Source
function Run { & $PW -NoLogo -NoProfile -File $CA @args }

Write-Host "=== plataforma: $(if($IsWindows){'Windows'}elseif($IsMacOS){'macOS'}else{'Linux'}) / PS $($PSVersionTable.PSVersion) ==="
Write-Host ''

# --- merge preserva o que nao e nosso ------------------------------------
@{
    theme = 'light'
    permissions = @{ allow = @('Bash(git *)'); deny = @('Bash(rm -rf /)') }
    env = @{ MEU_VAR = 'preservar' }
    hooks = @{ PostToolUse = @(@{ matcher='Write'; hooks=@(@{ type='command'; command='echo oi' }) }) }
} | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Work 'settings.json')

Write-Host 'on / merge'
Run on | Out-Null
$c = Cfg
Check 'theme preservado'            ($c.theme -eq 'light')
Check 'env do usuario preservado'   ($c.env.MEU_VAR -eq 'preservar')
Check 'PostToolUse preservado'      ($c.hooks.ContainsKey('PostToolUse'))
Check 'allow anterior preservado'   ($c.permissions.allow -contains 'Bash(git *)')
Check 'deny zerado'                 (@($c.permissions.deny).Count -eq 0)
Check 'modo bypassPermissions'      ($c.permissions.defaultMode -eq 'bypassPermissions')
Check 'hook instalado'              (@($c.hooks.PreToolUse).Count -ge 1)
Check 'doneMeansMerged'             ($c.doneMeansMerged -eq $true)
Check 'effortLevel high'            ($c.effortLevel -eq 'high')
Check 'HOME no escopo'              ($c.permissions.additionalDirectories -contains $HOME)

Write-Host ''
Write-Host 'idempotencia'
Run on | Out-Null; Run on | Out-Null
Check 'hook nao duplica'            (@((Cfg).hooks.PreToolUse).Count -eq 1)

Write-Host ''
Write-Host 'status / exit codes'
Run status | Out-Null
Check 'status ON sai 0'             ($LASTEXITCODE -eq 0)
Run off | Out-Null
$c = Cfg
Check 'off volta pra default'       ($c.permissions.defaultMode -eq 'default')
Check 'off remove nosso hook'       (-not $c.ContainsKey('hooks') -or -not $c.hooks.ContainsKey('PreToolUse') -or @($c.hooks.PreToolUse).Count -eq 0)
Check 'off preserva PostToolUse'    ($c.hooks.ContainsKey('PostToolUse'))
Check 'off remove os extras'        (-not $c.ContainsKey('doneMeansMerged'))
Check 'off preserva theme'          ($c.theme -eq 'light')
Run status | Out-Null
Check 'status OFF sai 1'            ($LASTEXITCODE -eq 1)
Run on | Out-Null
Run status | Out-Null
Check 'status ON de novo sai 0'     ($LASTEXITCODE -eq 0)

Write-Host ''
Write-Host 'compatibilidade com o script bash'
$bash = Join-Path $PSScriptRoot '..' 'bin' 'claude-autonomous'
if (-not $IsWindows -and (Test-Path $bash)) {
    $out = & bash $bash status 2>&1 | Out-String
    Check 'bash reconhece o hook do PowerShell' ($out -match 'OK\s+auto-approve hook')
    & bash $bash off  | Out-Null
    Run status | Out-Null
    Check 'PowerShell ve o off do bash'         ($LASTEXITCODE -eq 1)
    & bash $bash on   | Out-Null
    Run status | Out-Null
    Check 'PowerShell ve o on do bash'          ($LASTEXITCODE -eq 0)
} else {
    Write-Host '  (pulado: sem bash nesta plataforma)'
}

Write-Host ''
Write-Host 'backups'
Check 'cada run gera um backup'     (@(Get-ChildItem (Join-Path $Work 'backups') -ErrorAction SilentlyContinue).Count -ge 3)

Write-Host ''
Write-Host 'secrets'
$name = 'CA_TEST_PS'; $value = 'gsk_teste_powershell_123456'
$hasBackend = $IsWindows -or $IsMacOS -or (Get-Command secret-tool -ErrorAction SilentlyContinue)
if ($hasBackend) {
    $value | & $PW -NoLogo -NoProfile -File $CA secret import $name | Out-Null
    $names = (Run secret list | Out-String)
    Check 'import gravou'            ($names -match $name)
    Check 'list nao vaza o valor'    (-not ($names -match [regex]::Escape($value)))
    $got = (& $PW -NoLogo -NoProfile -File $CA run $name -- $PW -NoLogo -NoProfile -Command "`$env:$name" | Out-String).Trim()
    Check 'run injetou o valor exato' ($got -eq $value)
    & $PW -NoLogo -NoProfile -File $CA run $name -- $PW -NoLogo -NoProfile -Command 'exit 42' | Out-Null
    Check 'run propaga exit code'    ($LASTEXITCODE -eq 42)
    Run secret rm $name | Out-Null
    Check 'rm apagou'                (-not ((Run secret list | Out-String) -match $name))
    & $PW -NoLogo -NoProfile -File $CA run 'NAO_EXISTE_XYZ' -- $PW -NoLogo -NoProfile -Command 'exit 0' 2>&1 | Out-Null
    Check 'run falha se falta segredo' ($LASTEXITCODE -ne 0)
    & $PW -NoLogo -NoProfile -File $CA secret import 'CA_SEM_PIPE' 2>&1 | Out-Null
    Check 'import sem pipe falha em vez de travar' ($LASTEXITCODE -ne 0)
} else {
    Write-Host '  (pulado: sem backend de chaveiro nesta maquina)'
}

Write-Host ''
Write-Host 'forma por plataforma (as branches do Windows, vistas de qualquer host)'
$win  = (Run __shape windows | Out-String | ConvertFrom-Json -AsHashtable)
$unix = (Run __shape unix    | Out-String | ConvertFrom-Json -AsHashtable)
Check 'Windows usa cmd.exe'          ($win.hook.command -eq 'cmd.exe')
Check 'Windows passa /c echo'        (@($win.hook.args)[0] -eq '/c' -and @($win.hook.args)[1] -eq 'echo')
Check 'Windows leva o marcador'      ((@($win.hook.args) -join '') -like '*claude-autonomous*')
Check 'Unix usa /bin/echo'           ($unix.hook.command -eq '/bin/echo')
Check 'Unix leva o marcador'         ((@($unix.hook.args) -join '') -like '*claude-autonomous*')
Check 'as duas formas tem timeout'   ($win.hook.timeout -eq 5 -and $unix.hook.timeout -eq 5)
Check 'HOME entra no escopo sempre'  (@($win.dirs) -contains $HOME -and @($unix.dirs) -contains $HOME)

Write-Host ''
Write-Host 'regressao: um argumento so nao vira string'
Run secret list | Out-Null
Check 'secret com 1 argumento funciona' ($LASTEXITCODE -eq 0)

Write-Host ''
Write-Host 'nomes invalidos'
Run secret rm '1nome-invalido' 2>&1 | Out-Null
Check 'recusa nome invalido'        ($LASTEXITCODE -ne 0)

Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "$($script:pass) passaram, $($script:fail) falharam"
exit $script:fail
