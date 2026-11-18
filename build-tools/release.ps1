<#
  release.ps1 —— 一条命令发版（规则见 F:\vebcoding\RULES.md / Classday\Docs\RELEASE-RETENTION.md）
  流程：改版本号 -> 构建 -> 收产物到 artifacts\<版本>\ -> iOS 触发 CI 取回 IPA
        -> 备份上一版并清理旧版 -> 写 RELEASE-NOTES.md
  用法：
    .\release.ps1 -Version 2.10.5                     # 安卓本地构建 + iOS 推 CI
    .\release.ps1 -Version 2.10.5 -Platform android    # 只出安卓
    .\release.ps1 -Version 2.10.5 -SkipPrune           # 不清旧版（调试用）
#>
param(
  [Parameter(Mandatory=$true)][string]$Version,
  [ValidateSet("both","android","ios")][string]$Platform = "both",
  [switch]$SkipPrune,
  [int]$IosWaitMinutes = 40
)

$repo    = "F:\vebcoding\ClassDay\source\classday-ios"
$artRoot = "F:\vebcoding\ClassDay\artifacts"
$outDir  = Join-Path $artRoot $Version
$enc     = New-Object System.Text.UTF8Encoding($false)

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Say "发布课曜 $Version（$Platform）-> $outDir"

# ---------- 1. 版本号 ----------
$vp = @($Version -split "[.\-+]" | Where-Object { $_ -match "^\d+$" } | ForEach-Object { [int]$_ })
while ($vp.Count -lt 3) { $vp += 0 }
$code = $vp[0] * 10000 + $vp[1] * 100 + $vp[2]

