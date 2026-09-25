# Puts `sandbox` on your PATH on Windows by adding this folder, which holds
# sandbox.cmd, to your user PATH. Safe to run again. Run it with:
#
#   powershell -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

# Edit the registry value itself: [Environment]::GetEnvironmentVariable expands
# entries like %USERPROFILE%\... and SetEnvironmentVariable saves them as a
# plain string, which Windows no longer expands.
$key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
$entries = @($key.GetValue('Path', '', 'DoNotExpandEnvironmentNames') -split ';' | Where-Object { $_ })
$expanded = $entries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') }
if ($expanded -contains $repo) {
    Write-Host "$repo is already on your PATH"
} else {
    $key.SetValue('Path', (($entries + $repo) -join ';'), 'ExpandString')
    # Writing the registry doesn't tell Explorer (which starts new terminals) that
    # the environment changed. Setting any variable through .NET does.
    [Environment]::SetEnvironmentVariable('SANDBOX_CLI_INSTALL', '1', 'User')
    [Environment]::SetEnvironmentVariable('SANDBOX_CLI_INSTALL', $null, 'User')
    Write-Host "Added $repo to your PATH; open a new terminal to use sandbox"
}
$key.Close()

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host 'Note: sandbox needs Docker Desktop, which is not on your PATH (https://docs.docker.com/desktop/setup/install/windows-install/)'
}
# The same Python that sandbox.cmd picks. The Microsoft Store's placeholder
# `python` fails this check, as does a py launcher with no Python installed.
$python = @('py', 'python') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
$pythonOk = $false
if ($python) {
    try {
        & $python -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>$null
        $pythonOk = $LASTEXITCODE -eq 0
    } catch {}
}
if (-not $pythonOk) {
    Write-Host 'Note: sandbox needs Python 3.9 or newer (https://www.python.org/downloads/windows/)'
}
