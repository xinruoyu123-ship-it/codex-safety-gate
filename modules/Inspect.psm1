Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Artifact.psm1') -Force

function Get-RiskRules {
    return @(
        [pscustomobject]@{id='download_exec';cap='supply_chain.dynamic_exec';severity=5;regex='(?im)(curl|wget|irm|Invoke-RestMethod|Invoke-WebRequest)[^\r\n|]{0,300}\|\s*(sh|bash|pwsh|powershell|iex|Invoke-Expression)\b'},
        [pscustomobject]@{id='dynamic_exec';cap='process.dynamic_code';severity=4;regex='(?i)\bInvoke-Expression\b|\biex\b|\beval\s*\('},
        [pscustomobject]@{id='elevation';cap='os.elevation';severity=5;regex='(?im)Start-Process[^\r\n]{0,300}-Verb\s+RunAs|#Requires\s+-RunAsAdministrator|\brunas(?:\.exe)?\b'},
        [pscustomobject]@{id='persistence';cap='os.persistence';severity=5;regex='(?i)\bRegister-ScheduledTask\b|\bschtasks(?:\.exe)?\b|\bNew-Service\b|\bsc(?:\.exe)?\s+(create|config|start)\b'},
        [pscustomobject]@{id='registry';cap='os.registry_write';severity=4;regex='(?i)\b(HKCU:|HKLM:|reg\.exe\s+(add|delete)|Set-ItemProperty[^\r\n]{0,200}Registry)'},
        [pscustomobject]@{id='path';cap='os.path_write';severity=4;regex='(?i)\bsetx(?:\.exe)?\b[^\r\n]*\bPATH\b|SetEnvironmentVariable\([^\r\n]{0,300}PATH'},
        [pscustomobject]@{id='codex_config';cap='codex.config_write';severity=4;regex='(?i)(\.codex[\\/](config\.toml|models_cache\.json|auth\.json)|openai_base_url|model_provider|model_catalog_json)'},
        [pscustomobject]@{id='agents';cap='codex.global_agents_write';severity=3;regex='(?i)\.codex[\\/]AGENTS\.md|AGENTS\.md'},
        [pscustomobject]@{id='skills';cap='codex.skill_install';severity=3;regex='(?i)\.codex[\\/]skills[\\/]|skillsRoot|targetSkill|SKILL\.md'},
        [pscustomobject]@{id='proxy';cap='network.local_proxy';severity=5;regex='(?i)(openai_base_url|127\.0\.0\.1|localhost).{0,160}(proxy|listen|\/v1)|(?:proxy|listen).{0,160}(127\.0\.0\.1|localhost)'},
        [pscustomobject]@{id='wrapper';cap='codex.launcher_wrap';severity=4;regex='(?i)codex[-_ ]?shim|Set-Alias[^\r\n]*\bcodex\b|(?:rename|move|copy)[^\r\n]{0,200}codex(?:\.exe)?'},
        [pscustomobject]@{id='credentials';cap='secrets.access';severity=5;regex='(?i)(\.ssh[\\/]|id_rsa|id_ed25519|auth\.json|cookies?\.sqlite|Login Data|credential manager|dpapi)'},
        [pscustomobject]@{id='network';cap='network.outbound';severity=3;regex='(?i)\b(Invoke-WebRequest|Invoke-RestMethod|curl(?:\.exe)?|wget)\b|https?://'},
        [pscustomobject]@{id='package_install';cap='supply_chain.package_install';severity=3;regex='(?im)\b(npm\s+(install|i)|pip(?:3)?\s+install|winget\s+install|choco\s+install|scoop\s+install)\b'},
        [pscustomobject]@{id='spawn';cap='process.spawn';severity=3;regex='(?i)\bStart-Process\b|\bsubprocess\.(run|Popen)\b|\bchild_process\b|\bcodex\s+exec\b'},
        [pscustomobject]@{id='delete';cap='filesystem.destructive_delete';severity=4;regex='(?im)Remove-Item[^\r\n]{0,240}-Recurse[^\r\n]{0,240}-Force|\brd\s+\/s\b|\brmdir\s+\/s\b'},
        [pscustomobject]@{id='prompt_artifacts';cap='privacy.prompt_artifacts';severity=3;regex='(?i)(prompt\.md|stdout\.jsonl|stderr\.txt|final\.md|manifest\.json)'}
    )
}

