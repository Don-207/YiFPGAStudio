`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"

module yifpga_debug_packetizer (
    input  wire        clk,
    input  wire        rst,

    input  wire        msg_valid,
    input  wire [7:0]  msg_type,
    input  wire [7:0]  payload_len,
    input  wire [255:0] payload_flat,
    output wire        msg_ready,

    output reg         out_valid,
    output reg  [7:0]  out_data,
    input  wire        out_ready
);

localparam STATE_IDLE = 1'b0;
localparam STATE_SEND = 1'b1;

reg         state;
reg [7:0]   latched_type;
reg [7:0]   latched_len;
reg [255:0] latched_payload;
reg [7:0]   byte_index;
reg [7:0]   checksum_value;

integer i;

assign msg_ready = (state == STATE_IDLE) && !out_valid && (payload_len <= `YFD_MAX_PAYLOAD_BYTES);

always @(*) begin
    checksum_value = `YFD_VERSION ^ latched_type ^ latched_len;
    for (i = 0; i < 32; i = i + 1) begin
        if (i < latched_len) begin
            checksum_value = checksum_value ^ latched_payload[(i * 8) +: 8];
        end
    end
end

function [7:0] frame_byte;
    input [7:0] index;
    begin
        if (index == 8'd0) begin
            frame_byte = `YFD_SOF;
        end else if (index == 8'd1) begin
            frame_byte = `YFD_VERSION;
        end else if (index == 8'd2) begin
            frame_byte = latched_type;
        end else if (index == 8'd3) begin
            frame_byte = latched_len;
        end else if (index < (8'd4 + latched_len)) begin
            frame_byte = latched_payload[((index - 8'd4) * 8) +: 8];
        end else begin
            frame_byte = checksum_value;
        end
    end
endfunction

always @(posedge clk) begin
    if (rst) begin
        state <= STATE_IDLE;
        latched_type <= 8'd0;
        latched_len <= 8'd0;
        latched_payload <= 256'd0;
        byte_index <= 8'd0;
        out_valid <= 1'b0;
        out_data <= 8'd0;
    end else begin
        if (out_valid && out_ready) begin
            out_valid <= 1'b0;
        end

        if (state == STATE_IDLE) begin
            if (msg_valid && msg_ready) begin
                state <= STATE_SEND;
                latched_type <= msg_type;
                latched_len <= payload_len;
                latched_payload <= payload_flat;
                byte_index <= 8'd0;
            end
        end else if (!out_valid || out_ready) begin
            out_valid <= 1'b1;
            out_data <= frame_byte(byte_index);

            if (byte_index == (8'd4 + latched_len)) begin
                state <= STATE_IDLE;
                byte_index <= 8'd0;
            end else begin
                byte_index <= byte_index + 8'd1;
            end
        end
    end
end

endmodule
