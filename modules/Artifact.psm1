Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Get-CsgArtifactLimits {
    $policyPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'policy.default.json'
    return (Read-JsonFile $policyPath).artifact_limits
}

function Assert-CsgContentLimits {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Limits
    )
    $files=@(Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction Stop)
    if($files.Count -gt [int]$Limits.max_files){throw "Artifact has $($files.Count) files; limit is $($Limits.max_files)."}
    [long]$total=0
    foreach($file in $files){
        if([long]$file.Length -gt [long]$Limits.max_single_file_bytes){throw "Artifact file exceeds the single-file limit: $($file.FullName)"}
        $relative=Get-RelativePathSafe -Base $Root -Full $file.FullName
        if($relative.Length -gt [int]$Limits.max_relative_path_chars){throw "Artifact path exceeds the length limit: $relative"}
        if($total -gt ([long]$Limits.max_total_bytes - [long]$file.Length)){throw "Artifact expanded size exceeds $($Limits.max_total_bytes) bytes."}
        $total += [long]$file.Length
    }
    return [pscustomobject]@{files=$files.Count;total_bytes=$total}
}

function Test-CsgZipArchive {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Limits
    )
    $archive=[IO.Compression.ZipFile]::OpenRead($Path)
    try{
        $seen=@{}
        [long]$total=0
        [int]$fileCount=0
        foreach($entry in $archive.Entries){
            $relative=$entry.FullName.Replace('/','\').TrimEnd('\')
            if([string]::IsNullOrWhiteSpace($relative)){continue}
            if($relative.StartsWith('\') -or $relative.Contains(':') -or $relative -match '(^|\\)\.\.(\\|$)'){
                throw "Archive entry escapes the artifact root: $($entry.FullName)"
            }
            if($relative.Length -gt [int]$Limits.max_relative_path_chars){throw "Archive path exceeds the length limit: $relative"}
            if($entry.Name){
                $key=$relative.ToLowerInvariant()
                if($seen.ContainsKey($key)){throw "Archive contains a duplicate path: $relative"}
                $seen[$key]=$true
                $fileCount++
                if($fileCount -gt [int]$Limits.max_files){throw "Archive file count exceeds $($Limits.max_files)."}
                if([long]$entry.Length -gt [long]$Limits.max_single_file_bytes){throw "Archive entry exceeds the single-file limit: $relative"}
                if($total -gt ([long]$Limits.max_total_bytes - [long]$entry.Length)){throw "Archive expanded size exceeds $($Limits.max_total_bytes) bytes."}
                $total += [long]$entry.Length
            }
        }
        return [pscustomobject]@{files=$fileCount;total_bytes=$total}
    }finally{$archive.Dispose()}
}

function Resolve-GitHubSource {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)

    if(Test-Path -LiteralPath $Source){
        $sourcePath=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Source).Path).TrimEnd('\','/')
        $destinationPath=[IO.Path]::GetFullPath($Destination).TrimEnd('\','/')
        $sourcePrefix=$sourcePath+[IO.Path]::DirectorySeparatorChar
        if($destinationPath.StartsWith($sourcePrefix,[StringComparison]::OrdinalIgnoreCase)){
            throw 'Local source contains the CSG artifact destination. Select the extension directory, not one of its parent directories.'
        }
        if((Split-Path -Leaf $sourcePath) -ieq '.codex' -or $sourcePath -match '(?i)[\\/]\.codex[\\/]sessions(?:[\\/]|$)'){
            throw 'Refusing to freeze the whole .codex directory or .codex\sessions. Select only the extension files that are under review.'
        }
        Copy-Tree -Source $sourcePath -Destination $Destination
        return [pscustomobject]@{kind='local';repository=$null;reference=$null;commit=$null}
    }

    $parts=Split-GitHubSourceUrl -Source $Source
    if(-not $parts){ throw '来源必须是本地目录或 GitHub 仓库 / tree / blob / raw 链接。' }

    $owner=$parts.owner
    $repo=$parts.repo
    $git=(Get-Command git -ErrorAction Stop).Source
    $oldGitPrompt=$env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT='0'
    try {
        $repositoryUrl="https://github.com/$owner/$repo.git"
        $ref=$parts.reference
        if(-not $ref -and $parts.candidate){
            $ref=Resolve-GitHubRef -RepositoryUrl $repositoryUrl -Candidate $parts.candidate -Git $git
        }
        if($ref){
            & $git init -q $Destination
            if($LASTEXITCODE -ne 0){ throw 'git init failed.' }
            & $git -C $Destination remote add origin $repositoryUrl
            if($LASTEXITCODE -ne 0){ throw 'git remote add failed.' }
            & $git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 -C $Destination fetch --depth 1 origin $ref
            if($LASTEXITCODE -ne 0){ throw 'git fetch failed.' }
            & $git -C $Destination checkout -q FETCH_HEAD
            if($LASTEXITCODE -ne 0){ throw 'git checkout failed.' }
        } else {
            & $git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 clone --depth 1 $repositoryUrl $Destination
            if($LASTEXITCODE -ne 0){ throw 'git clone failed.' }
        }
        $commit=(& $git -C $Destination rev-parse HEAD).Trim()
    } finally {
        if($null -eq $oldGitPrompt){Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue}else{$env:GIT_TERMINAL_PROMPT=$oldGitPrompt}
    }

    # Strip .git from the frozen source; provenance is recorded separately.
    Remove-Item -LiteralPath (Join-Path $Destination '.git') -Recurse -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{kind='github';repository="$owner/$repo";reference=$ref;commit=$commit}
}

