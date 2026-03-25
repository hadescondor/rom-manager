# 🎮 ROM Manager

A PowerShell-based tool for **curating, organizing, and deploying ROM collections** with smart syncing, dry-run support, and logging.

---

## ✨ Features

* 📂 **Interactive Curation**

  * Select files/folders via file dialog
  * Automatically builds/updates collection lists

* ⚡ **Smart Syncing**

  * Only copies new or changed files
  * Skips unchanged files for fast deployments

* 🧹 **Clean Mode**

  * Removes files from the build that are not in the collection

* 🔍 **Dry Run Mode**

  * Preview changes before executing (no files copied or deleted)

* 📊 **Change Summary**

  * Shows:

    * Files to copy
    * Files to skip
    * Files to remove
    * Missing files

* 📝 **Logging**

  * Full session logs saved automatically

* ⚙️ **Config-Driven**

  * Central JSON config for paths and devices

---

## 📁 Project Structure

```
D:\ROMs\
├── config.json
├── collections\      # Your curated lists (.txt files)
├── _build\           # Temporary build output
├── logs\             # Session logs
└── tools\
    └── rom-manager.ps1
```

---

## ⚙️ Configuration

Edit `config.json`:

```json
{
  "SourceRoot": "D:\\ROMs",
  "CollectionsRoot": "D:\\ROMs\\collections",
  "BuildRoot": "D:\\ROMs\\_build",
  "LogRoot": "D:\\ROMs\\logs",
  "Devices": {
    "rg28xx": "E:\\ROMs",
    "miyoo": "F:\\ROMs",
    "retroid": "G:\\ROMs"
  }
}
```

### 🔑 Key Fields

* **SourceRoot**
  Root directory where your ROM library lives

* **CollectionsRoot**
  Where your curated `.txt` files are stored

* **BuildRoot**
  Temporary staging area before deployment

* **Devices**
  Maps collection names → destination paths

---

## 🧭 Usage

Run the script:

```powershell
.\rom-manager.ps1
```

---

## 📋 Menu Options

```
1) Curate Collection
2) Deploy (Clean)
3) Deploy (No Clean)
4) Deploy (Dry Run)
5) Exit
```

---

## 🛠️ Workflow

### 1. Curate a Collection

* Select files and/or folders
* Choose an existing collection file (or create a new one)
* Files are saved as **relative paths**

Example output:

```
gba\Pokemon Emerald.zip
gb\Final Fantasy Adventure.zip
```

---

### 2. Deploy a Collection

* Select a collection file
* Tool builds a sync plan
* Displays a summary
* Prompts for confirmation

---

## 🔍 Sync Summary Example

```
=== Sync Summary ===
To Copy  : 5
To Skip  : 120
To Remove: 2
Missing  : 1
```

---

## 🧠 How Smart Sync Works

The tool compares:

* File size
* Last modified time

### Result:

* ✅ Copy if changed
* ⏭ Skip if identical
* 🗑 Remove if not in collection (Clean mode)

---

## 🧹 Clean Mode Explained

**Clean mode does NOT wipe the build folder.**

Instead, it:

* Removes files in `_build` that are **not in the collection**

### Example

**Collection:**

```
A.zip
B.zip
```

**Build folder before:**

```
A.zip
B.zip
C.zip
```

**After Clean:**

```
A.zip
B.zip
```

---

## 🧪 Dry Run Mode

* Uses robocopy’s `/L` flag
* No files are copied or deleted
* Safe way to preview changes

---

## 🚀 Deployment Details

After building the collection:

* Uses `robocopy` to sync to the target device
* Preserves folder structure
* Multi-threaded for speed

---

## 📝 Logging

* Logs stored in `/logs`
* Automatically created per session:

```
logs\session_YYYYMMDD_HHMMSS.log
```

Includes:

* Menu actions
* File operations
* Robocopy output

---

## ⚠️ Known Considerations

* Paths are case-insensitive but normalized internally
* Missing files are reported but not fatal
* Large collections benefit significantly from smart sync

---

## 💡 Tips

* Use **Dry Run** before large deployments
* Keep collections clean to avoid unnecessary removals
* Logs are helpful for troubleshooting

---

## 🔮 Future Ideas

* Device selection menu
* GUI interface (WinForms/WPF)
* Hash-based verification (optional)
* Progress indicators

---

## 🙌 Acknowledgments

Built as a custom tool for managing curated ROM libraries with efficiency and control.

---

## 📜 License

Personal use / modify as needed

```
```
