$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:LOCAL_ADMIN_USERNAME)) {
    Write-Host "LOCAL_ADMIN_USERNAME not set. Skipping local admin creation."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($env:LOCAL_ADMIN_PASSWORD)) {
    throw "LOCAL_ADMIN_USERNAME is set but LOCAL_ADMIN_PASSWORD is empty."
}

Write-Host "Creating local admin account '$($env:LOCAL_ADMIN_USERNAME)'."

$securePassword = ConvertTo-SecureString -String $env:LOCAL_ADMIN_PASSWORD -AsPlainText -Force

$existing = Get-LocalUser -Name $env:LOCAL_ADMIN_USERNAME -ErrorAction SilentlyContinue
if ($existing) {
    Set-LocalUser -Name $env:LOCAL_ADMIN_USERNAME -Password $securePassword -PasswordNeverExpires $true
} else {
    New-LocalUser -Name $env:LOCAL_ADMIN_USERNAME -Password $securePassword -PasswordNeverExpires -AccountNeverExpires
}

Add-LocalGroupMember -Group "Administrators" -Member $env:LOCAL_ADMIN_USERNAME -ErrorAction SilentlyContinue

Write-Host "Local admin account ready."
