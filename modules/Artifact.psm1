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

function Get-CsgGitHubApiHeaders {
    $headers=@{
        Accept='application/vnd.github+json'
        'User-Agent'='Codex-Safety-Gate'
        'X-GitHub-Api-Version'='2022-11-28'
    }
    $token=if($env:GITHUB_TOKEN){$env:GITHUB_TOKEN}elseif($env:GH_TOKEN){$env:GH_TOKEN}else{$null}
    if($token){$headers.Authorization="Bearer $token"}
    return $headers
}

function Invoke-CsgGitHubApi {
    param([Parameter(Mandatory)][string]$Path)
    return Invoke-RestMethod -Uri ("https://api.github.com$Path") -Headers (Get-CsgGitHubApiHeaders) -TimeoutSec 30
}

function Resolve-GitHubRefViaApi {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Candidate
    )
    $candidate=[uri]::UnescapeDataString($Candidate).Trim('/')
    if(-not $candidate.Contains('/')){return $candidate}
    $segments=@($candidate -split '/')
    for($count=$segments.Count;$count -ge 1;$count--){
        $name=($segments[0..($count-1)] -join '/')
        $encoded=[uri]::EscapeDataString($name)
        try{
            $null=Invoke-CsgGitHubApi -Path "/repos/$Owner/$Repository/commits/$encoded"
            return $name
        }catch{
            $status=$null
            try{$status=[int]$_.Exception.Response.StatusCode}catch{}
            if($status -notin @(404,422)){throw}
        }
    }
    throw "无法通过 GitHub API 识别链接中的分支或标签：$Candidate。"
}

function Get-CsgGitHubSubpath {
    param(
        [string]$Candidate,
        [Parameter(Mandatory)][string]$Reference,
        [string]$LinkKind
    )
    if($LinkKind -notin @('tree','blob','raw') -or [string]::IsNullOrWhiteSpace($Candidate)){return $null}
    $candidateValue=[uri]::UnescapeDataString($Candidate).Trim('/')
    if($candidateValue -eq $Reference){return $null}
    if(-not $candidateValue.StartsWith($Reference+'/',[StringComparison]::Ordinal)){
        throw 'Resolved GitHub ref is not a prefix of the requested tree/blob/raw path.'
    }
    $subpath=$candidateValue.Substring($Reference.Length+1)
    $segments=@($subpath -split '/')
    if([IO.Path]::IsPathRooted($subpath) -or $subpath.Contains('\') -or $subpath.Contains(':') -or $segments -contains '.' -or $segments -contains '..'){
        throw 'GitHub subpath is not a safe relative path.'
    }
    return $subpath
}

function Copy-CsgGitHubSelection {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Subpath,
        [string]$LinkKind
    )
    Assert-NoReparsePoints -Root $RepositoryRoot
    if([string]::IsNullOrWhiteSpace($Subpath)){
        Copy-Tree -Source $RepositoryRoot -Destination $Destination
        return
    }

    $selected=Resolve-CsgChildPath -Root $RepositoryRoot -RelativePath $Subpath -RejectReparsePoints
    if(-not (Test-Path -LiteralPath $selected)){throw "GitHub link subpath does not exist at the pinned commit: $Subpath"}
    $item=Get-Item -LiteralPath $selected -Force
    if($LinkKind -eq 'tree'){
        if(-not $item.PSIsContainer){throw "GitHub tree link does not resolve to a directory: $Subpath"}
        $target=Join-Path $Destination $item.Name
        Copy-Tree -Source $item.FullName -Destination $target
        return
    }

    if($item.PSIsContainer){throw "GitHub $LinkKind link does not resolve to a file: $Subpath"}
    $parent=Split-Path -Parent $item.FullName
    if([IO.Path]::GetFullPath($parent) -eq [IO.Path]::GetFullPath($RepositoryRoot)){
        New-Item -ItemType Directory -Force -Path $Destination|Out-Null
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name)
    }else{
        Copy-Tree -Source $parent -Destination (Join-Path $Destination (Split-Path -Leaf $parent))
    }
}

