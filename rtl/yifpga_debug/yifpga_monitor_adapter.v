`timescale 1ns / 1ps

`include "yifpga_monitor_pkg.vh"

module yifpga_monitor_adapter (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] timestamp,

    input  wire        resp_valid,
    output wire        resp_ready,
    input  wire [15:0] resp_seq,
    input  wire [15:0] resp_addr,
    input  wire        resp_write,
    input  wire [7:0]  resp_width,
    input  wire [7:0]  resp_status,
    input  wire [31:0] resp_rdata,
    input  wire [31:0] resp_old_value,
    input  wire [31:0] resp_new_value,

    output reg         msg_valid,
    input  wire        msg_ready,
    output reg  [7:0]  msg_type,
    output reg  [7:0]  payload_len,
    output reg  [255:0] payload_flat
);

assign resp_ready = !msg_valid || msg_ready;

always @(posedge clk) begin
    if (rst) begin
        msg_valid <= 1'b0;
        msg_type <= 8'd0;
        payload_len <= 8'd0;
        payload_flat <= 256'd0;
    end else begin
        if (msg_valid && msg_ready) begin
            msg_valid <= 1'b0;
        end

        if (resp_valid && resp_ready) begin
            msg_valid <= 1'b1;
            msg_type <= resp_write ? `YFD_TYPE_MONITOR_WRITE_RESP : `YFD_TYPE_MONITOR_READ_RESP;
            payload_flat <= 256'd0;
            payload_flat[31:0] <= timestamp;
            payload_flat[47:32] <= resp_seq;
            payload_flat[63:48] <= resp_addr;
            payload_flat[71:64] <= resp_status;

            if (resp_write) begin
                payload_len <= 8'd17;
                payload_flat[103:72] <= resp_old_value;
                payload_flat[135:104] <= resp_new_value;
            end else begin
                payload_len <= 8'd14;
                payload_flat[79:72] <= resp_width;
                payload_flat[111:80] <= resp_rdata;
            end
        end
    end
end

endmodule
