`timescale 1ns / 1ps

`include "yifpga_profiler_pkg.vh"

module yifpga_profiler_latency #(
    parameter ENABLE = 1,
    parameter METRIC_ID = `YFD_PROFILER_METRIC_DEMO_LATENCY,
    parameter TIMEOUT_CYCLES = 32'd0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,
    input  wire        enable,

    input  wire        start_valid,
    input  wire        end_valid,
    input  wire        timeout_clear,

    output reg         busy,
    output reg         metric_valid,
    output reg  [15:0] metric_id,
    output reg  [31:0] metric_value0,
    output reg  [31:0] metric_value1,
    output reg  [31:0] metric_value2,
    output reg  [31:0] metric_value3,
    output reg         metric_overflow
);

reg [31:0] timer;
reg [31:0] complete_count;
reg [31:0] min_latency;
reg [31:0] max_latency;
reg [31:0] latency_sum;
reg [15:0] busy_count;
reg [15:0] timeout_count;
reg        seen_latency;
reg        divide_busy;
reg [5:0]  divide_count;
reg [31:0] divide_dividend;
reg [31:0] divide_divisor;
reg [31:0] divide_quotient;
reg [32:0] divide_remainder;
reg [31:0] pending_value0;
reg [31:0] pending_value1;
reg [31:0] pending_value2;

wire [32:0] divide_shifted_remainder = {divide_remainder[31:0], divide_dividend[31]};
wire        divide_subtract = divide_shifted_remainder >= {1'b0, divide_divisor};
wire [32:0] divide_next_remainder = divide_subtract ?
    divide_shifted_remainder - {1'b0, divide_divisor} : divide_shifted_remainder;
wire [31:0] divide_next_quotient = {divide_quotient[30:0], divide_subtract};

wire timeout_hit = busy && (TIMEOUT_CYCLES != 32'd0) && (timer >= TIMEOUT_CYCLES);
wire event_timeout = timeout_clear || timeout_hit;
wire [31:0] observed_latency = timer;
wire [31:0] next_complete_count = (end_valid && busy && complete_count != 32'hFFFFFFFF) ? complete_count + 32'd1 : complete_count;
wire [31:0] next_min_latency = (!seen_latency || observed_latency < min_latency) ? observed_latency : min_latency;
wire [31:0] next_max_latency = (!seen_latency || observed_latency > max_latency) ? observed_latency : max_latency;
wire [31:0] next_latency_sum = latency_sum + observed_latency;
wire [15:0] next_busy_count = (start_valid && busy && busy_count != 16'hFFFF) ? busy_count + 16'd1 : busy_count;
wire [15:0] next_timeout_count = (event_timeout && busy && timeout_count != 16'hFFFF) ? timeout_count + 16'd1 : timeout_count;

always @(posedge clk) begin
    if (rst || clear) begin
        busy <= 1'b0;
        timer <= 32'd0;
        complete_count <= 32'd0;
        min_latency <= 32'd0;
        max_latency <= 32'd0;
        latency_sum <= 32'd0;
        busy_count <= 16'd0;
        timeout_count <= 16'd0;
        seen_latency <= 1'b0;
        divide_busy <= 1'b0;
        divide_count <= 6'd0;
        divide_dividend <= 32'd0;
        divide_divisor <= 32'd0;
        divide_quotient <= 32'd0;
        divide_remainder <= 33'd0;
        pending_value0 <= 32'd0;
        pending_value1 <= 32'd0;
        pending_value2 <= 32'd0;
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
            if (divide_busy) begin
                divide_dividend <= {divide_dividend[30:0], 1'b0};
                divide_remainder <= divide_next_remainder;
                divide_quotient <= divide_next_quotient;
                divide_count <= divide_count - 6'd1;

                if (divide_count == 6'd1) begin
                    divide_busy <= 1'b0;
                    metric_valid <= 1'b1;
                    metric_id <= METRIC_ID;
                    metric_value0 <= pending_value0;
                    metric_value1 <= pending_value1;
                    metric_value2 <= pending_value2;
                    metric_value3 <= divide_next_quotient;
                end
            end

            if (busy && timer != 32'hFFFFFFFF) begin
                timer <= timer + 32'd1;
            end

            busy_count <= next_busy_count;
            timeout_count <= next_timeout_count;

            if (end_valid && busy && !divide_busy) begin
                complete_count <= next_complete_count;
                min_latency <= next_min_latency;
                max_latency <= next_max_latency;
                latency_sum <= next_latency_sum;
                seen_latency <= 1'b1;
                busy <= 1'b0;
                timer <= 32'd0;

                divide_busy <= 1'b1;
                divide_count <= 6'd32;
                divide_dividend <= next_latency_sum;
                divide_divisor <= next_complete_count;
                divide_quotient <= 32'd0;
                divide_remainder <= 33'd0;
                pending_value0 <= next_complete_count;
                pending_value1 <= next_min_latency;
                pending_value2 <= next_max_latency;
            end else if (event_timeout && busy) begin
                busy <= 1'b0;
                timer <= 32'd0;

                metric_valid <= 1'b1;
                metric_id <= METRIC_ID;
                metric_value0 <= complete_count;
                metric_value1 <= min_latency;
                metric_value2 <= max_latency;
                metric_value3 <= {next_busy_count, next_timeout_count};
                metric_overflow <= 1'b1;
            end else if (start_valid && !busy && !divide_busy) begin
                busy <= 1'b1;
                timer <= 32'd0;
            end else if (start_valid && (busy || divide_busy)) begin
                metric_valid <= 1'b1;
                metric_id <= METRIC_ID;
                metric_value0 <= complete_count;
                metric_value1 <= min_latency;
                metric_value2 <= max_latency;
                metric_value3 <= {next_busy_count, next_timeout_count};
                metric_overflow <= 1'b1;
            end
        end
    end
end

endmodule
