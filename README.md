# Smart Backup Script

This is an automated backup tool that creates compressed backups, verifies them using checksums, and automatically removes old backups based on daily, weekly, and monthly retention rules.

It supports:
- Configurable backup location
- Excluding unnecessary folders (like `.git`, `node_modules`)
- Dry-run mode (test without doing changes)
- Logging actions to a file
- Preventing multiple script runs using a lock file

---

## 📂 Project Structure

smart-backup/
│

├── backup.sh # Main backup script

├── backup.config # Settings (edit this, not the script)

└── backup.log # Log output (created automatically)

yaml

---

## ⚙️ Setup

1. Open the folder:
   ```bash
   cd ~/smart-backup
Make the script executable:


chmod +x backup.sh
Edit the configuration file:


nano backup.config
Default example configuration:

BACKUP_DESTINATION="$HOME/backups"
EXCLUDE_PATTERNS=".git,node_modules,.cache"
DAILY_KEEP=7
WEEKLY_KEEP=4
MONTHLY_KEEP=3
NOTIFY_EMAIL=""
Create the backup destination if needed:


mkdir -p "$HOME/backups"
📦 Creating a Backup
Run normally:

./backup.sh /path/to/folder
Example:

./backup.sh "/mnt/c/Users/maddy/Documents"
🧪 Dry Run (No changes made)

./backup.sh --dry-run /path/to/folder
✅ Backup Verification
After creating a backup:

A checksum file .sha256 is created

The script verifies integrity

It test-extracts one file to ensure no corruption

🧹 Retention Logic (Automatic Cleanup)
The script keeps:

Last 7 daily backups

Last 4 weekly backups

Last 3 monthly backups

Older backups are deleted automatically.

📜 Logs
All actions are logged to:

lua
Copy code
backup.log
View log:

tail -n 50 backup.log
🛑 Prevent Multiple Runs
The script uses:

/tmp/backup.lock
If the script is already running, another instance will exit immediately.

🔄 Restore Files (When Needed)
List contents:


tar -tzf backup-YYYY-MM-DD-HHMM.tar.gz | head
Restore entire backup:

tar -xzf backup-YYYY-MM-DD-HHMM.tar.gz -C /restore/target/folder
Restore a single file:



tar -xzf backup-YYYY-MM-DD-HHMM.tar.gz -C /restore/target/folder path/to/file
