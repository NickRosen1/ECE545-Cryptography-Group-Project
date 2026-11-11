# SPDX-License-Identifier: GPL-3.0-only
[CmdletBinding()]
param([string]$VivadoBin='', [string[]]$Designs=@('reference','systemverilog'))
. "$PSScriptRoot/stage3_common.ps1"
$pdi=@(Read-Stage3Records 'pdi' | Where-Object {$_.Id -eq 7})[0]
$sdi=@(Read-Stage3Records 'sdi' | Where-Object {$_.Id -eq 7})[0]
$dout=@(Read-Stage3Records 'do' | Where-Object {$_.Id -eq 7})[0]
function Get-Segment([string]$Body,[string]$Type) {
    $match=[regex]::Match($Body,"(?ms)^HDR = $Type[0-9A-F]{7}\r?\nDAT = ([0-9A-F]+)")
    if(-not $match.Success) {throw "Missing segment $Type"}
    return $match.Groups[1].Value
}
$keyValue=Get-Segment $sdi.Body 'C'
$nonce=Get-Segment $pdi.Body 'D'
$ad=Get-Segment $pdi.Body '1'
$ct=Get-Segment $pdi.Body '5'
$tag=Get-Segment $pdi.Body '8'
$pt=Get-Segment $dout.Body '4'
$emptyPdi=@(Read-Stage3Records 'pdi' | Where-Object {$_.Id -eq 6})[0]
$emptySdi=@(Read-Stage3Records 'sdi' | Where-Object {$_.Id -eq 6})[0]
function Get-SvWords([string]$Body,[string]$Name) {
    $words=@(foreach($line in [regex]::Matches($Body,'(?m)^(?:INS|HDR|DAT|STT) = ([0-9A-F]+)')) {
        foreach($word in [regex]::Matches($line.Groups[1].Value,'.{8}')) { "32'h$($word.Value)" }
    })
    "localparam int ${Name}_COUNT=$($words.Count);"
    "localparam logic [31:0] $Name [0:$($words.Count-1)] = '{"+($words -join ',')+'};'
}
$reports=Join-Path $portRoot 'reports/stage3'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
foreach($design in $Designs) {
    $build=Join-Path $portRoot "build/stage3/tags/$design-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $build | Out-Null
    @"
// SPDX-License-Identifier: GPL-3.0-only
// Generated from unchanged upstream v1 MsgID=7, KeyID=3.
localparam logic [127:0] KEY_VALUE=128'h$keyValue;
localparam logic [127:0] NONCE_VALUE=128'h$nonce;
localparam logic [31:0] AD_VALUE=32'h$ad;
localparam logic [127:0] CT_VALUE=128'h$ct;
localparam logic [127:0] TAG_VALUE=128'h$tag;
localparam logic [127:0] PT_VALUE=128'h$pt;
"@ | Set-Content -Encoding ascii "$build/invalid_vectors.svh"
    Get-SvWords $pdi.Body 'PDI_NONEMPTY' | Add-Content -Encoding ascii "$build/invalid_vectors.svh"
    Get-SvWords $sdi.Body 'SDI_NONEMPTY' | Add-Content -Encoding ascii "$build/invalid_vectors.svh"
    Get-SvWords $dout.Body 'DO_NONEMPTY' | Add-Content -Encoding ascii "$build/invalid_vectors.svh"
    Get-SvWords $emptyPdi.Body 'PDI_EMPTY' | Add-Content -Encoding ascii "$build/invalid_vectors.svh"
    Get-SvWords $emptySdi.Body 'SDI_EMPTY' | Add-Content -Encoding ascii "$build/invalid_vectors.svh"
    Push-Location $build
    try {
        Invoke-Stage3Tool 'xvhdl' (@('--2008') + @(Get-Stage3Sources $design) + @("$portRoot/tb/stage3_core_dut.vhd","$sharedTb/LWC_TB_2pass_uut.vhd"))
        $sv=@('--sv','-i',$build,"$portRoot/tb/tb_invalid_tag.sv","$portRoot/tb/tb_invalid_tag_wrapper.sv")
        if($design -eq 'systemverilog') { $sv+=@("$portRoot/rtl/asconp.sv","$portRoot/rtl/crypto_core_2pass.sv") }
        Invoke-Stage3Tool 'xvlog' $sv
        Invoke-Stage3Tool 'xelab' @('work.tb_invalid_tag','-s','invalid_tags','--timescale','1ns/1ps')
        Invoke-Stage3Tool 'xsim' @('invalid_tags','-runall','-log','simulation.log')
        Copy-Item 'simulation.log' "$reports/$design-invalid-tags.log"
        Copy-Item 'commands.txt' "$reports/$design-invalid-tags-commands.txt"
        $log=Get-Content -Raw 'simulation.log'
        if($log -notmatch 'STAGE3_TAG_PASS cases=4 invalid=3' -or
            $log -match 'Fatal:|Error:|ERROR:|Failure:') {throw "Invalid-tag verification failed: $build"}
        Invoke-Stage3Tool 'xelab' @('work.tb_invalid_tag_wrapper','-s','invalid_tags_wrapper','--timescale','1ns/1ps')
        Invoke-Stage3Tool 'xsim' @('invalid_tags_wrapper','-runall','-log','wrapper.log')
        Copy-Item 'wrapper.log' "$reports/$design-invalid-tags-wrapper.log"
        Copy-Item 'commands.txt' "$reports/$design-invalid-tags-commands.txt"
        $log=Get-Content -Raw 'wrapper.log'
        if($log -notmatch 'STAGE3_WRAPPER_CHECKS_COMPLETE valid=1 empty_rejections=3 nonempty_limitations=3' -or
            $log -match 'Fatal:|Error:|ERROR:|Failure:') {throw "Wrapper negative-test checks incomplete: $build"}
    } finally {Pop-Location}
}
