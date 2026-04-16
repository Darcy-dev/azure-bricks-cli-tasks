Connect-AzAccount -Identity

$vms = Get-AzVM -Status
$stoppedCount = 0

foreach ($vm in $vms) {
    $status = ($vm.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus

    if ($status -eq "VM running") {
        Write-Output "Stopping VM: $($vm.Name) in $($vm.ResourceGroupName)..."
        Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force
        $stoppedCount++
    } else {
        Write-Output "VM $($vm.Name) is already $status. Skipping."
    }
}

Write-Output ""
Write-Output "Done. Stopped $stoppedCount VM(s)."
