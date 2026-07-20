`timescale 1ns / 1ps

module yifpga_debug_uart_tx #(
    parameter CLK_FREQ_HZ = 50000000,
    parameter BAUD        = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       data_valid,
    input  wire [7:0] data,
    output wire       data_ready,
    output wire       tx,
    output wire       busy
);

localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD;

reg [31:0] baud_count;
reg [3:0]  bit_index;
reg [7:0]  data_latched;
reg        tx_reg;
reg        busy_reg;

assign data_ready = !busy_reg;
assign tx = tx_reg;
assign busy = busy_reg;

always @(posedge clk) begin
    if (rst) begin
        baud_count <= 32'd0;
        bit_index <= 4'd0;
        data_latched <= 8'd0;
        tx_reg <= 1'b1;
        busy_reg <= 1'b0;
    end else begin
        if (!busy_reg) begin
            baud_count <= 32'd0;
            bit_index <= 4'd0;
            tx_reg <= 1'b1;

            if (data_valid) begin
                data_latched <= data;
                tx_reg <= 1'b0;
                busy_reg <= 1'b1;
            end
        end else if (baud_count == (CLKS_PER_BIT - 1)) begin
            baud_count <= 32'd0;

            if (bit_index < 4'd8) begin
                tx_reg <= data_latched[bit_index];
                bit_index <= bit_index + 4'd1;
            end else if (bit_index == 4'd8) begin
                tx_reg <= 1'b1;
                bit_index <= bit_index + 4'd1;
            end else begin
                tx_reg <= 1'b1;
                busy_reg <= 1'b0;
                bit_index <= 4'd0;
            end
        end else begin
            baud_count <= baud_count + 32'd1;
        end
    end
end

endmodule