function Get-InspectableFiles([string]$Root){
    $ext=@('.ps1','.psm1','.psd1','.sh','.bash','.zsh','.py','.js','.ts','.mjs','.cjs','.json','.toml','.yaml','.yml','.md','.cmd','.bat','.ini','.cfg','.txt')
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object {$_.Length -le 8MB -and ($ext -contains $_.Extension.ToLowerInvariant() -or $_.Name -in @('Dockerfile','Makefile'))})
}

function Invoke-ArtifactInspection {
    param([Parameter(Mandatory)][string]$ArtifactId)
    $root=Initialize-CsgLayout
    $tmp=Join-Path (Join-Path $root 'tmp') (New-Id 'inspect')
    $artifact=Expand-FrozenArtifact -ArtifactId $ArtifactId -Destination $tmp
    try {
        $findings=@()
        foreach($f in Get-InspectableFiles $tmp){
            $relative=(Get-RelativePathSafe -Base $tmp -Full $f.FullName).Replace('/','\')
            if($f.Name -ieq 'SKILL.md'){
                $findings += [pscustomobject]@{
                    rule='skill_structure';capability='codex.skill_install';severity=3
                    file=$relative;line=1;evidence='SKILL.md is present in the extension payload.'
                }
            }
            if($f.Name -ieq 'AGENTS.md'){
                $findings += [pscustomobject]@{
                    rule='agents_structure';capability='codex.global_agents_write';severity=3
                    file=$relative;line=1;evidence='AGENTS.md is present in the extension payload.'
                }
            }
            try{$text=[IO.File]::ReadAllText($f.FullName)}catch{continue}
            $isLegalNotice=$f.Name -match '^(?i:LICENSE|COPYING|NOTICE)(?:[-_.].*)?$'
            if(-not $isLegalNotice){
                foreach($rule in Get-RiskRules){
                    foreach($match in ([regex]::Matches($text,$rule.regex)|Select-Object -First 8)){
                        $line=(($text.Substring(0,$match.Index)) -split "`n").Count
                        $snippet=($match.Value -replace '\s+',' ').Trim()
                        if($snippet.Length -gt 180){$snippet=$snippet.Substring(0,180)+'…'}
                        $findings += [pscustomobject]@{
                            rule=$rule.id; capability=$rule.cap; severity=$rule.severity
                            file=$relative
                            line=$line; evidence=$snippet
                        }
                    }
                }
            }
        }

        $caps=@($findings|Select-Object -ExpandProperty capability -Unique|Sort-Object)
        $critical=@($findings|Where-Object severity -eq 5)
        $high=@($findings|Where-Object severity -eq 4)
        $medium=@($findings|Where-Object severity -eq 3)

        $band=if(@($critical|Where-Object {$_.capability -in @('secrets.access','os.elevation','os.persistence','supply_chain.dynamic_exec')}).Count){'RED'}
              elseif($critical.Count -or @($high|Where-Object {$_.capability -in @('codex.config_write','codex.launcher_wrap','os.registry_write','os.path_write')}).Count){'ORANGE'}
              elseif($high.Count -or $medium.Count){'YELLOW'}else{'GREEN'}

        $report=[ordered]@{
            schema_version=2;artifact_id=$ArtifactId;generated_at=(Get-Date).ToString('o')
            provenance=$artifact.provenance
            risk_band=$band
            capabilities=@($caps)
            counts=[ordered]@{critical=$critical.Count;high=$high.Count;medium=$medium.Count;total=$findings.Count}
            findings=@($findings | Sort-Object -Property @{
                Expression='severity';Descending=$true
            },@{
                Expression='file';Ascending=$true
            },@{
                Expression='line';Ascending=$true
            })
            disclaimer='Static inspection is evidence, not proof of safety. Behavior must be staged before promotion.'
        }
        $rdir=Join-Path (Join-Path $root 'reports') $ArtifactId
        Write-JsonFile $report (Join-Path $rdir 'inspection.json')
        return $report
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function *
