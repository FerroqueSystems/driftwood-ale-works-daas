$ErrorActionPreference = "Stop"

if ($env:RUN_CITRIX_OPTIMIZER -ne "true") {
    Write-Host "Citrix Optimizer disabled for this image build. Skipping."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($env:CITRIX_OPTIMIZER_ZIP_URL)) {
    throw "CITRIX_OPTIMIZER_ZIP_URL must be set when RUN_CITRIX_OPTIMIZER=true."
}

if ([string]::IsNullOrWhiteSpace($env:CITRIX_OPTIMIZER_TEMPLATE_NAME)) {
    throw "CITRIX_OPTIMIZER_TEMPLATE_NAME must be set when RUN_CITRIX_OPTIMIZER=true."
}

$installerRoot = "C:\Temp\PackerInstallers"
$optimizerRoot = "C:\Temp\CitrixOptimizer"
New-Item -ItemType Directory -Path $installerRoot -Force | Out-Null
New-Item -ItemType Directory -Path $optimizerRoot -Force | Out-Null

$zipUrl = $env:CITRIX_OPTIMIZER_ZIP_URL
$templateName = $env:CITRIX_OPTIMIZER_TEMPLATE_NAME
$zipFileName = [System.IO.Path]::GetFileName(([System.Uri]$zipUrl).AbsolutePath)
if ([string]::IsNullOrWhiteSpace($zipFileName)) {
    $zipFileName = "CitrixOptimizerTool.zip"
}

$zipPath = Join-Path $installerRoot $zipFileName

Write-Host "Downloading Citrix Optimizer from $zipUrl"
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

Write-Host "Extracting Citrix Optimizer"
Expand-Archive -Path $zipPath -DestinationPath $optimizerRoot -Force

$enginePath = Get-ChildItem -Path $optimizerRoot -Recurse -Filter "CtxOptimizerEngine.ps1" | Select-Object -First 1 -ExpandProperty FullName
if (-not $enginePath) {
    throw "CtxOptimizerEngine.ps1 was not found in the Citrix Optimizer package."
}

$templatePath = Get-ChildItem -Path $optimizerRoot -Recurse -Filter $templateName | Select-Object -First 1 -ExpandProperty FullName
if (-not $templatePath) {
    throw "Citrix Optimizer template '$templateName' was not found in the package."
}

Write-Host "Running Citrix Optimizer template $templateName"
& powershell.exe -ExecutionPolicy Bypass -File $enginePath -Source $templatePath -Mode Execute

if ($LASTEXITCODE -ne 0) {
    throw "Citrix Optimizer failed with exit code $LASTEXITCODE."
}

Write-Host "Citrix Optimizer completed successfully."
