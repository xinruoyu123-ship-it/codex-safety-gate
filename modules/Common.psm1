Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CsgRoot {
    if ($env:CSG_HOME) { return $env:CSG_HOME }
    return (Join-Path $HOME '.codex-safety-v2')
}

function Initialize-CsgLayout {
    $root = Get-CsgRoot
    foreach ($name in @('artifacts','reports','stages','registry','backups','tmp','toolchains')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $root $name) | Out-Null
    }
    return $root
}

function Write-JsonFile {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path,[int]$Depth=20)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $tempPath = Join-Path $parent ('.{0}.{1}.tmp' -f (Split-Path -Leaf $fullPath),[guid]::NewGuid().ToString('N'))
    try {
        $json = $Value | ConvertTo-Json -Depth $Depth
        [IO.File]::WriteAllText($tempPath,$json,[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($tempPath,$fullPath,$true)
    } finally {
        if ([IO.File]::Exists($tempPath)) { [IO.File]::Delete($tempPath) }
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RelativePathSafe {
    param([Parameter(Mandatory)][string]$Base,[Parameter(Mandatory)][string]$Full)
    $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd('\','/')
    $fullFull = [IO.Path]::GetFullPath($Full)
    $relative = [IO.Path]::GetRelativePath($baseFull,$fullFull)
    if ($relative -eq '..' -or $relative.StartsWith('..\',[StringComparison]::Ordinal) -or $relative.StartsWith('../',[StringComparison]::Ordinal) -or [IO.Path]::IsPathRooted($relative)) {
        throw "Path is outside the allowed root: $fullFull"
    }
    return $relative
}

function Assert-CsgSafeId {
    param([Parameter(Mandatory)][string]$Id,[string]$Kind='CSG')
    if ($Id.Length -gt 128 -or $Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $Id.Contains('..')) {
        throw "$Kind identifier contains unsafe path characters."
    }
    return $Id
}

function Resolve-CsgChildPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$RelativePath,
        [switch]$RejectReparsePoints
    )
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains(':')) {
        throw "Relative path is not allowed: $RelativePath"
    }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $targetFull = [IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))
    $null = Get-RelativePathSafe -Base $rootFull -Full $targetFull

    if ($RejectReparsePoints) {
        $current = $rootFull
        $segments = @($RelativePath -split '[\\/]' | Where-Object { $_ })
        foreach ($segment in @('') + $segments) {
            if ($segment) { $current = Join-Path $current $segment }
            if (Test-Path -LiteralPath $current) {
                $item = Get-Item -LiteralPath $current -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Reparse point is not allowed in a protected path: $current"
                }
            }
        }
    }
    return $targetFull
}

function Assert-NoReparsePoints {
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    $items = @((Get-Item -LiteralPath $Root -Force)) + @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop)
    $reparse = $items | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } | Select-Object -First 1
    if ($reparse) { throw "Reparse point is not allowed in CSG-controlled content: $($reparse.FullName)" }
}

function Test-CsgProtectedCodexPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = $RelativePath.Replace('/','\').TrimStart('\').ToLowerInvariant()
    $root = @($path -split '\\',2)[0]

    if ($path -match '^(auth|credentials)\.json(?:\.|$)') { return $true }
    if ($path -match '^(session_index|history|transcription-history)\.jsonl(?:\.|$)') { return $true }
    if ($path -match '^(config\.toml|agents\.md|models_cache\.json)(?:\.|$)') { return $true }
    if ($root -match '^\.{1,2}codex-global-state\.json(?:\.|$)' -or $root -match '\.sqlite(?:-.+)?$') { return $true }

    return $root -in @(
        'sessions','archived_sessions','attachments','.sandbox-secrets','browser',
        'computer-use','dictation-history','memories','automations','generated_images',
        'visualizations','worktrees','thread-writer-locks','process_manager','backups'
    )
}

