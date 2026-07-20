`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_trace_pkg.vh"
`include "yifpga_monitor_pkg.vh"
`include "yifpga_profiler_pkg.vh"
`include "yifpga_la_pkg.vh"

module yifpga_debug_board_demo #(
    parameter CLK_FREQ_HZ = 100000000,
    parameter UART_BAUD = 115200,
    parameter BUFFER_ADDR_WIDTH = 6,
    parameter HEARTBEAT_INTERVAL_TICKS = CLK_FREQ_HZ,
    parameter EVENT_INTERVAL_TICKS = CLK_FREQ_HZ / 10,
    parameter WATCH_INTERVAL_TICKS = CLK_FREQ_HZ / 20,
    parameter PRINT_INTERVAL_TICKS = CLK_FREQ_HZ / 5,
    parameter STATUS_INTERVAL_TICKS = CLK_FREQ_HZ / 10,
    parameter TRACE_SCENARIO_INTERVAL_TICKS = (CLK_FREQ_HZ / 200) + 17,
    parameter LED_HOLD_TICKS = CLK_FREQ_HZ / 20,
    parameter ENABLE_UART = 1,
    parameter ENABLE_JTAG = 1,
    parameter JTAG_PERF_MODE = 0,
    parameter JTAG_PERF_BYTE_INTERVAL_TICKS = 50
) (
    input  wire       clk_p,
    input  wire       clk_n,
    input  wire       reset_n,
    input  wire       demo_trigger,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire       led0,
    output wire       led1
);

`ifdef YIFPGA_DEBUG_SIM
wire clk = clk_p;
`else
wire clk;

