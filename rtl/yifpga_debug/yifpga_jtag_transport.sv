`timescale 1ns/1ps
module yifpga_jtag_transport #(
    parameter int ADDR_WIDTH = 12,
    parameter logic [31:0] BUILD_ID = 32'd0
) (
    input  logic       debug_clk,
    input  logic       debug_rst_n,
    input  logic [7:0] debug_data,
    input  logic       debug_valid,
    output logic       debug_ready,
    input  logic       jtag_clk,
    input  logic       jtag_rst_n,
    input  logic [31:0] session_id,
    input  logic       header_req,
    input  logic [5:0] header_addr,
    output logic [7:0] header_data,
    output logic       header_valid,
    input  logic       payload_req,
    output logic [7:0] payload_data,
    output logic       payload_valid,
    input  logic       payload_ready,
    input  logic       payload_commit,
    input  logic       payload_abort,
    output logic [31:0] overflow_count,
    output logic [31:0] dropped_bytes
);

logic [31:0] write_count, read_count;
logic [31:0] rd_write_count, rd_overflow_count, rd_dropped_bytes;
logic [31:0] mailbox_write_count;
logic [ADDR_WIDTH:0] available_bytes;
logic [7:0] ring_data;
logic ring_valid, ring_ready, ring_commit, ring_abort;

// Use one JTAG-domain snapshot for the ABI counter relation. Independently
// synchronized write_count and pointer distance can otherwise represent
// adjacent source cycles and violate write-read==available around wrap/refill.
assign mailbox_write_count = read_count + {{(31-ADDR_WIDTH){1'b0}}, available_bytes};

yifpga_jtag_ring_buffer #(.ADDR_WIDTH(ADDR_WIDTH)) u_ring (
    .wr_clk(debug_clk), .wr_rst_n(debug_rst_n), .wr_data(debug_data),
    .wr_valid(debug_valid), .wr_ready(debug_ready), .write_count(write_count),
    .overflow_count(overflow_count), .dropped_bytes(dropped_bytes),
    .rd_clk(jtag_clk), .rd_rst_n(jtag_rst_n), .rd_data(ring_data),
    .rd_valid(ring_valid), .rd_ready(ring_ready), .rd_commit(ring_commit),
    .rd_abort(ring_abort), .read_count(read_count),
    .available_bytes(available_bytes), .rd_write_count(rd_write_count),
    .rd_overflow_count(rd_overflow_count), .rd_dropped_bytes(rd_dropped_bytes)
);

yifpga_jtag_mailbox #(
    .ADDR_WIDTH(ADDR_WIDTH), .BUILD_ID(BUILD_ID)
) u_mailbox (
    .clk(jtag_clk), .rst_n(jtag_rst_n), .header_req(header_req),
    .header_addr(header_addr), .header_data(header_data), .header_valid(header_valid),
    .payload_req(payload_req), .payload_data(payload_data),
    .payload_valid(payload_valid), .payload_ready(payload_ready),
    .payload_commit(payload_commit), .payload_abort(payload_abort), .session_id(session_id),
    .write_count(mailbox_write_count), .read_count(read_count),
    .available_bytes(available_bytes), .overflow_count(rd_overflow_count),
    .dropped_bytes(rd_dropped_bytes), .ring_data(ring_data),
    .ring_valid(ring_valid), .ring_ready(ring_ready), .ring_commit(ring_commit),
    .ring_abort(ring_abort)
);

endmodule
