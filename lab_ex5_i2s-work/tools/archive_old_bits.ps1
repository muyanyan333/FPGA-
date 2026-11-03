$ErrorActionPreference = 'Stop'
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$workspacePrefix = $workspaceRoot.TrimEnd('\') + '\'
$projectRoot = Join-Path $workspaceRoot 'lab_ex5_i2s-work\src\td_project'
$keepPaths = @('camera_player.bit', 'camera_player_volume_manual.bit', 'camera_player_spectrum_voice.bit', 'camera_player_noflash_seed2.bit') | ForEach-Object { Join-Path $projectRoot $_ }
foreach ($path in $keepPaths) { if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing retained firmware: $path" } }
if ((Get-FileHash -LiteralPath $keepPaths[0]).Hash -ne (Get-FileHash -LiteralPath $keepPaths[1]).Hash) { throw 'Default firmware differs from current named build' }
$candidates = @(Get-ChildItem -LiteralPath $workspaceRoot -Recurse -File -Filter '*.bit' | Where-Object {
    $_.FullName -notin $keepPaths -and !$_.FullName.StartsWith((Join-Path $workspaceRoot 'lab_ex5_i2s\2_key_led\'), [StringComparison]::OrdinalIgnoreCase)
})
if (!$candidates.Count) { Write-Output 'No obsolete bit files remain'; exit 0 }
foreach ($file in $candidates) {
    $resolved = [IO.Path]::GetFullPath($file.FullName)
    if (!$resolved.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Outside workspace: $resolved" }
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Unexpected reparse point: $resolved" }
}
$archiveDir = Join-Path $workspaceRoot '_archive\old_bits'
New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$archivePath = Join-Path $archiveDir "old_bits_$stamp.zip"
$manifest = @($candidates | ForEach-Object { [pscustomobject]@{
    Path = [IO.Path]::GetRelativePath($workspaceRoot, $_.FullName)
    Bytes = $_.Length
    SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
} })
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($item in $manifest) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $workspaceRoot $item.Path), $item.Path.Replace('\','/'), [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
$sha = [Security.Cryptography.SHA256]::Create()
try {
    foreach ($item in $manifest) {
        $entry = $archive.GetEntry($item.Path.Replace('\','/'))
        if (!$entry -or $entry.Length -ne $item.Bytes) { throw "Archive missing or truncated: $($item.Path)" }
        $stream = $entry.Open()
        try { $digest = [Convert]::ToHexString($sha.ComputeHash($stream)) } finally { $stream.Dispose() }
        if ($digest -ne $item.SHA256) { throw "Archive checksum mismatch: $($item.Path)" }
        if ((Get-FileHash -LiteralPath (Join-Path $workspaceRoot $item.Path)).Hash -ne $item.SHA256) { throw "Source changed: $($item.Path)" }
    }
} finally { $sha.Dispose(); $archive.Dispose() }
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $archiveDir "old_bits_$stamp.json") -Encoding utf8
foreach ($file in $candidates) { Remove-Item -LiteralPath $file.FullName }
$remaining = @(Get-ChildItem -LiteralPath $workspaceRoot -Recurse -File -Filter '*.bit')
if (@($remaining | Where-Object { $_.FullName -notin $keepPaths -and !$_.FullName.Contains('\2_key_led\') }).Count) { throw 'Obsolete bit files remain' }
Write-Output "Archived and removed: $($candidates.Count) files"
Write-Output "Original bytes: $(($manifest | Measure-Object -Property Bytes -Sum).Sum)"
Write-Output "Archive bytes: $((Get-Item -LiteralPath $archivePath).Length)"
Write-Output "Archive: $archivePath"
$remaining | ForEach-Object { Write-Output ([IO.Path]::GetRelativePath($workspaceRoot, $_.FullName)) }
