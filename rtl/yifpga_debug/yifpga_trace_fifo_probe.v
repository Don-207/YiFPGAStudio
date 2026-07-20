`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_trace_pkg.vh"

module yifpga_trace_fifo_probe #(
    parameter ENABLE = 1,
    parameter VALUE_ID = 16'h0001
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        sample_valid,
    input  wire        almost_full,
    input  wire        overflow_valid,
    input  wire [31:0] level,

    output reg         mark_valid,
    output reg  [15:0] mark_trace_id,
    output reg  [7:0]  mark_level,
    output reg  [31:0] mark_arg0,

    output reg         value_valid,
    output reg  [15:0] value_trace_id,
    output reg  [15:0] value_id,
    output reg  [31:0] value_data
);

reg almost_full_d;

always @(posedge clk) begin
    if (rst) begin
        almost_full_d <= 1'b0;
        mark_valid <= 1'b0;
        mark_trace_id <= `YFD_TRACE_ID_FIFO;
        mark_level <= `YFD_LEVEL_WARNING;
        mark_arg0 <= 32'd0;
        value_valid <= 1'b0;
        value_trace_id <= `YFD_TRACE_ID_FIFO;
        value_id <= VALUE_ID;
        value_data <= 32'd0;
    end else begin
        almost_full_d <= almost_full;
        mark_valid <= 1'b0;
        value_valid <= 1'b0;

        if (ENABLE != 0) begin
            if (overflow_valid) begin
                mark_valid <= 1'b1;
                mark_trace_id <= `YFD_TRACE_ID_FIFO;
                mark_level <= `YFD_LEVEL_ERROR;
                mark_arg0 <= level;
            end else if (almost_full && !almost_full_d) begin
                mark_valid <= 1'b1;
                mark_trace_id <= `YFD_TRACE_ID_FIFO;
                mark_level <= `YFD_LEVEL_WARNING;
                mark_arg0 <= level;
            end

            if (sample_valid) begin
                value_valid <= 1'b1;
                value_trace_id <= `YFD_TRACE_ID_FIFO;
                value_id <= VALUE_ID;
                value_data <= level;
            end
        end
    end
end

endmodule
