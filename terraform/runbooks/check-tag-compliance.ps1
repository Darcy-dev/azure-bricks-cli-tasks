Connect-AzAccount -Identity

$requiredTags = @("Environment", "Owner", "CostCenter")
$resources = Get-AzResource
$nonCompliant = @()

foreach ($resource in $resources) {
    $missingTags = @()
    foreach ($tag in $requiredTags) {
        if (-not $resource.Tags -or -not $resource.Tags.ContainsKey($tag)) {
            $missingTags += $tag
        }
    }

    if ($missingTags.Count -gt 0) {
        $nonCompliant += [PSCustomObject]@{
            Name          = $resource.Name
            ResourceGroup = $resource.ResourceGroupName
            Type          = $resource.ResourceType
            MissingTags   = ($missingTags -join ", ")
        }
    }
}

Write-Output "Tag Compliance Report"
Write-Output "Required tags: $($requiredTags -join ', ')"
Write-Output "Total resources scanned: $($resources.Count)"
Write-Output "Non-compliant resources: $($nonCompliant.Count)"
Write-Output ""

if ($nonCompliant.Count -gt 0) {
    $nonCompliant | Format-Table -AutoSize
} else {
    Write-Output "All resources are compliant."
}
