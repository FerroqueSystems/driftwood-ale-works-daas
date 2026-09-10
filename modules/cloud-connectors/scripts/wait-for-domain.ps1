[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DomainFqdn,
    [Parameter(Mandatory = $true)][string]$Dc1PrivateIp,
    [Parameter(Mandatory = $true)][string]$Dc2PrivateIp
)

# Runs before the JsonADDomainExtension domain-join step (see
# modules/cloud-connectors/main.tf). Terraform's module-level depends_on
# between modules/domain-controllers and modules/cloud-connectors only
# orders resource-creation calls, not actual functional readiness - the
# domain controllers' own extensions report success before their post-
# promotion reboots even complete, so without this wait the domain-join step
# would be racing a forest that may not be up yet.

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\wait-for-domain.log" -Append

try {
    $srvName = "_ldap._tcp.dc._msdcs.$DomainFqdn"
    $deadline = (Get-Date).AddMinutes(20)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        foreach ($dcIp in @($Dc1PrivateIp, $Dc2PrivateIp)) {
            try {
                Resolve-DnsName -Name $srvName -Type SRV -Server $dcIp -ErrorAction Stop | Out-Null
                $ready = $true
                break
            }
            catch {
                Write-Host "Domain not ready via $dcIp yet ($($_.Exception.Message))"
            }
        }
        if ($ready) {
            break
        }
        Write-Host "Retrying in 30s..."
        Start-Sleep -Seconds 30
    }
    if (-not $ready) {
        throw "Domain '$DomainFqdn' did not become resolvable within 20 minutes."
    }
    Write-Host "Domain is ready."
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript
}
