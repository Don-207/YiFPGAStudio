`timescale 1ns / 1ps

module yifpga_debug_top #(
    parameter CLK_FREQ_HZ = 50000000,
    parameter UART_BAUD   = 115200,
    parameter BUFFER_ADDR_WIDTH = 4,
    parameter MONITOR_DEFAULT_DEMO_PERIOD = CLK_FREQ_HZ / 10,
    parameter ENABLE_UART = 1
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        uart_rx,

    input  wire        heartbeat_valid,
    input  wire        status_valid,

    input  wire        event_valid,
    input  wire [15:0] event_id,
    input  wire [7:0]  event_level,
    input  wire [31:0] event_arg0,

    input  wire        watch_valid,
    input  wire [15:0] watch_id,
    input  wire [31:0] watch_value,

    input  wire        print_valid,
    input  wire [15:0] print_id,
    input  wire [31:0] print_arg0,
    input  wire [31:0] print_arg1,

    input  wire        trace_span_begin_valid,
    input  wire [15:0] trace_span_begin_trace_id,
    input  wire [15:0] trace_span_begin_instance_id,
    input  wire [31:0] trace_span_begin_arg0,

    input  wire        trace_span_end_valid,
    input  wire [15:0] trace_span_end_trace_id,
    input  wire [15:0] trace_span_end_instance_id,
    input  wire [7:0]  trace_span_end_status,
    input  wire [31:0] trace_span_end_arg0,

    input  wire        trace_mark_valid,
    input  wire [15:0] trace_mark_trace_id,
    input  wire [7:0]  trace_mark_level,
    input  wire [31:0] trace_mark_arg0,

    input  wire        trace_value_valid,
    input  wire [15:0] trace_value_trace_id,
    input  wire [15:0] trace_value_id,
    input  wire [31:0] trace_value_data,

    input  wire        trace_drop_valid,
    input  wire [15:0] trace_drop_trace_id,
    input  wire [31:0] trace_drop_count,

    input  wire [31:0] monitor_counter0,
    output wire [31:0] monitor_control,
    output wire [31:0] monitor_led_control,
    output wire [31:0] monitor_demo_period,
    output wire [31:0] monitor_error_status,
    output wire        monitor_clear_counters_pulse,
    input  wire [31:0] profiler_status_set,
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
    output wire        la_start_readout_pulse,
    input  wire        profiler_msg_valid,
    input  wire [7:0]  profiler_msg_type,
    input  wire [7:0]  profiler_msg_len,
    input  wire [255:0] profiler_msg_payload,
    output wire        profiler_msg_ready,
    input  wire        la_msg_valid,
    input  wire [7:0]  la_msg_type,
    input  wire [7:0]  la_msg_len,
    input  wire [255:0] la_msg_payload,
    output wire        la_msg_ready,

    output wire        uart_tx,
    output wire        transport_byte_valid,
    output wire [7:0]  transport_byte_data,
    input  wire        transport_byte_ready,
    output wire        busy,
    output wire [15:0] buffer_used,
    output wire [15:0] drop_count,
    output wire [15:0] packet_count,
    output wire        la_probe_uart_rx_valid,
    output wire        la_probe_monitor_resp_valid
);

wire monitor_byte_valid;
wire [7:0] monitor_byte_data;
wire monitor_uart_frame_error;
wire monitor_req_valid;
wire monitor_req_ready;
wire [15:0] monitor_req_seq;
wire [15:0] monitor_req_addr;
wire monitor_req_write;
wire [7:0] monitor_req_width;
wire [31:0] monitor_req_wdata;
wire [31:0] monitor_req_wmask;
wire monitor_resp_valid;
wire monitor_resp_ready;
wire [15:0] monitor_resp_seq;
wire [15:0] monitor_resp_addr;
wire monitor_resp_write;
wire [7:0] monitor_resp_width;
wire [7:0] monitor_resp_status;
wire [31:0] monitor_resp_rdata;
wire [31:0] monitor_resp_old_value;
wire [31:0] monitor_resp_new_value;
wire monitor_msg_valid;
wire monitor_msg_ready;
wire [7:0] monitor_msg_type;
wire [7:0] monitor_msg_len;
wire [255:0] monitor_msg_payload;
wire monitor_checksum_error;
wire monitor_bad_len_error;
wire monitor_unsupported_error;
wire [2:0] monitor_parser_state;
(* keep = "true" *) wire monitor_ila_clk;
(* mark_debug = "true", keep = "true" *) wire [63:0] monitor_ila_probe;
reg [31:0] monitor_timestamp = 32'd0;

assign monitor_ila_clk = clk;
assign la_probe_uart_rx_valid = monitor_byte_valid;
assign la_probe_monitor_resp_valid = monitor_resp_valid;

assign monitor_ila_probe = {
    1'b0,
    busy,
    monitor_msg_ready,
    monitor_msg_valid,
    monitor_resp_ready,
    monitor_resp_valid,
    monitor_req_ready,
    monitor_req_valid,
    monitor_unsupported_error,
    monitor_bad_len_error,
    monitor_checksum_error,
    monitor_uart_frame_error,
    monitor_byte_valid,
    uart_rx,
    monitor_parser_state,
    monitor_msg_type,
    monitor_resp_status,
    monitor_req_width,
    monitor_byte_data,
    monitor_req_write,
    monitor_req_seq[7:0],
    buffer_used[5:0]
};

always @(posedge clk) begin
    if (rst) begin
        monitor_timestamp <= 32'd0;
    end else begin
        monitor_timestamp <= monitor_timestamp + 32'd1;
    end
end

yifpga_debug_uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD(UART_BAUD)
) u_monitor_uart_rx (
    .clk(clk),
    .rst(rst),
    .rx(uart_rx),
    .data_valid(monitor_byte_valid),
    .data(monitor_byte_data),
    .frame_error(monitor_uart_frame_error)
);

yifpga_debug_command_parser u_monitor_command_parser (
    .clk(clk),
    .rst(rst),
    .byte_valid(monitor_byte_valid),
    .byte_data(monitor_byte_data),
    .monitor_req_valid(monitor_req_valid),
    .monitor_req_ready(monitor_req_ready),
    .monitor_req_seq(monitor_req_seq),
    .monitor_req_addr(monitor_req_addr),
    .monitor_req_write(monitor_req_write),
    .monitor_req_width(monitor_req_width),
    .monitor_req_wdata(monitor_req_wdata),
    .monitor_req_wmask(monitor_req_wmask),
    .checksum_error(monitor_checksum_error),
    .bad_len_error(monitor_bad_len_error),
    .unsupported_error(monitor_unsupported_error),
    .debug_state(monitor_parser_state)
);

yifpga_monitor_core #(
    .DEFAULT_DEMO_PERIOD(MONITOR_DEFAULT_DEMO_PERIOD)
) u_monitor_core (
    .clk(clk),
    .rst(rst),
    .req_valid(monitor_req_valid),
    .req_ready(monitor_req_ready),
    .req_seq(monitor_req_seq),
    .req_addr(monitor_req_addr),
    .req_write(monitor_req_write),
    .req_width(monitor_req_width),
    .req_wdata(monitor_req_wdata),
    .req_wmask(monitor_req_wmask),
    .resp_valid(monitor_resp_valid),
    .resp_ready(monitor_resp_ready),
    .resp_seq(monitor_resp_seq),
    .resp_addr(monitor_resp_addr),
    .resp_write(monitor_resp_write),
    .resp_width(monitor_resp_width),
    .resp_status(monitor_resp_status),
    .resp_rdata(monitor_resp_rdata),
    .resp_old_value(monitor_resp_old_value),
    .resp_new_value(monitor_resp_new_value),
    .counter0(monitor_counter0),
    .profiler_status_set(profiler_status_set),
    .control(monitor_control),
    .led_control(monitor_led_control),
    .demo_period(monitor_demo_period),
    .error_status(monitor_error_status),
    .clear_counters_pulse(monitor_clear_counters_pulse),
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

yifpga_monitor_adapter u_monitor_adapter (
    .clk(clk),
    .rst(rst),
    .timestamp(monitor_timestamp),
    .resp_valid(monitor_resp_valid),
    .resp_ready(monitor_resp_ready),
    .resp_seq(monitor_resp_seq),
    .resp_addr(monitor_resp_addr),
    .resp_write(monitor_resp_write),
    .resp_width(monitor_resp_width),
    .resp_status(monitor_resp_status),
    .resp_rdata(monitor_resp_rdata),
    .resp_old_value(monitor_resp_old_value),
    .resp_new_value(monitor_resp_new_value),
    .msg_valid(monitor_msg_valid),
    .msg_ready(monitor_msg_ready),
    .msg_type(monitor_msg_type),
    .payload_len(monitor_msg_len),
    .payload_flat(monitor_msg_payload)
);

yifpga_debug_core #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .UART_BAUD(UART_BAUD),
    .BUFFER_ADDR_WIDTH(BUFFER_ADDR_WIDTH),
    .ENABLE_UART(ENABLE_UART)
) u_debug_core (
    .clk(clk),
    .rst(rst),
    .heartbeat_valid(heartbeat_valid),
    .status_valid(status_valid),
    .event_valid(event_valid),
    .event_id(event_id),
    .event_level(event_level),
    .event_arg0(event_arg0),
    .watch_valid(watch_valid),
    .watch_id(watch_id),
    .watch_value(watch_value),
    .print_valid(print_valid),
    .print_id(print_id),
    .print_arg0(print_arg0),
    .print_arg1(print_arg1),
    .trace_span_begin_valid(trace_span_begin_valid),
    .trace_span_begin_trace_id(trace_span_begin_trace_id),
    .trace_span_begin_instance_id(trace_span_begin_instance_id),
    .trace_span_begin_arg0(trace_span_begin_arg0),
    .trace_span_end_valid(trace_span_end_valid),
    .trace_span_end_trace_id(trace_span_end_trace_id),
    .trace_span_end_instance_id(trace_span_end_instance_id),
    .trace_span_end_status(trace_span_end_status),
    .trace_span_end_arg0(trace_span_end_arg0),
    .trace_mark_valid(trace_mark_valid),
    .trace_mark_trace_id(trace_mark_trace_id),
    .trace_mark_level(trace_mark_level),
    .trace_mark_arg0(trace_mark_arg0),
    .trace_value_valid(trace_value_valid),
    .trace_value_trace_id(trace_value_trace_id),
    .trace_value_id(trace_value_id),
    .trace_value_data(trace_value_data),
    .trace_drop_valid(trace_drop_valid),
    .trace_drop_trace_id(trace_drop_trace_id),
    .trace_drop_count(trace_drop_count),
    .monitor_msg_valid(monitor_msg_valid),
    .monitor_msg_type(monitor_msg_type),
    .monitor_msg_len(monitor_msg_len),
    .monitor_msg_payload(monitor_msg_payload),
    .monitor_msg_ready(monitor_msg_ready),
    .profiler_msg_valid(profiler_msg_valid),
    .profiler_msg_type(profiler_msg_type),
    .profiler_msg_len(profiler_msg_len),
    .profiler_msg_payload(profiler_msg_payload),
    .profiler_msg_ready(profiler_msg_ready),
    .la_msg_valid(la_msg_valid),
    .la_msg_type(la_msg_type),
    .la_msg_len(la_msg_len),
    .la_msg_payload(la_msg_payload),
    .la_msg_ready(la_msg_ready),
    .uart_tx(uart_tx),
    .transport_byte_valid(transport_byte_valid),
    .transport_byte_data(transport_byte_data),
    .transport_byte_ready(transport_byte_ready),
    .busy(busy),
    .buffer_used(buffer_used),
    .drop_count(drop_count),
    .packet_count(packet_count)
);

endmodule
