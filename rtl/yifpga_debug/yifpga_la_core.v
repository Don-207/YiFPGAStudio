`timescale 1ns / 1ps

`include "yifpga_la_pkg.vh"

module yifpga_la_core #(
    parameter SAMPLE_WIDTH = 32,
    parameter SAMPLE_DEPTH = 128
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        arm_pulse,
    input  wire        stop_pulse,
    input  wire        clear_pulse,
    input  wire        force_trigger_pulse,
    input  wire        start_readout_pulse,
    input  wire        readout_done_pulse,
    input  wire [15:0] sample_divisor,
    input  wire [15:0] capture_depth,
    input  wire [15:0] pretrigger_depth,
    input  wire [3:0]  trigger_mode,
    input  wire [4:0]  trigger_channel,
    input  wire [31:0] trigger_value,
    input  wire [31:0] trigger_mask,
    input  wire [SAMPLE_WIDTH-1:0] sample_bus,
    output reg  [2:0]  state,
    output reg  [15:0] samples_written,
    output reg  [15:0] trigger_index,
    output reg  [31:0] capture_id,
    output wire        done,
    output reg         overflow,
    output reg         config_error,
    output reg  [7:0]  error_code,
    output reg  [15:0] capture_flags,
    output reg  [31:0] trigger_sample_value,
    output reg  [4:0]  trigger_hit_channel,
    input  wire        read_req,
    input  wire [15:0] read_index,
    output reg  [SAMPLE_WIDTH-1:0] read_sample,
    output reg         read_valid
);

reg [SAMPLE_WIDTH-1:0] buffer [0:SAMPLE_DEPTH-1];
reg [15:0] write_ptr = 16'd0;
reg [15:0] div_count = 16'd0;
reg [15:0] post_remaining = 16'd0;
reg [15:0] read_start_ptr = 16'd0;
reg [15:0] read_addr = 16'd0;
reg [31:0] last_sample_value = 32'd0;

localparam [15:0] SAMPLE_DEPTH_U = SAMPLE_DEPTH;
localparam [16:0] SAMPLE_DEPTH_U17 = SAMPLE_DEPTH;
wire [15:0] effective_divisor = sample_divisor == 16'd0 ? 16'd1 : sample_divisor;
wire [15:0] effective_capture_depth = capture_depth;
wire [15:0] effective_pretrigger_depth = pretrigger_depth;
wire config_bad = (effective_capture_depth == 16'd0) ||
                  (effective_capture_depth > SAMPLE_DEPTH_U) ||
                  (effective_pretrigger_depth >= effective_capture_depth);
wire sample_due = (div_count == 16'd0);
wire active_capture = (state == `YFD_LA_STATE_ARMED) || (state == `YFD_LA_STATE_CAPTURING);
wire trigger_hit;
wire [4:0] trigger_hit_channel_w;
wire [31:0] trigger_sample_value_w;

assign done = state == `YFD_LA_STATE_DONE;

yifpga_la_trigger u_trigger (
    .clk(clk),
    .rst(rst),
    .enable(enable && (state == `YFD_LA_STATE_ARMED)),
    .sample_valid(sample_due && active_capture),
    .trigger_mode(trigger_mode),
    .trigger_channel(trigger_channel),
    .trigger_value(trigger_value),
    .trigger_mask(trigger_mask),
    .sample_bus(sample_bus[31:0]),
    .trigger_hit(trigger_hit),
    .hit_channel(trigger_hit_channel_w),
    .hit_sample_value(trigger_sample_value_w)
);

