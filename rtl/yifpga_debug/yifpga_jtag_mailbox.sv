`timescale 1ns/1ps
module yifpga_jtag_mailbox #(
    parameter int ADDR_WIDTH = 12,
    parameter logic [31:0] BUILD_ID = 32'd0
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        header_req,
    input  logic [5:0]  header_addr,
    output logic [7:0]  header_data,
    output logic        header_valid,
    input  logic        payload_req,
    output logic [7:0]  payload_data,
    output logic        payload_valid,
    input  logic        payload_ready,
    input  logic        payload_commit,
    input  logic        payload_abort,
    input  logic [31:0] session_id,
    input  logic [31:0] write_count,
    input  logic [31:0] read_count,
    input  logic [ADDR_WIDTH:0] available_bytes,
    input  logic [31:0] overflow_count,
    input  logic [31:0] dropped_bytes,
    input  logic [7:0]  ring_data,
    input  logic        ring_valid,
    output logic        ring_ready,
    output logic        ring_commit,
    output logic        ring_abort
);

localparam logic [31:0] MAGIC = 32'h544a_464f; // bytes: 4f 46 4a 54, "OFJT"
localparam logic [15:0] VERSION = 16'h0001;
localparam logic [15:0] CAPS = 16'h000f;
localparam logic [31:0] BUFFER_SIZE = (32'd1 << ADDR_WIDTH);
logic [319:0] header_live;
logic [319:0] header_snapshot;

always_comb begin
    header_live = {BUILD_ID, dropped_bytes, overflow_count,
                   {{(31-ADDR_WIDTH){1'b0}}, available_bytes},
                   read_count, write_count, BUFFER_SIZE, session_id,
                   CAPS, VERSION, MAGIC};
end

// While no Header response is active, continually prepare a coherent snapshot.
// The CAPTURE edge is the final update; header_req then stays asserted for the
// whole response scan, keeping all 40 bytes stable despite CDC counter changes.
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        header_snapshot <= '0;
    else if (!header_req)
        header_snapshot <= header_live;
end

always_comb begin
    header_data = header_snapshot[header_addr*8 +: 8];
    header_valid = header_req && (header_addr < 6'd40);
    payload_data = ring_data;
    payload_valid = payload_req && ring_valid;
    ring_ready = payload_req && payload_ready;
    ring_commit = payload_commit;
    ring_abort = payload_abort;
end

endmodule
