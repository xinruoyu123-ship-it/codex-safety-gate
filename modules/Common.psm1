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
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding utf8
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
    return [IO.Path]::GetRelativePath($baseFull,$fullFull)
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    $rootFull = [IO.Path]::GetFullPath($Root)
    $rows = @()
    foreach ($f in Get-ChildItem -LiteralPath $rootFull -Recurse -Force -File -ErrorAction SilentlyContinue) {
        $rows += [pscustomobject]@{
            path=(Get-RelativePathSafe -Base $rootFull -Full $f.FullName).Replace('/','\')
            size=[int64]$f.Length
            sha256=(Get-Sha256 $f.FullName)
        }
    }
    return @($rows | Sort-Object path)
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
