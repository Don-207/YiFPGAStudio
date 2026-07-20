`timescale 1ns/1ps
// Generic USER data-register command engine. All BSCAN signals are synchronous
// to TCK. A request scan is 32 bits, LSB first:
//   byte 0  8'hA6 command magic
//   byte 1  opcode: 1=40-byte header, 2=payload block
//   byte 2  length[7:0]
//   byte 3  length[15:8]
// The following scan returns exactly length bytes, LSB first. UPDATE commits a
// payload only when the exact response length was shifted; all partial/overlong
// scans abort the speculative mailbox read.
module yifpga_jtag_user_dr (
    input  logic       tck,
    input  logic       rst_n,
    input  logic       sel,
    input  logic       capture,
    input  logic       shift,
    input  logic       update,
    input  logic       tdi,
    output logic       tdo,

    output logic       header_req,
    output logic [5:0] header_addr,
    input  logic [7:0] header_data,
    input  logic       header_valid,
    output logic       payload_req,
    input  logic [7:0] payload_data,
    input  logic       payload_valid,
    output logic       payload_ready,
    output logic       payload_commit,
    output logic       payload_abort
);

localparam logic [7:0] COMMAND_MAGIC = 8'ha6;
localparam logic [7:0] OP_HEADER = 8'h01;
localparam logic [7:0] OP_PAYLOAD = 8'h02;
localparam logic [15:0] HEADER_LENGTH = 16'd40;
localparam logic [15:0] MAX_PAYLOAD = 16'd1024;

logic [31:0] request_shift;
logic [15:0] bit_count;
logic [15:0] response_length;
logic [7:0] response_opcode;
logic pending_response, response_active;
logic response_source_valid;

assign header_addr = bit_count[8:3];
assign header_req = sel && response_active && (response_opcode == OP_HEADER);
assign payload_req = sel && response_active && (response_opcode == OP_PAYLOAD);
assign response_source_valid = (response_opcode == OP_HEADER) ? header_valid :
                               (response_opcode == OP_PAYLOAD) ? payload_valid : 1'b0;
assign payload_ready = sel && shift && response_active &&
                       (response_opcode == OP_PAYLOAD) && response_source_valid &&
                       (bit_count[2:0] == 3'd7) &&
                       (bit_count < {response_length, 3'b000});

always_comb begin
    tdo = 1'b0;
    // TDO must already present bit zero when TAP enters Shift-DR. Gating it
    // with SHIFT loses the first bit on BSCANE2 because SHIFT asserts at that
    // transition edge.
    if (sel && response_active && response_source_valid &&
        (bit_count < {response_length, 3'b000})) begin
        if (response_opcode == OP_HEADER)
            tdo = header_data[bit_count[2:0]];
        else if (response_opcode == OP_PAYLOAD)
            tdo = payload_data[bit_count[2:0]];
    end
end

always_ff @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
        request_shift <= '0;
        bit_count <= '0;
        response_length <= '0;
        response_opcode <= '0;
        pending_response <= 1'b0;
        response_active <= 1'b0;
        payload_commit <= 1'b0;
        payload_abort <= 1'b0;
    end else begin
        payload_commit <= 1'b0;
        payload_abort <= 1'b0;

        if (sel && capture) begin
            bit_count <= 16'd0;
            request_shift <= 32'd0;
            response_active <= pending_response;
        end else if (sel && shift) begin
            if (!response_active && bit_count < 16'd32)
                request_shift[bit_count] <= tdi;
            if (bit_count != 16'hffff)
                bit_count <= bit_count + 1'b1;
        end

        if (sel && update) begin
            if (response_active) begin
                if (response_opcode == OP_PAYLOAD) begin
                    if (bit_count == {response_length, 3'b000})
                        payload_commit <= 1'b1;
                    else
                        payload_abort <= 1'b1;
                end
                pending_response <= 1'b0;
                response_active <= 1'b0;
            end else begin
                // Unknown/malformed requests are ignored deterministically.
                pending_response <= 1'b0;
                if (bit_count == 16'd32 && request_shift[7:0] == COMMAND_MAGIC) begin
                    if (request_shift[15:8] == OP_HEADER &&
                        request_shift[31:16] == HEADER_LENGTH) begin
                        response_opcode <= OP_HEADER;
                        response_length <= HEADER_LENGTH;
                        pending_response <= 1'b1;
                    end else if (request_shift[15:8] == OP_PAYLOAD &&
                                 request_shift[31:16] != 0 &&
                                 request_shift[31:16] <= MAX_PAYLOAD) begin
                        response_opcode <= OP_PAYLOAD;
                        response_length <= request_shift[31:16];
                        pending_response <= 1'b1;
                    end
                end
            end
        end
    end
end

endmodule
