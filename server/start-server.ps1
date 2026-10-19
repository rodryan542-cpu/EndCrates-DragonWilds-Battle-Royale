param(
    [Parameter(Mandatory=$true)][string]$ServerExe,
    [ValidateRange(20,1024)][int]$Slots=100,
    [ValidateRange(1024,65535)][int]$Port=7777
)
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $ServerExe -PathType Leaf)) { throw 'Select the installed Windows dedicated-server executable.' }
$serverPath=(Resolve-Path -LiteralPath $ServerExe).ProviderPath
if ([IO.Path]::GetExtension($serverPath) -ne '.exe') { throw 'A Windows server executable is required.' }
Write-Host 'The GameSession override is experimental. Verify real player admission and UE4SS loading.'
$serverArguments=@('-log','-NewConsole',('-Port='+$Port),('-ini:Game:[/Script/Engine.GameSession]:MaxPlayers='+$Slots))
Start-Process -FilePath $serverPath -WorkingDirectory ([IO.Path]::GetDirectoryName($serverPath)) -ArgumentList $serverArguments -WindowStyle Normal
