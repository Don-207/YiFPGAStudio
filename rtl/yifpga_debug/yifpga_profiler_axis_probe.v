`timescale 1ns / 1ps

`include "yifpga_profiler_pkg.vh"

module yifpga_profiler_axis_probe #(
    parameter ENABLE = 1,
    parameter DATA_WIDTH = 32,
    parameter METRIC_ID = `YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT,
    parameter COUNT_BYTES = 1,
    parameter STALL_MODE = 0
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,
    input  wire                         enable,

    input  wire                         axis_valid,
    input  wire                         axis_ready,
    input  wire [(DATA_WIDTH / 8)-1:0]  axis_keep,
    input  wire                         axis_last,

    output reg                          metric_valid,
    output reg  [15:0]                  metric_id,
    output reg  [31:0]                  metric_value0,
    output reg  [31:0]                  metric_value1,
    output reg  [31:0]                  metric_value2,
    output reg  [31:0]                  metric_value3,
    output reg                          metric_overflow
);

localparam KEEP_WIDTH = DATA_WIDTH / 8;

integer i;
reg [31:0] keep_count;
reg        handshake;
reg        active_cycle;
reg        stall_cycle;

always @* begin
    keep_count = 32'd0;
    for (i = 0; i < KEEP_WIDTH; i = i + 1) begin
        if (axis_keep[i]) begin
            keep_count = keep_count + 32'd1;
        end
    end

    handshake = axis_valid && axis_ready;
    active_cycle = axis_valid || axis_ready;
    if (STALL_MODE == 1) begin
        stall_cycle = axis_ready && !axis_valid;
    end else if (STALL_MODE == 2) begin
        stall_cycle = (axis_valid && !axis_ready) || (axis_ready && !axis_valid);
    end else begin
        stall_cycle = axis_valid && !axis_ready;
    end
end

always @(posedge clk) begin
    if (rst || clear) begin
        metric_valid <= 1'b0;
        metric_id <= METRIC_ID;
        metric_value0 <= 32'd0;
        metric_value1 <= 32'd0;
        metric_value2 <= 32'd0;
        metric_value3 <= 32'd0;
        metric_overflow <= 1'b0;
    end else begin
        metric_valid <= 1'b0;
        metric_id <= METRIC_ID;
        metric_value0 <= 32'd0;
        metric_value1 <= 32'd0;
        metric_value2 <= 32'd0;
        metric_value3 <= 32'd0;
        metric_overflow <= 1'b0;

        if (ENABLE != 0 && enable) begin
            metric_valid <= handshake || active_cycle || stall_cycle;
            metric_value0 <= handshake ? ((COUNT_BYTES != 0) ? keep_count : 32'd1) : 32'd0;
            metric_value1 <= handshake ? 32'd1 : 32'd0;
            metric_value2 <= active_cycle ? 32'd1 : 32'd0;
            metric_value3 <= stall_cycle ? 32'd1 : 32'd0;
        end
    end
end

endmodule
