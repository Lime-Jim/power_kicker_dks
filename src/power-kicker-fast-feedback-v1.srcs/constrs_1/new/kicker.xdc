# AXAU15 + PZ-FL4322 constraints for top_power_kicker.
# The old ad.xdc is no longer part of project_1.xpr; keep this file as the
# single top-level constraint source.

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 51.0 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes [current_design]

# ---------------------------------------------------------------------------
# Board system clock, buttons, reset, LED
# AXAU15 manual: SYS_CLK_P/N -> T24/U24, 200 MHz, Bank 65.
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN T24 [get_ports sys_clk_p]
set_property PACKAGE_PIN U24 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports {sys_clk_p sys_clk_n}]

set_property PACKAGE_PIN N26 [get_ports key1_rst]
set_property PACKAGE_PIN AA23 [get_ports key2_start]
set_property IOSTANDARD LVCMOS18 [get_ports {key1_rst key2_start}]

set_property PACKAGE_PIN AF13 [get_ports ext_reset]
set_property IOSTANDARD LVCMOS33 [get_ports ext_reset]
set_property PULLDOWN true [get_ports ext_reset]

set_property PACKAGE_PIN W21 [get_ports led_kick]
set_property IOSTANDARD LVCMOS18 [get_ports led_kick]

set_property PACKAGE_PIN A12 [get_ports uart_rx]
set_property PACKAGE_PIN A13 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS18 [get_ports {uart_rx uart_tx}]

# ---------------------------------------------------------------------------
# PZ-FL4322 SPI configuration bus
# AXAU15 FMC table:
#   FMC_LA20_N/P -> AF17/AE17
#   FMC_SDA      -> U26
#   FMC_LA15_P/N -> V21/V22
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN AF17 [get_ports spi_clk]
set_property PACKAGE_PIN AE17 [get_ports spi_io]
set_property IOSTANDARD LVCMOS18 [get_ports {spi_clk spi_io}]

set_property PACKAGE_PIN U26 [get_ports clk_spi_ce]
set_property PACKAGE_PIN V21 [get_ports adc_spi_ce]
set_property PACKAGE_PIN V22 [get_ports dac_spi_ce]
set_property IOSTANDARD LVCMOS18 [get_ports {clk_spi_ce adc_spi_ce dac_spi_ce}]

# ---------------------------------------------------------------------------
# DAC reference clock returned from PZ-FL4322 AD9516.
# Original FL4322 example maps fpga_clk_p to FMC_LA18_CC_P.
# AXAU15 FMC table: FMC_LA18_CC_P/N -> AD20/AE20.
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN AD20 [get_ports fpga_clk_p]
set_property PACKAGE_PIN AE20 [get_ports fpga_clk_n]
set_property IOSTANDARD LVDS [get_ports {fpga_clk_p fpga_clk_n}]
set_property DIFF_TERM_ADV TERM_100 [get_ports fpga_clk_p]
create_clock -period 2.000 -name fpga_clk_p [get_ports fpga_clk_p]

