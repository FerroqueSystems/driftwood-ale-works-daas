<#
.SYNOPSIS
  Starts, stops, or reports the status of every VM in this demo environment
  - domain controllers, Cloud Connectors, the self-hosted GitHub runner, and
  any Citrix MCS-provisioned VDAs.

.DESCRIPTION
  Discovers VMs by resource group rather than a hardcoded VM list, since the
  monthly rotation workflow creates a new dedicated resource group per
  machine catalog build (see modules/citrix/README.md) - "rg-vda-<env>-
  <label>" - that this script has no way to know about in advance. Covers:
    - The main environment resource group (everything Terraform directly
      manages: domain controllers, Cloud Connectors, the GitHub runner).
    - Every resource group matching the VDA resource-group prefix.

  Every Terraform-managed VM here also has a 7:00 PM Eastern auto-shutdown
  schedule attached (see environments/citrix-azure's
  enable_scheduled_shutdown variable) - this script is for ad-hoc control on
  top of that (e.g. stopping everything right after a demo session, or
  starting everything back up before the next one), not a replacement for
  it. It does NOT cover VDAs' own power state beyond what Citrix's delivery
  group autoscale schedules already do - Stop here deallocates the
  underlying Azure VM directly, which is a blunter instrument than Citrix's
  own autoscale and may cause Citrix Cloud to briefly show those machines as
  unregistered/unavailable until they're started again.

.PARAMETER Action
  Start, Stop, or Status.

.PARAMETER ResourceGroupName
  The main environment resource group (domain controllers, Cloud
  Connectors, GitHub runner). Defaults to "rg-driftwood-citrix-daas" -
  matches environments/citrix-azure/terraform.tfvars.example.

.PARAMETER VdaResourceGroupPrefix
  Prefix used to discover per-catalog-build VDA resource groups. Defaults
  to "rg-vda-" - matches the naming modules/citrix/main.tf uses.

.PARAMETER SubscriptionId
  Optional - switches context to this subscription before doing anything.
  Defaults to whatever subscription Connect-AzAccount already selected.

.PARAMETER Wait
  If set, blocks until every targeted VM reports the expected power state
  (PowerState/running for Start, PowerState/deallocated for Stop) or a
  10-minute timeout elapses, instead of firing the requests and returning
  immediately.

.EXAMPLE
  ./manage-demo-vms.ps1 -Action Status

.EXAMPLE
  ./manage-demo-vms.ps1 -Action Stop -Wait

.EXAMPLE
  ./manage-demo-vms.ps1 -Action Start -SubscriptionId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Start", "Stop", "Status")]
    [string]$Action,

    [string]$ResourceGroupName = "rg-driftwood-citrix-daas",

    [string]$VdaResourceGroupPrefix = "rg-vda-",

    [string]$SubscriptionId,

    [switch]$Wait
)

$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    throw "Az.Compute module not found - install it first: Install-Module -Name Az -Scope CurrentUser"
}

if (-not (Get-AzContext)) {
    throw "Not logged in - run Connect-AzAccount first."
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

Write-Host "Discovering resource groups..."
$resourceGroupNames = [System.Collections.Generic.List[string]]::new()

if (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue) {
    $resourceGroupNames.Add($ResourceGroupName)
}
else {
    Write-Warning "Resource group '$ResourceGroupName' not found - skipping."
}

$vdaGroups = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "$VdaResourceGroupPrefix*" }
foreach ($rg in $vdaGroups) {
    $resourceGroupNames.Add($rg.ResourceGroupName)
}

if ($resourceGroupNames.Count -eq 0) {
    Write-Host "No matching resource groups found - nothing to do."
    exit 0
}

Write-Host "Resource groups: $($resourceGroupNames -join ', ')"

$vms = foreach ($rg in $resourceGroupNames) {
    Get-AzVM -ResourceGroupName $rg -Status
}

if (-not $vms -or $vms.Count -eq 0) {
    Write-Host "No VMs found in those resource groups - nothing to do."
    exit 0
}

function Get-PowerState {
    param($Vm)
    ($Vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
}

function Wait-ForPowerState {
    param(
        [string[]]$ResourceGroups,
        [string]$ExpectedState,
        [int]$TimeoutMinutes = 10
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        Start-Sleep -Seconds 15
        $current = foreach ($rg in $ResourceGroups) { Get-AzVM -ResourceGroupName $rg -Status }
        $notReady = $current | Where-Object { (Get-PowerState $_) -ne $ExpectedState }
        if (-not $notReady) {
            Write-Host "All VMs reached '$ExpectedState'."
            return
        }
        Write-Host "Waiting on: $(($notReady | ForEach-Object { $_.Name }) -join ', ')"
    } while ((Get-Date) -lt $deadline)
    Write-Warning "Timed out after $TimeoutMinutes minutes waiting for '$ExpectedState'."
}

switch ($Action) {
    "Status" {
        $vms |
            ForEach-Object {
                [PSCustomObject]@{
                    ResourceGroup = $_.ResourceGroupName
                    Name          = $_.Name
                    PowerState    = Get-PowerState $_
                }
            } |
            Sort-Object ResourceGroup, Name |
            Format-Table -AutoSize
    }
    "Start" {
        foreach ($vm in $vms) {
            Write-Host "Starting $($vm.Name) (in $($vm.ResourceGroupName))..."
            Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -NoWait | Out-Null
        }
        if ($Wait) {
            Wait-ForPowerState -ResourceGroups $resourceGroupNames -ExpectedState "VM running"
        }
    }
    "Stop" {
        foreach ($vm in $vms) {
            Write-Host "Stopping (deallocating) $($vm.Name) (in $($vm.ResourceGroupName))..."
            Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force -NoWait | Out-Null
        }
        if ($Wait) {
            Wait-ForPowerState -ResourceGroups $resourceGroupNames -ExpectedState "VM deallocated"
        }
    }
}
