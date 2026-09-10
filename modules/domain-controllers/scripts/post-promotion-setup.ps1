[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DomainFqdn,
    [Parameter(Mandatory = $true)][string]$ServiceAccountName,
    [Parameter(Mandatory = $true)][string]$ServiceAccountPassword,
    [Parameter(Mandatory = $true)][string]$BaseOuName,
    [Parameter(Mandatory = $true)][string]$VdaOuName,
    [Parameter(Mandatory = $true)][string]$ConnectorOuName,
    [Parameter(Mandatory = $true)][string]$DevGroupName,
    [Parameter(Mandatory = $true)][string]$TestGroupName,
    [Parameter(Mandatory = $true)][string]$ProdGroupName,
    [Parameter(Mandatory = $true)][string]$TaskName
)

# Runs once, automatically, via the scheduled task promote-forest.ps1
# registers - fires at the first startup after this DC's forest-promotion
# reboot, as SYSTEM, so it never needs an explicit domain credential to talk
# to the (now fully up) local AD DS instance. Deliberately does NOT run
# inline in promote-forest.ps1 itself: AD DS/NTDS isn't reliably queryable
# until after the mandatory post-promotion reboot completes.
#
# Creates the OU structure, a service account used both for MCS provisioning
# (see modules/citrix) and Cloud Connector domain join (see
# modules/cloud-connectors), and the three AD groups the Dev/Test/Prod
# delivery groups' desktop access lists reference. The service account is
# added to Domain Admins - a deliberate demo-only simplification over
# Citrix's documented least-privilege OU-delegation, not production
# practice (see modules/domain-controllers/README.md).

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\post-promotion-setup.log" -Append

$markerPath = "C:\Windows\Temp\post-promotion-setup.marker"

try {
    if (Test-Path $markerPath) {
        Write-Host "Post-promotion setup already completed - skipping (idempotent re-run)."
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        exit 0
    }

    Write-Host "Waiting for AD DS to be ready..."
    $deadline = (Get-Date).AddMinutes(15)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        try {
            Get-ADDomain -Current LocalComputer | Out-Null
            $ready = $true
            break
        }
        catch {
            Write-Host "AD DS not ready yet ($($_.Exception.Message)) - retrying in 15s..."
            Start-Sleep -Seconds 15
        }
    }
    if (-not $ready) {
        throw "AD DS did not become ready within 15 minutes after reboot."
    }

    $domainDn = (Get-ADDomain).DistinguishedName
    $baseOuDn = "OU=$BaseOuName,$domainDn"
    $vdaOuDn = "OU=$VdaOuName,$baseOuDn"
    $connectorOuDn = "OU=$ConnectorOuName,$baseOuDn"

    $ousToCreate = @(
        @{ Name = $BaseOuName; Dn = $baseOuDn; Path = $domainDn },
        @{ Name = $VdaOuName; Dn = $vdaOuDn; Path = $baseOuDn },
        @{ Name = $ConnectorOuName; Dn = $connectorOuDn; Path = $baseOuDn }
    )
    foreach ($ou in $ousToCreate) {
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$($ou.Dn)'" -ErrorAction SilentlyContinue)) {
            Write-Host "Creating OU $($ou.Dn)..."
            New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -ProtectedFromAccidentalDeletion $false
        }
        else {
            Write-Host "OU $($ou.Dn) already exists - skipping."
        }
    }

    $svcPw = ConvertTo-SecureString -String $ServiceAccountPassword -AsPlainText -Force
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$ServiceAccountName'" -ErrorAction SilentlyContinue)) {
        Write-Host "Creating service account '$ServiceAccountName'..."
        New-ADUser -Name $ServiceAccountName -SamAccountName $ServiceAccountName `
            -AccountPassword $svcPw -Enabled $true -PasswordNeverExpires $true `
            -Path $baseOuDn
    }
    else {
        Write-Host "Service account '$ServiceAccountName' already exists - skipping creation."
    }
    Add-ADGroupMember -Identity "Domain Admins" -Members $ServiceAccountName -ErrorAction SilentlyContinue

    foreach ($groupName in @($DevGroupName, $TestGroupName, $ProdGroupName)) {
        if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
            Write-Host "Creating desktop access group '$groupName'..."
            New-ADGroup -Name $groupName -GroupScope Global -GroupCategory Security -Path $baseOuDn
        }
        else {
            Write-Host "Desktop access group '$groupName' already exists - skipping."
        }
    }

    New-Item -ItemType File -Path $markerPath -Force | Out-Null
    Write-Host "Post-promotion setup complete."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript
}
