Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Import-PwshToolchain {
    $root=Initialize-CsgLayout
    $pwsh=Get-Command pwsh -ErrorAction Stop
    $source=Split-Path -Parent $pwsh.Source
    $dest=Join-Path (Join-Path $root 'toolchains') 'pwsh'
    $payload=Join-Path $dest 'payload'

    if(Test-Path -LiteralPath $dest){Remove-Item -LiteralPath $dest -Recurse -Force}
    New-Item -ItemType Directory -Force -Path $payload | Out-Null

    # Copy the complete PowerShell installation directory so CoreCLR/native dependencies travel together.
    Copy-Tree -Source $source -Destination $payload
    $treeHash=Get-PayloadTreeHash $payload

    $manifest=[ordered]@{
        schema_version=2
        toolchain='pwsh'
        imported_at=(Get-Date).ToString('o')
        source=$source
        executable=(Split-Path -Leaf $pwsh.Source)
        version=$PSVersionTable.PSVersion.ToString()
        tree_sha256=$treeHash
        payload=$payload
        trust_note='This is a frozen copy of the host PowerShell 7 runtime. It is mapped read-only into Windows Sandbox.'
    }
    Write-JsonFile $manifest (Join-Path $dest 'toolchain.json')
    Write-Host "Frozen pwsh toolchain: $dest"
    Write-Host "SHA256(tree): $treeHash"
    return $manifest
}

function Get-PwshToolchain {
    $root=Initialize-CsgLayout
    $dest=Join-Path (Join-Path $root 'toolchains') 'pwsh'
    $mPath=Join-Path $dest 'toolchain.json'
    if(-not (Test-Path -LiteralPath $mPath)){return $null}
    $m=Read-JsonFile $mPath
    if(-not (Test-Path -LiteralPath $m.payload)){throw 'pwsh toolchain payload missing.'}
    $actual=Get-PayloadTreeHash $m.payload
    if($actual -ne $m.tree_sha256){throw 'pwsh toolchain hash mismatch.'}
    return $m
}

Export-ModuleMember -Function *
