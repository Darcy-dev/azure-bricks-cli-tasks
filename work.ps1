<#
.SYNOPSIS
    Runs during an AKS maintenance window and monitors node pool upgrade lifecycle.

.DESCRIPTION
    1. Waits for the maintenance window to start (if triggered early)
    2. Polls node pool provisioning states in a loop throughout the window
    3. Sends Slack notifications at each stage:
       - "UPDATING NODE IMAGE" — when any pool enters UpgradingNodeImageVersion
       - "SUCCEEDED"           — when all upgrading pools finish successfully
       - "NO ACTIONS DONE"     — when the window closes with no upgrades
    4. Compares current vs latest available node image for each pool
#>

# ── Hardcoded configuration ──────────────────────────────────────────────────
$ResourceGroupName     = "rg-maintenance"
$AksClusterName        = "aks-maintenance-demo"
$MaintenanceConfigName = "aksManagedNodeOSUpgradeSchedule"
$AutomationAccountName = "aa-maintenance-monitor"
$SlackWebhookUrl       = "https://hooks.slack.com/triggers/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"
$PollIntervalSeconds   = 60

$ErrorActionPreference = "Stop"

# ── Helper: send Slack notification ───────────────────────────────────────────
function Send-SlackNotification {
    param(
        [string]$Status,
        [string]$Message,
        [string]$NodePoolDetails,
        [string]$ImageVersion = ""
    )
    $body = @{
        cluster        = $AksClusterName
        resource_group = $ResourceGroupName
        node_pools     = $NodePoolDetails
        image_version  = $ImageVersion
        timestamp_utc  = [System.DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss")
        message        = "[$Status] $Message"
    } | ConvertTo-Json -Depth 3

    try {
        Invoke-RestMethod -Uri $SlackWebhookUrl -Method POST -Body $body -ContentType "application/json" | Out-Null
        Write-Output "Slack notification sent: $Status"
    } catch {
        Write-Output "WARNING: Slack notification failed: $($_.Exception.Message)"
    }
}

# ── Helper: get all node pool states ──────────────────────────────────────────
function Get-NodePoolStates {
    param([hashtable]$Headers)
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ContainerService/managedClusters/$AksClusterName/agentPools?api-version=2024-01-01"
    $response = Invoke-RestMethod -Uri $uri -Headers $Headers -Method GET

    $pools = @()
    foreach ($pool in $response.value) {
        # Get latest available image
        $upgradeUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ContainerService/managedClusters/$AksClusterName/agentPools/$($pool.name)/upgradeProfiles/default?api-version=2024-01-01"
        $latestImage = ""
        try {
            $upgradeInfo = Invoke-RestMethod -Uri $upgradeUri -Headers $Headers -Method GET
            $latestImage = $upgradeInfo.properties.latestNodeImageVersion
        } catch {
            $latestImage = "unknown"
        }

        $pools += @{
            name         = $pool.name
            state        = $pool.properties.provisioningState
            currentImage = $pool.properties.nodeImageVersion
            latestImage  = $latestImage
            isUpToDate   = ($pool.properties.nodeImageVersion -eq $latestImage)
        }
    }
    return $pools
}

# ── Helper: format pool details string ────────────────────────────────────────
function Format-PoolDetails {
    param($Pools)
    return ($Pools | ForEach-Object {
        $upToDate = if ($_.isUpToDate) { "current" } else { "outdated" }
        "$($_.name): $($_.state) | image=$($_.currentImage) | latest=$($_.latestImage) [$upToDate]"
    }) -join " | "
}

# ── Authenticate with managed identity ────────────────────────────────────────
Write-Output "Connecting with managed identity..."
Connect-AzAccount -Identity | Out-Null
$subscriptionId = (Get-AzContext).Subscription.Id
Write-Output "Subscription: $subscriptionId"

$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
$headers = @{ Authorization = "Bearer $token" }

# ── Retrieve maintenance configuration ────────────────────────────────────────
Write-Output "Fetching maintenance configuration '$MaintenanceConfigName'..."
$aksUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ContainerService/managedClusters/$AksClusterName/maintenanceConfigurations/${MaintenanceConfigName}?api-version=2024-01-01"
$configResponse = Invoke-RestMethod -Uri $aksUri -Headers $headers -Method GET

$schedule      = $configResponse.properties.maintenanceWindow.schedule
$durationHours = $configResponse.properties.maintenanceWindow.durationHours
$utcOffset     = $configResponse.properties.maintenanceWindow.utcOffset
if (-not $utcOffset) { $utcOffset = "+00:00" }

$weeklySchedule = $schedule.weekly
$dayOfWeek      = $weeklySchedule.dayOfWeek
$startTimeStr   = $configResponse.properties.maintenanceWindow.startTime

Write-Output "Schedule: $dayOfWeek $startTimeStr UTC (${durationHours}h)"

# ── Parse schedule parameters ─────────────────────────────────────────────────
$offsetSpan = [System.TimeSpan]::Zero
if ($utcOffset -match '^([+-])(\d{2}):(\d{2})$') {
    $sign = if ($Matches[1] -eq '-') { -1 } else { 1 }
    $offsetSpan = New-TimeSpan -Hours ($sign * [int]$Matches[2]) -Minutes ($sign * [int]$Matches[3])
}

$startParts  = $startTimeStr -split ':'
$startHour   = [int]$startParts[0]
$startMinute = [int]$startParts[1]

# ── Calculate the window end time ─────────────────────────────────────────────
function Get-WindowEnd {
    $now = [System.DateTimeOffset]::UtcNow.ToOffset($offsetSpan)

    # Try today
    $candidate = [System.DateTimeOffset]::new(
        $now.Year, $now.Month, $now.Day,
        $startHour, $startMinute, 0, $offsetSpan
    )
    $candidateEnd = $candidate.AddHours($durationHours)

    # If we're past today's window end, it might be yesterday's window still open
    if ([System.DateTimeOffset]::UtcNow -lt $candidateEnd) {
        return $candidateEnd.ToUniversalTime()
    }

    # Check yesterday (for overnight windows)
    $yesterday = $now.AddDays(-1)
    $candidateYesterday = [System.DateTimeOffset]::new(
        $yesterday.Year, $yesterday.Month, $yesterday.Day,
        $startHour, $startMinute, 0, $offsetSpan
    )
    return $candidateYesterday.AddHours($durationHours).ToUniversalTime()
}

$windowEndUtc = Get-WindowEnd
Write-Output "Window ends at: $($windowEndUtc.ToString('yyyy-MM-dd HH:mm:ss')) UTC"

# ── State tracking ────────────────────────────────────────────────────────────
$upgradeDetected     = $false
$upgradeNotifSent    = $false
$succeededNotifSent  = $false
$poolsBeingUpgraded  = @()

# ── Main monitoring loop ─────────────────────────────────────────────────────
Write-Output ""
Write-Output "=== Starting maintenance window monitoring loop ==="
Write-Output ""

while ([System.DateTimeOffset]::UtcNow -lt $windowEndUtc) {

    # Refresh token if needed (tokens last ~60 min, window can be up to 4h)
    try {
        $token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
        $headers = @{ Authorization = "Bearer $token" }
    } catch {
        Write-Output "WARNING: Token refresh failed, using existing token."
    }

    $nowStr = [System.DateTimeOffset]::UtcNow.ToString("HH:mm:ss")
    $pools = Get-NodePoolStates -Headers $headers

    # Log current state
    Write-Output "[$nowStr] Polling node pools..."
    foreach ($p in $pools) {
        $upToDate = if ($p.isUpToDate) { "current" } else { "outdated" }
        Write-Output "  $($p.name): $($p.state) | image=$($p.currentImage) [$upToDate]"
    }

    $upgradingPools = @($pools | Where-Object { $_.state -eq "UpgradingNodeImageVersion" })
    $allStates      = $pools | ForEach-Object { $_.state }

    # ── Detect upgrade starting ───────────────────────────────────────────────
    if ($upgradingPools.Count -gt 0 -and -not $upgradeNotifSent) {
        $upgradeDetected    = $true
        $upgradeNotifSent   = $true
        $poolsBeingUpgraded = $upgradingPools | ForEach-Object { $_.name }
        $details = Format-PoolDetails -Pools $pools

        Write-Output ""
        Write-Output ">>> UPGRADE DETECTED on: $($poolsBeingUpgraded -join ', ')"
        Write-Output ""

        $currentImg = ($pools | Select-Object -First 1).currentImage
        $latestImg  = ($pools | Select-Object -First 1).latestImage

        Send-SlackNotification `
            -Status "UPDATING NODE IMAGE" `
            -Message "Maintenance window is active. Node pools are being upgraded: $($poolsBeingUpgraded -join ', ')." `
            -NodePoolDetails $details `
            -ImageVersion "current=$currentImg | latest=$latestImg"
    }

    # ── Detect upgrade completed ──────────────────────────────────────────────
    if ($upgradeDetected -and -not $succeededNotifSent) {
        # Check if all pools that were upgrading are now Succeeded
        $stillUpgrading = @($pools | Where-Object {
            $_.state -eq "UpgradingNodeImageVersion"
        })

        if ($stillUpgrading.Count -eq 0) {
            $failedPools = @($pools | Where-Object { $_.state -eq "Failed" })

            if ($failedPools.Count -eq 0) {
                $succeededNotifSent = $true
                $details = Format-PoolDetails -Pools $pools

                Write-Output ""
                Write-Output ">>> ALL UPGRADES SUCCEEDED"
                Write-Output ""

                $finalImg = ($pools | Select-Object -First 1).currentImage

                Send-SlackNotification `
                    -Status "SUCCEEDED" `
                    -Message "All node pool upgrades completed successfully during the maintenance window." `
                    -NodePoolDetails $details `
                    -ImageVersion $finalImg

                # Done — upgrades finished, no need to keep polling
                break
            } else {
                $succeededNotifSent = $true
                $details = Format-PoolDetails -Pools $pools
                $failedNames = ($failedPools | ForEach-Object { $_.name }) -join ', '

                Write-Output ""
                Write-Output ">>> UPGRADE FAILED on: $failedNames"
                Write-Output ""

                Send-SlackNotification `
                    -Status "FAILED" `
                    -Message "Node pool upgrade failed on: $failedNames." `
                    -NodePoolDetails $details `
                    -ImageVersion ($pools | Select-Object -First 1).currentImage

                break
            }
        }
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}

# ── Window ended without any upgrade ─────────────────────────────────────────
if (-not $upgradeDetected) {
    Write-Output ""
    Write-Output ">>> Maintenance window ended. No upgrades were performed."
    Write-Output ""

    $pools = Get-NodePoolStates -Headers $headers
    $details = Format-PoolDetails -Pools $pools

    $outdated = @($pools | Where-Object { -not $_.isUpToDate })
    $extraInfo = if ($outdated.Count -gt 0) {
        "$($outdated.Count) pool(s) are outdated but were not upgraded in this window."
    } else {
        "All pools are already running the latest node image."
    }

    Send-SlackNotification `
        -Status "NO ACTIONS DONE" `
        -Message "Maintenance window closed with no node image upgrades. $extraInfo" `
        -NodePoolDetails $details `
        -ImageVersion ($pools | Select-Object -First 1).currentImage
}

Write-Output ""
Write-Output "=== Monitoring complete ==="
