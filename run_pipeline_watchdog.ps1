$rscript = "C:\Users\JackPHILPOTT\AppData\Local\Programs\R\R-4.6.0\bin\x64\Rscript.exe"
$scriptPath = "sampling_MSNA_NGA_2026_v3.R"
$logOut = "run_log_stage2_full.txt"
$logErr = "run_log_stage2_full_err.txt"
$memLimitMB = 1500

if (Test-Path $logOut) { Remove-Item $logOut -Force }
if (Test-Path $logErr) { Remove-Item $logErr -Force }

$proc = Start-Process -FilePath $rscript -ArgumentList $scriptPath `
  -RedirectStandardOutput $logOut -RedirectStandardError $logErr `
  -WorkingDirectory (Get-Location).Path -PassThru -NoNewWindow

Write-Output "Started Rscript PID $($proc.Id) at $(Get-Date)"

$killedForMemory = $false

while (-not $proc.HasExited) {
  Start-Sleep -Seconds 10
  $os = Get-CimInstance Win32_OperatingSystem
  $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
  if ($freeMB -lt $memLimitMB) {
    Write-Output "MEMORY WATCHDOG: free memory dropped to ${freeMB}MB (limit ${memLimitMB}MB) at $(Get-Date) - killing Rscript PID $($proc.Id)"
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Get-Process -Name Rscript -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $killedForMemory = $true
    break
  }
}

if ($killedForMemory) {
  Write-Output "RESULT: KILLED_FOR_MEMORY at $(Get-Date)"
} elseif ($proc.ExitCode -eq 0) {
  Write-Output "RESULT: SUCCESS at $(Get-Date)"
} else {
  Write-Output "RESULT: FAILED exit code $($proc.ExitCode) at $(Get-Date)"
}
