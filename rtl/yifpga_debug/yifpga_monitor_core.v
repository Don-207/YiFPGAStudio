`timescale 1ns / 1ps

`include "yifpga_monitor_pkg.vh"

module yifpga_monitor_core #(
    parameter DEFAULT_DEMO_PERIOD = 32'd1000000
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire [15:0] req_seq,
    input  wire [15:0] req_addr,
    input  wire        req_write,
    input  wire [7:0]  req_width,
    input  wire [31:0] req_wdata,
    input  wire [31:0] req_wmask,

    output reg         resp_valid,
    input  wire        resp_ready,
    output reg  [15:0] resp_seq,
    output reg  [15:0] resp_addr,
    output reg         resp_write,
    output reg  [7:0]  resp_width,
    output reg  [7:0]  resp_status,
    output reg  [31:0] resp_rdata,
    output reg  [31:0] resp_old_value,
    output reg  [31:0] resp_new_value,

    input  wire [31:0] counter0,
    input  wire [31:0] profiler_status_set,
    output wire [31:0] control,
    output wire [31:0] led_control,
    output wire [31:0] demo_period,
    output wire [31:0] error_status,
    output wire        clear_counters_pulse,
    output wire [31:0] profiler_control,
    output wire [31:0] profiler_sample_period,
    output wire        profiler_clear_pulse,
    output wire [31:0] profiler_status,
    output wire [31:0] profiler_metric_mask0,
    output wire [31:0] profiler_alert_threshold0,
    input  wire [31:0] la_status_set,
    input  wire [31:0] la_capture_id,
    output wire [31:0] la_control,
    output wire [31:0] la_status,
    output wire [31:0] la_sample_divisor,
    output wire [31:0] la_capture_depth,
    output wire [31:0] la_pretrigger_depth,
    output wire [31:0] la_trigger_mode,
    output wire [31:0] la_trigger_channel,
    output wire [31:0] la_trigger_value,
    output wire [31:0] la_trigger_mask,
    output wire [31:0] la_channel_mask,
    output wire        la_arm_pulse,
    output wire        la_stop_pulse,
    output wire        la_clear_pulse,
    output wire        la_force_trigger_pulse,
    output wire        la_start_readout_pulse
);

wire bank_resp_valid;
wire bank_resp_ready;
wire [7:0] bank_resp_status;
wire [31:0] bank_resp_rdata;
wire [31:0] bank_resp_old_value;
wire [31:0] bank_resp_new_value;

reg [15:0] pending_seq;
reg [15:0] pending_addr;
reg pending_write;
reg [7:0] pending_width;

assign bank_resp_ready = !resp_valid || resp_ready;

yifpga_monitor_reg_bank #(
    .DEFAULT_DEMO_PERIOD(DEFAULT_DEMO_PERIOD)
) u_reg_bank (
    .clk(clk),
    .rst(rst),
    .req_valid(req_valid),
    .req_ready(req_ready),
    .req_addr(req_addr),
    .req_write(req_write),
    .req_width(req_width),
    .req_wdata(req_wdata),
    .req_wmask(req_wmask),
    .resp_valid(bank_resp_valid),
    .resp_ready(bank_resp_ready),
    .resp_status(bank_resp_status),
    .resp_rdata(bank_resp_rdata),
    .resp_old_value(bank_resp_old_value),
    .resp_new_value(bank_resp_new_value),
    .counter0(counter0),
    .profiler_status_set(profiler_status_set),
    .control(control),
    .led_control(led_control),
    .demo_period(demo_period),
    .error_status(error_status),
    .clear_counters_pulse(clear_counters_pulse),
    .profiler_control(profiler_control),
    .profiler_sample_period(profiler_sample_period),
    .profiler_clear_pulse(profiler_clear_pulse),
    .profiler_status(profiler_status),
    .profiler_metric_mask0(profiler_metric_mask0),
    .profiler_alert_threshold0(profiler_alert_threshold0),
    .la_status_set(la_status_set),
    .la_capture_id(la_capture_id),
    .la_control(la_control),
    .la_status(la_status),
    .la_sample_divisor(la_sample_divisor),
    .la_capture_depth(la_capture_depth),
    .la_pretrigger_depth(la_pretrigger_depth),
    .la_trigger_mode(la_trigger_mode),
    .la_trigger_channel(la_trigger_channel),
    .la_trigger_value(la_trigger_value),
    .la_trigger_mask(la_trigger_mask),
    .la_channel_mask(la_channel_mask),
    .la_arm_pulse(la_arm_pulse),
    .la_stop_pulse(la_stop_pulse),
    .la_clear_pulse(la_clear_pulse),
    .la_force_trigger_pulse(la_force_trigger_pulse),
    .la_start_readout_pulse(la_start_readout_pulse)
);

always @(posedge clk) begin
    if (rst) begin
        pending_seq <= 16'd0;
        pending_addr <= 16'd0;
        pending_write <= 1'b0;
        pending_width <= 8'd0;
        resp_valid <= 1'b0;
        resp_seq <= 16'd0;
        resp_addr <= 16'd0;
        resp_write <= 1'b0;
        resp_width <= 8'd0;
        resp_status <= `YFD_MON_STATUS_OK;
        resp_rdata <= 32'd0;
        resp_old_value <= 32'd0;
        resp_new_value <= 32'd0;
    end else begin
        if (req_valid && req_ready) begin
            pending_seq <= req_seq;
            pending_addr <= req_addr;
            pending_write <= req_write;
            pending_width <= req_width;
        end

        if (resp_valid && resp_ready) begin
            resp_valid <= 1'b0;
        end

        if (bank_resp_valid && bank_resp_ready) begin
            resp_valid <= 1'b1;
            resp_seq <= pending_seq;
            resp_addr <= pending_addr;
            resp_write <= pending_write;
            resp_width <= pending_width;
            resp_status <= bank_resp_status;
            resp_rdata <= bank_resp_rdata;
            resp_old_value <= bank_resp_old_value;
            resp_new_value <= bank_resp_new_value;
        end
    end
end

endmodule
