-- SPDX-License-Identifier: GPL-3.0-only
-- Test adapter added 2026-11-10. Interface derived from Robert Primas's
-- CryptoCore_2pass, copyright (c) 2020 IAIK, Graz University of Technology.
-- See ../../LICENSE.txt. Uses the unchanged upstream payload FIFO.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity stage3_core_dut is
    port (
        clk, rst : in std_logic;
        key : in std_logic_vector(31 downto 0);
        key_valid, key_update : in std_logic;
        key_ready : out std_logic;
        bdi : in std_logic_vector(31 downto 0);
        bdi_valid : in std_logic;
        bdi_ready : out std_logic;
        bdi_valid_bytes : in std_logic_vector(3 downto 0);
        bdi_eot, bdi_eoi : in std_logic;
        bdi_type : in std_logic_vector(3 downto 0);
        bdo : out std_logic_vector(31 downto 0);
        bdo_valid : out std_logic;
        bdo_ready : in std_logic;
        bdo_valid_bytes : out std_logic_vector(3 downto 0);
        msg_auth, msg_auth_valid : out std_logic;
        msg_auth_ready : in std_logic;
        queued_words, read_words : out std_logic_vector(31 downto 0)
    );
end entity;
architecture test of stage3_core_dut is
    signal fdi, fdo : std_logic_vector(31 downto 0);
    signal fdi_valid, fdi_ready, fdo_valid, fdo_ready : std_logic;
begin
    core : entity work.CryptoCore_2pass
        port map (clk=>clk,rst=>rst,key=>key,key_valid=>key_valid,key_ready=>key_ready,
            key_update=>key_update,bdi=>bdi,bdi_valid=>bdi_valid,bdi_ready=>bdi_ready,
            bdi_valid_bytes=>bdi_valid_bytes,bdi_pad_loc=>"0000",bdi_size=>"100",
            bdi_eot=>bdi_eot,bdi_eoi=>bdi_eoi,bdi_type=>bdi_type,decrypt_in=>'1',hash_in=>'0',
            bdo=>bdo,bdo_valid=>bdo_valid,bdo_ready=>bdo_ready,bdo_type=>open,
            bdo_valid_bytes=>bdo_valid_bytes,end_of_block=>open,msg_auth=>msg_auth,
            msg_auth_valid=>msg_auth_valid,msg_auth_ready=>msg_auth_ready,
            fdi_data=>fdi,fdi_valid=>fdi_valid,fdi_ready=>fdi_ready,
            fdo_data=>fdo,fdo_valid=>fdo_valid,fdo_ready=>fdo_ready);
    payload : entity work.FIFO generic map(G_W=>32,G_DEPTH=>1024)
        port map(clk=>clk,rst=>rst,din=>fdo,din_valid=>fdo_valid,din_ready=>fdo_ready,
            dout=>fdi,dout_valid=>fdi_valid,dout_ready=>fdi_ready);
    process(clk)
        variable count, reads : integer := 0;
    begin
        if rising_edge(clk) then
            if rst='1' then count:=0; reads:=0;
            else
                if fdo_valid='1' and fdo_ready='1' then count:=count+1; end if;
                if fdi_valid='1' and fdi_ready='1' then count:=count-1; reads:=reads+1; end if;
            end if;
            queued_words<=std_logic_vector(to_unsigned(count,32));
            read_words<=std_logic_vector(to_unsigned(reads,32));
        end if;
    end process;
end architecture;
