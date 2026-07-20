`timescale 1ns / 1ps

`include "yifpga_profiler_pkg.vh"

module yifpga_profiler_frame_probe #(
    parameter ENABLE = 1,
    parameter METRIC_ID = `YFD_PROFILER_METRIC_FRAME_RATE
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,
    input  wire        enable,

    input  wire        frame_start,
    input  wire        frame_done,
    input  wire        frame_drop,
    input  wire        frame_error,

    output reg         metric_valid,
    output reg  [15:0] metric_id,
    output reg  [31:0] metric_value0,
    output reg  [31:0] metric_value1,
    output reg  [31:0] metric_value2,
    output reg  [31:0] metric_value3,
    output reg         metric_overflow
);

reg [31:0] interval_counter;
reg [31:0] done_count;
reg [15:0] drop_count;
reg [15:0] error_count;
reg [31:0] min_interval;
reg [31:0] max_interval;
reg        seen_done;

wire [31:0] next_interval_counter = (interval_counter == 32'hFFFFFFFF) ? interval_counter : interval_counter + 32'd1;
wire [31:0] observed_interval = interval_counter;
wire [31:0] next_min_interval = (!seen_done || observed_interval < min_interval) ? observed_interval : min_interval;
wire [31:0] next_max_interval = (!seen_done || observed_interval > max_interval) ? observed_interval : max_interval;
wire [31:0] next_done_count = (frame_done && done_count != 32'hFFFFFFFF) ? done_count + 32'd1 : done_count;
wire [15:0] next_drop_count = (frame_drop && drop_count != 16'hFFFF) ? drop_count + 16'd1 : drop_count;
wire [15:0] next_error_count = (frame_error && error_count != 16'hFFFF) ? error_count + 16'd1 : error_count;

always @(posedge clk) begin
    if (rst || clear) begin
        interval_counter <= 32'd0;
        done_count <= 32'd0;
        drop_count <= 16'd0;
        error_count <= 16'd0;
        min_interval <= 32'd0;
        max_interval <= 32'd0;
        seen_done <= 1'b0;
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
            interval_counter <= next_interval_counter;

            if (frame_done) begin
                interval_counter <= 32'd0;
                done_count <= next_done_count;
                min_interval <= next_min_interval;
                max_interval <= next_max_interval;
                seen_done <= 1'b1;
            end
            drop_count <= next_drop_count;
            error_count <= next_error_count;

            if (frame_done || frame_drop || frame_error) begin
                metric_valid <= 1'b1;
                metric_id <= METRIC_ID;
                metric_value0 <= next_done_count;
                metric_value1 <= {next_drop_count, next_error_count};
                metric_value2 <= frame_done ? next_min_interval : min_interval;
                metric_value3 <= frame_done ? next_max_interval : max_interval;
                metric_overflow <= frame_drop || frame_error;
            end
        end
    end
end

endmodule
