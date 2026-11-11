# SPDX-License-Identifier: GPL-3.0-only
[CmdletBinding()]
param (
    [string]$VivadoBin = '',
    [ValidateSet(0, 1, 2, 3, 4)]
    [int]$TestMode = 4,
    [switch]$Reference
)

$ErrorActionPreference = 'Stop'
$portRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $portRoot
$lwc = Join-Path $repoRoot 'hardware/isap_lwc'
$sharedRtl = Join-Path $repoRoot 'hardware/LWC_rtl'
$sharedTb = Join-Path $repoRoot 'hardware/LWC_tb'

if (-not $VivadoBin) {
    $tool = Get-Command xvhdl.bat -ErrorAction SilentlyContinue
    if ($tool) { $VivadoBin = Split-Path -Parent $tool.Source }
    elseif ($env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO 'bin' }
    elseif (Test-Path 'C:/Xilinx/Vivado/2024.2/bin/xvhdl.bat') {
        $VivadoBin = 'C:/Xilinx/Vivado/2024.2/bin'
    }
    else { throw 'Specify -VivadoBin pointing to the Vivado bin directory.' }
}
$VivadoBin = (Resolve-Path -LiteralPath $VivadoBin).Path
foreach ($name in 'xvhdl', 'xvlog', 'xelab', 'xsim') {
    if (-not (Test-Path -LiteralPath (Join-Path $VivadoBin "$name.bat"))) {
        throw "Missing Vivado tool $name in $VivadoBin"
    }
}

function Invoke-SimTool([string]$Name, [string[]]$ToolArgs) {
    Write-Host "> $Name $($ToolArgs -join ' ')"
    & (Join-Path $VivadoBin "$Name.bat") @ToolArgs
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
}

# Reuse the exact cryptotvgen records for these original AEAD message IDs.
# Separate work directories prevent the VHDL core and adapter from colliding.
$smokeIds = @(3, 6, 7, 8, 11, 12, 14, 16)
$design = if ($Reference) { 'reference' } else { 'systemverilog' }
$build = Join-Path $portRoot "build/aead_smoke/$design-mode$TestMode"
$vectors = Join-Path $build 'KAT/v1'
New-Item -ItemType Directory -Force -Path $vectors | Out-Null
foreach ($name in 'pdi', 'sdi', 'do') {
    $original = Get-Content -Raw -LiteralPath "$lwc/KAT/v1/$name.txt"
    $records = [regex]::Matches($original, '(?ms)^#### MsgID=\s*(\d+),[^\r\n]*\r?\n(.*?)(?=^#### |^###EOF|\z)')
    $selected = @($records | Where-Object { $smokeIds -contains [int]$_.Groups[1].Value })
    if ($selected.Count -ne $smokeIds.Count) {
        throw "Expected $($smokeIds.Count) smoke records in $name.txt, found $($selected.Count)."
    }
    $lines = foreach ($record in $selected) {
        $record.Groups[2].Value -split '\r?\n' |
            Where-Object { $_ -match '^(INS|HDR|DAT|STT) = |^# TB :' }
    }
    Set-Content -Encoding ascii -LiteralPath "$vectors/$name.txt" -Value ($lines + '###EOF')
}

$core = if ($Reference) {
    "$lwc/src_rtl/v1/CryptoCore.vhd"
} else {
    "$portRoot/rtl/crypto_core_2pass_binding.vhd"
}

# Use a VHDL top for generic overrides. Windows batch argument handling
# can split name=value arguments passed to xelab's generic_top option.
@"
entity aead_smoke_tb is
end entity;

architecture test of aead_smoke_tb is
begin
    bench : entity work.LWC_TB
        generic map (G_TEST_MODE => $TestMode, G_TIMEOUT_CYCLES => 5000);
end architecture;
"@ | Set-Content -Encoding ascii -LiteralPath "$build/aead_smoke_tb.vhd"

Push-Location $build
try {
    # Resolve the upstream manifest symlinks to their real files for Windows.
    Invoke-SimTool 'xvhdl' @('--2008',
        "$lwc/src_rtl/v1/design_pkg.vhd",
        "$lwc/src_rtl/LWC_config_32.vhd",
        "$sharedRtl/NIST_LWAPI_pkg.vhd",
        $core,
        "$sharedRtl/key_piso.vhd",
        "$sharedRtl/FIFO.vhd",
        "$sharedRtl/data_sipo.vhd",
        "$sharedRtl/data_piso.vhd",
        "$sharedRtl/PreProcessor.vhd",
        "$sharedRtl/PostProcessor.vhd",
        "$sharedRtl/LWC_2pass.vhd",
        "$lwc/src_tb/v1/LWC_TB_config.vhd",
        "$sharedTb/LWC_TB_2pass_uut.vhd",
        "$sharedTb/LWC_TB.vhd",
        "$build/aead_smoke_tb.vhd")
    if (-not $Reference) {
        Invoke-SimTool 'xvlog' @('--sv', "$portRoot/rtl/asconp.sv",
            "$portRoot/rtl/crypto_core_2pass.sv")
    }

    Invoke-SimTool 'xelab' @('work.aead_smoke_tb', '-s', 'aead_smoke', '--timescale', '1ns/1ps')
    Invoke-SimTool 'xsim' @('aead_smoke', '-runall', '-log', 'aead_smoke.log')
    $summary = Select-String -LiteralPath 'aead_smoke.log' -Pattern '\[PASS\] Simulation completed in \d+ cycles\.'
    $caseCount = @(Select-String -LiteralPath 'log.txt' -Pattern '^Testcase #').Count
    if (-not $summary -or $caseCount -ne $smokeIds.Count -or
        (Get-Item -LiteralPath 'failed_testvectors.txt').Length -ne 0) {
        throw "AEAD smoke test did not pass all $($smokeIds.Count) cases. See $build"
    }
    Write-Host "$design mode $TestMode passed all $caseCount AEAD smoke cases."
    if ($TestMode -eq 4) { Get-Content -LiteralPath 'timing.txt' }
}
finally { Pop-Location }

