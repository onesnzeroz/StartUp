[CmdletBinding()]
param(
    [switch]$RunTask
)

$ErrorActionPreference = 'Stop'

$TaskName = 'EnableAdministratorAndExpandDiskOnLogon'
$ScriptPath = $MyInvocation.MyCommand.Path

function Enable-AdministratorAccount {
    try {
        if (Get-Command -Name Enable-LocalUser -ErrorAction SilentlyContinue) {
            $adminUser = Get-LocalUser -Name 'Administrator' -ErrorAction Stop
            if (-not $adminUser.Enabled) {
                Enable-LocalUser -Name 'Administrator' -ErrorAction Stop
            }
        }
        else {
            $null = & net.exe user Administrator /active:yes
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to enable Administrator account using net.exe. ExitCode=$LASTEXITCODE"
            }
        }
    }
    catch {
        throw "Unable to enable Administrator account. $($_.Exception.Message)"
    }
}

function Expand-SystemPartition {
    try {
        $systemPartition = Get-Partition -DriveLetter 'C' -ErrorAction Stop
        $supportedSize = Get-PartitionSupportedSize -DriveLetter 'C' -ErrorAction Stop

        if ($systemPartition.Size -lt $supportedSize.SizeMax) {
            Resize-Partition -DriveLetter 'C' -Size $supportedSize.SizeMax -ErrorAction Stop
        }
    }
    catch {
        throw "Unable to resize system partition. $($_.Exception.Message)"
    }
}

function Remove-SelfTask {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    }
    catch {
        throw "Task cleanup failed. $($_.Exception.Message)"
    }
}

if ($RunTask) {
    Enable-AdministratorAccount
    Expand-SystemPartition
    Remove-SelfTask
    exit 0
}

try {
    $escapedScriptPath = $ScriptPath.Replace('"', '""')
    $actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$escapedScriptPath`" -RunTask"

    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $actionArgs
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    Register-ScheduledTask \
        -TaskName $TaskName \
        -Action $action \
        -Trigger $trigger \
        -Principal $principal \
        -Settings $settings \
        -Description 'Enables Administrator, expands C: partition to max, then deletes itself.' \
        -Force | Out-Null

    Write-Host "Scheduled task '$TaskName' has been created. It will run at next user logon."
}
catch {
    throw "Failed to register scheduled task. $($_.Exception.Message)"
}
