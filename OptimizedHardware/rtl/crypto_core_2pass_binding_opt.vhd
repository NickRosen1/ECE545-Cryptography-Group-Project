-- SPDX-License-Identifier: GPL-3.0-only
-- OptimizedHardware copy of SystemVerilogHardware/rtl/crypto_core_2pass_binding.vhd,
-- binding the LWC wrapper to crypto_core_2pass_opt. Interface from Robert Primas's CryptoCore_2pass.
-- Copyright (c) 2020 IAIK, Graz University of Technology, Austria.
-- See ../../LICENSE.txt for the GNU General Public License.
--
-- Compile this entity in place of the original VHDL core, in a separate
-- Vivado library/work directory. The upstream wrapper binds to this entity;
-- the component below binds to the SystemVerilog implementation.

library ieee;
use ieee.std_logic_1164.all;
use work.design_pkg.all;

entity CryptoCore_2pass is
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;
        key              : in  std_logic_vector(CCSW - 1 downto 0);
        key_valid        : in  std_logic;
        key_ready        : out std_logic;
        bdi              : in  std_logic_vector(CCW - 1 downto 0);
        bdi_valid        : in  std_logic;
        bdi_ready        : out std_logic;
        bdi_pad_loc      : in  std_logic_vector(CCWdiv8 - 1 downto 0);
        bdi_valid_bytes  : in  std_logic_vector(CCWdiv8 - 1 downto 0);
        bdi_size         : in  std_logic_vector(3 - 1 downto 0);
        bdi_eot          : in  std_logic;
        bdi_eoi          : in  std_logic;
        bdi_type         : in  std_logic_vector(4 - 1 downto 0);
        decrypt_in       : in  std_logic;
        key_update       : in  std_logic;
        hash_in          : in  std_logic;
        bdo              : out std_logic_vector(CCW - 1 downto 0);
        bdo_valid        : out std_logic;
        bdo_ready        : in  std_logic;
        bdo_type         : out std_logic_vector(4 - 1 downto 0);
        bdo_valid_bytes  : out std_logic_vector(CCWdiv8 - 1 downto 0);
        end_of_block     : out std_logic;
        msg_auth_valid   : out std_logic;
        msg_auth_ready   : in  std_logic;
        msg_auth         : out std_logic;
        fdi_data         : in  std_logic_vector(CCW - 1 downto 0);
        fdi_valid        : in  std_logic;
        fdi_ready        : out std_logic;
        fdo_data         : out std_logic_vector(CCW - 1 downto 0);
        fdo_valid        : out std_logic;
        fdo_ready        : in  std_logic
    );
end entity;

architecture systemverilog_binding of CryptoCore_2pass is
    component crypto_core_2pass_opt is
        port (
            clk              : in  std_logic;
            rst              : in  std_logic;
            key              : in  std_logic_vector(31 downto 0);
            key_valid        : in  std_logic;
            key_ready        : out std_logic;
            bdi              : in  std_logic_vector(31 downto 0);
            bdi_valid        : in  std_logic;
            bdi_ready        : out std_logic;
            bdi_pad_loc      : in  std_logic_vector(3 downto 0);
            bdi_valid_bytes  : in  std_logic_vector(3 downto 0);
            bdi_size         : in  std_logic_vector(2 downto 0);
            bdi_eot          : in  std_logic;
            bdi_eoi          : in  std_logic;
            bdi_type         : in  std_logic_vector(3 downto 0);
            decrypt_in       : in  std_logic;
            key_update       : in  std_logic;
            hash_in          : in  std_logic;
            bdo              : out std_logic_vector(31 downto 0);
            bdo_valid        : out std_logic;
            bdo_ready        : in  std_logic;
            bdo_type         : out std_logic_vector(3 downto 0);
            bdo_valid_bytes  : out std_logic_vector(3 downto 0);
            end_of_block     : out std_logic;
            msg_auth_valid   : out std_logic;
            msg_auth_ready   : in  std_logic;
            msg_auth         : out std_logic;
            fdi_data         : in  std_logic_vector(31 downto 0);
            fdi_valid        : in  std_logic;
            fdi_ready        : out std_logic;
            fdo_data         : out std_logic_vector(31 downto 0);
            fdo_valid        : out std_logic;
            fdo_ready        : in  std_logic
        );
    end component;
begin
    core : crypto_core_2pass_opt
        port map (
            clk              => clk,
            rst              => rst,
            key              => key,
            key_valid        => key_valid,
            key_ready        => key_ready,
            bdi              => bdi,
            bdi_valid        => bdi_valid,
            bdi_ready        => bdi_ready,
            bdi_pad_loc      => bdi_pad_loc,
            bdi_valid_bytes  => bdi_valid_bytes,
            bdi_size         => bdi_size,
            bdi_eot          => bdi_eot,
            bdi_eoi          => bdi_eoi,
            bdi_type         => bdi_type,
            decrypt_in       => decrypt_in,
            key_update       => key_update,
            hash_in          => hash_in,
            bdo              => bdo,
            bdo_valid        => bdo_valid,
            bdo_ready        => bdo_ready,
            bdo_type         => bdo_type,
            bdo_valid_bytes  => bdo_valid_bytes,
            end_of_block     => end_of_block,
            msg_auth_valid   => msg_auth_valid,
            msg_auth_ready   => msg_auth_ready,
            msg_auth         => msg_auth,
            fdi_data         => fdi_data,
            fdi_valid        => fdi_valid,
            fdi_ready        => fdi_ready,
            fdo_data         => fdo_data,
            fdo_valid        => fdo_valid,
            fdo_ready        => fdo_ready
        );
end architecture;