function Test-CsgPromotableCodexPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = $RelativePath.Replace('/','\').TrimStart('\')
    if (Test-CsgProtectedCodexPath -RelativePath $path) { return $false }

    $segments = @($path -split '\\')
    if ($segments.Count -lt 3 -or $segments[0] -ine 'skills') { return $false }
    if ($segments[1].Length -gt 128 -or $segments[1] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $segments[1].Contains('..')) { return $false }
    return $true
}

function Assert-CsgPromotableCodexPath {
    param([Parameter(Mandatory)][string]$RelativePath)
    if (Test-CsgProtectedCodexPath -RelativePath $RelativePath) {
        throw "Protected Codex path cannot be promoted: $RelativePath"
    }
    if (-not (Test-CsgPromotableCodexPath -RelativePath $RelativePath)) {
        throw "Generic promotion accepts only isolated skills/<name> files: $RelativePath"
    }
    return $RelativePath
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    $rootFull = [IO.Path]::GetFullPath($Root)
    Assert-NoReparsePoints -Root $rootFull
    $rows = @()
    foreach ($f in Get-ChildItem -LiteralPath $rootFull -Recurse -Force -File -ErrorAction Stop) {
        $rows += [pscustomobject]@{
            path=(Get-RelativePathSafe -Base $rootFull -Full $f.FullName).Replace('/','\')
            size=[int64]$f.Length
            sha256=(Get-Sha256 $f.FullName)
        }
    }
    return @($rows | Sort-Object @{Expression={
        [Convert]::ToHexString([Text.Encoding]::UTF8.GetBytes([string]$_.path))
    }})
}

function Compare-TreeSnapshots {
    param($Before,$After)
    $b=@{}; $a=@{}
    foreach($x in @($Before)){ $b[$x.path.ToLowerInvariant()]=$x }
    foreach($x in @($After)){ $a[$x.path.ToLowerInvariant()]=$x }
    $changes=@()
    foreach($k in @($b.Keys+$a.Keys|Sort-Object -Unique)){
        if(-not $b.ContainsKey($k)){
            $changes += [pscustomobject]@{action='added';path=$a[$k].path;before=$null;after=$a[$k].sha256}
        } elseif(-not $a.ContainsKey($k)){
            $changes += [pscustomobject]@{action='deleted';path=$b[$k].path;before=$b[$k].sha256;after=$null}
        } elseif($b[$k].sha256 -ne $a[$k].sha256){
            $changes += [pscustomobject]@{action='modified';path=$a[$k].path;before=$b[$k].sha256;after=$a[$k].sha256}
        }
    }
    return @($changes)
}

function New-Id {
    param([string]$Prefix='csg')
    return ('{0}-{1}-{2}' -f $Prefix,(Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8)))
}

function Copy-Tree {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    if(-not (Test-Path -LiteralPath $Source)){ return }
    Assert-NoReparsePoints -Root $Source
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Recurse -Force | ForEach-Object {
        $rel=Get-RelativePathSafe -Base $Source -Full $_.FullName
        $dst=Join-Path $Destination $rel
        if($_.PSIsContainer){ New-Item -ItemType Directory -Force -Path $dst | Out-Null }
        else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
        }
    }
}


function Get-FileState {
    param([Parameter(Mandatory)][string]$Path)
    if(-not (Test-Path -LiteralPath $Path)){ return [pscustomobject]@{exists=$false;sha256=$null;size=$null} }
    $item=Get-Item -LiteralPath $Path -Force
    if($item.PSIsContainer){ return [pscustomobject]@{exists=$true;sha256=$null;size=$null;directory=$true} }
    return [pscustomobject]@{exists=$true;sha256=(Get-Sha256 $Path);size=[int64]$item.Length;directory=$false}
}

function Get-PayloadTreeHash {
    param([Parameter(Mandatory)][string]$Root)
    $snapshot=Get-TreeSnapshot $Root
    $canonical = ($snapshot | ForEach-Object { "$($_.path.Replace('\','/'))`t$($_.size)`t$($_.sha256)" }) -join "`n"
    $bytes=[Text.Encoding]::UTF8.GetBytes($canonical)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

Export-ModuleMember -Function *
