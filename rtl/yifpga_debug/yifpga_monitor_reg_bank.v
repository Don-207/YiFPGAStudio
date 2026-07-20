`timescale 1ns / 1ps

`include "yifpga_monitor_pkg.vh"
`include "yifpga_profiler_pkg.vh"
`include "yifpga_la_pkg.vh"

module yifpga_monitor_reg_bank #(
    parameter DEFAULT_DEMO_PERIOD = 32'd1000000
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire [15:0] req_addr,
    input  wire        req_write,
    input  wire [7:0]  req_width,
    input  wire [31:0] req_wdata,
    input  wire [31:0] req_wmask,

    output reg         resp_valid,
    input  wire        resp_ready,
    output reg  [7:0]  resp_status,
    output reg  [31:0] resp_rdata,
    output reg  [31:0] resp_old_value,
    output reg  [31:0] resp_new_value,

    input  wire [31:0] counter0,
    input  wire [31:0] profiler_status_set,
    output reg  [31:0] control,
    output reg  [31:0] led_control,
    output reg  [31:0] demo_period,
    output reg  [31:0] error_status,
    output reg         clear_counters_pulse,
    output reg  [31:0] profiler_control,
    output reg  [31:0] profiler_sample_period,
    output reg         profiler_clear_pulse,
    output reg  [31:0] profiler_status,
    output reg  [31:0] profiler_metric_mask0,
    output reg  [31:0] profiler_alert_threshold0,

    input  wire [31:0] la_status_set,
    input  wire [31:0] la_capture_id,
    output reg  [31:0] la_control,
    output reg  [31:0] la_status,
    output reg  [31:0] la_sample_divisor,
    output reg  [31:0] la_capture_depth,
    output reg  [31:0] la_pretrigger_depth,
    output reg  [31:0] la_trigger_mode,
    output reg  [31:0] la_trigger_channel,
    output reg  [31:0] la_trigger_value,
    output reg  [31:0] la_trigger_mask,
    output reg  [31:0] la_channel_mask,
    output reg         la_arm_pulse,
    output reg         la_stop_pulse,
    output reg         la_clear_pulse,
    output reg         la_force_trigger_pulse,
    output reg         la_start_readout_pulse
);

wire can_accept = !resp_valid || resp_ready;
assign req_ready = can_accept;

reg [31:0] old_value;
reg [31:0] new_value;
reg [7:0] status;
reg is_known;
reg is_writable;
reg is_trigger;
reg is_w1c;

