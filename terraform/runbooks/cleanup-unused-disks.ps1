Connect-AzAccount -Identity

$disks = Get-AzDisk | Where-Object { $_.DiskState -eq "Unattached" }

if ($disks.Count -eq 0) {
    Write-Output "No unattached disks found."
    return
}

Write-Output "Found $($disks.Count) unattached disk(s):"
Write-Output ""

$removedCount = 0
foreach ($disk in $disks) {
    $ageDays = (New-TimeSpan -Start $disk.TimeCreated -End (Get-Date)).Days
    Write-Output "  Disk: $($disk.Name) | RG: $($disk.ResourceGroupName) | Size: $($disk.DiskSizeGB) GB | Age: $ageDays days"

    Remove-AzDisk -ResourceGroupName $disk.ResourceGroupName -DiskName $disk.Name -Force
    $removedCount++
}

Write-Output ""
Write-Output "Done. Removed $removedCount unattached disk(s)."