# ---------------------------------------------------------------------------
# AD9643 ADC LVDS inputs.
# These P-side pins match the PZ-FL4322 example. The N-side pins are the
# complementary pins of each differential pair and are inferred by IBUFDS.
# ---------------------------------------------------------------------------
set_property IOSTANDARD LVDS [get_ports {adc_data_p1[*]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {adc_data_p1[*]}]

set_property PACKAGE_PIN T25  [get_ports {adc_data_p1[0]}]
set_property PACKAGE_PIN AB21 [get_ports {adc_data_p1[1]}]
set_property PACKAGE_PIN N23  [get_ports {adc_data_p1[2]}]
set_property PACKAGE_PIN N24  [get_ports {adc_data_p1[3]}]
set_property PACKAGE_PIN V24  [get_ports {adc_data_p1[4]}]
set_property PACKAGE_PIN N21  [get_ports {adc_data_p1[5]}]
set_property PACKAGE_PIN R25  [get_ports {adc_data_p1[6]}]
set_property PACKAGE_PIN P25  [get_ports {adc_data_p1[7]}]
set_property PACKAGE_PIN R20  [get_ports {adc_data_p1[8]}]
set_property PACKAGE_PIN P20  [get_ports {adc_data_p1[9]}]
set_property PACKAGE_PIN W25  [get_ports {adc_data_p1[10]}]
set_property PACKAGE_PIN R22  [get_ports {adc_data_p1[11]}]
set_property PACKAGE_PIN T22  [get_ports {adc_data_p1[12]}]
set_property PACKAGE_PIN N19  [get_ports {adc_data_p1[13]}]

set_property IOSTANDARD LVDS [get_ports adc_clk_p]
set_property DIFF_TERM_ADV TERM_100 [get_ports adc_clk_p]
set_property PACKAGE_PIN V23 [get_ports adc_clk_p]
create_clock -period 4.000 -name adc_clk_p [get_ports adc_clk_p]

# ---------------------------------------------------------------------------
# AD9122 DAC frame/DCI.
# Original FL4322 example:
#   dac_frame_p -> FMC_LA14_P -> U19
#   dac_dci_p   -> FMC_LA17_CC_P -> AC19
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN U19 [get_ports dac_frame_p]
set_property PACKAGE_PIN V19 [get_ports dac_frame_n]
set_property IOSTANDARD LVDS [get_ports {dac_frame_p dac_frame_n}]

set_property PACKAGE_PIN AC19 [get_ports dac_dci_p]
set_property PACKAGE_PIN AD19 [get_ports dac_dci_n]
set_property IOSTANDARD LVDS [get_ports {dac_dci_p dac_dci_n}]

# ---------------------------------------------------------------------------
# AD9122 DAC 16-bit LVDS data bus.
# These package pins are the AXAU15 translation of the PZ-FL4322 example.
# ---------------------------------------------------------------------------
set_property IOSTANDARD LVDS [get_ports {dac_data_p[*]}]
set_property IOSTANDARD LVDS [get_ports {dac_data_n[*]}]

set_property PACKAGE_PIN AB25 [get_ports {dac_data_p[0]}]
set_property PACKAGE_PIN AB26 [get_ports {dac_data_n[0]}]

set_property PACKAGE_PIN AD24 [get_ports {dac_data_p[1]}]
set_property PACKAGE_PIN AD25 [get_ports {dac_data_n[1]}]

set_property PACKAGE_PIN AE25 [get_ports {dac_data_p[2]}]
set_property PACKAGE_PIN AE26 [get_ports {dac_data_n[2]}]

set_property PACKAGE_PIN AC26 [get_ports {dac_data_p[3]}]
set_property PACKAGE_PIN AD26 [get_ports {dac_data_n[3]}]

set_property PACKAGE_PIN AF24 [get_ports {dac_data_p[4]}]
set_property PACKAGE_PIN AF25 [get_ports {dac_data_n[4]}]

set_property PACKAGE_PIN AF18 [get_ports {dac_data_p[5]}]
set_property PACKAGE_PIN AF19 [get_ports {dac_data_n[5]}]

set_property PACKAGE_PIN AC18 [get_ports {dac_data_p[6]}]
set_property PACKAGE_PIN AD18 [get_ports {dac_data_n[6]}]

set_property PACKAGE_PIN Y17 [get_ports {dac_data_p[7]}]
set_property PACKAGE_PIN AA17 [get_ports {dac_data_n[7]}]

set_property PACKAGE_PIN AA19 [get_ports {dac_data_p[8]}]
set_property PACKAGE_PIN AB19 [get_ports {dac_data_n[8]}]

set_property PACKAGE_PIN AA22 [get_ports {dac_data_p[9]}]
set_property PACKAGE_PIN AB22 [get_ports {dac_data_n[9]}]

set_property PACKAGE_PIN Y20 [get_ports {dac_data_p[10]}]
set_property PACKAGE_PIN Y21 [get_ports {dac_data_n[10]}]

set_property PACKAGE_PIN AB17 [get_ports {dac_data_p[11]}]
set_property PACKAGE_PIN AC17 [get_ports {dac_data_n[11]}]

set_property PACKAGE_PIN AA20 [get_ports {dac_data_p[12]}]
set_property PACKAGE_PIN AB20 [get_ports {dac_data_n[12]}]

set_property PACKAGE_PIN U21 [get_ports {dac_data_p[13]}]
set_property PACKAGE_PIN U22 [get_ports {dac_data_n[13]}]

set_property PACKAGE_PIN AE22 [get_ports {dac_data_p[14]}]
set_property PACKAGE_PIN AF22 [get_ports {dac_data_n[14]}]

set_property PACKAGE_PIN T20 [get_ports {dac_data_p[15]}]
set_property PACKAGE_PIN U20 [get_ports {dac_data_n[15]}]

# Dynamic board-profile constraints and clock groups are applied by
# constraints/load_external_timing.tcl (FILE_TYPE=Tcl, implementation only,
# PROCESSING_ORDER=LATE). Do not put source/info/file commands in managed XDC.