always @(*) begin
    old_value = 32'd0;
    is_known = 1'b1;
    is_writable = 1'b0;
    is_trigger = 1'b0;
    is_w1c = 1'b0;

    case (req_addr)
        `YFD_MON_ADDR_ID: old_value = `YFD_MONITOR_ID_VALUE;
        `YFD_MON_ADDR_VERSION: old_value = `YFD_MONITOR_VERSION_VALUE;
        `YFD_MON_ADDR_CONTROL: begin
            old_value = control;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LED_CONTROL: begin
            old_value = led_control;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_DEMO_PERIOD: begin
            old_value = demo_period;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_COUNTER0: old_value = counter0;
        `YFD_MON_ADDR_CLEAR_COUNTERS: begin
            old_value = 32'd0;
            is_writable = 1'b1;
            is_trigger = 1'b1;
        end
        `YFD_MON_ADDR_ERROR_STATUS: begin
            old_value = error_status;
            is_writable = 1'b1;
            is_w1c = 1'b1;
        end
        `YFD_MON_ADDR_PROFILER_ID: old_value = `YFD_PROFILER_ID_VALUE;
        `YFD_MON_ADDR_PROFILER_VERSION: old_value = `YFD_PROFILER_VERSION_VALUE;
        `YFD_MON_ADDR_PROFILER_CONTROL: begin
            old_value = profiler_control;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_PROFILER_SAMPLE_PERIOD: begin
            old_value = profiler_sample_period;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_PROFILER_CLEAR: begin
            old_value = 32'd0;
            is_writable = 1'b1;
            is_trigger = 1'b1;
        end
        `YFD_MON_ADDR_PROFILER_STATUS: begin
            old_value = profiler_status | profiler_status_set;
            is_writable = 1'b1;
            is_w1c = 1'b1;
        end
        `YFD_MON_ADDR_PROFILER_METRIC_MASK0: begin
            old_value = profiler_metric_mask0;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_PROFILER_ALERT_THRESHOLD0: begin
            old_value = profiler_alert_threshold0;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_ID: old_value = `YFD_LA_ID_VALUE;
        `YFD_MON_ADDR_LA_VERSION: old_value = `YFD_LA_VERSION_VALUE;
        `YFD_MON_ADDR_LA_CONTROL: begin
            old_value = la_control;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_STATUS: begin
            // [2:0] is a mutually exclusive live state, not a sticky flag
            // field. Keep only [31:3] latched/W1C; OR-ing historical state
            // values makes ARMED(1) -> CAPTURING(2) appear as DONE(3).
            old_value = (la_status & 32'hFFFFFFF8) | la_status_set;
            is_writable = 1'b1;
            is_w1c = 1'b1;
        end
        `YFD_MON_ADDR_LA_SAMPLE_DIVISOR: begin
            old_value = la_sample_divisor;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_CAPTURE_DEPTH: begin
            old_value = la_capture_depth;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_PRETRIGGER_DEPTH: begin
            old_value = la_pretrigger_depth;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_TRIGGER_MODE: begin
            old_value = la_trigger_mode;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_TRIGGER_CHANNEL: begin
            old_value = la_trigger_channel;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_TRIGGER_VALUE: begin
            old_value = la_trigger_value;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_TRIGGER_MASK: begin
            old_value = la_trigger_mask;
            is_writable = 1'b1;
        end
        `YFD_MON_ADDR_LA_COMMAND: begin
            old_value = 32'd0;
            is_writable = 1'b1;
            is_trigger = 1'b1;
        end
        `YFD_MON_ADDR_LA_CAPTURE_ID: old_value = la_capture_id;
        `YFD_MON_ADDR_LA_CHANNEL_MASK: begin
            old_value = la_channel_mask;
            is_writable = 1'b1;
        end
        default: begin
            is_known = 1'b0;
            old_value = 32'd0;
        end
    endcase

    new_value = old_value;
    status = `YFD_MON_STATUS_OK;

    if (!is_known) begin
        status = `YFD_MON_STATUS_BAD_ADDR;
    end else if (req_width != 8'd4) begin
        status = `YFD_MON_STATUS_BAD_LEN;
    end else if (req_write && !is_writable) begin
        status = `YFD_MON_STATUS_DENIED;
    end else if (req_write && req_addr == `YFD_MON_ADDR_DEMO_PERIOD && ((old_value & ~req_wmask) | (req_wdata & req_wmask)) == 32'd0) begin
        status = `YFD_MON_STATUS_BAD_VALUE;
    end else if (req_write && req_addr == `YFD_MON_ADDR_PROFILER_SAMPLE_PERIOD && ((old_value & ~req_wmask) | (req_wdata & req_wmask)) == 32'd0) begin
        status = `YFD_MON_STATUS_BAD_VALUE;
    end else if (req_write && req_addr == `YFD_MON_ADDR_LA_SAMPLE_DIVISOR && ((old_value & ~req_wmask) | (req_wdata & req_wmask)) == 32'd0) begin
        status = `YFD_MON_STATUS_BAD_VALUE;
    end else if (req_write && req_addr == `YFD_MON_ADDR_LA_CAPTURE_DEPTH &&
                 ((((old_value & ~req_wmask) | (req_wdata & req_wmask)) == 32'd0) ||
                  (((old_value & ~req_wmask) | (req_wdata & req_wmask)) > {16'd0, `YFD_LA_MAX_SAMPLE_DEPTH}))) begin
        status = `YFD_MON_STATUS_BAD_VALUE;
    end else if (req_write && req_addr == `YFD_MON_ADDR_LA_PRETRIGGER_DEPTH &&
                 (((old_value & ~req_wmask) | (req_wdata & req_wmask)) >= la_capture_depth)) begin
        status = `YFD_MON_STATUS_BAD_VALUE;
    end else if (req_write && req_addr == `YFD_MON_ADDR_LA_TRIGGER_MODE &&
                 (((old_value & ~req_wmask) | (req_wdata & req_wmask)) > {28'd0, `YFD_LA_TRIGGER_MASK_MATCH})) begin
        status = `YFD_MON_STATUS_BAD_VALUE;
    end else if (req_write && req_addr == `YFD_MON_ADDR_LA_TRIGGER_CHANNEL &&
                 (((old_value & ~req_wmask) | (req_wdata & req_wmask)) > 32'd31)) begin
        status = `YFD_MON_STATUS_BAD_VALUE;
    end else if (req_write && is_w1c) begin
        new_value = old_value & ~req_wdata;
    end else if (req_write && is_trigger) begin
        new_value = 32'd0;
    end else if (req_write) begin
        new_value = (old_value & ~req_wmask) | (req_wdata & req_wmask);
    end
end

always @(posedge clk) begin
    if (rst) begin
        resp_valid <= 1'b0;
        resp_status <= `YFD_MON_STATUS_OK;
        resp_rdata <= 32'd0;
        resp_old_value <= 32'd0;
        resp_new_value <= 32'd0;
        control <= 32'd0;
        led_control <= 32'd0;
        demo_period <= DEFAULT_DEMO_PERIOD;
        error_status <= 32'd0;
        clear_counters_pulse <= 1'b0;
        profiler_control <= 32'd0;
        profiler_sample_period <= `YFD_PROFILER_DEFAULT_SAMPLE_PERIOD;
        profiler_clear_pulse <= 1'b0;
        profiler_status <= 32'd0;
        profiler_metric_mask0 <= 32'hFFFFFFFF;
        profiler_alert_threshold0 <= 32'd96;
        la_control <= 32'd0;
        la_status <= 32'd0;
        la_sample_divisor <= 32'd1;
        la_capture_depth <= 32'd32;
        la_pretrigger_depth <= 32'd8;
        la_trigger_mode <= {28'd0, `YFD_LA_TRIGGER_MASK_MATCH};
        la_trigger_channel <= 32'd7;
        la_trigger_value <= 32'h00000080;
        la_trigger_mask <= 32'h00000080;
        la_channel_mask <= 32'hFFFFFFFF;
        la_arm_pulse <= 1'b0;
        la_stop_pulse <= 1'b0;
        la_clear_pulse <= 1'b0;
        la_force_trigger_pulse <= 1'b0;
        la_start_readout_pulse <= 1'b0;
    end else begin
        clear_counters_pulse <= 1'b0;
        profiler_clear_pulse <= 1'b0;
        la_arm_pulse <= 1'b0;
        la_stop_pulse <= 1'b0;
        la_clear_pulse <= 1'b0;
        la_force_trigger_pulse <= 1'b0;
        la_start_readout_pulse <= 1'b0;
        profiler_status <= profiler_status | profiler_status_set;
        la_status <= (la_status | la_status_set) & 32'hFFFFFFF8;

        if (resp_valid && resp_ready) begin
            resp_valid <= 1'b0;
        end

        if (req_valid && req_ready) begin
            resp_valid <= 1'b1;
            resp_status <= status;
            resp_rdata <= old_value;
            resp_old_value <= old_value;
            resp_new_value <= (status == `YFD_MON_STATUS_OK) ? new_value : old_value;

            if (status == `YFD_MON_STATUS_OK && req_write) begin
                case (req_addr)
                    `YFD_MON_ADDR_CONTROL: control <= new_value;
                    `YFD_MON_ADDR_LED_CONTROL: led_control <= new_value;
                    `YFD_MON_ADDR_DEMO_PERIOD: demo_period <= new_value;
                    `YFD_MON_ADDR_CLEAR_COUNTERS: clear_counters_pulse <= |req_wdata;
                    `YFD_MON_ADDR_ERROR_STATUS: error_status <= new_value;
                    `YFD_MON_ADDR_PROFILER_CONTROL: profiler_control <= new_value;
                    `YFD_MON_ADDR_PROFILER_SAMPLE_PERIOD: profiler_sample_period <= new_value;
                    `YFD_MON_ADDR_PROFILER_CLEAR: profiler_clear_pulse <= |req_wdata;
                    `YFD_MON_ADDR_PROFILER_STATUS: profiler_status <= new_value | profiler_status_set;
                    `YFD_MON_ADDR_PROFILER_METRIC_MASK0: profiler_metric_mask0 <= new_value;
                    `YFD_MON_ADDR_PROFILER_ALERT_THRESHOLD0: profiler_alert_threshold0 <= new_value;
                    `YFD_MON_ADDR_LA_CONTROL: la_control <= new_value;
                    `YFD_MON_ADDR_LA_STATUS: la_status <= (new_value | la_status_set) & 32'hFFFFFFF8;
                    `YFD_MON_ADDR_LA_SAMPLE_DIVISOR: la_sample_divisor <= new_value;
                    `YFD_MON_ADDR_LA_CAPTURE_DEPTH: la_capture_depth <= new_value;
                    `YFD_MON_ADDR_LA_PRETRIGGER_DEPTH: la_pretrigger_depth <= new_value;
                    `YFD_MON_ADDR_LA_TRIGGER_MODE: la_trigger_mode <= new_value;
                    `YFD_MON_ADDR_LA_TRIGGER_CHANNEL: la_trigger_channel <= new_value;
                    `YFD_MON_ADDR_LA_TRIGGER_VALUE: la_trigger_value <= new_value;
                    `YFD_MON_ADDR_LA_TRIGGER_MASK: la_trigger_mask <= new_value;
                    `YFD_MON_ADDR_LA_COMMAND: begin
                        la_arm_pulse <= req_wdata[0];
                        la_stop_pulse <= req_wdata[1];
                        la_clear_pulse <= req_wdata[2];
                        la_force_trigger_pulse <= req_wdata[3];
                        la_start_readout_pulse <= req_wdata[4];
                    end
                    `YFD_MON_ADDR_LA_CHANNEL_MASK: la_channel_mask <= new_value;
                    default: begin end
                endcase
            end
        end
    end
end

endmodule
