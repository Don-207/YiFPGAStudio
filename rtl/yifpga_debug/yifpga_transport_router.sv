`timescale 1ns/1ps
module yifpga_transport_router #(
    parameter bit ENABLE_UART = 1'b1,
    parameter bit ENABLE_JTAG = 1'b1
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] in_data,
    input  logic       in_valid,
    output logic       in_ready,
    output logic [7:0] uart_data,
    output logic       uart_valid,
    input  logic       uart_ready,
    output logic [7:0] jtag_data,
    output logic       jtag_valid,
    input  logic       jtag_ready,
    output logic [31:0] uart_dropped_bytes,
    output logic [31:0] jtag_dropped_bytes
);

// The producer is never backpressured by a disabled or congested transport.
// Each enabled output independently accepts or drops the current byte.
assign in_ready   = 1'b1;
assign uart_data  = in_data;
assign jtag_data  = in_data;
assign uart_valid = ENABLE_UART && in_valid && uart_ready;
assign jtag_valid = ENABLE_JTAG && in_valid && jtag_ready;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_dropped_bytes <= 32'd0;
        jtag_dropped_bytes <= 32'd0;
    end else if (in_valid) begin
        if (ENABLE_UART && !uart_ready && uart_dropped_bytes != 32'hffff_ffff)
            uart_dropped_bytes <= uart_dropped_bytes + 1'b1;
        if (ENABLE_JTAG && !jtag_ready && jtag_dropped_bytes != 32'hffff_ffff)
            jtag_dropped_bytes <= jtag_dropped_bytes + 1'b1;
    end
end

endmodule
