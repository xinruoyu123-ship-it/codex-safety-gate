#requires -Version 7.0
[CmdletBinding(DefaultParameterSetName='Directory')]
param(
    [Parameter(Mandatory,ParameterSetName='Directory')][string]$PackageRoot,
    [Parameter(Mandatory,ParameterSetName='Archive')][string]$ArchivePath,
    [switch]$RunTests,
    [switch]$RequireReleaseEligible
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-CsgStreamSha256 {
    param([Parameter(Mandatory)][IO.Stream]$Stream)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([Convert]::ToHexString($sha.ComputeHash($Stream))).ToLowerInvariant()}
    finally{$sha.Dispose()}
}

function Get-CsgFileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-CsgCanonicalTreeHash {
    param([Parameter(Mandatory)]$Rows)
    $canonical=(@($Rows)|Sort-Object @{Expression={
        [Convert]::ToHexString([Text.Encoding]::UTF8.GetBytes([string]$_.path))
    }}|ForEach-Object {
        "$([string]$_.path -replace '\\','/')`t$([long]$_.size)`t$([string]$_.sha256)"
    }) -join "`n"
    $bytes=[Text.Encoding]::UTF8.GetBytes($canonical)
    return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Assert-CsgArchivePath {
    param([Parameter(Mandatory)][string]$Path)
    $relative=$Path.Replace('/','\').TrimEnd('\')
    if([string]::IsNullOrWhiteSpace($relative)){return $null}
    if($relative.StartsWith('\') -or $relative.Contains(':') -or $relative -match '(^|\\)\.\.(\\|$)'){
        throw "Release archive contains an unsafe path: $Path"
    }
    if($relative.Length -gt 240){throw "Release archive path exceeds 240 characters: $relative"}
    return $relative
}

function Assert-CsgInventory {
    param([Parameter(Mandatory)]$Manifest,[Parameter(Mandatory)]$ActualRows)
    $expected=@{}
    foreach($row in @($Manifest.files)){
        $path=([string]$row.path).Replace('/','\')
        $key=$path.ToLowerInvariant()
        if($expected.ContainsKey($key)){throw "Release manifest contains a duplicate path: $path"}
        if($path -ieq 'RELEASE-MANIFEST.json'){throw 'RELEASE-MANIFEST.json must not list itself.'}
        $expected[$key]=$row
    }

    $actual=@{}
    foreach($row in @($ActualRows)){
        $key=([string]$row.path).ToLowerInvariant()
        if($actual.ContainsKey($key)){throw "Release content contains a duplicate path: $($row.path)"}
        $actual[$key]=$row
    }

    $allKeys=@($expected.Keys+$actual.Keys|Sort-Object -Unique)
    foreach($key in $allKeys){
        if(-not $expected.ContainsKey($key)){throw "Release contains an unlisted file: $($actual[$key].path)"}
        if(-not $actual.ContainsKey($key)){throw "Release manifest lists a missing file: $($expected[$key].path)"}
        if([long]$expected[$key].size -ne [long]$actual[$key].size -or [string]$expected[$key].sha256 -ne [string]$actual[$key].sha256){
            throw "Release file does not match its manifest: $($expected[$key].path)"
        }
    }
}

function Assert-CsgRuntimeManifest {
    param([Parameter(Mandatory)]$RuntimeManifest,[Parameter(Mandatory)]$Rows)
    if([string]$RuntimeManifest.platform -ne 'win-x64'){throw 'Release runtime platform must be win-x64.'}
    if([string]$RuntimeManifest.source.url -notmatch '^https://github\.com/PowerShell/PowerShell/releases/download/v[0-9.]+/PowerShell-[0-9.]+-win-x64\.zip$'){
        throw 'Release runtime source is not a pinned official PowerShell archive URL.'
    }
    foreach($hash in @($RuntimeManifest.executable_sha256,$RuntimeManifest.runtime_tree_sha256,$RuntimeManifest.source.archive_sha256,$RuntimeManifest.source.hashes_sha256)){
        if([string]$hash -notmatch '^[0-9a-f]{64}$'){throw 'Release runtime manifest contains an invalid SHA256.'}
    }

    $runtimeRows=@($Rows|Where-Object {([string]$_.path).StartsWith('runtime\pwsh\',[StringComparison]::OrdinalIgnoreCase)}|ForEach-Object {
        [pscustomobject]@{
            path=([string]$_.path).Substring('runtime\pwsh\'.Length)
            size=[long]$_.size
            sha256=[string]$_.sha256
        }
    })
    if($runtimeRows.Count -ne [int]$RuntimeManifest.file_count){throw 'Bundled runtime file count does not match runtime/manifest.json.'}
    $runtimeBytes=($runtimeRows|Measure-Object -Property size -Sum).Sum
    if([long]$runtimeBytes -ne [long]$RuntimeManifest.total_bytes){throw 'Bundled runtime size does not match runtime/manifest.json.'}
    if((Get-CsgCanonicalTreeHash $runtimeRows) -ne [string]$RuntimeManifest.runtime_tree_sha256){throw 'Bundled runtime tree hash does not match runtime/manifest.json.'}

    $exePath=('runtime\'+([string]$RuntimeManifest.executable).Replace('/','\')).ToLowerInvariant()
    $exe=@($Rows|Where-Object {([string]$_.path).ToLowerInvariant() -eq $exePath})
    if($exe.Count -ne 1 -or [string]$exe[0].sha256 -ne [string]$RuntimeManifest.executable_sha256){throw 'Bundled runtime executable hash does not match runtime/manifest.json.'}
}

function Invoke-CsgPackageTests {
    param([Parameter(Mandatory)][string]$Root)
    $pwsh=Join-Path $Root 'runtime\pwsh\pwsh.exe'
    if(-not (Test-Path -LiteralPath $pwsh)){throw 'Bundled pwsh.exe is missing.'}
    foreach($name in @('Run-StaticTests.ps1','Run-GuiSmokeTests.ps1','Run-LauncherTests.ps1','Run-VmProvisioningTests.ps1')){
        & $pwsh -NoProfile -File (Join-Path $Root "tests\$name")
        if($LASTEXITCODE -ne 0){throw "Release package test failed: $name (exit $LASTEXITCODE)"}
    }
}

$manifest=$null
$actualRows=@()
$runtimeManifest=$null
$resolvedPackageRoot=$null
$temporaryExtract=$null

if($PSCmdlet.ParameterSetName -eq 'Directory'){
    $resolvedPackageRoot=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PackageRoot).Path)
    $reparse=@(Get-Item -LiteralPath $resolvedPackageRoot -Force)+@(Get-ChildItem -LiteralPath $resolvedPackageRoot -Recurse -Force -ErrorAction Stop) |
        Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0} | Select-Object -First 1
    if($reparse){throw "Release directory contains a reparse point: $($reparse.FullName)"}
    $manifestPath=Join-Path $resolvedPackageRoot 'RELEASE-MANIFEST.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8|ConvertFrom-Json
    $runtimeManifest=Get-Content -LiteralPath (Join-Path $resolvedPackageRoot 'runtime\manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    $actualRows=@(Get-ChildItem -LiteralPath $resolvedPackageRoot -Recurse -Force -File -ErrorAction Stop |
        Where-Object {$_.FullName -ne $manifestPath} | ForEach-Object {
            [pscustomobject]@{
                path=[IO.Path]::GetRelativePath($resolvedPackageRoot,$_.FullName).Replace('/','\')
                size=[long]$_.Length
                sha256=Get-CsgFileSha256 $_.FullName
            }
        })
}else{
    $resolvedArchive=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ArchivePath).Path)
    $archive=[IO.Compression.ZipFile]::OpenRead($resolvedArchive)
    try{
        $seen=@{}
        $entries=@{}
        [long]$total=0
        foreach($entry in $archive.Entries){
            $relative=Assert-CsgArchivePath $entry.FullName
            if(-not $relative -or -not $entry.Name){continue}
            $key=$relative.ToLowerInvariant()
            if($seen.ContainsKey($key)){throw "Release archive contains a duplicate path: $relative"}
            $seen[$key]=$true
            if($entry.Length -gt 512MB){throw "Release archive entry exceeds 512 MB: $relative"}
            if($total -gt (2GB-$entry.Length)){throw 'Release archive expands beyond 2 GB.'}
            $total += [long]$entry.Length
            $stream=$entry.Open()
            try{$hash=Get-CsgStreamSha256 $stream}finally{$stream.Dispose()}
            $row=[pscustomobject]@{path=$relative;size=[long]$entry.Length;sha256=$hash}
            $entries[$key]=$entry
            if($relative -ine 'RELEASE-MANIFEST.json'){$actualRows+=$row}
        }
        if($actualRows.Count -gt 10000){throw 'Release archive contains more than 10,000 files.'}

        $manifestEntry=$entries['release-manifest.json']
        if(-not $manifestEntry){throw 'Release archive is missing RELEASE-MANIFEST.json.'}
        $stream=$manifestEntry.Open();$reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false),$true)
        try{$manifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose();$stream.Dispose()}

        $runtimeEntry=$entries['runtime\manifest.json']
        if(-not $runtimeEntry){throw 'Release archive is missing runtime/manifest.json.'}
        $stream=$runtimeEntry.Open();$reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false),$true)
        try{$runtimeManifest=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose();$stream.Dispose()}
    }finally{$archive.Dispose()}
}

