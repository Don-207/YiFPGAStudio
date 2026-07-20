`timescale 1ns/1ps
// Xilinx integration boundary: BSCANE2 -> generic USER-DR engine -> transport.
// Board designs instantiate this module only when JTAG transport is enabled.
module yifpga_jtag_transport_xilinx #(
    parameter int ADDR_WIDTH = 12,
    parameter int USER_CHAIN = 2,
    parameter logic [31:0] BUILD_ID = 32'd0
) (
    input  logic        debug_clk,
    input  logic        debug_rst_n,
    input  logic [7:0]  debug_data,
    input  logic        debug_valid,
    output logic        debug_ready,
    input  logic [31:0] session_id,
    output logic [31:0] overflow_count,
    output logic [31:0] dropped_bytes
);

logic capture, drck, bscan_reset, runtest, sel, shift, tck, tdi, update, tdo;
logic header_req, header_valid, payload_req, payload_valid, payload_ready;
logic payload_commit, payload_abort;
logic [5:0] header_addr;
logic [7:0] header_data, payload_data;
logic command_rst_n;

// TAP reset cancels the command engine only. Resetting the ring read domain
// without simultaneously resetting its debug-clock write domain corrupts the
// cross-domain counter distance after a host reconnect.
assign command_rst_n = debug_rst_n && !bscan_reset;

yifpga_jtag_bscan_xilinx #(.USER_CHAIN(USER_CHAIN)) u_bscan (
    .capture(capture), .drck(drck), .reset(bscan_reset), .runtest(runtest),
    .sel(sel), .shift(shift), .tck(tck), .tdi(tdi), .update(update), .tdo(tdo)
);

yifpga_jtag_user_dr u_user_dr (
    .tck(tck), .rst_n(command_rst_n), .sel(sel), .capture(capture), .shift(shift),
    .update(update), .tdi(tdi), .tdo(tdo), .header_req(header_req),
    .header_addr(header_addr), .header_data(header_data), .header_valid(header_valid),
    .payload_req(payload_req), .payload_data(payload_data), .payload_valid(payload_valid),
    .payload_ready(payload_ready), .payload_commit(payload_commit),
    .payload_abort(payload_abort)
);

yifpga_jtag_transport #(.ADDR_WIDTH(ADDR_WIDTH), .BUILD_ID(BUILD_ID)) u_transport (
    .debug_clk(debug_clk), .debug_rst_n(debug_rst_n), .debug_data(debug_data),
    .debug_valid(debug_valid), .debug_ready(debug_ready), .jtag_clk(tck),
    .jtag_rst_n(debug_rst_n), .session_id(session_id), .header_req(header_req),
    .header_addr(header_addr), .header_data(header_data), .header_valid(header_valid),
    .payload_req(payload_req), .payload_data(payload_data), .payload_valid(payload_valid),
    .payload_ready(payload_ready), .payload_commit(payload_commit),
    .payload_abort(payload_abort), .overflow_count(overflow_count),
    .dropped_bytes(dropped_bytes)
);

endmodule
