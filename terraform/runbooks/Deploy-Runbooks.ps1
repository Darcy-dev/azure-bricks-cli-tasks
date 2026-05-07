param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$AutomationAccountName
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestPath = Join-Path $scriptDir ".." "runbooks.json"
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

foreach ($file in $manifest.PSObject.Properties) {
    $fileName = $file.Name
    $config = $file.Value
    $filePath = Join-Path $scriptDir $fileName

    if (-not (Test-Path $filePath)) {
        Write-Warning "Skipping '$fileName' - file not found"
        continue
    }

    Write-Host "Deploying runbook '$($config.name)' from '$fileName'..."

    az automation runbook replace-content `
        --resource-group $ResourceGroupName `
        --automation-account-name $AutomationAccountName `
        --name $config.name `
        --content @$filePath

    az automation runbook publish `
        --resource-group $ResourceGroupName `
        --automation-account-name $AutomationAccountName `
        --name $config.name

    Write-Host "Published '$($config.name)' successfully."
}

Write-Host "All runbooks deployed."
