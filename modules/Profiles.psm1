Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Artifact.psm1') -Force

function Get-AddonProfile {
    param([Parameter(Mandatory)][string]$ArtifactId)
    $root=Initialize-CsgLayout
    $tmp=Join-Path (Join-Path $root 'tmp') (New-Id 'profile')
    $artifact=Expand-FrozenArtifact -ArtifactId $ArtifactId -Destination $tmp
    try {
        $all=@(Get-ChildItem -LiteralPath $tmp -Recurse -Force -File)
        $names=@($all|ForEach-Object {$_.Name.ToLowerInvariant()})
        $text=''
        foreach($f in ($all|Where-Object {$_.Length -lt 2MB -and $_.Extension -in @('.md','.ps1','.json','.toml','.ts','.js','.py','.sh')}|Select-Object -First 80)){
            try{$text += "`n" + [IO.File]::ReadAllText($f.FullName)}catch{}
        }

        $profile='unknown'
        $risk='YELLOW'
        $reason=@()

        if($text -match '(?i)openai_base_url|model_provider|localhost.{0,80}(proxy|listen)|127\.0\.0\.1'){
            $profile='proxy-gateway';$risk='ORANGE'
            $reason+='modifies or interposes model/provider/network routing'
        } elseif($text -match '(?i)codex\s+exec|auto-agent|router|delegate|sub.?agent'){
            $profile='agent-router';$risk='YELLOW'
            $reason+='launches or routes Codex worker agents'
        } elseif('skill.md' -in $names -or $text -match '(?i)\.codex[\\/]skills'){
            $profile='skill';$risk='YELLOW'
            $reason+='installs Codex skill content'
        } elseif($text -match '(?i)mcp|model context protocol'){
            $profile='mcp';$risk='ORANGE'
            $reason+='integrates an MCP/tool service'
        }

        $recipe='manual'
        $installCommand=$null
        $installWin=$all|Where-Object {$_.Name -ieq 'install-windows.ps1'}|Select-Object -First 1
        if($installWin){
            $raw=[IO.File]::ReadAllText($installWin.FullName)
            $rel=Get-RelativePathSafe -Base $tmp -Full $installWin.FullName
            if($raw -match '(?i)\bHomePath\b'){
                $recipe='windows-homepath-installer'
                $installCommand="pwsh -NoProfile -File `".\$($rel.Replace('\','/'))`" -HomePath `$env:CSG_TARGET_HOME"
            } else {
                $recipe='windows-installer-manual-target'
            }
        } elseif($profile -eq 'skill'){
            $skillFile=$all|Where-Object {$_.Name -ieq 'SKILL.md'}|Select-Object -First 1
            if($skillFile){
                $skillRoot=Split-Path -Parent $skillFile.FullName
                $relativeSkillRoot=Get-RelativePathSafe -Base $tmp -Full $skillRoot
                $skillName=(Split-Path -Leaf $skillRoot) -replace '[^A-Za-z0-9._-]','-'
                if([string]::IsNullOrWhiteSpace($skillName)){$skillName='reviewed-addon'}
                $quotedRelative=$relativeSkillRoot.Replace('\','/').Replace("'","''")
                $recipe='csg-safe-skill-copy'
                $installCommand="`$src=Join-Path (Get-Location) '$quotedRelative'; `$dst=Join-Path `$env:CSG_TARGET_CODEX_HOME 'skills\$skillName'; New-Item -ItemType Directory -Force -Path `$dst|Out-Null; Get-ChildItem -LiteralPath `$src -Force | Copy-Item -Destination `$dst -Recurse -Force"
            }
        }

        return [pscustomobject]@{
            profile=$profile
            risk_hint=$risk
            reason=@($reason)
            recipe=$recipe
            install_command=$installCommand
            automatic=($null -ne $installCommand)
            note=if($profile -eq 'proxy-gateway'){'Proxy/gateway addons require a dedicated runtime profile; generic file-overlay promotion is intentionally insufficient.'}else{$null}
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function *
