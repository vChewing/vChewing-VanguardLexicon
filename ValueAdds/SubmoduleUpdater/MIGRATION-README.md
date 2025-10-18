# Submodule URL Migration Scripts

This directory contains scripts to migrate git submodule URLs from `gitee.com/vChewing/libvchewing-data` to `gitlink.org.cn/vChewing/vChewing-VanguardLexicon` across all commits and tags in a repository's history.

## ⚠️ Important Warnings

**THESE SCRIPTS REWRITE GIT HISTORY!** 

Before using:
1. **Create a full backup** of your repository
2. **Test on a clone** first, not the original repository
3. **Coordinate with all team members** - everyone will need to re-clone after the migration
4. **Understand that all commit SHAs will change**

## Available Scripts

### 1. Update-SubmoduleURLs.ps1 (PowerShell)

PowerShell script using `git filter-branch` to rewrite repository history.

**Prerequisites:**
- Git
- PowerShell (pwsh) or Windows PowerShell

**Usage:**
```powershell
pwsh Update-SubmoduleURLs.ps1 <repo-path-1> [repo-path-2] [...]
```

**Example:**
```powershell
pwsh Update-SubmoduleURLs.ps1 /path/to/vChewing-macOS /path/to/vChewing-OSX-Legacy
```

### 2. update-submodule-urls.py (Python)

Python script using `git-filter-repo` to rewrite repository history.

**Prerequisites:**
- Python 3.6+
- Git  
- git-filter-repo (`pip install git-filter-repo`)

**Usage:**
```bash
python3 update-submodule-urls.py <repo-path-1> [repo-path-2] [...]
```

**Example:**
```bash
python3 update-submodule-urls.py /path/to/vChewing-macOS /path/to/vChewing-OSX-Legacy
```

## What the Scripts Do

1. **Rewrite history**: Replace all occurrences of old submodule URLs with the new URL in all commits and tags
2. **Update working tree**: Checkout HEAD to reflect the changes
3. **Sync submodules**: Update submodule configuration
4. **Run garbage collection**: Clean up the repository and reduce size
5. **Verify**: Check if any old URLs remain

## URLs Being Replaced

The scripts replace the following URL patterns:
- `https://gitee.com/vChewing/libvchewing-data.git`
- `https://gitee.com/vChewing/libvchewing-data`
- `http://gitee.com/vChewing/libvchewing-data.git`
- `http://gitee.com/vChewing/libvchewing-data`
- `git@gitee.com:vChewing/libvchewing-data.git`
- `git://gitee.com/vChewing/libvchewing-data`

All are replaced with:
- `https://gitlink.org.cn/vChewing/vChewing-VanguardLexicon.git`

## After Running the Scripts

The scripts DO NOT push changes automatically. After verification, you must manually push:

```bash
# Push all branches (WARNING: Force push!)
git push --force-with-lease --all

# Push all tags (WARNING: Force push!)
git push --force-with-lease --tags
```

## Known Issues

⚠️ **Important**: During development and testing, we discovered that git-filter-repo's `--replace-text` feature and blob callbacks do not reliably replace URLs in `.gitmodules` files for some repositories, even though they work correctly on simple test cases. The root cause is still under investigation.

**Recommendations:**
1. Always test on a backup/clone first
2. Manually verify the changes after running the script
3. Check several commits in history to ensure URLs were replaced:
   ```bash
   git log --all --oneline --grep="<search-term>"
   git show <commit-sha>:.gitmodules
   ```

## Troubleshooting

### Script fails with "not a git repository"
Ensure the path points to a directory containing a `.git` folder.

### Old URLs still present after running
1. Check the script output for errors
2. Manually inspect commits: `git show <commit>:.gitmodules`
3. Verify you're checking the correct branch/tag

### "origin remote removed" warning
This is expected behavior for git-filter-repo to prevent accidental pushes of rewritten history to the wrong remote.

## Recovery

If something goes wrong:

### PowerShell Script (filter-branch)
```bash
# Restore from backup refs
git reset --hard refs/original/refs/heads/main

# Or restore from tag
git reset --hard BACKUP-<timestamp>
```

### Python Script (filter-repo)
You'll need to restore from your backup clone, as git-filter-repo doesn't keep original refs by default.

## Support

For issues or questions, please open an issue in the repository.
