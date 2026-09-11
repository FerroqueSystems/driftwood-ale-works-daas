[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DomainFqdn,
    [Parameter(Mandatory = $true)][string]$DomainNetbiosName,
    [Parameter(Mandatory = $true)][string]$Dc1PrivateIp,
    [Parameter(Mandatory = $true)][string]$SafeModePassword,
    [Parameter(Mandatory = $true)][string]$ServiceAccountName,
    [Parameter(Mandatory = $true)][string]$ServiceAccountPassword
)

# Promotes this VM as a second domain controller in the forest DC1 (via
# promote-forest.ps1) already created. Waits for both the forest AND the
# service account post-promotion-setup.ps1 creates on DC1 to be ready before
# attempting anything - DC1's own Custom Script Extension reports success
# well before DC1 has actually rebooted (see promote-forest.ps1), so this is
# a real race without an explicit wait here, not just a formality.
#
# Uses the service account (not a "default domain Administrator" account)
# for its own credentials - deliberately avoids relying on ambiguous
# built-in-Administrator-carries-over-to-domain-admin behavior, which is
# untested here and may not hold the way it would on a non-Azure-provisioned
# VM (Azure's provisioning agent doesn't necessarily enable/use the literal
# built-in Administrator account the way on-prem Windows setups do).

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\promote-additional-dc.log" -Append

try {
    $domainRole = (Get-CimInstance -ClassName Win32_ComputerSystem).DomainRole
    if ($domainRole -ge 4) {
        Write-Host "Already a domain controller (DomainRole=$domainRole) - skipping promotion (idempotent re-run)."
        exit 0
    }

    Write-Host "Installing AD-Domain-Services and RSAT-AD-PowerShell features..."
    Install-WindowsFeature -Name AD-Domain-Services, RSAT-AD-PowerShell -IncludeManagementTools | Out-Null

    $svcPw = ConvertTo-SecureString -String $ServiceAccountPassword -AsPlainText -Force
    $svcCred = New-Object System.Management.Automation.PSCredential("$DomainNetbiosName\$ServiceAccountName", $svcPw)

    Write-Host "Waiting for the forest (via $Dc1PrivateIp) and the '$ServiceAccountName' service account to be ready..."
    $deadline = (Get-Date).AddMinutes(20)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        try {
            Get-ADUser -Filter "SamAccountName -eq '$ServiceAccountName'" -Server $Dc1PrivateIp -Credential $svcCred -ErrorAction Stop | Out-Null
            $ready = $true
            break
        }
        catch {
            Write-Host "Not ready yet ($($_.Exception.Message)) - retrying in 30s..."
            Start-Sleep -Seconds 30
        }
    }
    if (-not $ready) {
        throw "Forest/service account did not become ready within 20 minutes."
    }

    # This machine's own NIC still points at Azure's default DNS resolver
    # (modules/domain-controllers' NIC-level override - needed so its own
    # bootstrap could resolve the public blob storage endpoint before any DC
    # existed to ask). Azure's resolver has no idea "driftwood.local" is a
    # thing, so Install-ADDSDomainController's own DNS-based SRV record
    # lookup for the domain fails ("could not be contacted") even though the
    # -Server-targeted Get-ADUser check above just succeeded. Safe to point
    # at DC1 directly now - the public-DNS bootstrap need is already behind
    # us at this point in the script.
    $netAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    Write-Host "Pointing DNS at $Dc1PrivateIp (via '$($netAdapter.Name)') so domain discovery can actually find $DomainFqdn..."
    Set-DnsClientServerAddress -InterfaceAlias $netAdapter.Name -ServerAddresses $Dc1PrivateIp

    $safeModePw = ConvertTo-SecureString -String $SafeModePassword -AsPlainText -Force

    Write-Host "Promoting as an additional domain controller in $DomainFqdn..."
    Install-ADDSDomainController `
        -DomainName $DomainFqdn `
        -Credential $svcCred `
        -SafeModeAdministratorPassword $safeModePw `
        -InstallDns `
        -NoRebootOnCompletion `
        -Force

    # See promote-forest.ps1's identical comment - a background shutdown.exe
    # does not reliably survive this script's own process exiting under the
    # Custom Script Extension agent, so this uses a one-time Scheduled Task
    # instead.
    Write-Host "Additional DC promotion complete. Scheduling a reboot in 90 seconds via a one-time task so this script can report success first."
    $rebootTaskName = "DriftwoodAdditionalDcReboot"
    $rebootAction = New-ScheduledTaskAction -Execute "shutdown.exe" -Argument "/r /t 0 /f /c `"Rebooting to complete AD DS domain controller promotion`""
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
