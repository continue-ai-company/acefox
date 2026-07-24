[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunnerUrl,

    [Parameter(Mandatory = $true)]
    [string]$RunnerToken,

    [Parameter(Mandatory = $true)]
    [string]$RunnerName,

    [Parameter(Mandatory = $true)]
    [string]$RunnerLabels,

    [string]$RunnerGroup = '',

    [string]$WorkDirectory = '_work'
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Run from an Administrator PowerShell session so the runner can be installed as a service.'
}

$runnerConfig = Join-Path (Get-Location) 'config.cmd'
if (-not (Test-Path -LiteralPath $runnerConfig)) {
    throw 'config.cmd is missing. Run this script from the extracted C:\actions-runner directory.'
}

if (Test-Path -LiteralPath (Join-Path (Get-Location) '.runner')) {
    throw 'This runner directory is already configured. Remove or replace it in GitHub before re-registering.'
}

# Do not write or print $RunnerToken. config.cmd stores only the credential
# required by the GitHub Actions runner service.
$configArguments = @(
    '--unattended'
    '--url', $RunnerUrl
    '--token', $RunnerToken
    '--name', $RunnerName
    '--labels', $RunnerLabels
    '--work', $WorkDirectory
)

if ($RunnerGroup) {
    $configArguments += @('--runnergroup', $RunnerGroup)
}

$configArguments += '--runasservice'

& $runnerConfig @configArguments

if ($LASTEXITCODE -ne 0) {
    throw "Runner registration failed with exit code $LASTEXITCODE."
}

Get-Service 'actions.runner*' | Format-Table -AutoSize
Write-Host "Runner '$RunnerName' is registered as a Windows service."
