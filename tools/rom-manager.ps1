Add-Type -AssemblyName System.Windows.Forms

# --- Load Config ---
$configPath = "D:\rom-manager\config.json"
$config = Get-Content $configPath | ConvertFrom-Json

# --- Globals ---
$SourceRoot = $config.SourceRoot
$CollectionsRoot = $config.CollectionsRoot
$BuildRoot = $config.BuildRoot
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
    $relative = $allFiles | ForEach-Object {
        $_.Replace("$SourceRoot\", "").Trim()
    } | Where-Object { $_ }

    # Merge
    $existing = if (Test-Path $inventory) { Get-Content $inventory } else { @() }

    $final = ($existing + $relative) | Sort-Object -Unique

    # Preview
    $final | Out-GridView -Title "Preview"

    # Save
    [System.IO.File]::WriteAllLines($inventory, $final)

    Write-Host "Updated: $inventory"
}

# --- Analysis ---

function Get-SyncPlan {
    param(
        [string]$InventoryFile,
        [string]$SourceRoot,
        [string]$BuildPath,
        [switch]$Clean
    )

    $entries = Get-Content $InventoryFile | Where-Object { $_ }

    $toCopy = @()
    $toSkip = @()
    $missing = @()
    $expectedFiles = @()

    foreach ($entry in $entries) {
        $src = Join-Path $SourceRoot $entry
        $dst = Join-Path $BuildPath $entry

        $expectedFiles += $dst

        if (!(Test-Path $src)) {
            $missing += $entry
            continue
        }

        $copyNeeded = $true

        if (Test-Path $dst) {
            $srcInfo = Get-Item $src
            $dstInfo = Get-Item $dst

            if ($srcInfo.Length -eq $dstInfo.Length -and
                $srcInfo.LastWriteTime -eq $dstInfo.LastWriteTime) {
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

    if ($Clean -and (Test-Path $BuildPath)) {
        $existingFiles = Get-ChildItem $BuildPath -Recurse -File | Select-Object -ExpandProperty FullName

        foreach ($file in $existingFiles) {
            if ($file -notin $expectedFiles) {
                $toRemove += $file.Replace("$BuildPath\", "")
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

# --- Build Function ---

function Sync-BuildFolder {
    param(
        [string]$InventoryFile,
        [string]$SourceRoot,
        [string]$BuildPath,
        [switch]$Clean
    )

    $entries = Get-Content $InventoryFile | Where-Object { $_ }

    $expectedFiles = @()
    $copied = 0
    $skipped = 0
    $missing = @()

    foreach ($entry in $entries) {
        $src = Join-Path $SourceRoot $entry
        $dst = Join-Path $BuildPath $entry

        $expectedFiles += $dst

        if (!(Test-Path $src)) {
            $missing += $entry
            continue
        }

        $dstDir = Split-Path $dst
        if (!(Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }

        $copyNeeded = $true

        if (Test-Path $dst) {
            $srcInfo = Get-Item $src
            $dstInfo = Get-Item $dst

            # Compare size + last write time (fast)
            if ($srcInfo.Length -eq $dstInfo.Length -and
                $srcInfo.LastWriteTime -eq $dstInfo.LastWriteTime) {
                $copyNeeded = $false
            }
        }

        if ($copyNeeded) {
            Copy-Item $src $dst -Force
            $copied++
        } else {
            $skipped++
        }
    }

    # --- Optional cleanup ---
    if ($Clean) {
        $existingFiles = Get-ChildItem $BuildPath -Recurse -File | Select-Object -ExpandProperty FullName

        foreach ($file in $existingFiles) {
            if ($file -notin $expectedFiles) {
                Remove-Item $file -Force
            }
        }
    }

    # --- Report ---
    Write-Host "Copied: $copied"
    Write-Host "Skipped: $skipped"
    if ($missing.Count -gt 0) {
        Write-Host "Missing files:" -ForegroundColor Yellow
        $missing
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

    # --- Call Build Function ---
    $buildPath = Join-Path $BuildRoot $setName

    if (!(Test-Path $buildPath)) {
        New-Item -ItemType Directory -Path $buildPath | Out-Null
    }

    $plan = Get-SyncPlan -InventoryFile $inventory `
                        -SourceRoot $SourceRoot `
                        -BuildPath $buildPath `
                        -Clean:$Clean

    Show-SyncSummary $plan

    # --- Confirmation ---
    $confirm = Read-Host "Proceed with sync? (y/n)"
    if ($confirm -ne "y") {
        Write-Host "Cancelled."
        return
    }

    # --- Execute ---

    Sync-BuildFolder -InventoryFile $inventory `
                    -SourceRoot $SourceRoot `
                    -BuildPath $buildPath `
                    -Clean:$Clean

    Write-Host "Build complete."

        # Robocopy
        $roboargs = @(
            "`"$buildPath`"",
            "`"$dest`"",
            "/MIR",
            "/MT:16",
            "/R:1",
            "/W:1",
            "/XO" # exclude older files
        )

        if ($DryRun) {
            $roboargs += "/L"
            Write-Host "Running in DRY RUN mode"
        }

        robocopy @roboargs

        Write-Host "Deploy finished."
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
        "5" { return }
        default { Write-Host "Invalid option" }
    }

    Read-Host "Press Enter to continue"
}

Stop-Log