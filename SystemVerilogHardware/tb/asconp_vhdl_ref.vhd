-- SPDX-License-Identifier: GPL-3.0-only
-- Mixed-language test adapter added 2026-11-10. See ../../LICENSE.txt.
-- The oracle is the unchanged upstream Asconp, not a duplicated round model.
library ieee;
use ieee.std_logic_1164.all;

entity asconp_vhdl_ref is
    port (
        state_in  : in  std_logic_vector(319 downto 0);
        rcon      : in  std_logic_vector(3 downto 0);
        state_out : out std_logic_vector(319 downto 0)
    );
end entity;

architecture reference of asconp_vhdl_ref is
begin
    dut : entity work.Asconp(behavior)
        port map (state_in => state_in, rcon => rcon, state_out => state_out);
end architecture;
