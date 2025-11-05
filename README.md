# Smart Backup Script

# A. Project Overview

This project is a backup rotation script.
It creates backups of a directory, saves them in a backup folder, and then removes old backups based on the rotation rules.

Why it is useful:
It helps keep backups organized without using too much storage.
Old backups are deleted automatically, so you do not have to manage them manually.

# B. How to Use It
1. Installation Steps

Copy the script into your system.

Make sure you have bash and basic Linux commands installed.

Give execution permission:

chmod +x backup.sh


Create a folder to store backups if it does not exist:

mkdir backups

2. Basic Usage Example

Run the script like this:

./backup.sh /path/to/source_folder /path/to/backups_folder


Example:

./backup.sh ~/mydata ~/backups

3. Command Options Explained
Option / Input	Meaning
1st argument	The folder you want to back up
2nd argument	The folder where backups will be stored
Rotation limit	Number of backups to keep (set inside script)
# C. How It Works
1. Rotation Algorithm

The script checks how many backups already exist in the backup folder.

If the number of backups is greater than the limit, the oldest backup is deleted first.

Then a new backup is created.

This keeps only the most recent backups.

2. Checksum Creation

After creating a backup .tar.gz file, the script generates a checksum using:

sha256sum


The checksum is saved in a .sha256 file to verify data integrity.

3. Backup Folder Structure
backups/
   backup_2025-11-05_10-30.tar.gz
   backup_2025-11-05_10-30.tar.gz.sha256
   backup_2025-11-04_09-15.tar.gz
   backup_2025-11-04_09-15.tar.gz.sha256
   ...

# D. Design Decisions

Simple .tar.gz compression was chosen because it is fast and widely supported.

The rotation was done using the oldest-first delete approach because it is easy and reliable.

Checksums help ensure the backup files are not corrupted.

Challenges Faced:

Ensuring correct sorting of backups by date.

Making sure backup folders were created even if missing.

Solutions:

Used date-based filenames for easy sorting.

Script checks and creates backup folder if needed.

# E. Testing
How Testing Was Done

Created a test folder with sample files.

Ran the script multiple times to generate multiple backups.

Checked if:

Backups were created correctly.

Old backups were removed when limit was reached.

Checksums were generated.

Example Output
Backup created: backup_2025-11-05_10-30.tar.gz
Checksum created: backup_2025-11-05_10-30.tar.gz.sha256
Oldest backup removed: backup_2025-11-03_08-10.tar.gz

# F. Known Limitations

Does not support remote backups (e.g., SSH or cloud storage).

No email or alert notification system.

Backup rotation limit must be edited manually inside the script.

No GUI — it is command-line only.

Possible Improvements:

Add support for S3 or Google Drive uploads.

Add email/Slack notifications.

Allow rotation limit to be passed as a command-line argument.

