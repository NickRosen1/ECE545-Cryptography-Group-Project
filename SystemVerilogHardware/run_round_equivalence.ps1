# SPDX-License-Identifier: GPL-3.0-only
# Added 2026-11-10. Run from any directory; all products stay under this tree.
[CmdletBinding()]
param (
    [string]$VivadoBin = '',
    [string]$Iverilog = ''
)
$ErrorActionPreference = 'Stop'
$portRoot = $PSScriptRoot
$repoRoot = Split-Path -Parent $portRoot
$build = Join-Path $portRoot 'build/round_equivalence'

if (-not $VivadoBin) {
    $tool = Get-Command xvhdl.bat -ErrorAction SilentlyContinue
    if ($tool) { $VivadoBin = Split-Path -Parent $tool.Source }
    elseif ($env:XILINX_VIVADO) { $VivadoBin = Join-Path $env:XILINX_VIVADO 'bin' }
    elseif (Test-Path 'C:/Xilinx/Vivado/2024.2/bin/xvhdl.bat') {
        $VivadoBin = 'C:/Xilinx/Vivado/2024.2/bin'
    }
    else { throw 'Specify -VivadoBin pointing to the Vivado bin directory.' }
}
foreach ($name in 'xvhdl', 'xvlog', 'xelab', 'xsim') {
    if (-not (Test-Path (Join-Path $VivadoBin "$name.bat"))) {
        throw "Missing Vivado tool: $name in $VivadoBin"
    }
}

New-Item -ItemType Directory -Force -Path $build | Out-Null
function Invoke-SimTool([string]$Name, [string[]]$ToolArgs) {
    Write-Host "> $Name $($ToolArgs -join ' ')"
    & (Join-Path $VivadoBin "$Name.bat") @ToolArgs
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE" }
}

Push-Location $build
try {
    # Remove the previous PASS log only; never accept an old simulation result.
    if (Test-Path -LiteralPath 'equivalence.log') {
        Remove-Item -LiteralPath 'equivalence.log'
    }
    # Compile the complete, unchanged upstream file. Only Asconp is elaborated.
    # Use the symlink target directly: Windows Git can check links out as text.
    Invoke-SimTool 'xvhdl' @('--2008',
        "$repoRoot/hardware/isap_lwc/src_rtl/v1/design_pkg.vhd",
        "$repoRoot/hardware/isap_lwc/src_rtl/LWC_config_32.vhd",
        "$repoRoot/hardware/LWC_rtl/NIST_LWAPI_pkg.vhd",
        "$repoRoot/hardware/isap_lwc/src_rtl/v1/CryptoCore.vhd",
        "$portRoot/tb/asconp_vhdl_ref.vhd")
    Invoke-SimTool 'xvlog' @('--sv', "$portRoot/rtl/asconp.sv",
        "$portRoot/tb/tb_asconp_equiv.sv")
    Invoke-SimTool 'xelab' @('work.tb_asconp_equiv', '-s', 'asconp_equiv',
        '--timescale', '1ns/1ps')
    Invoke-SimTool 'xsim' @('asconp_equiv', '-runall', '-log', 'equivalence.log')
    if (-not (Select-String -LiteralPath 'equivalence.log' -Quiet -SimpleMatch `
            'PASS: 81504 Ascon-p comparisons against original VHDL; seed=1a128a20')) {
        throw 'Simulation did not report the expected completed comparison suite.'
    }

    if (-not $Iverilog) {
        $tool = Get-Command iverilog -ErrorAction SilentlyContinue
        if ($tool) { $Iverilog = $tool.Source }
        elseif (Test-Path 'C:/iverilog/bin/iverilog.exe') {
            $Iverilog = 'C:/iverilog/bin/iverilog.exe'
        }
    }
    if ($Iverilog) {
        & $Iverilog -g2012 -Wall -s asconp_sv -t null "$portRoot/rtl/asconp.sv"
        if ($LASTEXITCODE -ne 0) { throw 'Icarus RTL compile failed.' }
        Write-Host 'PASS: Icarus SystemVerilog RTL compile.'
    }
    else { Write-Host 'SKIP: Icarus not found; mixed-language comparison completed.' }
}
finally { Pop-Location }
