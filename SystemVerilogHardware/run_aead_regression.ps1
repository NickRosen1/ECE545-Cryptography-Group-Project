# SPDX-License-Identifier: GPL-3.0-only
# Full upstream AEAD regression, added 2026-11-10. See ../LICENSE.txt.
[CmdletBinding()]
param([string]$VivadoBin = '', [int[]]$Modes = @(0,1),
      [string[]]$Designs = @('reference','systemverilog'))
. "$PSScriptRoot/stage3_common.ps1"
$reportRoot = Join-Path $portRoot 'reports/stage3'
New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
$pdi = @(Read-Stage3Records 'pdi')
$sdi = @{}; Read-Stage3Records 'sdi' | ForEach-Object { $sdi[$_.Id] = $_ }
$dout = @{}; Read-Stage3Records 'do' | ForEach-Object { $dout[$_.Id] = $_ }
$aead = @($pdi | Where-Object { $_.Body -match 'INS = [23]0000000' })
$hash = @($pdi | Where-Object { $_.Body -match 'INS = 80000000' })
if ($aead.Count -ne 648 -or $hash.Count -ne 648 -or $pdi.Count -ne 1296) {
    throw 'Unexpected upstream dataset; review selection rather than silently changing coverage.'
}
$selection = foreach ($record in $aead) {
    $id=$record.Id
    if (-not $sdi.ContainsKey($id) -or -not $dout.ContainsKey($id) -or
        $sdi[$id].KeyId -ne $record.KeyId -or $dout[$id].KeyId -ne $record.KeyId -or
        $record.Body -notmatch 'INS = 70000000') { throw "Key/record dependency mismatch at $id" }
    [pscustomobject]@{MessageId=$id; KeyId=$record.KeyId;
        Operation=$(if ($record.Body -match 'INS = 20000000') {'ENC'} else {'DEC'});
        TestbenchId=($id -band 255)}
}
$selection | Export-Csv -NoTypeInformation -Encoding ascii "$reportRoot/selection.csv"
$hash | Select-Object Id,KeyId | Export-Csv -NoTypeInformation -Encoding ascii "$reportRoot/excluded_hash.csv"
$expectedWords = 0
foreach ($r in $aead) {
    foreach ($m in [regex]::Matches($dout[$r.Id].Body, '(?m)^(?:HDR|DAT|STT) = ([0-9A-Fa-fXx]+)')) {
        if ($m.Groups[1].Value.Length % 8) { throw 'Unaligned expected output' }
        $expectedWords += $m.Groups[1].Value.Length / 8
    }
}
$results = @()
foreach ($design in $Designs) {
    if ($design -notin @('reference','systemverilog')) { throw "Unknown design $design" }
    foreach ($mode in $Modes) {
        if ($mode -notin @(0,1,4)) { throw "Unsupported mode $mode" }
        # A unique directory prevents stale snapshots/logs from satisfying checks.
        $runId = [guid]::NewGuid().ToString('N')
        $build = Join-Path $portRoot "build/stage3/regression/$design-mode$mode-$runId"
        $vectors = Join-Path $build 'KAT/v1'
        New-Item -ItemType Directory -Force -Path $vectors | Out-Null
        $lengths = foreach ($r in $aead) {
            $words=0
            foreach ($m in [regex]::Matches($r.Body, '(?m)^(?:INS|HDR|DAT) = ([0-9A-Fa-f]+)')) {
                $words += $m.Groups[1].Value.Length / 8
            }
            "$($r.Id) $words"
        }
        Set-Content -Encoding ascii "$build/message_lengths.txt" -Value $lengths
        $uut = Get-Content -Raw "$sharedTb/LWC_TB_2pass_uut.vhd"
        $monitor = @'
    stage3_cycles : entity work.stage3_timing_monitor
        port map (clk=>clk, rst=>rst, pdi_valid=>pdi_valid, pdi_ready=>pdi_ready,
                  do_valid=>do_valid, do_ready=>do_ready, do_last=>do_last);
end architecture;
'@
        if ([regex]::Matches($uut, '(?i)end architecture;').Count -ne 1) { throw 'UUT insertion point changed' }
        $uut = "-- SPDX-License-Identifier: GPL-3.0-only`n-- Derived 2026-11-10 from hardware/LWC_tb/LWC_TB_2pass_uut.vhd.`n-- Only a passive timing monitor is added; original wrapper and FIFO remain.`n" + [regex]::Replace($uut, '(?i)end architecture;', $monitor)
        Set-Content -Encoding ascii "$build/LWC_TB_2pass_uut_monitored.vhd" $uut
        foreach ($name in 'pdi','sdi','do') {
            $bodies = foreach ($r in $aead) {
                $source = switch ($name) { 'pdi' {$r} 'sdi' {$sdi[$r.Id]} 'do' {$dout[$r.Id]} }
                $body = $source.Original
                if ($name -eq 'do') {
                    $op = if ($r.Body -match 'INS = 20000000') {2} else {3}
                    $label = '# TB :{0:X1}{1:X2}{2:X2} (diagnostic IDs modulo 256; see selection.csv)' -f $op,($r.KeyId -band 255),($r.Id -band 255)
                    $body = [regex]::Replace($body, '(?m)^# TB :[^\r\n]+', $label)
                }
                if ((Get-BusWords $body) -cne (Get-BusWords $source.Original)) {
                    throw "Changed original bus words for $name MsgID $($r.Id)"
                }
                $body
            }
            Set-Content -Encoding ascii "$vectors/$name.txt" -Value ($bodies + '###EOF')
        }
        @"
-- SPDX-License-Identifier: GPL-3.0-only
-- Generated test top; original LWC_TB remains unchanged.
entity stage3_aead_tb is end entity;
architecture test of stage3_aead_tb is begin
    bench : entity work.LWC_TB generic map (
        G_TEST_MODE => $mode, G_TIMEOUT_CYCLES => 10000,
        G_MAX_FAILURES => 1, G_CLK_PERIOD_PS => 10000,
        G_PDI_STALLS => 3, G_SDI_STALLS => 3, G_DO_STALLS => 3,
        G_RANDOM_STALL => false, G_RANDOM_SEED => 1);
end architecture;
"@ | Set-Content -Encoding ascii "$build/stage3_aead_tb.vhd"
        # Bounded simulation plus explicit PASS/count checks: a time limit is not success.
        "run 100 ms`nquit" | Set-Content -Encoding ascii "$build/run.tcl"
        Push-Location $build
        try {
            $sources = @(Get-Stage3Sources $design) + @("$lwc/src_tb/v1/LWC_TB_config.vhd",
                "$portRoot/tb/lwc_timing_monitor.vhd", "$build/LWC_TB_2pass_uut_monitored.vhd",
                "$sharedTb/LWC_TB.vhd", "$build/stage3_aead_tb.vhd")
            Invoke-Stage3Tool 'xvhdl' (@('--2008') + $sources)
            if ($design -eq 'systemverilog') {
                Invoke-Stage3Tool 'xvlog' @('--sv', "$portRoot/rtl/asconp.sv", "$portRoot/rtl/crypto_core_2pass.sv")
            }
            Invoke-Stage3Tool 'xelab' @('work.stage3_aead_tb','-s','stage3_aead','--timescale','1ns/1ps')
            Invoke-Stage3Tool 'xsim' @('stage3_aead','-tclbatch','run.tcl','-log','simulation.log')
            $log = Get-Content -Raw 'simulation.log'
            Copy-Item -LiteralPath 'simulation.log' -Destination "$reportRoot/$design-mode$mode.log"
            Copy-Item -LiteralPath 'commands.txt' -Destination "$reportRoot/$design-mode$mode-commands.txt"
            $cases = @(Select-String 'log.txt' -Pattern '^Testcase #').Count
            $matched = @(Select-String 'log.txt' -Pattern 'Matched!').Count
            if ($log -notmatch '\[PASS\] Simulation completed in (\d+) cycles\.' -or
                $log -match '\[FAIL|\[Error\]|Fatal:|Error:|ERROR:' -or $cases -ne 648 -or
                $matched -ne $expectedWords -or (Get-Item 'failed_testvectors.txt').Length -ne 0 -or
                (Get-Content -Raw 'result.txt').Trim() -ne '0') {
                throw "Regression failed: $design mode $mode; cases=$cases matched=$matched; $build"
            }
            $cycles = [int]([regex]::Match($log, 'Simulation completed in (\d+) cycles').Groups[1].Value)
            if ($log -notmatch 'STAGE3_TIMING_COMPLETE 648') { throw 'Passive timing monitor did not complete' }
            {
                $timing = @(Get-Content 'stream_cycles.txt' | Where-Object { $_.Trim() })
                if ($timing.Count -ne 648) { throw 'Missing per-message timing rows' }
                $mapped = for ($i=0; $i -lt $timing.Count; $i++) {
                    $fields = $timing[$i].Split(',')
                    if ([int]$fields[0] -ne $selection[$i].MessageId) { throw 'Timing row ID/order mismatch' }
                    [pscustomobject]@{MessageId=$selection[$i].MessageId; Operation=$selection[$i].Operation; Cycles=[int]$fields[1]}
                }
                $mapped | Export-Csv -NoTypeInformation -Encoding ascii "$reportRoot/$design-mode$mode-cycles.csv"
            }.Invoke()
            Copy-Item -LiteralPath 'simulation.log' -Destination "$reportRoot/$design-mode$mode.log"
            Copy-Item -LiteralPath 'commands.txt' -Destination "$reportRoot/$design-mode$mode-commands.txt"
            $results += [pscustomobject]@{Design=$design;Mode=$mode;Cases=$cases;MatchedWords=$matched;TotalCycles=$cycles;Build=$build;RunId=$runId;Passed=$true}
            $results | ConvertTo-Json -Depth 5 | Set-Content -Encoding ascii "$reportRoot/regression.json"
            Write-Host "PASS $design mode=$mode cases=$cases words=$matched cycles=$cycles"
        } finally { Pop-Location }
    }
}
if ('reference' -in $Designs -and 'systemverilog' -in $Designs) {
  foreach ($mode in $Modes) {
    $ref = @(Import-Csv "$reportRoot/reference-mode$mode-cycles.csv")
    $sv = @(Import-Csv "$reportRoot/systemverilog-mode$mode-cycles.csv")
    $comparison = for ($i=0; $i -lt 648; $i++) {
        if ($ref[$i].MessageId -ne $sv[$i].MessageId) { throw 'Timing identity mismatch' }
        [pscustomobject]@{MessageId=$ref[$i].MessageId;Operation=$ref[$i].Operation;
            VhdlCycles=[int]$ref[$i].Cycles;SvCycles=[int]$sv[$i].Cycles;Delta=([int]$sv[$i].Cycles-[int]$ref[$i].Cycles)}
    }
    $comparison | Export-Csv -NoTypeInformation -Encoding ascii "$reportRoot/mode$mode-cycle-comparison.csv"
    if (@($comparison | Where-Object {$_.Delta -ne 0}).Count) { throw "Per-message timing mismatch in mode $mode" }
    Write-Host "PASS: all 648 per-message cycle counts match in mode $mode."
  }
}
