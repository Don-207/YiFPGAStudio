`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_trace_pkg.vh"

module yifpga_trace_irq_probe #(
    parameter ENABLE = 1
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        irq_level,
    input  wire [31:0] irq_arg0,

    output reg         mark_valid,
    output reg  [15:0] mark_trace_id,
    output reg  [7:0]  mark_level,
    output reg  [31:0] mark_arg0
);

reg irq_level_d;

always @(posedge clk) begin
    if (rst) begin
        irq_level_d <= 1'b0;
        mark_valid <= 1'b0;
        mark_trace_id <= `YFD_TRACE_ID_IRQ;
        mark_level <= `YFD_LEVEL_INFO;
        mark_arg0 <= 32'd0;
    end else begin
        irq_level_d <= irq_level;
        mark_valid <= 1'b0;

        if (ENABLE != 0) begin
            if (irq_level && !irq_level_d) begin
                mark_valid <= 1'b1;
                mark_trace_id <= `YFD_TRACE_ID_IRQ;
                mark_level <= `YFD_LEVEL_INFO;
                mark_arg0 <= irq_arg0;
            end else if (!irq_level && irq_level_d) begin
                mark_valid <= 1'b1;
                mark_trace_id <= `YFD_TRACE_ID_IRQ;
                mark_level <= `YFD_LEVEL_DEBUG;
                mark_arg0 <= irq_arg0;
            end
        end
    end
end

endmodule
