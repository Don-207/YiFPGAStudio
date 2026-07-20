`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_trace_pkg.vh"

module yifpga_trace_frame_probe #(
    parameter ENABLE = 1
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        frame_start_valid,
    input  wire        frame_end_valid,
    input  wire        frame_drop_valid,
    input  wire [15:0] frame_id,
    input  wire [31:0] arg0,

    output reg         span_begin_valid,
    output reg  [15:0] span_begin_trace_id,
    output reg  [15:0] span_begin_instance_id,
    output reg  [31:0] span_begin_arg0,

    output reg         span_end_valid,
    output reg  [15:0] span_end_trace_id,
    output reg  [15:0] span_end_instance_id,
    output reg  [7:0]  span_end_status,
    output reg  [31:0] span_end_arg0,

    output reg         mark_valid,
    output reg  [15:0] mark_trace_id,
    output reg  [7:0]  mark_level,
    output reg  [31:0] mark_arg0
);

always @(posedge clk) begin
    if (rst) begin
        span_begin_valid <= 1'b0;
        span_end_valid <= 1'b0;
        mark_valid <= 1'b0;
        span_begin_trace_id <= `YFD_TRACE_ID_FRAME;
        span_begin_instance_id <= 16'd0;
        span_begin_arg0 <= 32'd0;
        span_end_trace_id <= `YFD_TRACE_ID_FRAME;
        span_end_instance_id <= 16'd0;
        span_end_status <= `YFD_TRACE_STATUS_OK;
        span_end_arg0 <= 32'd0;
        mark_trace_id <= `YFD_TRACE_ID_FRAME;
        mark_level <= `YFD_LEVEL_WARNING;
        mark_arg0 <= 32'd0;
    end else begin
        span_begin_valid <= 1'b0;
        span_end_valid <= 1'b0;
        mark_valid <= 1'b0;

        if (ENABLE != 0) begin
            if (frame_start_valid) begin
                span_begin_valid <= 1'b1;
                span_begin_trace_id <= `YFD_TRACE_ID_FRAME;
                span_begin_instance_id <= frame_id;
                span_begin_arg0 <= arg0;
            end else if (frame_drop_valid) begin
                mark_valid <= 1'b1;
                mark_trace_id <= `YFD_TRACE_ID_FRAME;
                mark_level <= `YFD_LEVEL_WARNING;
                mark_arg0 <= arg0;
            end else if (frame_end_valid) begin
                span_end_valid <= 1'b1;
                span_end_trace_id <= `YFD_TRACE_ID_FRAME;
                span_end_instance_id <= frame_id;
                span_end_status <= `YFD_TRACE_STATUS_OK;
                span_end_arg0 <= arg0;
            end
        end
    end
end

endmodule
