Add-Type -AssemblyName System.Windows.Forms

$configPath = "D:\rom-manager\config.json"

if (!(Test-Path $configPath)) {
    throw "Config file not found: $configPath"
}

try {
    $config = Get-Content $configPath | ConvertFrom-Json
} catch {
    throw "Invalid JSON in config file."
}

# --- Globals ---
$SourceRoot = $config.SourceRoot
$CollectionsRoot = $config.CollectionsRoot
$LogRoot = $config.LogRoot

# --- Ensure folders exist ---
$LogRoot | ForEach-Object {
    if (!(Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null }
}

# --- Logging ---
function Start-Log {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LogRoot "session_$timestamp.log"
    Start-Transcript -Path $logFile | Out-Null
    return $logFile
}

function Stop-Log {
    Stop-Transcript | Out-Null
}

# --- Select Inventory File ---
function Select-Inventory {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.InitialDirectory = $CollectionsRoot
    $dialog.Filter = "Text Files (*.txt)|*.txt"

    if ($dialog.ShowDialog() -eq "OK") {
        return $dialog.FileName
    }
    return $null
}

# --- Curate ---
function Invoke-Curation {
    Write-Host "Launching curation..."

    $selectedPaths = @()

    # File picker
    $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $fileDialog.Multiselect = $true
    $fileDialog.InitialDirectory = $SourceRoot

    if ($fileDialog.ShowDialog() -eq "OK") {
        $selectedPaths += $fileDialog.FileNames
    }

    if (-not $selectedPaths) {
        Write-Host "Nothing selected."
        return
    }

    # Inventory selection
    $inventory = Select-Inventory
    if (-not $inventory) { return }

    # Expand files
    $allFiles = @()
    foreach ($path in $selectedPaths) {
        if (Test-Path $path -PathType Container) {
            $allFiles += Get-ChildItem $path -Recurse -File | ForEach-Object { $_.FullName }
        } else {
            $allFiles += $path
        }
    }

    # Normalize
    $normalizedSource = (Resolve-Path $SourceRoot).Path
    $relative = $allFiles | ForEach-Object {
        $_.Replace("$normalizedSource\", "").Trim()
    } | Where-Object { $_ }

    # Merge
    $existing = if (Test-Path $inventory) { Get-Content $inventory } else { @() }

    $final = ($existing + $relative) | Sort-Object -Unique

    if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
    $final | Out-GridView -Title "Preview"
    } else {
        Write-Host "Preview (first 20):"
        $final | Select-Object -First 20
    }

    # Save
    [System.IO.File]::WriteAllLines($inventory, $final)

    Write-Host "Updated: $inventory"
}

# --- Analysis ---

function Get-SyncPlan {
    param(
        [string]$InventoryFile,
        [string]$SourceRoot,
        [string]$Destination,
        [switch]$Clean
    )

    $entries = Get-Content $InventoryFile | Where-Object { $_ }

    $toCopy = @()
    $toSkip = @()
    $missing = @()
    $expectedFiles = @()

    foreach ($entry in $entries) {
        $src = Join-Path $SourceRoot $entry
        $dst = Join-Path $Destination $entry

        $expectedFiles += $dst

        if (!(Test-Path $src)) {
            $missing += $entry
            continue
        }

        $copyNeeded = $true

        if (Test-Path $dst) {
            $srcInfo = Get-Item $src
            $dstInfo = Get-Item $dst

            if ($srcInfo.Length -eq $dstInfo.Length) {
                $copyNeeded = $false
            }
        }

        if ($copyNeeded) {
            $toCopy += $entry
        } else {
            $toSkip += $entry
        }
    }

    $toRemove = @()

    if ($Clean -and (Test-Path $Destination)) {
        $existingFiles = Get-ChildItem $Destination -Recurse -File | Select-Object -ExpandProperty FullName

        $expectedFilesLower = $expectedFiles | ForEach-Object {
            if (Test-Path $_) {
                (Resolve-Path $_).Path.ToLower()
            } else {
                $_.ToLower()
            }
        }

        $destRoot = (Resolve-Path $Destination).Path

        $exclusions = $config.Exclusions | ForEach-Object { $_.ToLower() }
        $excludeDirs = $config.ExcludeDirectories | ForEach-Object { $_.ToLower() }

        foreach ($file in $existingFiles) {
            $relative = $file.Replace("$destRoot\", "")
            $fileName = [IO.Path]::GetFileName($relative).ToLower()

            $isExcludedDir = $false
            foreach ($dir in $excludeDirs) {
                if ($relative.ToLower().StartsWith($dir)) {
                    $isExcludedDir = $true
                    break
                }
            }

            if ($file.ToLower() -notin $expectedFilesLower -and
                $fileName -notin $exclusions -and
                -not $isExcludedDir) {

                $toRemove += $relative
            }
        }
    }

    return [PSCustomObject]@{
        ToCopy   = $toCopy
        ToSkip   = $toSkip
        ToRemove = $toRemove
        Missing  = $missing
    }
}

# --- Show Summary ---

function Show-SyncSummary {
    param($plan)

    Write-Host ""
    Write-Host "=== Sync Summary ===" -ForegroundColor Cyan

    Write-Host "To Copy  : $($plan.ToCopy.Count)"
    Write-Host "To Skip  : $($plan.ToSkip.Count)"
    Write-Host "To Remove: $($plan.ToRemove.Count)"
    Write-Host "Missing  : $($plan.Missing.Count)"

    if ($plan.ToCopy.Count -gt 0) {
        Write-Host "`nFiles to copy:" -ForegroundColor Green
        $plan.ToCopy | Select-Object -First 10
        if ($plan.ToCopy.Count -gt 10) {
            Write-Host "...and $($plan.ToCopy.Count - 10) more"
        }
    }

    if ($plan.ToRemove.Count -gt 0) {
        Write-Host "`nFiles to remove:" -ForegroundColor Yellow
        $plan.ToRemove | Select-Object -First 10
        if ($plan.ToRemove.Count -gt 10) {
            Write-Host "...and $($plan.ToRemove.Count - 10) more"
        }
    }

    if ($plan.Missing.Count -gt 0) {
        Write-Host "`nMissing files:" -ForegroundColor Red
        $plan.Missing
    }

    Write-Host ""
}

# --- Sync Function ---
function Invoke-DirectSync {
    param(
        [object]$Plan,
        [string]$SourceRoot,
        [string]$Destination,
        [switch]$DryRun,
        [switch]$Clean
    )

    Write-Host "`n=== Executing Sync === ($($Plan.ToCopy.Count) copies, $($Plan.ToRemove.Count) deletes)" -ForegroundColor Cyan

    # --- Copy phase ---
    if ($Plan.ToCopy.Count -eq 0) {
        Write-Host "No files to copy."
    }
    if ($Plan.ToCopy.Count -gt 0) {
        $total = $Plan.ToCopy.Count
        $current = 0

        foreach ($entry in $Plan.ToCopy) {
            $current++

            $percent = [int](($current / $total) * 100)
            $displayName = [IO.Path]::GetFileName($entry)

            Write-Progress `
                -Activity "Copying files" `
                -Status "$current of $total ($percent%) - $displayName" `
                -PercentComplete $percent

            $src = Join-Path $SourceRoot $entry
            $dst = Join-Path $Destination $entry
            $dstDir = Split-Path $dst

            if (!(Test-Path $dstDir)) {
                if (-not $DryRun) {
                    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
                }
            }

            if ($DryRun) {
                Write-Host "[DRY RUN] Copy: $entry"
            } else {
                Copy-Item $src $dst -Force
            }
        }

        # Clear progress bar when done
        Write-Progress -Activity "Copying files" -Completed
    }

    # --- Remove phase ---
    if ($Clean -and $Plan.ToRemove.Count -gt 0) {

        $total = $Plan.ToRemove.Count
        $current = 0

        foreach ($entry in $Plan.ToRemove) {
            $current++

            $percent = [int](($current / $total) * 100)

            Write-Progress `
                -Activity "Removing files" `
                -Status "$current of $total ($percent%)" `
                -PercentComplete $percent

            $dst = Join-Path $Destination $entry

            if ($DryRun) {
                Write-Host "[DRY RUN] Remove: $entry"
            } else {
                if (Test-Path $dst) {
                    Remove-Item $dst -Force
                }
            }
        }
    }

    Write-Host "`nSync complete." -ForegroundColor Green
}

# --- Safe Guards ---
function Assert-SafeDestination {
    param(
        [string]$SourceRoot,
        [string]$Destination
    )

    $src = (Resolve-Path $SourceRoot).Path.ToLower()

    $dst = if (Test-Path $Destination) {
        (Resolve-Path $Destination).Path.ToLower()
    } else {
        $Destination.ToLower()
    }

    if ($src -eq $dst) {
        throw "Destination cannot be the same as SourceRoot!"
    }

    if ($src.StartsWith($dst)) {
        throw "Destination cannot be a parent of SourceRoot!"
    }
}

# --- Deploy ---
function Invoke-Deploy {
    param(
        [bool]$DryRun = $false,
        [switch]$Clean
    )

    $inventory = Select-Inventory
    if (-not $inventory) { return }

    $setName = [IO.Path]::GetFileNameWithoutExtension($inventory)

    if (-not $config.Devices.$setName) {
        Write-Host "No device mapping found for $setName"
        return
    }

    $dest = $config.Devices.$setName

    Assert-SafeDestination -SourceRoot $SourceRoot -Destination $dest

    $plan = Get-SyncPlan -InventoryFile $inventory `
                        -SourceRoot $SourceRoot `
                        -Destination $dest `
                        -Clean:$Clean

    Show-SyncSummary $plan

    if ($Clean -and $Plan.ToRemove.Count -gt 50) {
        Write-Host "WARNING: About to delete $($Plan.ToRemove.Count) files!" -ForegroundColor Red
        $confirm = Read-Host "Type DELETE to confirm"

        if ($confirm -ne "DELETE") {
            Write-Host "Aborted."
            return
        }
    }

    $confirm = Read-Host "Proceed with sync? (y/n)"
    if ($confirm -notmatch "^(y|yes)$") {
        Write-Host "Cancelled."
        return
    }

    Invoke-DirectSync -Plan $plan `
                    -SourceRoot $SourceRoot `
                    -Destination $dest `
                    -DryRun:$DryRun `
                    -Clean:$Clean

    Write-Host "Deployment complete."
    }

# --- Menu ---
function Show-Menu {
    Clear-Host
    Write-Host "=== ROM Manager ==="
    Write-Host "1) Curate Collection"
    Write-Host "2) Deploy Collection (Clean)"
    Write-Host "3) Deploy Collection (No Clean)"
    Write-Host "4) Deploy (Dry Run)"
    Write-Host "5) Exit"
}

# --- Main Loop ---
$log = Start-Log

while ($true) {
    Show-Menu
    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" { Invoke-Curation }
        "2" { Invoke-Deploy -DryRun $false -Clean }
        "3" { Invoke-Deploy -DryRun $false }
        "4" { Invoke-Deploy -DryRun $true }
        "5" {
            Stop-Log
            return
        }
        default { Write-Host "Invalid option" }
    }

    Read-Host "Press Enter to continue"
}