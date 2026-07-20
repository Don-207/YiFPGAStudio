`timescale 1ns / 1ps

module yifpga_debug_uart_rx #(
    parameter CLK_FREQ_HZ = 50000000,
    parameter BAUD = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg        data_valid,
    output reg [7:0]  data,
    output reg        frame_error
);

localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD;
localparam integer HALF_BIT = CLKS_PER_BIT / 2;

localparam STATE_IDLE  = 2'd0;
localparam STATE_START = 2'd1;
localparam STATE_DATA  = 2'd2;
localparam STATE_STOP  = 2'd3;

reg [1:0] state = STATE_IDLE;
reg [15:0] sample_count = 16'd0;
reg [3:0] bit_index = 4'd0;
reg [7:0] data_buf = 8'd0;
reg rx_ff0 = 1'b1;
reg rx_ff1 = 1'b1;

wire rx_fall = (rx_ff1 == 1'b1) && (rx_ff0 == 1'b0);

always @(posedge clk) begin
    if (rst) begin
        rx_ff0 <= 1'b1;
        rx_ff1 <= 1'b1;
    end else begin
        rx_ff0 <= rx;
        rx_ff1 <= rx_ff0;
    end
end

always @(posedge clk) begin
    if (rst) begin
        state <= STATE_IDLE;
        sample_count <= 16'd0;
        bit_index <= 4'd0;
        data_buf <= 8'd0;
        data <= 8'd0;
        data_valid <= 1'b0;
        frame_error <= 1'b0;
    end else begin
        data_valid <= 1'b0;
        frame_error <= 1'b0;

        case (state)
            STATE_IDLE: begin
                sample_count <= 16'd0;
                bit_index <= 4'd0;
                if (rx_fall) begin
                    sample_count <= HALF_BIT[15:0] - 16'd1;
                    state <= STATE_START;
                end
            end
            STATE_START: begin
                if (sample_count != 16'd0) begin
                    sample_count <= sample_count - 16'd1;
                end else begin
                    if (!rx_ff1) begin
                        sample_count <= CLKS_PER_BIT[15:0] - 16'd1;
                        bit_index <= 4'd0;
                        state <= STATE_DATA;
                    end else begin
                        state <= STATE_IDLE;
                    end
                end
            end
            STATE_DATA: begin
                if (sample_count != 16'd0) begin
                    sample_count <= sample_count - 16'd1;
                end else begin
                    data_buf[bit_index[2:0]] <= rx_ff1;
                    sample_count <= CLKS_PER_BIT[15:0] - 16'd1;
                    if (bit_index == 4'd7) begin
                        state <= STATE_STOP;
                    end else begin
                        bit_index <= bit_index + 4'd1;
                    end
                end
            end
            STATE_STOP: begin
                if (sample_count != 16'd0) begin
                    sample_count <= sample_count - 16'd1;
                end else begin
                    state <= STATE_IDLE;
                    if (rx_ff1) begin
                        data <= data_buf;
                        data_valid <= 1'b1;
                    end else begin
                        frame_error <= 1'b1;
                    end
                end
            end
            default: state <= STATE_IDLE;
        endcase
    end
end

endmodule