IBUFDS u_sys_clk_ibufds (
    .I(clk_p),
    .IB(clk_n),
    .O(clk)
);
`endif

wire rst = ~reset_n;

reg heartbeat_valid = 1'b0;
reg status_valid = 1'b0;
reg event_valid = 1'b0;
reg watch_valid = 1'b0;
reg print_valid = 1'b0;

reg pending_heartbeat = 1'b0;
reg pending_status = 1'b0;
reg pending_event = 1'b0;
reg pending_watch = 1'b0;
reg pending_print = 1'b0;

reg [31:0] heartbeat_counter = 32'd0;
reg [31:0] status_counter = 32'd0;
reg [31:0] event_counter = 32'd0;
reg [31:0] watch_counter = 32'd0;
reg [31:0] print_counter = 32'd0;
reg [31:0] watch_value = 32'd0;
reg [31:0] event_sequence = 32'd0;
reg [31:0] print_sequence = 32'd0;
reg [31:0] heartbeat_led_counter = 32'd0;
reg [31:0] event_led_counter = 32'd0;
reg        trigger_d = 1'b0;
reg [31:0] trace_counter = 32'd0;
reg [3:0]  trace_step = 4'd0;
reg [15:0] trace_frame_id = 16'd1;
reg [15:0] trace_dma_desc_id = 16'd1;
reg [31:0] trace_fifo_level = 32'd0;
reg        dma_start_valid = 1'b0;
reg        dma_done_valid = 1'b0;
reg        dma_error_valid = 1'b0;
reg        dma_timeout_valid = 1'b0;
reg        frame_start_valid = 1'b0;
reg        frame_end_valid = 1'b0;
reg        frame_drop_valid = 1'b0;
reg        fifo_sample_valid = 1'b0;
reg        fifo_almost_full = 1'b0;
reg        fifo_overflow_valid = 1'b0;
reg        irq_level = 1'b0;
reg        profiler_axis_valid = 1'b0;
reg        profiler_axis_ready = 1'b0;
reg [3:0]  profiler_axis_keep = 4'h0;
reg        profiler_axis_last = 1'b0;
reg        profiler_fifo_wr_en = 1'b0;
reg        profiler_fifo_rd_en = 1'b0;
reg        profiler_fifo_underflow = 1'b0;

wire busy;
wire [15:0] buffer_used;
wire [15:0] drop_count;
wire [15:0] packet_count;
wire [31:0] monitor_control;
wire [31:0] monitor_led_control;
wire [31:0] monitor_demo_period;
wire [31:0] monitor_error_status;
wire monitor_clear_counters_pulse;
wire [31:0] profiler_control;
wire [31:0] profiler_sample_period;
wire profiler_clear_pulse;
wire [31:0] profiler_status;
wire [31:0] profiler_metric_mask0;
wire [31:0] profiler_alert_threshold0;
wire [31:0] la_control;
wire [31:0] la_status;
wire [31:0] la_sample_divisor;
wire [31:0] la_capture_depth;
wire [31:0] la_pretrigger_depth;
wire [31:0] la_trigger_mode;
wire [31:0] la_trigger_channel;
wire [31:0] la_trigger_value;
wire [31:0] la_trigger_mask;
wire [31:0] la_channel_mask;
wire la_arm_pulse;
wire la_stop_pulse;
wire la_clear_pulse;
wire la_force_trigger_pulse;
wire la_start_readout_pulse;
wire [31:0] la_status_set;
wire [31:0] la_sample_bus_raw;
wire [31:0] la_sample_bus;
wire [2:0] la_core_state;
wire [15:0] la_samples_written;
wire [15:0] la_trigger_index;
wire [31:0] la_capture_id;
wire la_done;
wire la_overflow;
wire la_config_error;
wire [7:0] la_error_code;
wire [15:0] la_capture_flags;
wire [31:0] la_trigger_sample_value;
wire [4:0] la_trigger_hit_channel;
wire la_core_start_readout_pulse;
wire la_core_readout_done_pulse;
wire la_core_read_req;
wire [15:0] la_core_read_index;
wire [31:0] la_core_read_sample;
wire la_core_read_valid;
wire transport_byte_valid;
wire [7:0] transport_byte_data;
wire jtag_transport_ready;
wire [31:0] jtag_overflow_count;
wire [31:0] jtag_dropped_bytes;
wire perf_source_valid;
wire [7:0] perf_source_data;
wire jtag_input_valid = ENABLE_JTAG && (JTAG_PERF_MODE ? perf_source_valid : transport_byte_valid);
wire [7:0] jtag_input_data = JTAG_PERF_MODE ? perf_source_data : transport_byte_data;
localparam [31:0] JTAG_BUILD_ID = JTAG_PERF_MODE ? 32'h4d35_0001 : 32'h4d36_0001;
wire la_msg_valid;
wire la_msg_ready;
wire [7:0] la_msg_type;
wire [7:0] la_msg_len;
wire [255:0] la_msg_payload;
wire la_probe_uart_rx_valid;
wire la_probe_monitor_resp_valid;
wire [31:0] demo_period_ticks = (monitor_demo_period == 32'd0) ? EVENT_INTERVAL_TICKS : monitor_demo_period;
wire profiler_enable = profiler_control[0];
wire profiler_clear_all = profiler_clear_pulse || monitor_clear_counters_pulse;
wire trigger_rise = demo_trigger && !trigger_d;
wire la_readout_busy = la_core_state == `YFD_LA_STATE_READOUT;
wire dma_span_begin_valid;
wire [15:0] dma_span_begin_trace_id;
wire [15:0] dma_span_begin_instance_id;
wire [31:0] dma_span_begin_arg0;
wire dma_span_end_valid;
wire [15:0] dma_span_end_trace_id;
wire [15:0] dma_span_end_instance_id;
wire [7:0] dma_span_end_status;
wire [31:0] dma_span_end_arg0;
wire dma_mark_valid;
wire [15:0] dma_mark_trace_id;
wire [7:0] dma_mark_level;
wire [31:0] dma_mark_arg0;
wire frame_span_begin_valid;
wire [15:0] frame_span_begin_trace_id;
wire [15:0] frame_span_begin_instance_id;
wire [31:0] frame_span_begin_arg0;
wire frame_span_end_valid;
wire [15:0] frame_span_end_trace_id;
wire [15:0] frame_span_end_instance_id;
wire [7:0] frame_span_end_status;
wire [31:0] frame_span_end_arg0;
wire frame_mark_valid;
wire [15:0] frame_mark_trace_id;
wire [7:0] frame_mark_level;
wire [31:0] frame_mark_arg0;
wire fifo_mark_valid;
wire [15:0] fifo_mark_trace_id;
wire [7:0] fifo_mark_level;
wire [31:0] fifo_mark_arg0;
wire fifo_value_valid;
wire [15:0] fifo_value_trace_id;
wire [15:0] fifo_value_id;
wire [31:0] fifo_value_data;
wire irq_mark_valid;
wire [15:0] irq_mark_trace_id;
wire [7:0] irq_mark_level;
wire [31:0] irq_mark_arg0;
wire axis_metric_valid;
wire [15:0] axis_metric_id;
wire [31:0] axis_metric_value0;
wire [31:0] axis_metric_value1;
wire [31:0] axis_metric_value2;
wire [31:0] axis_metric_value3;
wire axis_metric_overflow;
wire fifo_metric_valid;
wire [15:0] fifo_metric_id;
wire [31:0] fifo_metric_value0;
wire [31:0] fifo_metric_value1;
wire [31:0] fifo_metric_value2;
wire [31:0] fifo_metric_value3;
wire fifo_metric_overflow;
wire latency_busy;
wire latency_metric_valid;
wire [15:0] latency_metric_id;
wire [31:0] latency_metric_value0;
wire [31:0] latency_metric_value1;
wire [31:0] latency_metric_value2;
wire [31:0] latency_metric_value3;
wire latency_metric_overflow;
wire frame_metric_valid;
wire [15:0] frame_metric_id;
wire [31:0] frame_metric_value0;
wire [31:0] frame_metric_value1;
wire [31:0] frame_metric_value2;
wire [31:0] frame_metric_value3;
wire frame_metric_overflow;
wire profiler_metric_valid;
wire profiler_metric_ready;
wire [15:0] profiler_metric_id;
wire [31:0] profiler_metric_value0;
wire [31:0] profiler_metric_value1;
wire [31:0] profiler_metric_value2;
wire [31:0] profiler_metric_value3;
wire profiler_metric_overflow;
wire profiler_threshold_hit;
wire profiler_snapshot_valid;
wire profiler_snapshot_ready;
wire [15:0] profiler_snapshot_metric_id;
wire [15:0] profiler_snapshot_flags;
wire [31:0] profiler_snapshot_sample_cycles;
wire [31:0] profiler_snapshot_value0;
wire [31:0] profiler_snapshot_value1;
wire [31:0] profiler_snapshot_value2;
wire [31:0] profiler_snapshot_value3;
wire [15:0] profiler_snapshot_overflow_count;
wire profiler_alert_valid;
wire profiler_alert_ready;
wire [15:0] profiler_alert_metric_id;
wire [7:0] profiler_alert_level;
wire [7:0] profiler_alert_code;
wire [31:0] profiler_alert_arg0;
wire [31:0] profiler_alert_arg1;
wire profiler_msg_valid;
wire profiler_msg_ready;
wire [7:0] profiler_msg_type;
wire [7:0] profiler_msg_len;
wire [255:0] profiler_msg_payload;
wire [31:0] profiler_status_set;
wire [1:0] profiler_metric_select;
reg [3:0] profiler_metric_pending = 4'd0;
reg [31:0] axis_pending_value0 = 32'd0;
reg [31:0] axis_pending_value1 = 32'd0;
reg [31:0] axis_pending_value2 = 32'd0;
reg [31:0] axis_pending_value3 = 32'd0;
reg        axis_pending_overflow = 1'b0;
reg [31:0] fifo_pending_value0 = 32'd0;
reg [31:0] fifo_pending_value1 = 32'd0;
reg [31:0] fifo_pending_value2 = 32'd0;
reg [31:0] fifo_pending_value3 = 32'd0;
reg        fifo_pending_overflow = 1'b0;
reg [31:0] latency_pending_value0 = 32'd0;
reg [31:0] latency_pending_value1 = 32'd0;
reg [31:0] latency_pending_value2 = 32'd0;
reg [31:0] latency_pending_value3 = 32'd0;
reg        latency_pending_overflow = 1'b0;
reg [31:0] frame_pending_value0 = 32'd0;
reg [31:0] frame_pending_value1 = 32'd0;
reg [31:0] frame_pending_value2 = 32'd0;
reg [31:0] frame_pending_value3 = 32'd0;
reg        frame_pending_overflow = 1'b0;
reg [1:0]  profiler_metric_slot = 2'd0;
reg        la_done_d = 1'b0;

