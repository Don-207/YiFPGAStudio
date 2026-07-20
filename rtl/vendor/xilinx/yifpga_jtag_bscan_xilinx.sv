`timescale 1ns/1ps
module yifpga_jtag_bscan_xilinx #(
    parameter int USER_CHAIN = 2
) (
    output logic capture,
    output logic drck,
    output logic reset,
    output logic runtest,
    output logic sel,
    output logic shift,
    output logic tck,
    output logic tdi,
    output logic update,
    input  logic tdo
);

// UltraScale adapter only. Generic transport RTL must not instantiate BSCANE2.
BSCANE2 #(.JTAG_CHAIN(USER_CHAIN)) u_bscan (
    .CAPTURE(capture), .DRCK(drck), .RESET(reset), .RUNTEST(runtest),
    .SEL(sel), .SHIFT(shift), .TCK(tck), .TDI(tdi), .TMS(),
    .UPDATE(update), .TDO(tdo)
);

endmodule
