# SPDX-License-Identifier: GPL-3.0-only
# Stage 3 build helpers, added 2026-11-10. See ../LICENSE.txt.
$ErrorActionPreference = 'Stop'
$portRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $portRoot
$lwc = Join-Path $repoRoot 'hardware/isap_lwc'
$sharedRtl = Join-Path $repoRoot 'hardware/LWC_rtl'
$sharedTb = Join-Path $repoRoot 'hardware/LWC_tb'
if (-not $VivadoBin) { $VivadoBin = 'C:/Xilinx/Vivado/2024.2/bin' }
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
function Invoke-Stage3Tool([string]$Name, [string[]]$ToolArgs) {
    $command = "$Name " + (($ToolArgs | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    Add-Content -Encoding ascii -LiteralPath 'commands.txt' -Value $command
    Write-Host "> $command"
    & (Join-Path $VivadoBin "$Name.bat") @ToolArgs
    if ($LASTEXITCODE -ne 0) { throw "$Name exited $LASTEXITCODE" }
}
function Get-Stage3Sources([string]$Design) {
    $core = if ($Design -eq 'reference') { "$lwc/src_rtl/v1/CryptoCore.vhd" }
            else { "$portRoot/rtl/crypto_core_2pass_binding.vhd" }
    return @("$lwc/src_rtl/v1/design_pkg.vhd", "$lwc/src_rtl/LWC_config_32.vhd",
        "$sharedRtl/NIST_LWAPI_pkg.vhd", $core,
        "$sharedRtl/key_piso.vhd", "$sharedRtl/FIFO.vhd", "$sharedRtl/data_sipo.vhd",
        "$sharedRtl/data_piso.vhd", "$sharedRtl/PreProcessor.vhd",
        "$sharedRtl/PostProcessor.vhd", "$sharedRtl/LWC_2pass.vhd")
}
function Read-Stage3Records([string]$Name) {
    $raw = Get-Content -Raw -LiteralPath "$lwc/KAT/v1/$Name.txt"
    $matches = [regex]::Matches($raw, '(?ms)^#### MsgID=\s*(\d+),\s*KeyID=\s*(\d+)[^\r\n]*\r?\n(.*?)(?=^#### |^###EOF|\z)')
    $seen = @{}
    foreach ($match in $matches) {
        $id = [int]$match.Groups[1].Value
        if ($seen.ContainsKey($id)) { throw "Duplicate MsgID $id in $Name" }
        $seen[$id] = $true
        [pscustomobject]@{ Id=$id; KeyId=[int]$match.Groups[2].Value;
            Body=$match.Groups[3].Value; Original=$match.Value }
    }
}
function Get-BusWords([string]$Body) {
    return (([regex]::Matches($Body, '(?m)^(INS|HDR|DAT|STT) = [^\r\n]+') |
        ForEach-Object { $_.Value }) -join "`n")
}