wire trace_span_begin_valid = frame_span_begin_valid || dma_span_begin_valid;
wire [15:0] trace_span_begin_trace_id =
    frame_span_begin_valid ? frame_span_begin_trace_id : dma_span_begin_trace_id;
wire [15:0] trace_span_begin_instance_id =
    frame_span_begin_valid ? frame_span_begin_instance_id : dma_span_begin_instance_id;
wire [31:0] trace_span_begin_arg0 =
    frame_span_begin_valid ? frame_span_begin_arg0 : dma_span_begin_arg0;

wire trace_span_end_valid = frame_span_end_valid || dma_span_end_valid;
wire [15:0] trace_span_end_trace_id =
    frame_span_end_valid ? frame_span_end_trace_id : dma_span_end_trace_id;
wire [15:0] trace_span_end_instance_id =
    frame_span_end_valid ? frame_span_end_instance_id : dma_span_end_instance_id;
wire [7:0] trace_span_end_status =
    frame_span_end_valid ? frame_span_end_status : dma_span_end_status;
wire [31:0] trace_span_end_arg0 =
    frame_span_end_valid ? frame_span_end_arg0 : dma_span_end_arg0;

wire trace_mark_valid = fifo_mark_valid || irq_mark_valid || frame_mark_valid || dma_mark_valid;
wire [15:0] trace_mark_trace_id =
    fifo_mark_valid ? fifo_mark_trace_id :
    irq_mark_valid ? irq_mark_trace_id :
    frame_mark_valid ? frame_mark_trace_id : dma_mark_trace_id;
wire [7:0] trace_mark_level =
    fifo_mark_valid ? fifo_mark_level :
    irq_mark_valid ? irq_mark_level :
    frame_mark_valid ? frame_mark_level : dma_mark_level;
wire [31:0] trace_mark_arg0 =
    fifo_mark_valid ? fifo_mark_arg0 :
    irq_mark_valid ? irq_mark_arg0 :
    frame_mark_valid ? frame_mark_arg0 : dma_mark_arg0;

wire trace_value_valid = fifo_value_valid;
wire [15:0] trace_value_trace_id = fifo_value_trace_id;
wire [15:0] trace_value_id = fifo_value_id;
wire [31:0] trace_value_data = fifo_value_data;

