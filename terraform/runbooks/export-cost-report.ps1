Connect-AzAccount -Identity

$endDate = Get-Date
$startDate = $endDate.AddDays(-30)

$startStr = $startDate.ToString("yyyy-MM-dd")
$endStr = $endDate.ToString("yyyy-MM-dd")

Write-Output "Cost Report: $startStr to $endStr"
Write-Output "==========================================="

$usage = Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate -ErrorAction SilentlyContinue

if (-not $usage -or $usage.Count -eq 0) {
    Write-Output "No usage data available for this period."
    return
}

$grouped = $usage | Group-Object -Property ConsumedService | Sort-Object { ($_.Group | Measure-Object -Property PretaxCost -Sum).Sum } -Descending

$totalCost = 0
foreach ($service in $grouped) {
    $cost = ($service.Group | Measure-Object -Property PretaxCost -Sum).Sum
    $totalCost += $cost
    Write-Output ("{0,-45} {1,12:C2}" -f $service.Name, $cost)
}

Write-Output "==========================================="
Write-Output ("{0,-45} {1,12:C2}" -f "TOTAL", $totalCost)
Write-Output ""
Write-Output "Top 5 services account for the majority of spend."
