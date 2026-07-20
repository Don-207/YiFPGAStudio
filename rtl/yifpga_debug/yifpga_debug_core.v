`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_trace_pkg.vh"

module yifpga_debug_core #(
    parameter CLK_FREQ_HZ = 50000000,
    parameter UART_BAUD   = 115200,
    parameter BUFFER_ADDR_WIDTH = 4,
    parameter ENABLE_UART = 1
) (
    input  wire        clk,
    input  wire        rst,

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

    input  wire        monitor_msg_valid,
    input  wire [7:0]  monitor_msg_type,
    input  wire [7:0]  monitor_msg_len,
    input  wire [255:0] monitor_msg_payload,
    output wire        monitor_msg_ready,

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
    output reg  [15:0] drop_count,
    output reg  [15:0] packet_count
);

wire [31:0] timestamp;
wire        packetizer_ready;
wire        packet_byte_valid;
wire [7:0]  packet_byte_data;
wire        uart_data_ready;
wire        uart_busy;
wire        packet_byte_ready;
wire [2:0]  input_count;
wire        fifo_wr_ready;
wire        fifo_rd_valid;
wire [7:0]  fifo_rd_type;
wire [7:0]  fifo_rd_len;
wire [255:0] fifo_rd_payload;
wire        fifo_rd_ready;
wire [BUFFER_ADDR_WIDTH:0] fifo_used_count;
wire        stream_wr_ready;
wire        packet_accepted;
wire        legacy_msg_valid;
wire        legacy_packet_accepted;
wire        trace_msg_valid;
wire [7:0]  trace_msg_type;
wire [7:0]  trace_msg_len;
wire [255:0] trace_msg_payload;
wire        trace_ready;
wire        trace_accepted;
wire        trace_dropped;
wire        trace_msg_ready;
wire [15:0] core_drop_increment;
reg         fifo_wr_valid;
reg  [7:0]  fifo_wr_type;
reg  [7:0]  fifo_wr_len;
reg  [255:0] fifo_wr_payload;

// UART mode preserves the legacy paced stream. In JTAG-only mode the mailbox
// readiness drives the packetizer directly, removing the UART baud bottleneck.
assign packet_byte_ready = ENABLE_UART ? uart_data_ready : transport_byte_ready;
assign transport_byte_valid = packet_byte_valid && packet_byte_ready;
assign transport_byte_data = packet_byte_data;

yifpga_debug_timestamp u_timestamp (
    .clk(clk),
    .rst(rst),
    .timestamp(timestamp)
);

assign input_count = {2'b0, event_valid} + {2'b0, watch_valid} + {2'b0, print_valid} +
                     {2'b0, heartbeat_valid} + {2'b0, status_valid};
assign legacy_msg_valid = (input_count != 3'd0);
assign packet_accepted = fifo_wr_valid && fifo_wr_ready;
assign legacy_packet_accepted = packet_accepted && !monitor_msg_valid && legacy_msg_valid;
assign fifo_rd_ready = fifo_rd_valid && packetizer_ready;
assign buffer_used = {{(16 - BUFFER_ADDR_WIDTH - 1){1'b0}}, fifo_used_count};
assign busy = uart_busy || fifo_rd_valid || !packetizer_ready || packet_byte_valid;
assign monitor_msg_ready = fifo_wr_ready;
// Handshake-aware streams stop two entries before full so a Monitor response
// and a pulse-only legacy source both retain admission headroom during bursts.
assign stream_wr_ready = fifo_wr_ready &&
                         (fifo_used_count < ((1 << BUFFER_ADDR_WIDTH) - 2));
assign trace_msg_ready = stream_wr_ready && !monitor_msg_valid && !legacy_msg_valid;
assign la_msg_ready = stream_wr_ready && !monitor_msg_valid && !legacy_msg_valid &&
                      !trace_msg_valid;
assign profiler_msg_ready = stream_wr_ready && !monitor_msg_valid && !legacy_msg_valid &&
                            !trace_msg_valid && !la_msg_valid;
assign core_drop_increment =
    (input_count > {2'b0, legacy_packet_accepted}) ?
        {13'd0, input_count - {2'b0, legacy_packet_accepted}} : 16'd0;

always @(*) begin
    fifo_wr_valid = 1'b0;
    fifo_wr_type = 8'd0;
    fifo_wr_len = 8'd0;
    fifo_wr_payload = 256'd0;

    if (monitor_msg_valid) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = monitor_msg_type;
        fifo_wr_len = monitor_msg_len;
        fifo_wr_payload = monitor_msg_payload;
    end else if (event_valid) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = `YFD_TYPE_EVENT;
        fifo_wr_len = 8'd11;
        fifo_wr_payload[31:0] = timestamp;
        fifo_wr_payload[47:32] = event_id;
        fifo_wr_payload[55:48] = event_level;
        fifo_wr_payload[87:56] = event_arg0;
    end else if (watch_valid) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = `YFD_TYPE_WATCH;
        fifo_wr_len = 8'd10;
        fifo_wr_payload[31:0] = timestamp;
        fifo_wr_payload[47:32] = watch_id;
        fifo_wr_payload[79:48] = watch_value;
    end else if (print_valid) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = `YFD_TYPE_DEBUG_PRINT;
        fifo_wr_len = 8'd14;
        fifo_wr_payload[31:0] = timestamp;
        fifo_wr_payload[47:32] = print_id;
        fifo_wr_payload[79:48] = print_arg0;
        fifo_wr_payload[111:80] = print_arg1;
    end else if (heartbeat_valid) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = `YFD_TYPE_HEARTBEAT;
        fifo_wr_len = 8'd4;
        fifo_wr_payload[31:0] = timestamp;
    end else if (status_valid) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = `YFD_TYPE_STATUS;
        fifo_wr_len = 8'd10;
        fifo_wr_payload[31:0] = timestamp;
        fifo_wr_payload[47:32] = buffer_used;
        fifo_wr_payload[63:48] = drop_count;
        fifo_wr_payload[79:64] = packet_count;
    end else if (trace_msg_valid && stream_wr_ready) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = trace_msg_type;
        fifo_wr_len = trace_msg_len;
        fifo_wr_payload = trace_msg_payload;
    end else if (la_msg_valid && stream_wr_ready) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = la_msg_type;
        fifo_wr_len = la_msg_len;
        fifo_wr_payload = la_msg_payload;
    end else if (profiler_msg_valid && stream_wr_ready) begin
        fifo_wr_valid = 1'b1;
        fifo_wr_type = profiler_msg_type;
        fifo_wr_len = profiler_msg_len;
        fifo_wr_payload = profiler_msg_payload;
    end