assign profiler_metric_valid = profiler_metric_pending[profiler_metric_slot];
assign profiler_metric_select = profiler_metric_slot;
assign profiler_metric_id =
    (profiler_metric_select == 2'd0) ? `YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT :
    (profiler_metric_select == 2'd1) ? `YFD_PROFILER_METRIC_FIFO_DEMO_LEVEL :
    (profiler_metric_select == 2'd2) ? `YFD_PROFILER_METRIC_DEMO_LATENCY :
                                       `YFD_PROFILER_METRIC_FRAME_RATE;
assign profiler_metric_value0 =
    (profiler_metric_select == 2'd0) ? axis_pending_value0 :
    (profiler_metric_select == 2'd1) ? fifo_pending_value0 :
    (profiler_metric_select == 2'd2) ? latency_pending_value0 : frame_pending_value0;
assign profiler_metric_value1 =
    (profiler_metric_select == 2'd0) ? axis_pending_value1 :
    (profiler_metric_select == 2'd1) ? fifo_pending_value1 :
    (profiler_metric_select == 2'd2) ? latency_pending_value1 : frame_pending_value1;
assign profiler_metric_value2 =
    (profiler_metric_select == 2'd0) ? axis_pending_value2 :
    (profiler_metric_select == 2'd1) ? fifo_pending_value2 :
    (profiler_metric_select == 2'd2) ? latency_pending_value2 : frame_pending_value2;
assign profiler_metric_value3 =
    (profiler_metric_select == 2'd0) ? axis_pending_value3 :
    (profiler_metric_select == 2'd1) ? fifo_pending_value3 :
    (profiler_metric_select == 2'd2) ? latency_pending_value3 : frame_pending_value3;
assign profiler_threshold_hit =
    (profiler_alert_threshold0 != 32'd0) &&
    (((profiler_metric_select == 2'd1) && (fifo_pending_value0 >= profiler_alert_threshold0)) ||
     ((profiler_metric_select == 2'd2) && (latency_pending_value2 >= profiler_alert_threshold0)));
assign profiler_metric_overflow =
    ((profiler_metric_select == 2'd0) && axis_pending_overflow) ||
    ((profiler_metric_select == 2'd1) && fifo_pending_overflow) ||
    ((profiler_metric_select == 2'd2) && latency_pending_overflow) ||
    ((profiler_metric_select == 2'd3) && frame_pending_overflow) ||
    profiler_threshold_hit;
assign profiler_status_set = {
    29'd0,
    profiler_msg_valid && !profiler_msg_ready,
    (drop_count != 16'd0),
    profiler_snapshot_valid && profiler_snapshot_ready && (profiler_snapshot_overflow_count != 16'd0)
};
assign la_sample_bus_raw = {
    5'd0,
    la_readout_busy,
    la_config_error,
    la_overflow,
    la_core_state,
    trace_fifo_level[7:0],
    buffer_used[7:0],
    frame_start_valid,
    profiler_snapshot_valid,
    la_probe_monitor_resp_valid,
    trace_span_begin_valid || trace_span_end_valid || trace_mark_valid || trace_value_valid,
    profiler_msg_valid || event_valid || watch_valid || print_valid || heartbeat_valid || status_valid,
    !busy,
    la_probe_uart_rx_valid,
    busy
};
assign la_status_set = {
    16'd0,
    la_error_code,
    la_msg_valid && !la_msg_ready,
    la_readout_busy,
    la_config_error,
    la_overflow,
    la_done,
    la_core_state
};

yifpga_la_probe_pack u_la_probe_pack (
    .probe_bits(la_sample_bus_raw & la_channel_mask),
    .sample_bus(la_sample_bus)
);

yifpga_la_core #(
    .SAMPLE_WIDTH(32),
    .SAMPLE_DEPTH(`YFD_LA_MAX_SAMPLE_DEPTH)
) u_la_core (
    .clk(clk),
    .rst(rst),
    .enable(la_control[0]),
    .arm_pulse(la_arm_pulse),
    .stop_pulse(la_stop_pulse),
    .clear_pulse(la_clear_pulse),
    .force_trigger_pulse(la_force_trigger_pulse),
    .start_readout_pulse(la_core_start_readout_pulse),
    .readout_done_pulse(la_core_readout_done_pulse),
    .sample_divisor(la_sample_divisor[15:0]),
    .capture_depth(la_capture_depth[15:0]),
    .pretrigger_depth(la_pretrigger_depth[15:0]),
    .trigger_mode(la_control[2] ? la_trigger_mode[3:0] : `YFD_LA_TRIGGER_DISABLED),
    .trigger_channel(la_trigger_channel[4:0]),
    .trigger_value(la_trigger_value),
    .trigger_mask(la_trigger_mask),
    .sample_bus(la_sample_bus),
    .state(la_core_state),
    .samples_written(la_samples_written),
    .trigger_index(la_trigger_index),
    .capture_id(la_capture_id),
    .done(la_done),
    .overflow(la_overflow),
    .config_error(la_config_error),
    .error_code(la_error_code),
    .capture_flags(la_capture_flags),
    .trigger_sample_value(la_trigger_sample_value),
    .trigger_hit_channel(la_trigger_hit_channel),
    .read_req(la_core_read_req),
    .read_index(la_core_read_index),
    .read_sample(la_core_read_sample),
    .read_valid(la_core_read_valid)
);

yifpga_la_adapter u_la_adapter (
    .clk(clk),
    .rst(rst),
    .timestamp(watch_value),
    .start_readout_pulse(la_start_readout_pulse || (la_control[1] && la_done && !la_done_d)),
    .core_start_readout_pulse(la_core_start_readout_pulse),
    .core_readout_done_pulse(la_core_readout_done_pulse),
    .core_state(la_core_state),
    .core_error_code(la_error_code),
    .core_samples_written(la_samples_written),
    .core_trigger_index(la_trigger_index),
    .core_capture_id(la_capture_id),
    .core_capture_flags(la_capture_flags),
    .core_sample_period_cycles({16'd0, la_sample_divisor[15:0]}),
    .core_trigger_channel(la_trigger_hit_channel),
    .core_trigger_sample_value(la_trigger_sample_value),
    .core_trigger_value(la_trigger_value),
    .core_read_req(la_core_read_req),
    .core_read_index(la_core_read_index),
    .core_read_sample(la_core_read_sample),
    .core_read_valid(la_core_read_valid),
    .msg_valid(la_msg_valid),
    .msg_ready(la_msg_ready),
    .msg_type(la_msg_type),
    .payload_len(la_msg_len),
    .payload_flat(la_msg_payload)
);

yifpga_trace_dma_probe u_dma_trace_probe (
    .clk(clk),
    .rst(rst),
    .start_valid(dma_start_valid),
    .done_valid(dma_done_valid),
    .error_valid(dma_error_valid),
    .timeout_valid(dma_timeout_valid),
    .desc_id(trace_dma_desc_id),
    .arg0(trace_fifo_level),
    .span_begin_valid(dma_span_begin_valid),
    .span_begin_trace_id(dma_span_begin_trace_id),
    .span_begin_instance_id(dma_span_begin_instance_id),
    .span_begin_arg0(dma_span_begin_arg0),
    .span_end_valid(dma_span_end_valid),
    .span_end_trace_id(dma_span_end_trace_id),
    .span_end_instance_id(dma_span_end_instance_id),
    .span_end_status(dma_span_end_status),
    .span_end_arg0(dma_span_end_arg0),
    .mark_valid(dma_mark_valid),
    .mark_trace_id(dma_mark_trace_id),
    .mark_level(dma_mark_level),
    .mark_arg0(dma_mark_arg0)
);

yifpga_trace_frame_probe u_frame_trace_probe (
    .clk(clk),
    .rst(rst),
    .frame_start_valid(frame_start_valid),
    .frame_end_valid(frame_end_valid),
    .frame_drop_valid(frame_drop_valid),
    .frame_id(trace_frame_id),
    .arg0(trace_fifo_level),
    .span_begin_valid(frame_span_begin_valid),
    .span_begin_trace_id(frame_span_begin_trace_id),
    .span_begin_instance_id(frame_span_begin_instance_id),
    .span_begin_arg0(frame_span_begin_arg0),
    .span_end_valid(frame_span_end_valid),
    .span_end_trace_id(frame_span_end_trace_id),
    .span_end_instance_id(frame_span_end_instance_id),
    .span_end_status(frame_span_end_status),
    .span_end_arg0(frame_span_end_arg0),
    .mark_valid(frame_mark_valid),
    .mark_trace_id(frame_mark_trace_id),
    .mark_level(frame_mark_level),
    .mark_arg0(frame_mark_arg0)
);

yifpga_trace_fifo_probe u_fifo_trace_probe (
    .clk(clk),
    .rst(rst),
    .sample_valid(fifo_sample_valid),
    .almost_full(fifo_almost_full),
    .overflow_valid(fifo_overflow_valid),
    .level(trace_fifo_level),
    .mark_valid(fifo_mark_valid),
    .mark_trace_id(fifo_mark_trace_id),
    .mark_level(fifo_mark_level),
    .mark_arg0(fifo_mark_arg0),
    .value_valid(fifo_value_valid),
    .value_trace_id(fifo_value_trace_id),
    .value_id(fifo_value_id),
    .value_data(fifo_value_data)
);

yifpga_trace_irq_probe u_irq_trace_probe (
    .clk(clk),
    .rst(rst),
    .irq_level(irq_level),
    .irq_arg0({16'd0, trace_dma_desc_id}),
    .mark_valid(irq_mark_valid),
    .mark_trace_id(irq_mark_trace_id),
    .mark_level(irq_mark_level),
    .mark_arg0(irq_mark_arg0)
);

yifpga_profiler_axis_probe #(
    .DATA_WIDTH(32),
    .STALL_MODE(2)
) u_axis_profiler_probe (
    .clk(clk),
    .rst(rst),
    .clear(profiler_clear_all),
    .enable(profiler_enable && (fifo_sample_valid || fifo_almost_full || fifo_overflow_valid || profiler_fifo_underflow)),
    .axis_valid(profiler_axis_valid),
    .axis_ready(profiler_axis_ready),
    .axis_keep(profiler_axis_keep),
    .axis_last(profiler_axis_last),
    .metric_valid(axis_metric_valid),
    .metric_id(axis_metric_id),
    .metric_value0(axis_metric_value0),
    .metric_value1(axis_metric_value1),
    .metric_value2(axis_metric_value2),
    .metric_value3(axis_metric_value3),
    .metric_overflow(axis_metric_overflow)
);

yifpga_profiler_fifo_probe #(
    .LEVEL_WIDTH(16)
) u_fifo_profiler_probe (
    .clk(clk),
    .rst(rst),
    .clear(profiler_clear_all),
    .enable(profiler_enable),
    .fifo_level(trace_fifo_level[15:0]),
    .fifo_wr_en(profiler_fifo_wr_en),
    .fifo_rd_en(profiler_fifo_rd_en),
    .fifo_full(fifo_almost_full),
    .fifo_empty(trace_fifo_level == 32'd0),
    .fifo_overflow(fifo_overflow_valid),
    .fifo_underflow(profiler_fifo_underflow),
    .metric_valid(fifo_metric_valid),
    .metric_id(fifo_metric_id),
    .metric_value0(fifo_metric_value0),
    .metric_value1(fifo_metric_value1),
    .metric_value2(fifo_metric_value2),
    .metric_value3(fifo_metric_value3),
    .metric_overflow(fifo_metric_overflow)
);

yifpga_profiler_latency #(
    .TIMEOUT_CYCLES(CLK_FREQ_HZ / 20)
) u_latency_profiler_probe (
    .clk(clk),
    .rst(rst),
    .clear(profiler_clear_all),
    .enable(profiler_enable),
    .start_valid(dma_start_valid),
    .end_valid(dma_done_valid),
    .timeout_clear(dma_timeout_valid),
    .busy(latency_busy),
    .metric_valid(latency_metric_valid),
    .metric_id(latency_metric_id),
    .metric_value0(latency_metric_value0),
    .metric_value1(latency_metric_value1),
    .metric_value2(latency_metric_value2),
    .metric_value3(latency_metric_value3),
    .metric_overflow(latency_metric_overflow)
);

yifpga_profiler_frame_probe u_frame_profiler_probe (
    .clk(clk),
    .rst(rst),
    .clear(profiler_clear_all),
    .enable(profiler_enable),
    .frame_start(frame_start_valid),
    .frame_done(frame_end_valid),
    .frame_drop(frame_drop_valid),
    .frame_error(dma_error_valid),
    .metric_valid(frame_metric_valid),
    .metric_id(frame_metric_id),
    .metric_value0(frame_metric_value0),
    .metric_value1(frame_metric_value1),
    .metric_value2(frame_metric_value2),
    .metric_value3(frame_metric_value3),
    .metric_overflow(frame_metric_overflow)
);

yifpga_profiler_core #(
    .DEFAULT_SAMPLE_PERIOD(`YFD_PROFILER_DEFAULT_SAMPLE_PERIOD)
) u_profiler_core (
    .clk(clk),
    .rst(rst),
    .enable(profiler_enable),
    .clear_pulse(profiler_clear_all),
    .sample_period(profiler_sample_period),
    .metric_mask(profiler_metric_mask0),
    .metric_valid(profiler_metric_valid),
    .metric_ready(profiler_metric_ready),
    .metric_id(profiler_metric_id),
    .metric_value0(profiler_metric_value0),
    .metric_value1(profiler_metric_value1),
    .metric_value2(profiler_metric_value2),
    .metric_value3(profiler_metric_value3),
    .metric_overflow(profiler_metric_overflow),
    .snapshot_valid(profiler_snapshot_valid),
    .snapshot_ready(profiler_snapshot_ready),
    .snapshot_metric_id(profiler_snapshot_metric_id),
    .snapshot_flags(profiler_snapshot_flags),
    .snapshot_sample_cycles(profiler_snapshot_sample_cycles),
    .snapshot_value0(profiler_snapshot_value0),
    .snapshot_value1(profiler_snapshot_value1),
    .snapshot_value2(profiler_snapshot_value2),
    .snapshot_value3(profiler_snapshot_value3),
    .snapshot_overflow_count(profiler_snapshot_overflow_count),
    .alert_valid(profiler_alert_valid),
    .alert_ready(profiler_alert_ready),
    .alert_metric_id(profiler_alert_metric_id),
    .alert_level(profiler_alert_level),
    .alert_code(profiler_alert_code),
    .alert_arg0(profiler_alert_arg0),
    .alert_arg1(profiler_alert_arg1)
);

yifpga_profiler_adapter u_profiler_adapter (
    .clk(clk),
    .rst(rst),
    .timestamp(watch_value),
    .snapshot_valid(profiler_snapshot_valid),
    .snapshot_ready(profiler_snapshot_ready),
    .snapshot_metric_id(profiler_snapshot_metric_id),
    .snapshot_flags(profiler_snapshot_flags),
    .snapshot_sample_cycles(profiler_snapshot_sample_cycles),
    .snapshot_value0(profiler_snapshot_value0),
    .snapshot_value1(profiler_snapshot_value1),
    .snapshot_value2(profiler_snapshot_value2),
    .snapshot_value3(profiler_snapshot_value3),
    .snapshot_overflow_count(profiler_snapshot_overflow_count),
    .alert_valid(profiler_alert_valid),
    .alert_ready(profiler_alert_ready),
    .alert_metric_id(profiler_alert_metric_id),
    .alert_level(profiler_alert_level),
    .alert_code(profiler_alert_code),
    .alert_arg0(profiler_alert_arg0),
    .alert_arg1(profiler_alert_arg1),
    .msg_valid(profiler_msg_valid),
    .msg_ready(profiler_msg_ready),
    .msg_type(profiler_msg_type),
    .payload_len(profiler_msg_len),
    .payload_flat(profiler_msg_payload)
);

yifpga_debug_top #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .UART_BAUD(UART_BAUD),
    .BUFFER_ADDR_WIDTH(BUFFER_ADDR_WIDTH),
    .MONITOR_DEFAULT_DEMO_PERIOD(EVENT_INTERVAL_TICKS),
    .ENABLE_UART(ENABLE_UART)
) u_debug_top (
    .clk(clk),
    .rst(rst),
    .uart_rx(uart_rx),
    .heartbeat_valid(heartbeat_valid),
    .status_valid(status_valid),
    .event_valid(event_valid),
    .event_id(16'h1001),
    .event_level(`YFD_LEVEL_INFO),
    .event_arg0(event_sequence),
    .watch_valid(watch_valid),
    .watch_id(16'h2001),
    .watch_value(watch_value),
    .print_valid(print_valid),
    .print_id(16'h3001),
    .print_arg0(print_sequence),
    .print_arg1({16'hCAFE, buffer_used}),
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
    .trace_drop_valid(1'b0),
    .trace_drop_trace_id(`YFD_TRACE_ID_GLOBAL),
    .trace_drop_count(32'd0),
    .monitor_counter0(watch_value),
    .monitor_control(monitor_control),
    .monitor_led_control(monitor_led_control),
    .monitor_demo_period(monitor_demo_period),
    .monitor_error_status(monitor_error_status),
    .monitor_clear_counters_pulse(monitor_clear_counters_pulse),
    .profiler_status_set(profiler_status_set),
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
    .la_start_readout_pulse(la_start_readout_pulse),
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
    .transport_byte_ready(jtag_transport_ready),
    .busy(busy),
    .buffer_used(buffer_used),
    .drop_count(drop_count),
    .packet_count(packet_count),
    .la_probe_uart_rx_valid(la_probe_uart_rx_valid),
    .la_probe_monitor_resp_valid(la_probe_monitor_resp_valid)
);

`ifndef YIFPGA_DEBUG_SIM
generate if (ENABLE_JTAG) begin : g_jtag_transport
yifpga_jtag_perf_source #(
    .BYTE_INTERVAL_TICKS(JTAG_PERF_BYTE_INTERVAL_TICKS)
) u_jtag_perf_source (
    .clk(clk), .rst_n(~rst), .data(perf_source_data), .valid(perf_source_valid),
    .ready(jtag_transport_ready)
);

yifpga_jtag_transport_xilinx #(
    .ADDR_WIDTH(12), .USER_CHAIN(2), .BUILD_ID(JTAG_BUILD_ID)
) u_jtag_transport (
    .debug_clk(clk), .debug_rst_n(~rst),
    .debug_data(jtag_input_data), .debug_valid(jtag_input_valid),
    .debug_ready(jtag_transport_ready), .session_id(32'h0000_0001),
    .overflow_count(jtag_overflow_count), .dropped_bytes(jtag_dropped_bytes)
);
end else begin : g_no_jtag_transport
    assign perf_source_valid = 1'b0;
    assign perf_source_data = 8'h00;
    assign jtag_transport_ready = 1'b1;
    assign jtag_overflow_count = 32'd0;
    assign jtag_dropped_bytes = 32'd0;
end endgenerate
`endif

assign led0 = monitor_led_control[0] || (heartbeat_led_counter != 32'd0);
assign led1 = monitor_led_control[1] || (drop_count != 16'd0) || (event_led_counter != 32'd0);

always @(posedge clk) begin
    if (rst) begin
        la_done_d <= 1'b0;
    end else begin
        la_done_d <= la_done;
    end
end

always @(posedge clk) begin
    if (rst || profiler_clear_all) begin
        profiler_metric_slot <= 2'd0;
        profiler_metric_pending <= 4'd0;
        axis_pending_value0 <= 32'd0;
        axis_pending_value1 <= 32'd0;
        axis_pending_value2 <= 32'd0;
        axis_pending_value3 <= 32'd0;
        axis_pending_overflow <= 1'b0;
        fifo_pending_value0 <= 32'd0;
        fifo_pending_value1 <= 32'd0;
        fifo_pending_value2 <= 32'd0;
        fifo_pending_value3 <= 32'd0;
        fifo_pending_overflow <= 1'b0;
        latency_pending_value0 <= 32'd0;
        latency_pending_value1 <= 32'd0;
        latency_pending_value2 <= 32'd0;
        latency_pending_value3 <= 32'd0;
        latency_pending_overflow <= 1'b0;
        frame_pending_value0 <= 32'd0;
        frame_pending_value1 <= 32'd0;
        frame_pending_value2 <= 32'd0;
        frame_pending_value3 <= 32'd0;
        frame_pending_overflow <= 1'b0;
    end else begin
        if (profiler_snapshot_valid && profiler_snapshot_ready) begin
            profiler_metric_slot <= profiler_metric_slot + 2'd1;
        end

        if (profiler_metric_valid && profiler_metric_ready) begin
            profiler_metric_pending[profiler_metric_select] <= 1'b0;
        end

        if (axis_metric_valid) begin
            profiler_metric_pending[0] <= 1'b1;
            axis_pending_value0 <= axis_metric_value0;
            axis_pending_value1 <= axis_metric_value1;
            axis_pending_value2 <= axis_metric_value2;
            axis_pending_value3 <= axis_metric_value3;
            axis_pending_overflow <= axis_metric_overflow;
        end
        if (fifo_metric_valid) begin
            profiler_metric_pending[1] <= 1'b1;
            fifo_pending_value0 <= fifo_metric_value0;
            fifo_pending_value1 <= fifo_metric_value1;
            fifo_pending_value2 <= fifo_metric_value2;
            fifo_pending_value3 <= fifo_metric_value3;
            fifo_pending_overflow <= fifo_metric_overflow;
        end
        if (latency_metric_valid) begin
            profiler_metric_pending[2] <= 1'b1;
            latency_pending_value0 <= latency_metric_value0;
            latency_pending_value1 <= latency_metric_value1;
            latency_pending_value2 <= latency_metric_value2;
            latency_pending_value3 <= latency_metric_value3;
            latency_pending_overflow <= latency_metric_overflow;
        end
        if (frame_metric_valid) begin
            profiler_metric_pending[3] <= 1'b1;
            frame_pending_value0 <= frame_metric_value0;
            frame_pending_value1 <= frame_metric_value1;
            frame_pending_value2 <= frame_metric_value2;
            frame_pending_value3 <= frame_metric_value3;
            frame_pending_overflow <= frame_metric_overflow;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        heartbeat_valid <= 1'b0;
        status_valid <= 1'b0;
        event_valid <= 1'b0;
        watch_valid <= 1'b0;
        print_valid <= 1'b0;
        pending_heartbeat <= 1'b1;
        pending_status <= 1'b1;
        pending_event <= 1'b1;
        pending_watch <= 1'b1;
        pending_print <= 1'b1;
        heartbeat_counter <= 32'd0;
        status_counter <= 32'd0;
        event_counter <= 32'd0;
        watch_counter <= 32'd0;
        print_counter <= 32'd0;
        watch_value <= 32'd0;
        event_sequence <= 32'd0;
        print_sequence <= 32'd0;
        heartbeat_led_counter <= 32'd0;
        event_led_counter <= 32'd0;
        trigger_d <= 1'b0;
        trace_counter <= 32'd0;
        trace_step <= 4'd0;
        trace_frame_id <= 16'd1;
        trace_dma_desc_id <= 16'd1;
        trace_fifo_level <= 32'd0;
        dma_start_valid <= 1'b0;
        dma_done_valid <= 1'b0;
        dma_error_valid <= 1'b0;
        dma_timeout_valid <= 1'b0;
        frame_start_valid <= 1'b0;
        frame_end_valid <= 1'b0;
        frame_drop_valid <= 1'b0;
        fifo_sample_valid <= 1'b0;
        fifo_almost_full <= 1'b0;
        fifo_overflow_valid <= 1'b0;
        irq_level <= 1'b0;
        profiler_axis_valid <= 1'b0;
        profiler_axis_ready <= 1'b0;
        profiler_axis_keep <= 4'h0;
        profiler_axis_last <= 1'b0;
        profiler_fifo_wr_en <= 1'b0;
        profiler_fifo_rd_en <= 1'b0;
        profiler_fifo_underflow <= 1'b0;
    end else begin
        heartbeat_valid <= 1'b0;
        status_valid <= 1'b0;
        event_valid <= 1'b0;
        watch_valid <= 1'b0;
        print_valid <= 1'b0;
        dma_start_valid <= 1'b0;
        dma_done_valid <= 1'b0;
        dma_error_valid <= 1'b0;
        dma_timeout_valid <= 1'b0;
        frame_start_valid <= 1'b0;
        frame_end_valid <= 1'b0;
        frame_drop_valid <= 1'b0;
        fifo_sample_valid <= 1'b0;
        fifo_overflow_valid <= 1'b0;
        profiler_axis_valid <= 1'b0;
        profiler_axis_ready <= 1'b0;
        profiler_axis_keep <= 4'h0;
        profiler_axis_last <= 1'b0;
        profiler_fifo_wr_en <= 1'b0;
        profiler_fifo_rd_en <= 1'b0;
        profiler_fifo_underflow <= 1'b0;
        trigger_d <= demo_trigger;
        watch_value <= watch_value + 32'd1;

        if (monitor_clear_counters_pulse) begin
            heartbeat_counter <= 32'd0;
            status_counter <= 32'd0;
            event_counter <= 32'd0;
            watch_counter <= 32'd0;
            print_counter <= 32'd0;
            watch_value <= 32'd0;
            event_sequence <= 32'd0;
            print_sequence <= 32'd0;
            trace_counter <= 32'd0;
            trace_step <= 4'd0;
        end

        if (heartbeat_counter >= HEARTBEAT_INTERVAL_TICKS - 1) begin
            heartbeat_counter <= 32'd0;
            pending_heartbeat <= 1'b1;
        end else begin
            heartbeat_counter <= heartbeat_counter + 32'd1;
        end

        if (status_counter >= STATUS_INTERVAL_TICKS - 1) begin
            status_counter <= 32'd0;
            pending_status <= 1'b1;
        end else begin
            status_counter <= status_counter + 32'd1;
        end

        if (event_counter >= demo_period_ticks - 1) begin
            event_counter <= 32'd0;
            pending_event <= 1'b1;
        end else begin
            event_counter <= event_counter + 32'd1;
        end

        if (watch_counter >= WATCH_INTERVAL_TICKS - 1) begin
            watch_counter <= 32'd0;
            pending_watch <= 1'b1;
        end else begin
            watch_counter <= watch_counter + 32'd1;
        end

        if (print_counter >= PRINT_INTERVAL_TICKS - 1) begin
            print_counter <= 32'd0;
            pending_print <= 1'b1;
        end else begin
            print_counter <= print_counter + 32'd1;
        end

        if (trigger_rise) begin
            pending_event <= 1'b1;
            pending_print <= 1'b1;
            trace_step <= 4'd0;
            trace_counter <= TRACE_SCENARIO_INTERVAL_TICKS - 1;
        end

        if (trace_counter >= demo_period_ticks - 1) begin
            trace_counter <= 32'd0;
            case (trace_step)
                4'd0: begin
                    frame_start_valid <= 1'b1;
                    trace_fifo_level <= 32'd16;
                    profiler_axis_valid <= 1'b1;
                    profiler_axis_ready <= 1'b1;
                    profiler_axis_keep <= 4'hF;
                    profiler_fifo_wr_en <= 1'b1;
                    trace_step <= 4'd1;
                end
                4'd1: begin
                    dma_start_valid <= 1'b1;
                    trace_fifo_level <= 32'd32;
                    profiler_axis_valid <= 1'b1;
                    profiler_axis_ready <= 1'b1;
                    profiler_axis_keep <= 4'hF;
                    profiler_fifo_wr_en <= 1'b1;
                    trace_step <= 4'd2;
                end
                4'd2: begin
                    fifo_sample_valid <= 1'b1;
                    trace_fifo_level <= 32'd80;
                    profiler_axis_valid <= 1'b1;
                    profiler_axis_ready <= 1'b0;
                    profiler_axis_keep <= 4'hF;
                    profiler_fifo_wr_en <= 1'b1;
                    trace_step <= 4'd3;
                end
                4'd3: begin
                    fifo_almost_full <= 1'b1;
                    trace_fifo_level <= 32'd120;
                    profiler_axis_valid <= 1'b1;
                    profiler_axis_ready <= 1'b0;
                    profiler_axis_keep <= 4'hF;
                    profiler_fifo_wr_en <= 1'b1;
                    fifo_overflow_valid <= 1'b1;
                    trace_step <= 4'd4;
                end
                4'd4: begin
                    irq_level <= 1'b1;
                    profiler_axis_valid <= 1'b0;
                    profiler_axis_ready <= 1'b1;
                    profiler_fifo_rd_en <= 1'b1;
                    trace_step <= 4'd5;
                end
                4'd5: begin
                    irq_level <= 1'b0;
                    profiler_axis_valid <= 1'b1;
                    profiler_axis_ready <= 1'b1;
                    profiler_axis_keep <= 4'h7;
                    profiler_fifo_rd_en <= 1'b1;
                    trace_step <= 4'd6;
                end
                4'd6: begin
                    dma_done_valid <= 1'b1;
                    profiler_axis_valid <= 1'b1;
                    profiler_axis_ready <= 1'b1;
                    profiler_axis_keep <= 4'hF;
                    profiler_fifo_rd_en <= 1'b1;
                    trace_step <= 4'd7;
                end
                4'd7: begin
                    frame_end_valid <= 1'b1;
                    profiler_axis_valid <= 1'b1;
                    profiler_axis_ready <= 1'b1;
                    profiler_axis_keep <= 4'hF;
                    profiler_axis_last <= 1'b1;
                    profiler_fifo_rd_en <= 1'b1;
                    trace_step <= 4'd8;
                end
                4'd8: begin
                    dma_start_valid <= 1'b1;
                    profiler_axis_valid <= 1'b1;
                    profiler_axis_ready <= 1'b1;
                    profiler_axis_keep <= 4'hF;
                    trace_step <= 4'd9;
                end
                4'd9: begin
                    dma_timeout_valid <= 1'b1;
                    fifo_almost_full <= 1'b0;
                    profiler_fifo_underflow <= 1'b1;
                    trace_frame_id <= trace_frame_id + 16'd1;
                    trace_dma_desc_id <= trace_dma_desc_id + 16'd1;
                    trace_step <= 4'd0;
                end
                default: begin
                    trace_step <= 4'd0;
                end
            endcase
        end else begin
            trace_counter <= trace_counter + 32'd1;
        end

        if (heartbeat_led_counter != 32'd0) begin
            heartbeat_led_counter <= heartbeat_led_counter - 32'd1;
        end
        if (event_led_counter != 32'd0) begin
            event_led_counter <= event_led_counter - 32'd1;
        end

        if (pending_heartbeat) begin
            heartbeat_valid <= 1'b1;
            pending_heartbeat <= 1'b0;
            heartbeat_led_counter <= LED_HOLD_TICKS;
        end else if (pending_event) begin
            event_valid <= 1'b1;
            pending_event <= 1'b0;
            event_sequence <= event_sequence + 32'd1;
            event_led_counter <= LED_HOLD_TICKS;
        end else if (pending_watch) begin
            watch_valid <= 1'b1;
            pending_watch <= 1'b0;
        end else if (pending_print) begin
            print_valid <= 1'b1;
            pending_print <= 1'b0;
            print_sequence <= print_sequence + 32'd1;
        end else if (pending_status) begin
            status_valid <= 1'b1;
            pending_status <= 1'b0;
        end
    end
end

endmodule