function [15:0] inc_ptr;
    input [15:0] ptr;
    begin
        inc_ptr = (ptr == SAMPLE_DEPTH_U - 16'd1) ? 16'd0 : ptr + 16'd1;
    end
endfunction

function [15:0] add_ptr;
    input [15:0] base;
    input [15:0] offset;
    reg [16:0] sum;
    begin
        sum = {1'b0, base} + {1'b0, offset};
        add_ptr = (sum >= SAMPLE_DEPTH_U17) ? sum[15:0] - SAMPLE_DEPTH_U : sum[15:0];
    end
endfunction

function [15:0] calc_start_ptr;
    input [15:0] ptr;
    input [15:0] count;
    begin
        calc_start_ptr = (ptr >= count) ? ptr - count : ptr + SAMPLE_DEPTH_U - count;
    end
endfunction

task finish_capture;
    input forced;
    begin
        state <= `YFD_LA_STATE_DONE;
        read_start_ptr <= calc_start_ptr(write_ptr, samples_written);
        capture_flags <= `YFD_LA_FLAG_VALID |
                         `YFD_LA_FLAG_TRIGGERED |
                         (forced ? `YFD_LA_FLAG_FORCED : 16'd0) |
                         (overflow ? `YFD_LA_FLAG_OVERFLOW : 16'd0) |
                         ((samples_written < effective_capture_depth) ? `YFD_LA_FLAG_PARTIAL : 16'd0);
    end
endtask

always @(posedge clk) begin
    if (rst) begin
        state <= `YFD_LA_STATE_IDLE;
        samples_written <= 16'd0;
        trigger_index <= 16'd0;
        capture_id <= 32'd0;
        overflow <= 1'b0;
        config_error <= 1'b0;
        error_code <= `YFD_LA_ERROR_NONE;
        capture_flags <= 16'd0;
        trigger_sample_value <= 32'd0;
        trigger_hit_channel <= 5'd0;
        write_ptr <= 16'd0;
        div_count <= 16'd0;
        post_remaining <= 16'd0;
        read_start_ptr <= 16'd0;
        last_sample_value <= 32'd0;
        read_sample <= {SAMPLE_WIDTH{1'b0}};
        read_valid <= 1'b0;
    end else begin
        read_valid <= 1'b0;

        if (clear_pulse || !enable) begin
            state <= `YFD_LA_STATE_IDLE;
            samples_written <= 16'd0;
            trigger_index <= 16'd0;
            overflow <= 1'b0;
            config_error <= 1'b0;
            error_code <= `YFD_LA_ERROR_NONE;
            capture_flags <= 16'd0;
            trigger_sample_value <= 32'd0;
            trigger_hit_channel <= 5'd0;
            write_ptr <= 16'd0;
            div_count <= 16'd0;
            post_remaining <= 16'd0;
            read_start_ptr <= 16'd0;
            last_sample_value <= 32'd0;
        end else begin
            if (read_req && ((state == `YFD_LA_STATE_DONE) || (state == `YFD_LA_STATE_READOUT)) &&
                (read_index < samples_written)) begin
                read_addr = add_ptr(read_start_ptr, read_index);
                read_sample <= buffer[read_addr];
                read_valid <= 1'b1;
            end

            if (active_capture) begin
                if (div_count == effective_divisor - 16'd1) begin
                    div_count <= 16'd0;
                end else begin
                    div_count <= div_count + 16'd1;
                end
            end else begin
                div_count <= 16'd0;
            end

            case (state)
                `YFD_LA_STATE_IDLE: begin
                    if (arm_pulse) begin
                        if (config_bad) begin
                            state <= `YFD_LA_STATE_ERROR;
                            config_error <= 1'b1;
                            error_code <= `YFD_LA_ERROR_CONFIG;
                        end else begin
                            state <= `YFD_LA_STATE_ARMED;
                            capture_id <= capture_id + 32'd1;
                            samples_written <= 16'd0;
                            trigger_index <= 16'd0;
                            overflow <= 1'b0;
                            config_error <= 1'b0;
                            error_code <= `YFD_LA_ERROR_NONE;
                            capture_flags <= 16'd0;
                            write_ptr <= 16'd0;
                            post_remaining <= 16'd0;
                        end
                    end
                end

                `YFD_LA_STATE_ARMED: begin
                    if (stop_pulse) begin
                        finish_capture(1'b0);
                    end else if (force_trigger_pulse) begin
                        trigger_index <= samples_written == 16'd0 ? 16'd0 : samples_written - 16'd1;
                        trigger_sample_value <= samples_written == 16'd0 ? sample_bus[31:0] : last_sample_value;
                        trigger_hit_channel <= trigger_channel;
                        if (samples_written >= effective_capture_depth) begin
                            finish_capture(1'b1);
                        end else begin
                            state <= `YFD_LA_STATE_CAPTURING;
                            post_remaining <= effective_capture_depth - samples_written;
                            capture_flags <= `YFD_LA_FLAG_FORCED;
                        end
                    end else if (sample_due) begin
                        buffer[write_ptr] <= sample_bus;
                        last_sample_value <= sample_bus[31:0];
                        write_ptr <= inc_ptr(write_ptr);
                        if (samples_written < effective_pretrigger_depth) begin
                            samples_written <= samples_written + 16'd1;
                        end

                        if (trigger_hit) begin
                            trigger_index <= samples_written;
                            trigger_sample_value <= trigger_sample_value_w;
                            trigger_hit_channel <= trigger_hit_channel_w;
                            samples_written <= samples_written + 16'd1;
                        if ((samples_written + 16'd1) >= effective_capture_depth) begin
                                state <= `YFD_LA_STATE_DONE;
                                read_start_ptr <= calc_start_ptr(inc_ptr(write_ptr), samples_written + 16'd1);
                                capture_flags <= `YFD_LA_FLAG_VALID |
                                                 `YFD_LA_FLAG_TRIGGERED |
                                                 (overflow ? `YFD_LA_FLAG_OVERFLOW : 16'd0);
                            end else begin
                                state <= `YFD_LA_STATE_CAPTURING;
                                post_remaining <= effective_capture_depth - (samples_written + 16'd1);
                            end
                        end else if ((samples_written >= effective_pretrigger_depth) && (effective_pretrigger_depth != 16'd0)) begin
                            overflow <= 1'b1;
                        end
                    end
                end

                `YFD_LA_STATE_CAPTURING: begin
                    if (stop_pulse) begin
                        finish_capture((capture_flags & `YFD_LA_FLAG_FORCED) != 16'd0);
                    end else if (sample_due && (post_remaining != 16'd0)) begin
                        buffer[write_ptr] <= sample_bus;
                        last_sample_value <= sample_bus[31:0];
                        write_ptr <= inc_ptr(write_ptr);
                        samples_written <= samples_written + 16'd1;
                        post_remaining <= post_remaining - 16'd1;
                        if (post_remaining == 16'd1) begin
                            state <= `YFD_LA_STATE_DONE;
                            read_start_ptr <= calc_start_ptr(inc_ptr(write_ptr), samples_written + 16'd1);
                            capture_flags <= `YFD_LA_FLAG_VALID |
                                             `YFD_LA_FLAG_TRIGGERED |
                                             (((capture_flags & `YFD_LA_FLAG_FORCED) != 16'd0) ? `YFD_LA_FLAG_FORCED : 16'd0) |
                                             (overflow ? `YFD_LA_FLAG_OVERFLOW : 16'd0);
                        end
                    end
                end

                `YFD_LA_STATE_DONE: begin
                    if (start_readout_pulse) begin
                        state <= `YFD_LA_STATE_READOUT;
                    end else if (arm_pulse) begin
                        if (config_bad) begin
                            state <= `YFD_LA_STATE_ERROR;
                            config_error <= 1'b1;
                            error_code <= `YFD_LA_ERROR_CONFIG;
                        end else begin
                            state <= `YFD_LA_STATE_ARMED;
                            capture_id <= capture_id + 32'd1;
                            samples_written <= 16'd0;
                            trigger_index <= 16'd0;
                            overflow <= 1'b0;
                            config_error <= 1'b0;
                            error_code <= `YFD_LA_ERROR_NONE;
                            capture_flags <= 16'd0;
                            write_ptr <= 16'd0;
                            post_remaining <= 16'd0;
                        end
                    end
                end

                `YFD_LA_STATE_READOUT: begin
                    if (readout_done_pulse) begin
                        state <= `YFD_LA_STATE_DONE;
                    end
                end

                `YFD_LA_STATE_ERROR: begin
                    if (arm_pulse && !config_bad) begin
                        state <= `YFD_LA_STATE_ARMED;
                        capture_id <= capture_id + 32'd1;
                        samples_written <= 16'd0;
                        trigger_index <= 16'd0;
                        overflow <= 1'b0;
                        config_error <= 1'b0;
                        error_code <= `YFD_LA_ERROR_NONE;
                        capture_flags <= 16'd0;
                        write_ptr <= 16'd0;
                        post_remaining <= 16'd0;
                    end
                end

                default: begin
                    state <= `YFD_LA_STATE_IDLE;
                end
            endcase
        end
    end
end

endmodule
