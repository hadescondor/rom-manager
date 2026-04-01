# ROM Manager

A PowerShell-based ROM curation and deployment tool that uses **inventory files as the single source of truth** to manage and synchronize collections across devices.

---

## 🚀 Features

* 🎮 Curate ROM collections via file picker UI
* 📄 Inventory-driven system (your `.txt` files define everything)
* 🔄 Smart sync (copy only when needed)
* 🧹 Optional clean mode (removes unmanaged files)
* 🔍 Dry-run support for safe previews
* 📊 Sync summary before execution
* 🛑 Safety checks to prevent dangerous operations
* 📝 Session logging

---

## 📁 Project Structure

```
rom-manager/
│
├── config.json          # Configuration file
├── rom-manager.ps1      # Main script
├── collections/         # Inventory files (.txt)
├── logs/                # Session logs
```

---

## ⚙️ Configuration

Edit `config.json`:

```json
{
  "SourceRoot": "D:\\ROMs",
  "CollectionsRoot": "D:\\rom-manager\\collections",
  "LogRoot": "D:\\rom-manager\\logs",
  "Devices": {
    "rg28xx": "E:\\ROMs",
    "rpc4b": "G:\\ROMs",
    "rpc6b": "H:\\ROMs"
  },
  "Exclusions": [
    ".nomedia",
    "systeminfo.txt",
    "systems.txt",
    "Thumbs.db"
  ],
  "ExcludeDirectories": [
    "BIOS",
    "System Volume Information"
  ]
}
```

> [!NOTE] 
> Anything in the "Exclusions" or "ExcludedDirectories" will not be removed when "Clean" is used.

### Fields

* **SourceRoot** → Master ROM directory
* **CollectionsRoot** → Where inventory files live
* **LogRoot** → Log output directory
* **Devices** → Maps inventory name → destination path

---

## 🧠 Core Concept

### Inventory = Source of Truth

Each `.txt` file defines a collection:

```
SuperMarioBros.nes
Zelda.nes
Metroid.nes
```

This list fully determines:

* What gets copied ✅
* What gets skipped ✅
* What gets deleted (in clean mode) ✅

---

## 🖥️ Usage

Run the script:

```powershell
.\rom-manager.ps1
```

### Menu Options

```
1) Curate Collection
2) Deploy Collection (Clean)
3) Deploy Collection (No Clean)
4) Deploy (Dry Run)
5) Exit
```

---

## 🎯 Curation Workflow

1. Select files/folders from `SourceRoot`
2. Select an inventory file
3. Script:

   * Expands folders recursively
   * Converts to relative paths
   * Merges with existing inventory
   * Removes duplicates
4. Preview is shown
5. Inventory file is updated

---

## 🔄 Deployment Behavior

### Sync Logic

For each file in inventory:

* ✅ Copy if missing
* ✅ Copy if changed (size or timestamp)
* ⏭ Skip if identical
* ⚠ Report if missing from source

---

## 🧹 Clean Mode

When using **Clean**, the destination becomes an exact mirror of the inventory.<sup>*see note below</sup>

### Example

#### Inventory:

```
Mario.nes
Zelda.nes
```

#### Destination BEFORE:

```
Mario.nes
Zelda.nes
Metroid.nes   ❌ extra
```

#### AFTER Clean:

```
Mario.nes
Zelda.nes
```

👉 Any file not in the inventory is **removed**<sup>*</sup>.

<sup>*Anything listed in the config under "Exclusions" or "ExcludedDirectories" will not be removed when "Clean" is used.</sup>

---

## 🔍 Dry Run

Simulates the entire sync:

* Shows what would be copied
* Shows what would be deleted
* Makes **no changes**

---

## 📊 Sync Summary

Before execution, the tool shows:

```
To Copy   : X
To Skip   : Y
To Remove : Z
Missing   : N
```

Large deletes (>50 files) require manual confirmation.

---

## 🛡️ Safety Features

* Prevents syncing into source directory
* Prevents dangerous parent/child path overlap
* Requires confirmation for large deletions
* Dry-run mode for safe testing

---

## 📝 Logging

Each session creates a log file:

```
logs/session_YYYYMMDD_HHMMSS.log
```

---

## ⚡ Design Principles

* Deterministic (same input → same result)
* Inventory-driven
* Minimal unnecessary copying
* Safe by default
* Transparent operations

---

## 🔮 Future Improvements (Optional)

* Parallel copy operations for performance
* File hash comparison for deeper validation
* CLI argument support (non-interactive mode)
* Progress bars for large sync jobs

---

## ✅ Summary

ROM Manager is a lightweight but powerful tool that gives you:

* Full control over your ROM sets
* Clean, predictable deployments
* Confidence through preview + safety checks

---

Enjoy managing your collections 🎮
