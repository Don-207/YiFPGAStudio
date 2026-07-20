`timescale 1ns / 1ps

module yifpga_la_probe_pack (
    input  wire [31:0] probe_bits,
    output wire [31:0] sample_bus
);

assign sample_bus = probe_bits;

endmodule
