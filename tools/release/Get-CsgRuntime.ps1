#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$DestinationRoot,
    [string]$ArchivePath,
    [string]$CacheDirectory,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$repo=if($RepositoryRoot){[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryRoot).Path)}else{[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
Import-Module (Join-Path $repo 'modules\Common.psm1') -Force
$manifest=Read-JsonFile (Join-Path $repo 'runtime\manifest.json')
$destination=if($DestinationRoot){[IO.Path]::GetFullPath($DestinationRoot)}else{Join-Path $repo 'runtime\pwsh'}
$cache=if($CacheDirectory){[IO.Path]::GetFullPath($CacheDirectory)}else{Join-Path $repo '.devtools\runtime'}

function Test-CsgRuntimeDirectory {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Manifest)
    if(-not (Test-Path -LiteralPath $Path -PathType Container)){return $false}
    Assert-NoReparsePoints -Root $Path
    $rows=@(Get-TreeSnapshot $Path)
    if($rows.Count -ne [int]$Manifest.file_count){return $false}
    if([long](($rows|Measure-Object -Property size -Sum).Sum) -ne [long]$Manifest.total_bytes){return $false}
    if((Get-PayloadTreeHash $Path) -ne [string]$Manifest.runtime_tree_sha256){return $false}
    $exe=Join-Path $Path 'pwsh.exe'
    return (Test-Path -LiteralPath $exe -PathType Leaf) -and (Get-Sha256 $exe) -eq [string]$Manifest.executable_sha256
}

New-Item -ItemType Directory -Force -Path $cache|Out-Null
$archive=if($ArchivePath){[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ArchivePath).Path)}else{Join-Path $cache ([string]$manifest.source.archive)}
if(-not (Test-Path -LiteralPath $archive)){
    if($ArchivePath){throw "Runtime archive not found: $archive"}
    $download=Join-Path $cache ('.'+[string]$manifest.source.archive+'.'+[guid]::NewGuid().ToString('N')+'.download')
    try{
        Invoke-WebRequest -Uri ([string]$manifest.source.url) -OutFile $download -MaximumRedirection 10
        if((Get-Sha256 $download) -ne [string]$manifest.source.archive_sha256){throw 'Downloaded runtime archive SHA256 does not match runtime/manifest.json.'}
        [IO.File]::Move($download,$archive,$true)
    }finally{
        if(Test-Path -LiteralPath $download){Remove-Item -LiteralPath $download -Force}
    }
}
if((Get-Sha256 $archive) -ne [string]$manifest.source.archive_sha256){throw 'Runtime archive SHA256 does not match runtime/manifest.json.'}

$zip=[IO.Compression.ZipFile]::OpenRead($archive)
try{
    $seen=@{}
    [long]$total=0
    [int]$files=0
    foreach($entry in $zip.Entries){
        $relative=$entry.FullName.Replace('/','\').TrimEnd('\')
        if([string]::IsNullOrWhiteSpace($relative)){continue}
        if($relative.StartsWith('\') -or $relative.Contains(':') -or $relative -match '(^|\\)\.\.(\\|$)'){
            throw "Runtime archive contains an unsafe path: $($entry.FullName)"
        }
        if($entry.Name){
            $key=$relative.ToLowerInvariant()
            if($seen.ContainsKey($key)){throw "Runtime archive contains a duplicate path: $relative"}
            $seen[$key]=$true
            $files++
            if($entry.Length -gt 512MB){throw "Runtime archive entry exceeds 512 MB: $relative"}
            if($total -gt (1GB-$entry.Length)){throw 'Runtime archive expands beyond 1 GB.'}
            $total += [long]$entry.Length
        }
    }
}finally{$zip.Dispose()}
if($files -ne [int]$manifest.file_count -or $total -ne [long]$manifest.total_bytes){throw 'Runtime archive inventory does not match runtime/manifest.json.'}

if(Test-CsgRuntimeDirectory -Path $destination -Manifest $manifest){
    [pscustomobject]@{status='verified-existing';runtime=$destination;archive=$archive;archive_sha256=[string]$manifest.source.archive_sha256}|Format-List
    exit 0
}
if((Test-Path -LiteralPath $destination) -and -not $Force){
    throw "Runtime destination exists but does not match the manifest: $destination. Re-run with -Force only after reviewing the target."
}

$parent=Split-Path -Parent $destination
New-Item -ItemType Directory -Force -Path $parent|Out-Null
$temporary=Join-Path $parent ('.csg-runtime-import-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Path $temporary|Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $temporary
    if(-not (Test-CsgRuntimeDirectory -Path $temporary -Manifest $manifest)){throw 'Expanded runtime does not match runtime/manifest.json.'}
    if(Test-Path -LiteralPath $destination){Remove-Item -LiteralPath $destination -Recurse -Force}
    Move-Item -LiteralPath $temporary -Destination $destination
}finally{
    $resolvedParent=[IO.Path]::GetFullPath($parent).TrimEnd('\')+'\'
    $resolvedTemporary=[IO.Path]::GetFullPath($temporary)
    if((Test-Path -LiteralPath $resolvedTemporary) -and $resolvedTemporary.StartsWith($resolvedParent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTemporary).StartsWith('.csg-runtime-import-')){
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}

[pscustomobject]@{status='imported';runtime=$destination;archive=$archive;archive_sha256=[string]$manifest.source.archive_sha256}|Format-List
