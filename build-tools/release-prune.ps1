<#
  release-prune.ps1 - 发布产物轮转（规则见 F:\vebcoding\RULES.md）
  1) 备份上一个大版本到 artifacts\_backup\<version>.zip（校验项数）
  2) 删除所有更旧的版本目录 + artifacts 根下散落临时文件
  3) _backup 里只保留上一版一份
  用法: .\release-prune.ps1 -ProjectRoot F:\vebcoding\ClassDay -CurrentVersion 2.10.4 [-DryRun]
#>
param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$CurrentVersion,
  [switch]$DryRun
)

Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
$art = Join-Path $ProjectRoot "artifacts"
if (-not (Test-Path $art)) { throw "找不到 artifacts: $art" }

function Get-VerNum([string]$name) {
  $nums = @()
  foreach ($p in ($name -split "[.\-_+]")) {
    if ($p -match "^\d+$") { $nums += [int]$p } else { break }
  }
  if ($nums.Count -eq 0) { return $null }
  return ($nums -join ".")
}

$dirs = Get-ChildItem $art -Directory | Where-Object {
  $_.Name -match '^\d+(\.\d+){0,3}$' -and $_.Name -ne $CurrentVersion
}
$dirs = $dirs | Sort-Object { [version](Get-VerNum $_.Name) }

$prev = $null
$older = @()
if ($dirs.Count -ge 1) { $prev = $dirs[$dirs.Count - 1] }
if ($dirs.Count -ge 2) { $older = $dirs[0..($dirs.Count - 2)] }

$backupDir = Join-Path $art "_backup"
if (-not $DryRun -and -not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

if ($prev) {
  $zip = Join-Path $backupDir ($prev.Name + ".zip")
  $files = Get-ChildItem $prev.FullName -Recurse -File
  $sum = ($files | Measure-Object Length -Sum).Sum
  Write-Output ("备份上一版: {0}  {1} 文件 / {2} MB -> {3}" -f $prev.Name, $files.Count, [math]::Round($sum/1MB,1), $zip)
  if (-not $DryRun) {
    if (Test-Path $zip) { Remove-Item $zip -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($prev.FullName, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    $z = [System.IO.Compression.ZipFile]::OpenRead($zip)
    $inZip = ($z.Entries | Where-Object { $_.Name -ne "" }).Count
    $z.Dispose()
    if ($inZip -lt [math]::Floor($files.Count * 0.9)) { throw ("备份校验失败: zip {0} 项 < 源 {1}" -f $inZip, $files.Count) }
    Write-Output ("  校验通过: {0} 项, {1} MB" -f $inZip, [math]::Round((Get-Item $zip).Length/1MB,1))
    if (-not $DryRun) {
      Write-Output ("  备份完成，删除原目录: {0}" -f $prev.Name)
      Remove-Item $prev.FullName -Recurse -Force
    }
  }
} else {
  Write-Output "没有更早版本，跳过备份"
}

foreach ($d in $older) {
  $files = Get-ChildItem $d.FullName -Recurse -File
  $sum = ($files | Measure-Object Length -Sum).Sum
  Write-Output ("删除旧版本: {0}  {1} 文件 / {2} MB" -f $d.Name, $files.Count, [math]::Round($sum/1MB,1))
  if (-not $DryRun) { Remove-Item $d.FullName -Recurse -Force }
}

if (Test-Path $backupDir) {
  Get-ChildItem $backupDir -Filter *.zip | ForEach-Object {
    if (-not $prev -or $_.BaseName -ne $prev.Name) {
      Write-Output ("删除过期备份: {0}" -f $_.Name)
      if (-not $DryRun) { Remove-Item $_.FullName -Force }
    }
  }
}

Get-ChildItem $art -Directory | Where-Object { $_.Name -match "^(ci-log|debug|tmp)" } | ForEach-Object {
  Write-Output ("删除调试目录: {0}" -f $_.Name)
  if (-not $DryRun) { Remove-Item $_.FullName -Recurse -Force }
}

Get-ChildItem $art -File | Where-Object { $_.Extension -in @(".log", ".tmp") -or $_.Name -like "tmp-*" } | ForEach-Object {
  Write-Output ("删除散落文件: {0}" -f $_.Name)
  if (-not $DryRun) { Remove-Item $_.FullName -Force }
}

Write-Output ""
Write-Output "==== 最终保留 ===="
Get-ChildItem $art | Sort-Object Name | ForEach-Object {
  if ($_.PSIsContainer) {
    $sz = [math]::Round(((Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)/1MB, 1)
    Write-Output ("  [目录] {0}  {1} MB" -f $_.Name, $sz)
  } else {
    Write-Output ("  [文件] {0}  {1} MB" -f $_.Name, [math]::Round($_.Length/1MB, 2))
  }
}
