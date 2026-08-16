#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$RuntimePath,
    [string]$RuntimeArchivePath,
    [string]$OutputDirectory,
    [switch]$AllowDirty
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-CsgStreamSha256 {
    param([Parameter(Mandatory)][IO.Stream]$Stream)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([Convert]::ToHexString($sha.ComputeHash($Stream))).ToLowerInvariant()}
    finally{$sha.Dispose()}
}

function Assert-CsgRuntimeArchive {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)]$RuntimeManifest
    )
    $archiveHash=(Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($archiveHash -ne [string]$RuntimeManifest.source.archive_sha256){throw 'Runtime archive SHA256 does not match runtime/manifest.json.'}

    $runtimeRows=@(Get-TreeSnapshot $RuntimeRoot)
    $runtimeMap=@{}
    foreach($row in $runtimeRows){$runtimeMap[([string]$row.path).ToLowerInvariant()]=$row}

    $archive=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try{
        $archiveMap=@{}
        foreach($entry in $archive.Entries){
            if(-not $entry.Name){continue}
            $relative=$entry.FullName.Replace('/','\')
            if($relative.StartsWith('\') -or $relative.Contains(':') -or $relative -match '(^|\\)\.\.(\\|$)'){
                throw "Runtime archive contains an unsafe path: $($entry.FullName)"
            }
            $key=$relative.ToLowerInvariant()
            if($archiveMap.ContainsKey($key)){throw "Runtime archive contains a duplicate path: $relative"}
            $stream=$entry.Open()
            try{$hash=Get-CsgStreamSha256 $stream}finally{$stream.Dispose()}
            $archiveMap[$key]=[pscustomobject]@{path=$relative;size=[long]$entry.Length;sha256=$hash}
        }
    }finally{$archive.Dispose()}

    foreach($key in @($runtimeMap.Keys+$archiveMap.Keys|Sort-Object -Unique)){
        if(-not $runtimeMap.ContainsKey($key) -or -not $archiveMap.ContainsKey($key)){
            throw "Runtime directory and official archive have different file sets: $key"
        }
        if([long]$runtimeMap[$key].size -ne [long]$archiveMap[$key].size -or [string]$runtimeMap[$key].sha256 -ne [string]$archiveMap[$key].sha256){
            throw "Runtime file differs from the official archive: $key"
        }
    }
    return $archiveHash
}

function New-CsgDeterministicZip {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path)
    if(Test-Path -LiteralPath $Path){Remove-Item -LiteralPath $Path -Force}
    $archive=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
    $timestamp=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
    try{
        $relativePaths=[string[]]@(Get-ChildItem -LiteralPath $Root -Recurse -Force -File|ForEach-Object {
            [IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')
        })
        [Array]::Sort($relativePaths,[StringComparer]::Ordinal)
        foreach($relative in $relativePaths){
            $file=Get-Item -LiteralPath (Join-Path $Root $relative.Replace('/','\')) -Force
            $entry=$archive.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime=$timestamp
            $source=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            $destination=$entry.Open()
            try{$source.CopyTo($destination)}finally{$destination.Dispose();$source.Dispose()}
        }
    }finally{$archive.Dispose()}
}

$repo=if($RepositoryRoot){[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryRoot).Path)}else{[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
$runtime=if($RuntimePath){[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RuntimePath).Path)}else{Join-Path $repo 'runtime\pwsh'}
$output=if($OutputDirectory){[IO.Path]::GetFullPath($OutputDirectory)}else{Join-Path $repo 'dist'}
$common=Join-Path $repo 'modules\Common.psm1'
Import-Module $common -Force

$git=(Get-Command git.exe -ErrorAction Stop).Source
if((& $git -C $repo rev-parse --is-inside-work-tree) -ne 'true'){throw 'RepositoryRoot is not a Git worktree.'}
$commit=(& $git -C $repo rev-parse HEAD).Trim()
$commitTime=(& $git -C $repo show -s --format=%cI HEAD).Trim()
$status=@(& $git -c core.quotepath=false -C $repo status --porcelain=v1 --untracked-files=all)
$sourceClean=($status.Count -eq 0)
if(-not $sourceClean -and -not $AllowDirty){throw 'Release builds require a clean Git worktree. Use -AllowDirty only for non-publishable development verification.'}

$versionManifest=Read-JsonFile (Join-Path $repo 'VERSION.json')
$runtimeManifest=Read-JsonFile (Join-Path $repo 'runtime\manifest.json')
if(-not (Test-Path -LiteralPath $runtime)){throw "Bundled runtime directory not found: $runtime"}
Assert-NoReparsePoints -Root $runtime
$runtimeRows=@(Get-TreeSnapshot $runtime)
if($runtimeRows.Count -ne [int]$runtimeManifest.file_count){throw 'Runtime file count does not match runtime/manifest.json.'}
if([long](($runtimeRows|Measure-Object -Property size -Sum).Sum) -ne [long]$runtimeManifest.total_bytes){throw 'Runtime size does not match runtime/manifest.json.'}
if((Get-PayloadTreeHash $runtime) -ne [string]$runtimeManifest.runtime_tree_sha256){throw 'Runtime tree hash does not match runtime/manifest.json.'}
$runtimeExe=Join-Path (Split-Path -Parent $runtime) ([string]$runtimeManifest.executable)
if((Get-Sha256 $runtimeExe) -ne [string]$runtimeManifest.executable_sha256){throw 'Runtime executable hash does not match runtime/manifest.json.'}

$runtimeArchiveVerified=$false
$runtimeArchiveHash=$null
if($RuntimeArchivePath){
    $resolvedRuntimeArchive=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RuntimeArchivePath).Path)
    $runtimeArchiveHash=Assert-CsgRuntimeArchive -ArchivePath $resolvedRuntimeArchive -RuntimeRoot $runtime -RuntimeManifest $runtimeManifest
    $runtimeArchiveVerified=$true
}elseif(-not $AllowDirty){
    throw 'A publishable build requires -RuntimeArchivePath pointing to the pinned official PowerShell archive.'
}

New-Item -ItemType Directory -Force -Path $output|Out-Null
$work=Join-Path $output ('.csg-release-work-'+[guid]::NewGuid().ToString('N'))
$packageRoot=Join-Path $work 'package'
$version=[string]$versionManifest.version
$archiveName="codex-safety-gate-$version-win-x64.zip"
$archivePath=Join-Path $output $archiveName
$reportPath=Join-Path $output 'release-report.json'
$sumsPath=Join-Path $output 'SHA256SUMS.txt'

try{
    New-Item -ItemType Directory -Path $packageRoot|Out-Null
    $sourceFiles=@(& $git -c core.quotepath=false -C $repo ls-files --cached)
    if($AllowDirty){$sourceFiles+=@(& $git -c core.quotepath=false -C $repo ls-files --others --exclude-standard)}
    $sourceFiles=@($sourceFiles|Sort-Object -Unique)
    foreach($relative in $sourceFiles){
        $normalized=$relative.Replace('/','\')
        if($normalized -match '^(\.git|dist|runtime\\pwsh|\.devtools|\.codex|\.codex-safety-v2)(\\|$)'){continue}
        if($normalized -match '(?i)(^|\\)(auth|credentials)\.json(?:\.|$)|(^|\\)\.env(?:\.|$)|\.(pem|key|pfx|p12|iso|vdi|vbox)$'){
            throw "Source inventory contains a forbidden release path: $normalized"
        }
        $sourcePath=Resolve-CsgChildPath -Root $repo -RelativePath $normalized -RejectReparsePoints
        if(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)){throw "Source inventory file is missing: $normalized"}
        $item=Get-Item -LiteralPath $sourcePath -Force
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Source inventory contains a reparse point: $normalized"}
        $destination=Join-Path $packageRoot $normalized
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)|Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destination -Force
    }

    Copy-Tree -Source $runtime -Destination (Join-Path $packageRoot 'runtime\pwsh')
    $inventory=@(Get-TreeSnapshot $packageRoot)
    $releaseEligible=$sourceClean -and $runtimeArchiveVerified
    $releaseManifest=[ordered]@{
        schema_version=1
        product='codex-safety-gate'
        version=$version
        platform='windows-x64'
        source=[ordered]@{
            commit=$commit
            commit_time=$commitTime
            clean=$sourceClean
            dirty_paths=if($sourceClean){@()}else{@($status)}
        }
        runtime=$runtimeManifest
        runtime_archive_verified=$runtimeArchiveVerified
        runtime_archive_sha256=$runtimeArchiveHash
        release_eligible=$releaseEligible
        deterministic_timestamp='1980-01-01T00:00:00Z'
        files=$inventory
    }
    Write-JsonFile -Value $releaseManifest -Path (Join-Path $packageRoot 'RELEASE-MANIFEST.json') -Depth 30

    & (Join-Path $repo 'tools\release\Test-CsgRelease.ps1') -PackageRoot $packageRoot -RunTests
    if($LASTEXITCODE -ne 0){throw 'Release package directory verification failed.'}

    New-CsgDeterministicZip -Root $packageRoot -Path $archivePath
    & (Join-Path $repo 'tools\release\Test-CsgRelease.ps1') -ArchivePath $archivePath
    if($LASTEXITCODE -ne 0){throw 'Release archive verification failed.'}

    $archiveHash=Get-Sha256 $archivePath
    [IO.File]::WriteAllText($sumsPath,"$archiveHash  $archiveName`r`n",[Text.UTF8Encoding]::new($false))
    $report=[ordered]@{
        schema_version=1
        generated_at=(Get-Date).ToUniversalTime().ToString('o')
        archive=$archivePath
        archive_sha256=$archiveHash
        release_manifest_sha256=Get-Sha256 (Join-Path $packageRoot 'RELEASE-MANIFEST.json')
        source_commit=$commit
        source_clean=$sourceClean
        runtime_archive_verified=$runtimeArchiveVerified
        release_eligible=$releaseEligible
    }
    Write-JsonFile -Value $report -Path $reportPath
    [pscustomobject]@{
        archive=$archivePath
        sha256=$archiveHash
        files=$inventory.Count+1
        source_clean=$sourceClean
        runtime_archive_verified=$runtimeArchiveVerified
        release_eligible=$releaseEligible
    }|Format-List
}finally{
    $resolvedOutput=[IO.Path]::GetFullPath($output).TrimEnd('\')+'\'
    $resolvedWork=[IO.Path]::GetFullPath($work)
    if($resolvedWork.StartsWith($resolvedOutput,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedWork).StartsWith('.csg-release-work-')){
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force -ErrorAction SilentlyContinue
    }
}
