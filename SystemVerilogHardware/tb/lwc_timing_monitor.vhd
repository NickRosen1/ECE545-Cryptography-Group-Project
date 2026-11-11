-- SPDX-License-Identifier: GPL-3.0-only
-- Passive instrumentation added 2026-11-10. See ../../LICENSE.txt.
-- Reuses the original structural architecture, wrapper, FIFO, and testbench.
-- No stimulus/ready signal is altered. Metadata preserves full original IDs.
library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;

entity stage3_timing_monitor is
    port (clk, rst, pdi_valid, pdi_ready, do_valid, do_ready, do_last : in std_logic);
end entity;

architecture passive of stage3_timing_monitor is
begin
    monitor : process
        type integers is array(0 to 647) of integer;
        variable ids, lengths, starts : integers;
        variable row : line;
        variable cycle, input_case, output_case, remaining : natural := 0;
        file metadata : text open read_mode is "message_lengths.txt";
        file results : text open write_mode is "stream_cycles.txt";
    begin
        for i in ids'range loop
            assert not endfile(metadata) report "Missing timing metadata" severity failure;
            readline(metadata, row);
            read(row, ids(i));
            read(row, lengths(i));
            starts(i) := -1;
        end loop;
        assert endfile(metadata) report "Extra timing metadata" severity failure;
        file_close(metadata);
        loop
            wait until rising_edge(clk);
            if rst = '1' then
                cycle := 0;
                input_case := 0;
                output_case := 0;
                remaining := 0;
            else
                cycle := cycle + 1;
                if pdi_valid = '1' and pdi_ready = '1' then
                    if remaining = 0 then
                        assert input_case < 648 report "Extra input transaction" severity failure;
                        starts(input_case) := cycle;
                        remaining := lengths(input_case);
                        input_case := input_case + 1;
                    end if;
                    remaining := remaining - 1;
                end if;
                if do_valid = '1' and do_ready = '1' and do_last = '1' then
                    assert output_case < 648 report "Extra status" severity failure;
                    assert starts(output_case) >= 0 report "Status before transaction" severity failure;
                    write(row, ids(output_case)); write(row, string'(","));
                    write(row, cycle - starts(output_case)); writeline(results, row);
                    output_case := output_case + 1;
                    if output_case = 648 then
                        assert input_case = 648 and remaining = 0
                            report "Incomplete input stream" severity failure;
                        file_close(results);
                        report "STAGE3_TIMING_COMPLETE 648" severity note;
                        wait;
                    end if;
                end if;
            end if;
        end loop;
    end process;
end architecture;
