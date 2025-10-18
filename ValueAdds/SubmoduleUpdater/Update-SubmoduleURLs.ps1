param(
  [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
  [string[]]$Repos
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Check prerequisites
& git --version | Out-Null
if ($LASTEXITCODE -ne 0) { 
  throw "git not found. Please install git first." 
}

# URL mappings
$oldURLs = @(
  "https://gitee.com/vChewing/libvchewing-data.git",
  "https://gitee.com/vChewing/libvchewing-data",
  "http://gitee.com/vChewing/libvchewing-data.git",
  "http://gitee.com/vChewing/libvchewing-data",
  "git@gitee.com:vChewing/libvchewing-data.git",
  "git://gitee.com/vChewing/libvchewing-data"
)
$newURL = "https://gitlink.org.cn/vChewing/vChewing-VanguardLexicon.git"

foreach ($repoPath in $Repos) {
  Write-Host "`n========================================" -ForegroundColor Cyan
  Write-Host "Processing repository: $repoPath" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  
  # Resolve to absolute path
  $fullPath = Resolve-Path -Path $repoPath -ErrorAction Stop
  
  # Verify it's a git repository
  if (-not (Test-Path (Join-Path $fullPath ".git"))) { 
    throw "Not a git repository: $fullPath" 
  }
  
  Push-Location $fullPath
  try {
    Write-Host "[INFO] Rewriting .gitmodules in all commits using git filter-branch..." -ForegroundColor Yellow
    
    # Suppress deprecated warning
    $env:FILTER_BRANCH_SQUELCH_WARNING = "1"
    
    # Create a filter script that will be executed for each commit
    $filterScript = @"
if [ -f .gitmodules ]; then
  # Use perl for reliable in-place editing across platforms (case-insensitive)
  perl -i -pe 's|https://gitee\.com/vchewing/libvchewing-data\.git|$newURL|gi' .gitmodules
  perl -i -pe 's|https://gitee\.com/vchewing/libvchewing-data|$newURL|gi' .gitmodules
  perl -i -pe 's|http://gitee\.com/vchewing/libvchewing-data\.git|$newURL|gi' .gitmodules
  perl -i -pe 's|http://gitee\.com/vchewing/libvchewing-data|$newURL|gi' .gitmodules
  perl -i -pe 's|git\@gitee\.com:vchewing/libvchewing-data\.git|$newURL|gi' .gitmodules
  perl -i -pe 's|git://gitee\.com/vchewing/libvchewing-data|$newURL|gi' .gitmodules
fi
"@
    
    # Run filter-branch with tree-filter (checks out files, slower but reliable)
    git filter-branch --force --tree-filter $filterScript --tag-name-filter cat -- --all
    
    if ($LASTEXITCODE -ne 0) {
      throw "git filter-branch failed for $fullPath"
    }
    
    Write-Host "[INFO] Updating working tree..." -ForegroundColor Yellow
    
    # Update working tree to reflect changes
    git checkout HEAD 2>&1 | Out-Null
    
    # Sync submodule configuration
    Write-Host "[INFO] Syncing submodules..." -ForegroundColor Yellow
    git submodule sync --recursive 2>&1 | Out-Null
    
    # Verify the changes
    Write-Host "[INFO] Verifying changes..." -ForegroundColor Yellow
    $grepResult = git --no-pager grep -n "gitee.com/vChewing/libvchewing-data" -- .gitmodules 2>&1
    
    if ($LASTEXITCODE -eq 0) {
      Write-Host "[WARN] Leftover gitee URL found in $fullPath/.gitmodules:" -ForegroundColor Red
      Write-Host $grepResult -ForegroundColor Red
    } else {
      Write-Host "[OK] Successfully replaced all URLs in $fullPath" -ForegroundColor Green
    }
    
    # Clean up filter-branch backup refs
    Write-Host "[INFO] Cleaning up backup refs..." -ForegroundColor Yellow
    git for-each-ref --format="%(refname)" refs/original/ | ForEach-Object {
      git update-ref -d $_
    }
    
    # Run garbage collection
    Write-Host "[INFO] Running git gc to clean up repository..." -ForegroundColor Yellow
    git reflog expire --expire=now --all 2>&1 | Out-Null
    git gc --prune=now --aggressive 2>&1 | Out-Null
    
    Write-Host "[OK] Repository $fullPath processed successfully!" -ForegroundColor Green
    Write-Host "[INFO] To push the rewritten history, run:" -ForegroundColor Yellow
    Write-Host "       git push --force-with-lease --all" -ForegroundColor Cyan
    Write-Host "       git push --force-with-lease --tags" -ForegroundColor Cyan
    
  } catch {
    Write-Host "[ERROR] Failed to process $fullPath : $_" -ForegroundColor Red
    throw
  } finally {
    Pop-Location
  }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "All repositories processed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
