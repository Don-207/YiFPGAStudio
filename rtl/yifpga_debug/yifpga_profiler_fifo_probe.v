`timescale 1ns / 1ps

`include "yifpga_profiler_pkg.vh"

module yifpga_profiler_fifo_probe #(
    parameter ENABLE = 1,
    parameter LEVEL_WIDTH = 16,
    parameter METRIC_ID = `YFD_PROFILER_METRIC_FIFO_DEMO_LEVEL
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,
    input  wire                         enable,

    input  wire [LEVEL_WIDTH-1:0]       fifo_level,
    input  wire                         fifo_wr_en,
    input  wire                         fifo_rd_en,
    input  wire                         fifo_full,
    input  wire                         fifo_empty,
    input  wire                         fifo_overflow,
    input  wire                         fifo_underflow,

    output reg                          metric_valid,
    output reg  [15:0]                  metric_id,
    output reg  [31:0]                  metric_value0,
    output reg  [31:0]                  metric_value1,
    output reg  [31:0]                  metric_value2,
    output reg  [31:0]                  metric_value3,
    output reg                          metric_overflow
);

reg [31:0] max_level;
reg [31:0] min_level;
reg [15:0] overflow_count;
reg [15:0] underflow_count;
reg        seen_sample;
wire [31:0] level_ext = {{(32-LEVEL_WIDTH){1'b0}}, fifo_level};
wire [31:0] next_max_level = (!seen_sample || level_ext > max_level) ? level_ext : max_level;
wire [31:0] next_min_level = (!seen_sample || level_ext < min_level) ? level_ext : min_level;
wire [15:0] next_overflow_count = (fifo_overflow && overflow_count != 16'hFFFF) ? overflow_count + 16'd1 : overflow_count;
wire [15:0] next_underflow_count = (fifo_underflow && underflow_count != 16'hFFFF) ? underflow_count + 16'd1 : underflow_count;
wire sample_event = (level_ext != metric_value0) || fifo_wr_en || fifo_rd_en ||
                    fifo_overflow || fifo_underflow;

always @(posedge clk) begin
    if (rst || clear) begin
        max_level <= 32'd0;
        min_level <= 32'd0;
        overflow_count <= 16'd0;
        underflow_count <= 16'd0;
        seen_sample <= 1'b0;
        metric_valid <= 1'b0;
        metric_id <= METRIC_ID;
        metric_value0 <= 32'd0;
        metric_value1 <= 32'd0;
        metric_value2 <= 32'd0;
        metric_value3 <= 32'd0;
        metric_overflow <= 1'b0;
    end else begin
        metric_valid <= 1'b0;
        metric_overflow <= 1'b0;

        if (ENABLE != 0 && enable) begin
            max_level <= next_max_level;
            min_level <= next_min_level;
            overflow_count <= next_overflow_count;
            underflow_count <= next_underflow_count;
            seen_sample <= 1'b1;

            // Gauge values are cumulative/latest snapshots. Re-emitting an
            // unchanged gauge every clock makes the Profiler Core aggregate
            // the same value repeatedly and eventually saturate. Publish only
            // on an observable FIFO change or error event.
            metric_valid <= sample_event;
            metric_id <= METRIC_ID;
            metric_value0 <= level_ext;
            metric_value1 <= next_max_level;
            metric_value2 <= next_min_level;
            metric_value3 <= {next_overflow_count, next_underflow_count};
            metric_overflow <= fifo_overflow || fifo_underflow;
        end
    end
end

endmodule
