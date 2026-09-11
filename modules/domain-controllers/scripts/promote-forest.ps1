[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DomainFqdn,
    [Parameter(Mandatory = $true)][string]$DomainNetbiosName,
    [Parameter(Mandatory = $true)][string]$SafeModePassword,
    [Parameter(Mandatory = $true)][string]$ServiceAccountName,
    [Parameter(Mandatory = $true)][string]$ServiceAccountPassword,
    [Parameter(Mandatory = $true)][string]$BaseOuName,
    [Parameter(Mandatory = $true)][string]$VdaOuName,
    [Parameter(Mandatory = $true)][string]$ConnectorOuName,
    [Parameter(Mandatory = $true)][string]$DevGroupName,
    [Parameter(Mandatory = $true)][string]$TestGroupName,
    [Parameter(Mandatory = $true)][string]$ProdGroupName
)

# Promotes this VM into a brand-new AD DS forest. Runs via a Custom Script
# Extension - see modules/domain-controllers/README.md for why the reboot is
# handled the way it is below (Install-ADDSForest normally reboots on its
# own, which would kill the extension mid-run and report a false failure).
#
# The actual OU/service-account/AD-group setup happens in
# post-promotion-setup.ps1 (downloaded alongside this script), registered
# here as a run-once-at-startup scheduled task, since none of that is
# reliably available until after this promotion's mandatory reboot.

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\promote-forest.log" -Append

try {
    $domainRole = (Get-CimInstance -ClassName Win32_ComputerSystem).DomainRole
    if ($domainRole -ge 4) {
        Write-Host "Already a domain controller (DomainRole=$domainRole) - skipping forest promotion (idempotent re-run)."
        exit 0
    }

    Write-Host "Installing AD-Domain-Services feature..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

    $postPromotionScript = Join-Path $PSScriptRoot "post-promotion-setup.ps1"
    if (-not (Test-Path $postPromotionScript)) {
        throw "post-promotion-setup.ps1 not found next to this script - check the Custom Script Extension's fileUris."
    }

    $taskName = "DriftwoodPostPromotionSetup"
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existingTask) {
        Write-Host "Registering a one-time, run-at-startup scheduled task to finish AD setup after the reboot..."
        $taskArgs = @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$postPromotionScript`"",
            "-DomainFqdn", "`"$DomainFqdn`"",
            "-ServiceAccountName", "`"$ServiceAccountName`"",
            "-ServiceAccountPassword", "`"$ServiceAccountPassword`"",
            "-BaseOuName", "`"$BaseOuName`"",
            "-VdaOuName", "`"$VdaOuName`"",
            "-ConnectorOuName", "`"$ConnectorOuName`"",
            "-DevGroupName", "`"$DevGroupName`"",
            "-TestGroupName", "`"$TestGroupName`"",
            "-ProdGroupName", "`"$ProdGroupName`"",
            "-TaskName", "`"$taskName`""
        ) -join " "

        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
    }
    else {
        Write-Host "Post-promotion scheduled task already registered - leaving it as-is."
    }

    $safeModePw = ConvertTo-SecureString -String $SafeModePassword -AsPlainText -Force

    Write-Host "Promoting to a new AD DS forest: $DomainFqdn ($DomainNetbiosName)..."
    Install-ADDSForest `
        -DomainName $DomainFqdn `
        -DomainNetbiosName $DomainNetbiosName `
        -SafeModeAdministratorPassword $safeModePw `
        -InstallDns `
        -NoRebootOnCompletion `
        -Force

    # A background shutdown.exe (even via Start-Process, even fully detached)
    # does not reliably survive this script's own process exiting - the
    # Custom Script Extension agent tears down the whole process tree/job
    # object once the extension reports completion, silently killing the
    # pending delayed reboot along with it (confirmed: a real apply reported
    # this extension as "Succeeded" and exited, but the VM's last boot time
    # never advanced - the scheduled reboot never actually fired). A one-time
    # Scheduled Task runs under the Task Scheduler service instead, immune to
    # the CSE's own process cleanup - same reasoning as the post-promotion
    # continuation task registered above.
    Write-Host "Forest promotion complete. Scheduling a reboot in 90 seconds via a one-time task so this script can report success first; the post-promotion task will finish setup once the DC comes back up."
    $rebootTaskName = "DriftwoodPostForestPromotionReboot"
    $rebootAction = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "/r /t 0 /f /c `"Rebooting to complete AD DS forest promotion`""
    $rebootTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(90)
    $rebootPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $rebootTaskName -Action $rebootAction -Trigger $rebootTrigger -Principal $rebootPrincipal -Force | Out-Null
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript
}
