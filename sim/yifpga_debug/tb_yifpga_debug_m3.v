`timescale 1ns / 1ps

module tb_yifpga_debug_m3;

localparam [7:0] YFD_SOF = 8'hA5;
localparam [7:0] YFD_VERSION = 8'h01;
localparam [7:0] YFD_TYPE_DEBUG_PRINT = 8'h02;
localparam [7:0] YFD_TYPE_EVENT = 8'h03;
localparam [7:0] YFD_TYPE_WATCH = 8'h04;

reg clk = 1'b0;
reg rst = 1'b1;

integer errors = 0;
integer i;

always #5 clk = ~clk;

reg         rb_wr_valid = 1'b0;
reg  [7:0]  rb_wr_type = 8'd0;
reg  [7:0]  rb_wr_len = 8'd0;
reg  [255:0] rb_wr_payload = 256'd0;
wire        rb_wr_ready;
wire        rb_rd_valid;
wire [7:0]  rb_rd_type;
wire [7:0]  rb_rd_len;
wire [255:0] rb_rd_payload;
reg         rb_rd_ready = 1'b0;
wire [2:0]  rb_used_count;

reg         seq_wr_valid = 1'b0;
reg  [7:0]  seq_wr_type = 8'd0;
reg  [7:0]  seq_wr_len = 8'd0;
reg  [255:0] seq_wr_payload = 256'd0;
wire        seq_wr_ready;
wire        seq_rd_valid;
wire [7:0]  seq_rd_type;
wire [7:0]  seq_rd_len;
wire [255:0] seq_rd_payload;
wire        seq_rd_ready;
wire [2:0]  seq_used_count;
wire        packetizer_ready;
wire        packet_byte_valid;
wire [7:0]  packet_byte_data;

reg        core_event_valid = 1'b0;
reg [15:0] core_event_id = 16'd0;
reg [7:0]  core_event_level = 8'd1;
reg [31:0] core_event_arg0 = 32'd0;
wire       core_uart_tx;
wire       core_busy;
wire [15:0] core_buffer_used;
wire [15:0] core_drop_count;
wire [15:0] core_packet_count;
reg         core_la_msg_valid = 1'b0;
wire        core_la_msg_ready;

yifpga_debug_ring_buffer #(
    .ADDR_WIDTH(2)
) u_ring_buffer_direct (
    .clk(clk),
    .rst(rst),
    .wr_valid(rb_wr_valid),
    .wr_type(rb_wr_type),
    .wr_len(rb_wr_len),
    .wr_payload(rb_wr_payload),
    .wr_ready(rb_wr_ready),
    .rd_valid(rb_rd_valid),
    .rd_type(rb_rd_type),
    .rd_len(rb_rd_len),
    .rd_payload(rb_rd_payload),
    .rd_ready(rb_rd_ready),
    .used_count(rb_used_count)
);

yifpga_debug_ring_buffer #(
    .ADDR_WIDTH(2)
) u_ring_buffer_sequence (
    .clk(clk),
    .rst(rst),
    .wr_valid(seq_wr_valid),
    .wr_type(seq_wr_type),
    .wr_len(seq_wr_len),
    .wr_payload(seq_wr_payload),
    .wr_ready(seq_wr_ready),
    .rd_valid(seq_rd_valid),
    .rd_type(seq_rd_type),
    .rd_len(seq_rd_len),
    .rd_payload(seq_rd_payload),
    .rd_ready(seq_rd_ready),
    .used_count(seq_used_count)
);

assign seq_rd_ready = seq_rd_valid && packetizer_ready;

yifpga_debug_packetizer u_packetizer (
    .clk(clk),
    .rst(rst),
    .msg_valid(seq_rd_valid),
    .msg_type(seq_rd_type),
    .payload_len(seq_rd_len),
    .payload_flat(seq_rd_payload),
    .msg_ready(packetizer_ready),
    .out_valid(packet_byte_valid),
    .out_data(packet_byte_data),
    .out_ready(1'b1)
);

yifpga_debug_top #(
    .CLK_FREQ_HZ(10000000),
    .UART_BAUD(1000000),
    .BUFFER_ADDR_WIDTH(2)
) u_core (
    .clk(clk),
    .rst(rst),
    .uart_rx(1'b1),
    .heartbeat_valid(1'b0),
    .status_valid(1'b0),
    .event_valid(core_event_valid),
    .event_id(core_event_id),
    .event_level(core_event_level),
    .event_arg0(core_event_arg0),
    .watch_valid(1'b0),
    .watch_id(16'd0),
    .watch_value(32'd0),
    .print_valid(1'b0),
    .print_id(16'd0),
    .print_arg0(32'd0),
    .print_arg1(32'd0),
    .trace_span_begin_valid(1'b0),
    .trace_span_begin_trace_id(16'd0),
    .trace_span_begin_instance_id(16'd0),
    .trace_span_begin_arg0(32'd0),
    .trace_span_end_valid(1'b0),
    .trace_span_end_trace_id(16'd0),
    .trace_span_end_instance_id(16'd0),
    .trace_span_end_status(8'd0),
    .trace_span_end_arg0(32'd0),
    .trace_mark_valid(1'b0),
    .trace_mark_trace_id(16'd0),
    .trace_mark_level(8'd0),
    .trace_mark_arg0(32'd0),
    .trace_value_valid(1'b0),
    .trace_value_trace_id(16'd0),
    .trace_value_id(16'd0),
    .trace_value_data(32'd0),
    .trace_drop_valid(1'b0),
    .trace_drop_trace_id(16'd0),
    .trace_drop_count(32'd0),
    .monitor_counter0(32'd0),
    .monitor_control(),
    .monitor_led_control(),
    .monitor_demo_period(),
    .monitor_error_status(),
    .monitor_clear_counters_pulse(),
    .profiler_status_set(32'd0),
    .profiler_control(),
    .profiler_sample_period(),
    .profiler_clear_pulse(),
    .profiler_status(),
    .profiler_metric_mask0(),
    .profiler_alert_threshold0(),
    .profiler_msg_valid(1'b0),
    .profiler_msg_type(8'd0),
    .profiler_msg_len(8'd0),
    .profiler_msg_payload(256'd0),
    .profiler_msg_ready(),
    .la_status_set(32'd0),
    .la_capture_id(32'd0),
    .la_msg_valid(core_la_msg_valid),
    .la_msg_type(8'h40),
    .la_msg_len(8'd24),
    .la_msg_payload(256'hA5A5),
    .la_msg_ready(core_la_msg_ready),
    .transport_byte_ready(1'b1),
    .uart_tx(core_uart_tx),
    .busy(core_busy),
    .buffer_used(core_buffer_used),
    .drop_count(core_drop_count),
    .packet_count(core_packet_count)
);

task check;
    input condition;
    input [8 * 80 - 1:0] message;
    begin
        if (!condition) begin
            $display("ERROR: %0s", message);
            errors = errors + 1;
        end
    end
endtask

task rb_write;
    input [7:0] msg_type;
    input [15:0] msg_id;
    begin
        rb_wr_type = msg_type;
        rb_wr_len = 8'd10;
        rb_wr_payload = 256'd0;
        rb_wr_payload[47:32] = msg_id;
        rb_wr_valid = 1'b1;
        @(posedge clk);
        #1;
        rb_wr_valid = 1'b0;
    end
endtask

task seq_write;
    input [7:0] msg_type;
    input [7:0] msg_len;
    input [15:0] msg_id;
    begin
        seq_wr_type = msg_type;
        seq_wr_len = msg_len;
        seq_wr_payload = 256'd0;
        seq_wr_payload[31:0] = 32'h12345678;
        seq_wr_payload[47:32] = msg_id;
        seq_wr_payload[79:48] = 32'hA5A50000 | msg_id;
        seq_wr_payload[111:80] = 32'h5A5A0000 | msg_id;
        seq_wr_valid = 1'b1;
        @(posedge clk);
        #1;
        seq_wr_valid = 1'b0;
    end
endtask

task packet_read_byte;
    output [7:0] value;
    integer wait_count;
    begin
        wait_count = 0;
        while (!packet_byte_valid && wait_count < 1000) begin
            wait_count = wait_count + 1;
            @(posedge clk);
            #1;
        end
        if (wait_count == 1000) begin
            $display("ERROR: timed out waiting for packetizer byte");
            errors = errors + 1;
            value = 8'd0;
        end else begin
            value = packet_byte_data;
            @(posedge clk);
            #1;
        end
    end
endtask

task expect_packet;
    input [7:0] expected_type;
    input [7:0] expected_len;
    input [15:0] expected_id;
    integer index;
    reg [7:0] bytes [0:31];
    reg [7:0] checksum;
    reg [15:0] actual_id;
    begin
        for (index = 0; index < expected_len + 5; index = index + 1) begin
            packet_read_byte(bytes[index]);
        end

    check(bytes[0] == YFD_SOF, "packet SOF mismatch");
    check(bytes[1] == YFD_VERSION, "packet version mismatch");
        check(bytes[2] == expected_type, "packet type mismatch");
        check(bytes[3] == expected_len, "packet len mismatch");

        checksum = 8'd0;
        for (index = 1; index < expected_len + 4; index = index + 1) begin
            checksum = checksum ^ bytes[index];
        end
        check(checksum == bytes[expected_len + 4], "packet checksum mismatch");

        actual_id = {bytes[9], bytes[8]};
        check(actual_id == expected_id, "packet id/order mismatch");
    end
endtask

task core_send_event;
    input [15:0] id;
    begin
        core_event_id = id;
        core_event_arg0 = {16'hCAFE, id};
        core_event_valid = 1'b1;
        @(posedge clk);
        #1;
        core_event_valid = 1'b0;
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (5) @(posedge clk);
    #1;

    check(rb_used_count == 3'd0, "ring buffer should reset empty");
    check(rb_rd_valid == 1'b0, "empty ring buffer should not assert rd_valid");

    rb_write(YFD_TYPE_EVENT, 16'h1000);
    rb_write(YFD_TYPE_WATCH, 16'h1001);
    check(rb_used_count == 3'd2, "ring buffer half-full count mismatch");

    rb_write(YFD_TYPE_DEBUG_PRINT, 16'h1002);
    rb_write(YFD_TYPE_EVENT, 16'h1003);
    check(rb_used_count == 3'd4, "ring buffer full count mismatch");
    check(rb_wr_ready == 1'b0, "full ring buffer should deassert wr_ready");

    rb_wr_type = YFD_TYPE_WATCH;
    rb_wr_len = 8'd10;
    rb_wr_payload = 256'd0;
    rb_wr_payload[47:32] = 16'h1004;
    rb_wr_valid = 1'b1;
    rb_rd_ready = 1'b1;
    @(posedge clk);
    #1;
    rb_wr_valid = 1'b0;
    rb_rd_ready = 1'b0;
    check(rb_used_count == 3'd4, "full simultaneous read/write should keep count full");

    for (i = 1; i < 5; i = i + 1) begin
        check(rb_rd_valid == 1'b1, "ring buffer should have data while draining");
        check(rb_rd_payload[47:32] == (16'h1000 + i[15:0]), "ring buffer order mismatch");
        rb_rd_ready = 1'b1;
        @(posedge clk);
        #1;
        rb_rd_ready = 1'b0;
    end
    check(rb_used_count == 3'd0, "ring buffer should drain to empty");

    seq_write(YFD_TYPE_EVENT, 8'd11, 16'h2001);
    seq_write(YFD_TYPE_WATCH, 8'd10, 16'h2002);
    seq_write(YFD_TYPE_DEBUG_PRINT, 8'd14, 16'h2003);
    expect_packet(YFD_TYPE_EVENT, 8'd11, 16'h2001);
    expect_packet(YFD_TYPE_WATCH, 8'd10, 16'h2002);
    expect_packet(YFD_TYPE_DEBUG_PRINT, 8'd14, 16'h2003);

    for (i = 0; i < 8; i = i + 1) begin
        core_send_event(16'h3000 + i[15:0]);
    end
    core_la_msg_valid = 1'b1;
    repeat (20) @(posedge clk);
    #1;
    core_la_msg_valid = 1'b0;
    check(core_packet_count == 16'd5, "core packet_count should include only accepted burst messages");
    check(core_drop_count == 16'd3, "core drop_count should count full-buffer drops");
    check(!core_la_msg_ready, "held LA message should remain backpressured while buffer is full");
    check(core_drop_count == 16'd3, "held ready/valid message must not repeatedly increment drop_count");

    if (errors == 0) begin
        $display("PASS: YiFPGA Debug M3 ring buffer, packet order, and overflow checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