end

yifpga_trace_adapter u_trace_adapter (
    .clk(clk),
    .rst(rst),
    .timestamp(timestamp),
    .span_begin_valid(trace_span_begin_valid),
    .span_begin_trace_id(trace_span_begin_trace_id),
    .span_begin_instance_id(trace_span_begin_instance_id),
    .span_begin_arg0(trace_span_begin_arg0),
    .span_end_valid(trace_span_end_valid),
    .span_end_trace_id(trace_span_end_trace_id),
    .span_end_instance_id(trace_span_end_instance_id),
    .span_end_status(trace_span_end_status),
    .span_end_arg0(trace_span_end_arg0),
    .mark_valid(trace_mark_valid),
    .mark_trace_id(trace_mark_trace_id),
    .mark_level(trace_mark_level),
    .mark_arg0(trace_mark_arg0),
    .value_valid(trace_value_valid),
    .value_trace_id(trace_value_trace_id),
    .value_id(trace_value_id),
    .value_data(trace_value_data),
    .drop_valid(trace_drop_valid),
    .drop_trace_id(trace_drop_trace_id),
    .drop_count(trace_drop_count),
    .trace_ready(trace_ready),
    .trace_accepted(trace_accepted),
    .trace_dropped(trace_dropped),
    .msg_valid(trace_msg_valid),
    .msg_type(trace_msg_type),
    .payload_len(trace_msg_len),
    .payload_flat(trace_msg_payload),
    .msg_ready(trace_msg_ready)
);

yifpga_debug_ring_buffer #(
    .ADDR_WIDTH(BUFFER_ADDR_WIDTH)
) u_ring_buffer (
    .clk(clk),
    .rst(rst),
    .wr_valid(fifo_wr_valid),
    .wr_type(fifo_wr_type),
    .wr_len(fifo_wr_len),
    .wr_payload(fifo_wr_payload),
    .wr_ready(fifo_wr_ready),
    .rd_valid(fifo_rd_valid),
    .rd_type(fifo_rd_type),
    .rd_len(fifo_rd_len),
    .rd_payload(fifo_rd_payload),
    .rd_ready(fifo_rd_ready),
    .used_count(fifo_used_count)
);

yifpga_debug_packetizer u_packetizer (
    .clk(clk),
    .rst(rst),
    .msg_valid(fifo_rd_valid),
    .msg_type(fifo_rd_type),
    .payload_len(fifo_rd_len),
    .payload_flat(fifo_rd_payload),
    .msg_ready(packetizer_ready),
    .out_valid(packet_byte_valid),
    .out_data(packet_byte_data),
    .out_ready(packet_byte_ready)
);

generate if (ENABLE_UART) begin : g_uart_tx
yifpga_debug_uart_tx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD(UART_BAUD)
) u_uart_tx (
    .clk(clk),
    .rst(rst),
    .data_valid(packet_byte_valid),
    .data(packet_byte_data),
    .data_ready(uart_data_ready),
    .tx(uart_tx),
    .busy(uart_busy)
);
end else begin : g_no_uart_tx
    assign uart_data_ready = 1'b0;
    assign uart_tx = 1'b1;
    assign uart_busy = 1'b0;
end endgenerate

always @(posedge clk) begin
    if (rst) begin
        drop_count <= 16'd0;
        packet_count <= 16'd0;
    end else begin
        if (packet_accepted) begin
            packet_count <= packet_count + 16'd1;
        end
        drop_count <= drop_count + core_drop_increment + {15'd0, trace_dropped};
    end
end

endmodule