function Resolve-GitHubSourceViaCodeload {
    param(
        [Parameter(Mandatory)]$Parts,
        [Parameter(Mandatory)][string]$Destination
    )
    $owner=[string]$Parts.owner
    $repo=[string]$Parts.repo
    $ref=[string]$Parts.reference
    if(-not $ref -and $Parts.candidate){
        $ref=Resolve-GitHubRefViaApi -Owner $owner -Repository $repo -Candidate ([string]$Parts.candidate)
    }
    if(-not $ref){
        $metadata=Invoke-CsgGitHubApi -Path "/repos/$owner/$repo"
        $ref=[string]$metadata.default_branch
    }
    if([string]::IsNullOrWhiteSpace($ref)){throw 'GitHub did not return a default branch or requested ref.'}
    $subpath=Get-CsgGitHubSubpath -Candidate ([string]$Parts.candidate) -Reference $ref -LinkKind ([string]$Parts.link_kind)

    $encodedRef=[uri]::EscapeDataString($ref)
    $commitInfo=Invoke-CsgGitHubApi -Path "/repos/$owner/$repo/commits/$encodedRef"
    $commit=[string]$commitInfo.sha
    if($commit -notmatch '^[0-9a-f]{40}$'){throw 'GitHub API did not return a full commit SHA.'}

    $work=Join-Path (Split-Path -Parent $Destination) ('.csg-codeload-'+[guid]::NewGuid().ToString('N'))
    $archive=Join-Path $work 'source.zip'
    $expanded=Join-Path $work 'expanded'
    try{
        New-Item -ItemType Directory -Path $work,$expanded|Out-Null
        $url="https://codeload.github.com/$owner/$repo/zip/$commit"
        Invoke-WebRequest -Uri $url -Headers @{'User-Agent'='Codex-Safety-Gate'} -OutFile $archive -MaximumRedirection 10 -TimeoutSec 60
        if((Get-Item -LiteralPath $archive).Length -gt 512MB){throw 'GitHub codeload archive exceeds the 512 MB download limit.'}
        $upstreamHash=Get-Sha256 $archive
        $null=Test-CsgZipArchive -Path $archive -Limits (Get-CsgArtifactLimits)
        Expand-Archive -LiteralPath $archive -DestinationPath $expanded
        Assert-NoReparsePoints -Root $expanded
        $roots=@(Get-ChildItem -LiteralPath $expanded -Force -Directory)
        $rootFiles=@(Get-ChildItem -LiteralPath $expanded -Force -File)
        if($roots.Count -ne 1 -or $rootFiles.Count){throw 'GitHub codeload archive does not contain one repository root directory.'}
        Copy-CsgGitHubSelection -RepositoryRoot $roots[0].FullName -Destination $Destination -Subpath $subpath -LinkKind ([string]$Parts.link_kind)
        return [pscustomobject]@{
            kind='github-codeload';repository="$owner/$repo";reference=$ref;commit=$commit
            source_subpath=$subpath;link_kind=[string]$Parts.link_kind;upstream_archive_sha256=$upstreamHash
        }
    }finally{
        $parent=[IO.Path]::GetFullPath((Split-Path -Parent $Destination)).TrimEnd('\')+'\'
        $resolved=[IO.Path]::GetFullPath($work)
        if((Test-Path -LiteralPath $resolved) -and $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('.csg-codeload-')){
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-GitHubSourceViaGit {
    param(
        [Parameter(Mandatory)]$Parts,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Git,
        [Parameter(Mandatory)][string]$RepositoryUrl
    )
    $destinationParent=Split-Path -Parent ([IO.Path]::GetFullPath($Destination))
    $work=Join-Path $destinationParent ('.csg-git-'+[guid]::NewGuid().ToString('N'))
    $repositoryRoot=Join-Path $work 'repository'
    $selection=Join-Path $work 'selection'
    $oldGitPrompt=$env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT='0'
    try {
        New-Item -ItemType Directory -Force -Path $destinationParent,$work|Out-Null
        $ref=[string]$Parts.reference
        if(-not $ref -and $Parts.candidate){
            $ref=Resolve-GitHubRef -RepositoryUrl $RepositoryUrl -Candidate ([string]$Parts.candidate) -Git $Git
        }
        if($ref){
            & $Git init -q $repositoryRoot
            if($LASTEXITCODE -ne 0){ throw 'git init failed.' }
            & $Git -C $repositoryRoot remote add origin $RepositoryUrl
            if($LASTEXITCODE -ne 0){ throw 'git remote add failed.' }
            & $Git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 -C $repositoryRoot fetch --depth 1 origin $ref
            if($LASTEXITCODE -ne 0){ throw 'git fetch failed.' }
            & $Git -C $repositoryRoot checkout -q FETCH_HEAD
            if($LASTEXITCODE -ne 0){ throw 'git checkout failed.' }
        } else {
            & $Git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 clone --depth 1 $RepositoryUrl $repositoryRoot
            if($LASTEXITCODE -ne 0){ throw 'git clone failed.' }
        }

        $commit=(& $Git -C $repositoryRoot rev-parse HEAD).Trim()
        if($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$'){throw 'git did not return a full commit SHA.'}
        if(-not $ref){
            $headRef=(& $Git -C $repositoryRoot symbolic-ref --quiet --short HEAD 2>$null)
            if($LASTEXITCODE -eq 0 -and $headRef){$ref=([string]$headRef).Trim()}
        }
        if(-not $ref){$ref=$commit}
        $subpath=Get-CsgGitHubSubpath -Candidate ([string]$Parts.candidate) -Reference $ref -LinkKind ([string]$Parts.link_kind)

        $gitDirectory=Join-Path $repositoryRoot '.git'
        if(Test-Path -LiteralPath $gitDirectory){Remove-Item -LiteralPath $gitDirectory -Recurse -Force -ErrorAction Stop}
        if(Test-Path -LiteralPath $gitDirectory){throw 'git metadata could not be removed from the frozen source.'}
        Assert-NoReparsePoints -Root $repositoryRoot
        $null=Assert-CsgContentLimits -Root $repositoryRoot -Limits (Get-CsgArtifactLimits)
        Copy-CsgGitHubSelection -RepositoryRoot $repositoryRoot -Destination $selection -Subpath $subpath -LinkKind ([string]$Parts.link_kind)
        $null=Assert-CsgContentLimits -Root $selection -Limits (Get-CsgArtifactLimits)
        Copy-Tree -Source $selection -Destination $Destination
        return [pscustomobject]@{
            kind='github';repository="$($Parts.owner)/$($Parts.repo)";reference=$ref;commit=$commit
            source_subpath=$subpath;link_kind=[string]$Parts.link_kind;upstream_archive_sha256=$null
        }
    }finally{
        if($null -eq $oldGitPrompt){Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue}else{$env:GIT_TERMINAL_PROMPT=$oldGitPrompt}
        $parent=[IO.Path]::GetFullPath($destinationParent).TrimEnd('\')+'\'
        $resolved=[IO.Path]::GetFullPath($work)
        if((Test-Path -LiteralPath $resolved) -and $resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('.csg-git-')){
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
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
    $gitCommand=Get-Command git -ErrorAction SilentlyContinue
    $git=if($gitCommand){$gitCommand.Source}else{$null}
    $gitFailure=if($git){$null}else{'git.exe is not installed or not on PATH.'}
    if($git){
        $repositoryUrl="https://github.com/$owner/$repo.git"
        try{return Resolve-GitHubSourceViaGit -Parts $parts -Destination $Destination -Git $git -RepositoryUrl $repositoryUrl}
        catch{$gitFailure=$_.Exception.Message}
    }

    Write-Warning "Git source retrieval failed; using commit-pinned GitHub codeload fallback. Git error: $gitFailure"
    try{return Resolve-GitHubSourceViaCodeload -Parts $parts -Destination $Destination}
    catch{throw "GitHub source retrieval failed with Git and codeload. Git: $gitFailure Codeload: $($_.Exception.Message)"}
}

function Split-GitHubSourceUrl {
    param([Parameter(Mandatory)][string]$Source)

    $rawHost=$false
    $m=[regex]::Match($Source,'^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+?)(?:\.git)?(?:/releases/tag/(?<tag>[^?#]+)|/(?<kind>tree|blob|raw)/(?<refpath>[^?#]+))?/?$')
    if(-not $m.Success){
        $m=[regex]::Match($Source,'^https://raw\.githubusercontent\.com/(?<owner>[^/]+)/(?<repo>[^/?#]+?)(?:\.git)?/(?<refpath>[^?#]+)$')
        $rawHost=$m.Success
    }
    if(-not $m.Success){ return $null }

    if($m.Groups['owner'].Value -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$' -or $m.Groups['repo'].Value -notmatch '^[A-Za-z0-9._-]+$'){
        return $null
    }

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
        link_kind=if($rawHost){'raw'}elseif($m.Groups['tag'].Success){'release'}elseif($m.Groups['kind'].Success){$m.Groups['kind'].Value}else{'repository'}
    }
}

function Resolve-GitHubRef {
    param(
        [Parameter(Mandatory)][string]$RepositoryUrl,
        [Parameter(Mandatory)][string]$Candidate,
        [string]$Git='git'
    )

    $candidate=[uri]::UnescapeDataString($Candidate).Trim('/')
    if(-not $candidate.Contains('/')){ return $candidate }
    $firstSegment=($candidate -split '/',2)[0]
    if($firstSegment -match '^[0-9a-fA-F]{40}$'){return $firstSegment.ToLowerInvariant()}

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
                source_subpath=if($prov.PSObject.Properties.Name -contains 'source_subpath'){$prov.source_subpath}else{$null}
                link_kind=if($prov.PSObject.Properties.Name -contains 'link_kind'){$prov.link_kind}else{$null}
                upstream_archive_sha256=if($prov.PSObject.Properties.Name -contains 'upstream_archive_sha256'){$prov.upstream_archive_sha256}else{$null}
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

Export-ModuleMember -Function New-FrozenArtifact,Get-FrozenArtifact,Expand-FrozenArtifact,Split-GitHubSourceUrl,Resolve-GitHubRef,Resolve-GitHubRefViaApi,Resolve-GitHubSourceViaGit,Resolve-GitHubSourceViaCodeload,Get-CsgGitHubSubpath,Copy-CsgGitHubSelection,Get-CsgArtifactLimits,Assert-CsgContentLimits,Test-CsgZipArchive
