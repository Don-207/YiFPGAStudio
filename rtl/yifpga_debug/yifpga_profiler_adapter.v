`timescale 1ns / 1ps

`include "yifpga_profiler_pkg.vh"

module yifpga_profiler_adapter (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] timestamp,

    input  wire        snapshot_valid,
    output wire        snapshot_ready,
    input  wire [15:0] snapshot_metric_id,
    input  wire [15:0] snapshot_flags,
    input  wire [31:0] snapshot_sample_cycles,
    input  wire [31:0] snapshot_value0,
    input  wire [31:0] snapshot_value1,
    input  wire [31:0] snapshot_value2,
    input  wire [31:0] snapshot_value3,
    input  wire [15:0] snapshot_overflow_count,

    input  wire        alert_valid,
    output wire        alert_ready,
    input  wire [15:0] alert_metric_id,
    input  wire [7:0]  alert_level,
    input  wire [7:0]  alert_code,
    input  wire [31:0] alert_arg0,
    input  wire [31:0] alert_arg1,

    output reg         msg_valid,
    input  wire        msg_ready,
    output reg  [7:0]  msg_type,
    output reg  [7:0]  payload_len,
    output reg  [255:0] payload_flat
);

wire can_accept = !msg_valid || msg_ready;

assign alert_ready = can_accept;
assign snapshot_ready = can_accept && !alert_valid;

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

        if (alert_valid && alert_ready) begin
            msg_valid <= 1'b1;
            msg_type <= `YFD_TYPE_PROFILER_ALERT;
            payload_len <= `YFD_PROFILER_LEN_ALERT;
            payload_flat <= 256'd0;
            payload_flat[31:0] <= timestamp;
            payload_flat[47:32] <= alert_metric_id;
            payload_flat[55:48] <= alert_level;
            payload_flat[63:56] <= alert_code;
            payload_flat[95:64] <= alert_arg0;
            payload_flat[127:96] <= alert_arg1;
        end else if (snapshot_valid && snapshot_ready) begin
            msg_valid <= 1'b1;
            msg_type <= `YFD_TYPE_PROFILER_SNAPSHOT;
            payload_len <= `YFD_PROFILER_LEN_SNAPSHOT;
            payload_flat <= 256'd0;
            payload_flat[31:0] <= timestamp;
            payload_flat[47:32] <= snapshot_metric_id;
            payload_flat[63:48] <= snapshot_flags;
            payload_flat[95:64] <= snapshot_sample_cycles;
            payload_flat[127:96] <= snapshot_value0;
            payload_flat[159:128] <= snapshot_value1;
            payload_flat[191:160] <= snapshot_value2;
            payload_flat[223:192] <= snapshot_value3;
            payload_flat[239:224] <= snapshot_overflow_count;
            payload_flat[255:240] <= 16'd0;
        end
    end
end

endmodule
