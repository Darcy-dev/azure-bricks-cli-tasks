Connect-AzAccount -Identity

$resourceGroups = Get-AzResourceGroup
foreach ($rg in $resourceGroups) {
    Write-Output "Resource Group: $($rg.ResourceGroupName) | Location: $($rg.Location)"
}

Write-Output ""
Write-Output "Total: $($resourceGroups.Count) resource group(s)"
