# registrar_watcher.ps1  v3.0
# ─────────────────────────────────────────────────────────────────────────────
# Usa pythonw.exe (sem console) para manter o processo vivo em background.
#
# Uso:
#   cd C:\Users\djast
#   powershell -ExecutionPolicy Bypass -File .\registrar_watcher.ps1
# ─────────────────────────────────────────────────────────────────────────────

$TaskName    = "LegoDocWatcher"
$ScriptsDir  = "C:\Users\djast"
$WatcherScript = Join-Path $ScriptsDir "watch_documentacao.py"

# Localiza pythonw.exe na mesma pasta do python.exe
$PythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $PythonExe) {
    Write-Host "ERRO: Python nao encontrado no PATH." -ForegroundColor Red
    exit 1
}
$PythonwExe = Join-Path (Split-Path $PythonExe) "pythonw.exe"
if (-not (Test-Path $PythonwExe)) {
    Write-Host "ERRO: pythonw.exe nao encontrado em: $PythonwExe" -ForegroundColor Red
    exit 1
}

# Verifica se o watcher existe
if (-not (Test-Path $WatcherScript)) {
    Write-Host "ERRO: Arquivo nao encontrado: $WatcherScript" -ForegroundColor Red
    exit 1
}

# Remove tarefa anterior se existir
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Tarefa anterior removida."
}

# pythonw.exe roda sem janela e sem console — processo fica vivo em background
$Action = New-ScheduledTaskAction `
    -Execute $PythonwExe `
    -Argument "`"$WatcherScript`"" `
    -WorkingDirectory $ScriptsDir

$Trigger = New-ScheduledTaskTrigger -AtLogOn

$Principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive `
    -RunLevel Limited

$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName   $TaskName `
    -Action     $Action `
    -Trigger    $Trigger `
    -Principal  $Principal `
    -Settings   $Settings `
    -Description "Monitora arquivos do projeto LEGO e regenera DOCUMENTACAO_TECNICA.md automaticamente." `
    | Out-Null

Write-Host ""
Write-Host "OK - Tarefa '$TaskName' registrada com sucesso!" -ForegroundColor Green
Write-Host ""
Write-Host "   pythonw : $PythonwExe"
Write-Host "   Script  : $WatcherScript"
Write-Host "   Gatilho : Login do Windows"
Write-Host ""
Write-Host "Para iniciar agora sem reiniciar:"
Write-Host "   Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para verificar se esta rodando:"
Write-Host "   Get-Process pythonw" -ForegroundColor Cyan
Write-Host ""
Write-Host "Para remover:"
Write-Host "   Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor Cyan
