`timescale 1ns / 1ps

module yifpga_profiler_counter #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             clear,
    input  wire             add_valid,
    input  wire [WIDTH-1:0] add_value,
    output reg  [WIDTH-1:0] value,
    output reg              saturated,
    output reg              overflow_pulse
);

wire [WIDTH-1:0] max_value = {WIDTH{1'b1}};
wire will_overflow = add_valid && (add_value > (max_value - value));

always @(posedge clk) begin
    if (rst || clear) begin
        value <= {WIDTH{1'b0}};
        saturated <= 1'b0;
        overflow_pulse <= 1'b0;
    end else begin
        overflow_pulse <= 1'b0;
        if (add_valid) begin
            if (will_overflow) begin
                value <= max_value;
                saturated <= 1'b1;
                overflow_pulse <= 1'b1;
            end else begin
                value <= value + add_value;
            end
        end
    end
end

endmodule