function Split-GitHubSourceUrl {
    param([Parameter(Mandatory)][string]$Source)

    $m=[regex]::Match($Source,'^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+?)(?:\.git)?(?:/releases/tag/(?<tag>[^?#]+)|/tree/(?<refpath>[^?#]+)|/blob/(?<refpath>[^?#]+)|/raw/(?<refpath>[^?#]+))?/?$')
    if(-not $m.Success){
        $m=[regex]::Match($Source,'^https://raw\.githubusercontent\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+?)(?:\.git)?/(?<refpath>[^?#]+)$')
    }
    if(-not $m.Success){ return $null }

    $candidate=$null
    if($m.Groups['refpath'].Success){
        $candidate=$m.Groups['refpath'].Value.Trim('/')
    }
    $reference=$null
    if($m.Groups['tag'].Success){
        $reference=[uri]::UnescapeDataString($m.Groups['tag'].Value.Trim('/'))
    }

    return [pscustomobject]@{
        owner=$m.Groups['owner'].Value
        repo=$m.Groups['repo'].Value
        reference=$reference
        candidate=$candidate
    }
}

function Resolve-GitHubRef {
    param(
        [Parameter(Mandatory)][string]$RepositoryUrl,
        [Parameter(Mandatory)][string]$Candidate,
        [string]$Git='git'
    )

    $candidate=[uri]::UnescapeDataString($Candidate)
    if(-not $candidate.Contains('/')){ return $candidate }

    $best=$null
    try {
        $refs=& $Git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 ls-remote --heads --tags $RepositoryUrl 2>$null
        if($LASTEXITCODE -eq 0){
            foreach($line in @($refs)){
                $parts=$line -split "`t"
                if($parts.Count -lt 2){continue}
                $fullRef=$parts[1]
                foreach($prefix in @('refs/heads/','refs/tags/')){
                    if($fullRef.StartsWith($prefix,[StringComparison]::Ordinal)){
                        $name=$fullRef.Substring($prefix.Length)
                        if(($candidate -eq $name) -or $candidate.StartsWith($name + '/',[StringComparison]::Ordinal)){
                            if(-not $best -or $name.Length -gt $best.Length){$best=$name}
                        }
                    }
                }
            }
        }
    } catch { }

    if($best){ return $best }
    throw "无法可靠识别 GitHub 链接中的分支或标签：$Candidate。请检查网络，或改用仓库首页/明确 release tag。"
}

