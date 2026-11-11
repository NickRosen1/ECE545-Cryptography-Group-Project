# SPDX-License-Identifier: GPL-3.0-only
[CmdletBinding()]
param([string]$VivadoBin='', [double]$ClockPeriodNs=10.0,
      [string[]]$Designs=@('reference','systemverilog'))
. "$PSScriptRoot/stage3_common.ps1"
foreach ($design in $Designs) {
    if ($design -notin @('reference','systemverilog')) { throw 'Invalid design' }
    $build=Join-Path $portRoot "build/stage3/synthesis/$design-$([guid]::NewGuid().ToString('N'))"
    $reports=Join-Path $portRoot "reports/stage3/synthesis/$design"
    New-Item -ItemType Directory -Force -Path $build,$reports | Out-Null
    Push-Location $build
    try {
        Invoke-Stage3Tool 'vivado' @('-mode','batch','-nojournal','-source',"$portRoot/synth_stage3.tcl",
            '-tclargs',$design,$ClockPeriodNs.ToString([cultureinfo]::InvariantCulture),$reports)
        if (-not (Select-String -LiteralPath 'vivado.log' -SimpleMatch -Quiet -Pattern "STAGE3_SYNTHESIS_COMPLETE $design")) {
            throw "Synthesis did not finish: $build"
        }
        Copy-Item 'vivado.log', 'commands.txt' -Destination $reports
    } finally { Pop-Location }
}