if([int]$manifest.schema_version -ne 1){throw 'Unsupported release manifest schema.'}
if([string]$manifest.product -ne 'codex-safety-gate'){throw 'Release manifest product is incorrect.'}
if($RequireReleaseEligible -and -not [bool]$manifest.release_eligible){throw 'Release manifest is not eligible for publication.'}
Assert-CsgInventory -Manifest $manifest -ActualRows $actualRows
Assert-CsgRuntimeManifest -RuntimeManifest $runtimeManifest -Rows $actualRows

if($RunTests){
    if($PSCmdlet.ParameterSetName -eq 'Archive'){
        $temporaryExtract=Join-Path ([IO.Path]::GetTempPath()) ('csg-release-verify-'+[guid]::NewGuid().ToString('N'))
        try{
            New-Item -ItemType Directory -Path $temporaryExtract|Out-Null
            Expand-Archive -LiteralPath $resolvedArchive -DestinationPath $temporaryExtract
            Invoke-CsgPackageTests -Root $temporaryExtract
        }finally{
            $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            $resolved=[IO.Path]::GetFullPath($temporaryExtract)
            if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('csg-release-verify-')){
                Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }else{
        Invoke-CsgPackageTests -Root $resolvedPackageRoot
    }
}

[pscustomobject]@{
    status='PASS'
    version=[string]$manifest.version
    release_eligible=[bool]$manifest.release_eligible
    files=$actualRows.Count
    runtime_files=[int]$runtimeManifest.file_count
    runtime_tree_sha256=[string]$runtimeManifest.runtime_tree_sha256
}|Format-List