function New-FrozenArtifact {
    param([Parameter(Mandatory)][string]$Source)

    $root=Initialize-CsgLayout
    $id=New-Id 'artifact'
    $dir=Join-Path (Join-Path $root 'artifacts') $id
    $src=Join-Path $dir 'source'
    New-Item -ItemType Directory -Force -Path $src | Out-Null

    try {
        $prov=Resolve-GitHubSource -Source $Source -Destination $src
        Remove-Item -LiteralPath (Join-Path $src '.git') -Recurse -Force -ErrorAction SilentlyContinue
        $limits=Get-CsgArtifactLimits
        $null=Assert-CsgContentLimits -Root $src -Limits $limits
        $treeHash=Get-PayloadTreeHash $src

        $zip=Join-Path $dir 'source.zip'
        Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip -CompressionLevel Optimal
        $zipHash=Get-Sha256 $zip

        $manifest=[ordered]@{
            schema_version=2
            artifact_id=$id
            frozen_at=(Get-Date).ToString('o')
            input=$Source
            provenance=[ordered]@{
                kind=$prov.kind
                repository=$prov.repository
                reference=$prov.reference
                commit=$prov.commit
                source_tree_sha256=$treeHash
                archive_sha256=$zipHash
            }
            source_archive=$zip
            immutable_intent='All later inspection/staging must use this frozen archive/hash, not refetch the source.'
        }
        Write-JsonFile $manifest (Join-Path $dir 'artifact.json')
        Remove-Item -LiteralPath $src -Recurse -Force

        return $manifest
    } catch {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Get-FrozenArtifact {
    param([Parameter(Mandatory)][string]$ArtifactId)
    $null=Assert-CsgSafeId -Id $ArtifactId -Kind 'Artifact'
    $root=Initialize-CsgLayout
    $dir=Join-Path (Join-Path $root 'artifacts') $ArtifactId
    Assert-NoReparsePoints -Root $dir
    $mPath=Join-Path $dir 'artifact.json'
    if(-not (Test-Path -LiteralPath $mPath)){ throw "Unknown ArtifactId: $ArtifactId" }
    $m=Read-JsonFile $mPath
    $zip=Join-Path $dir 'source.zip'
    if((Get-Sha256 $zip) -ne $m.provenance.archive_sha256){ throw 'Frozen artifact hash mismatch. Refusing to continue.' }
    return [pscustomobject]@{dir=$dir;zip=$zip;manifest=$m}
}

function Expand-FrozenArtifact {
    param([Parameter(Mandatory)][string]$ArtifactId,[Parameter(Mandatory)][string]$Destination)
    $a=Get-FrozenArtifact $ArtifactId
    $root=Initialize-CsgLayout
    $tmpRoot=Join-Path $root 'tmp'
    $destinationFull=[IO.Path]::GetFullPath($Destination)
    $relativeDestination=Get-RelativePathSafe -Base $tmpRoot -Full $destinationFull
    if($relativeDestination -eq '.'){throw 'Frozen artifacts must expand into a dedicated child of the CSG temporary directory.'}
    if(Test-Path -LiteralPath $destinationFull){Assert-NoReparsePoints -Root $destinationFull}
    $null=Test-CsgZipArchive -Path $a.zip -Limits (Get-CsgArtifactLimits)
    if(Test-Path -LiteralPath $destinationFull){Remove-Item -LiteralPath $destinationFull -Recurse -Force}
    New-Item -ItemType Directory -Force -Path $destinationFull | Out-Null
    Expand-Archive -LiteralPath $a.zip -DestinationPath $destinationFull -Force
    $hash=Get-PayloadTreeHash $destinationFull
    if($hash -ne $a.manifest.provenance.source_tree_sha256){ throw 'Expanded source tree hash mismatch.' }
    return $a.manifest
}

Export-ModuleMember -Function New-FrozenArtifact,Get-FrozenArtifact,Expand-FrozenArtifact,Split-GitHubSourceUrl,Resolve-GitHubRef,Get-CsgArtifactLimits,Assert-CsgContentLimits,Test-CsgZipArchive
