`timescale 1ns / 1ps

`include "yifpga_la_pkg.vh"

module yifpga_la_trigger (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        sample_valid,
    input  wire [3:0]  trigger_mode,
    input  wire [4:0]  trigger_channel,
    input  wire [31:0] trigger_value,
    input  wire [31:0] trigger_mask,
    input  wire [31:0] sample_bus,
    output reg         trigger_hit,
    output reg  [4:0]  hit_channel,
    output reg  [31:0] hit_sample_value
);

reg [31:0] prev_sample = 32'd0;
wire current_bit = sample_bus[trigger_channel];
wire previous_bit = prev_sample[trigger_channel];
wire level_hit = current_bit == trigger_value[0];
wire rising_hit = !previous_bit && current_bit;
wire falling_hit = previous_bit && !current_bit;
wire mask_hit = (sample_bus & trigger_mask) == (trigger_value & trigger_mask);

always @(*) begin
    trigger_hit = 1'b0;
    hit_channel = trigger_channel;
    hit_sample_value = sample_bus;

    if (enable && sample_valid) begin
        case (trigger_mode)
            `YFD_LA_TRIGGER_LEVEL: begin
                trigger_hit = level_hit;
            end
            `YFD_LA_TRIGGER_EDGE_RISING: begin
                trigger_hit = rising_hit;
            end
            `YFD_LA_TRIGGER_EDGE_FALLING: begin
                trigger_hit = falling_hit;
            end
            `YFD_LA_TRIGGER_MASK_MATCH: begin
                trigger_hit = mask_hit;
            end
            default: begin
                trigger_hit = 1'b0;
            end
        endcase
    end
end

always @(posedge clk) begin
    if (rst) begin
        prev_sample <= 32'd0;
    end else begin
        if (!enable) begin
            prev_sample <= sample_bus;
        end else if (sample_valid) begin
            prev_sample <= sample_bus;
        end
    end
end

endmodule
