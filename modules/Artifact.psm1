Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

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
        & $git -C $Destination fetch --depth 1 origin $ref
        if($LASTEXITCODE -ne 0){ throw 'git fetch failed.' }
        & $git -C $Destination checkout -q FETCH_HEAD
        if($LASTEXITCODE -ne 0){ throw 'git checkout failed.' }
    } else {
        & $git clone --depth 1 $repositoryUrl $Destination
        if($LASTEXITCODE -ne 0){ throw 'git clone failed.' }
    }
    $commit=(& $git -C $Destination rev-parse HEAD).Trim()

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
        $refs=& $Git ls-remote --heads --tags $RepositoryUrl 2>$null
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
    return ($candidate -split '/')[0]
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
    $root=Initialize-CsgLayout
    $dir=Join-Path (Join-Path $root 'artifacts') $ArtifactId
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
    if(Test-Path -LiteralPath $Destination){Remove-Item -LiteralPath $Destination -Recurse -Force}
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Expand-Archive -LiteralPath $a.zip -DestinationPath $Destination -Force
    $hash=Get-PayloadTreeHash $Destination
    if($hash -ne $a.manifest.provenance.source_tree_sha256){ throw 'Expanded source tree hash mismatch.' }
    return $a.manifest
}

Export-ModuleMember -Function *