if ($Platform -in @("both","android")) {
  Say "更新 Android versionName=$Version / versionCode=$code"
  $g = Join-Path $repo "android\app\build.gradle.kts"
  if (-not (Test-Path $g)) { throw "找不到 $g" }
  $t = [System.IO.File]::ReadAllText($g)
  $t = [regex]::Replace($t, "versionCode\s*=\s*\d+", "versionCode = $code")
  $t = [regex]::Replace($t, "versionName\s*=\s*`"[^`"]+`"", "versionName = `"$Version`"")
  [System.IO.File]::WriteAllText($g, $t, $enc)
}
if ($Platform -in @("both","ios")) {
  Say "更新 iOS MARKETING_VERSION=$Version"
  $pbx = Join-Path $repo "Classday\Classday.xcodeproj\project.pbxproj"
  if (-not (Test-Path $pbx)) { throw "找不到 $pbx" }
  $t = [System.IO.File]::ReadAllText($pbx)
  $t = [regex]::Replace($t, "MARKETING_VERSION = [0-9.]+;", "MARKETING_VERSION = $Version;")
  [System.IO.File]::WriteAllText($pbx, $t, $enc)
}

# ---------- 2. 安卓构建 ----------
if ($Platform -in @("both","android")) {
  Say "构建 Android release"
  $anda = Join-Path $repo "android"
  Push-Location $anda
  & ".\gradlew.bat" ":app:assembleRelease" "--offline" "--console=plain" "-q"
  $gx = $LASTEXITCODE
  Pop-Location
  if ($gx -ne 0) { throw "Android 构建失败（exit $gx）" }
  $apk  = Join-Path $anda "app\build\outputs\apk\release\app-release.apk"
  $dest = Join-Path $outDir "Classday-android-v$Version.apk"
  Copy-Item $apk $dest -Force
  Say ("APK: {0}  {1} MB" -f $dest, [math]::Round((Get-Item $dest).Length/1MB,1))
}

# ---------- 3. iOS 提交 + CI ----------
if ($Platform -in @("both","ios")) {
  Say "提交并推送 iOS 代码到 GitLab"
  Push-Location $repo
  $env:GIT_TERMINAL_PROMPT = "0"
  git add -A | Out-Null
  git reset -q -- Classday/Docs/project-check.log 2>$null
  $msgFile = Join-Path $env:TEMP "rel-msg.txt"
  [System.IO.File]::WriteAllText($msgFile, "release: 课曜 $Version", $enc)
  git -c i18n.commitEncoding=utf-8 commit -q -F $msgFile 2>$null
  git push gitlab "autoloop/improvements:autoloop/improvements" 2>&1 | Out-Null
  Say "已推送 GitLab（Codemagic 从该分支拉代码）"

  $tokenFile = "F:\vebcoding\ClassDay\build-tools\.github-token"
  if (Test-Path $tokenFile) {
    Say "推 GitHub ios-build 触发 CI（最多等 $IosWaitMinutes 分钟）"
    $tok = (Get-Content $tokenFile -Raw).Trim()
    $h = @{ Authorization = "Bearer $tok"; Accept = "application/vnd.github+json"; "User-Agent" = "classday-agent" }
    $ghRepo = "yuanyeye0210-debug/classday-ios"
    $snap = "rel-$Version"
    git checkout -q --orphan $snap 2>$null
    git add -A | Out-Null
    git -c i18n.commitEncoding=utf-8 commit -q -F $msgFile 2>$null
    git merge -s ours "origin/main" --allow-unrelated-histories -m "merge: main 历史" 2>$null | Out-Null
    git push origin "HEAD:ios-build" --force 2>&1 | Out-Null
    $sha = (git rev-parse HEAD)
    Say "已推 ios-build（$($sha.Substring(0,7))）"
    $deadline = (Get-Date).AddMinutes($IosWaitMinutes)
    $run = $null
    $ok  = $false
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 60
      try {
        $runs = Invoke-RestMethod "https://api.github.com/repos/$ghRepo/actions/runs?per_page=5&branch=ios-build" -Headers $h
        $run = $runs.workflow_runs | Where-Object { $_.head_sha -eq $sha } | Select-Object -First 1
        if (-not $run) { Say "CI 尚未登记，继续等"; continue }
        Say ("CI {0} {1}" -f $run.status, $run.conclusion)
        if ($run.status -eq "completed") { $ok = ($run.conclusion -eq "success"); break }
      } catch { Say "查询失败: $($_.Exception.Message)" }
    }
    if ($ok -and $run) {
      $arts = Invoke-RestMethod "https://api.github.com/repos/$ghRepo/actions/runs/$($run.id)/artifacts" -Headers $h
      $art = $arts.artifacts | Where-Object { $_.name -like "Classday-unsigned-ipa*" } | Select-Object -First 1
      if ($art) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
        $zip = Join-Path $outDir "ipa.zip"
        Invoke-WebRequest "https://api.github.com/repos/$ghRepo/actions/artifacts/$($art.id)/zip" -Headers $h -OutFile $zip
        $ex = Join-Path $outDir "ipa-x"
        if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $ex)
        $ipaFile = Get-ChildItem $ex -Recurse -Filter *.ipa | Select-Object -First 1
        if ($ipaFile) {
          Copy-Item $ipaFile.FullName (Join-Path $outDir "Classday-ios-v$Version.ipa") -Force
          Say "IPA 已取回"
        }
        Remove-Item $ex -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
      }
    } else {
      Write-Warning "GitHub CI 未在 $IosWaitMinutes 分钟内成功；可到 Codemagic 手动点构建（分支 autoloop/improvements）"
    }
  }
  git checkout -q autoloop/improvements 2>$null
  Pop-Location
}

# ---------- 4. 轮转 ----------
if (-not $SkipPrune) {
  Say "执行产物轮转（备份上一版 + 清理旧版）"
  & "F:\vebcoding\ClassDay\build-tools\release-prune.ps1" -ProjectRoot "F:\vebcoding\ClassDay" -CurrentVersion $Version
}

# ---------- 5. RELEASE-NOTES ----------
$files = Get-ChildItem $outDir -File | Where-Object { $_.Extension -in @(".apk",".ipa") }
$rows = @()
foreach ($f in $files) {
  $rows += ("| {0} | {1} MB | {2}... |" -f $f.Name, [math]::Round($f.Length/1MB,2), (Get-FileHash $f.FullName -Algorithm SHA256).Hash.Substring(0,32))
}
$notes = @(
  "# 课曜 $Version 发布记录",
  "",
  "- 版本：$Version",
  "- 发布：$(Get-Date -Format 'yyyy-MM-dd HH:mm')",
  "- 平台：$Platform",
  "",
  "## 产物",
  "",
  "| 文件 | 大小 | SHA256（前32位） |",
  "|---|---|---|"
) + $rows
[System.IO.File]::WriteAllText((Join-Path $outDir "RELEASE-NOTES.md"), ($notes -join "`r`n"), $enc)

Say "完成：$outDir"
Get-ChildItem $outDir -File | ForEach-Object { "    " + $_.Name }
