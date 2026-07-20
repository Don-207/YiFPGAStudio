`timescale 1ns / 1ps

module tb_yifpga_debug_protocol;

localparam integer CLK_FREQ_HZ = 10000000;
localparam integer UART_BAUD = 1000000;
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;

reg clk = 1'b0;
reg rst = 1'b1;

reg        event_valid = 1'b0;
reg [15:0] event_id = 16'd0;
reg [7:0]  event_level = 8'd0;
reg [31:0] event_arg0 = 32'd0;

wire uart_tx;
wire busy;
wire [15:0] buffer_used;
wire [15:0] drop_count;
wire [15:0] packet_count;

integer i;
integer errors = 0;
reg [7:0] rx_byte;
reg [7:0] expected [0:15];

always #5 clk = ~clk;

yifpga_debug_top #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .UART_BAUD(UART_BAUD)
) dut (
    .clk(clk),
    .rst(rst),
    .uart_rx(1'b1),
    .heartbeat_valid(1'b0),
    .status_valid(1'b0),
    .event_valid(event_valid),
    .event_id(event_id),
    .event_level(event_level),
    .event_arg0(event_arg0),
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
    .uart_tx(uart_tx),
    .busy(busy),
    .buffer_used(buffer_used),
    .drop_count(drop_count),
    .packet_count(packet_count)
);

task uart_read_byte;
    output [7:0] value;
    integer bit_index;
    begin
        value = 8'd0;
        wait (uart_tx == 1'b0);
        repeat (CLKS_PER_BIT + (CLKS_PER_BIT / 2)) @(posedge clk);

        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            value[bit_index] = uart_tx;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end

        if (uart_tx !== 1'b1) begin
            $display("ERROR: UART stop bit was not high");
            errors = errors + 1;
        end
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
    end
endtask

initial begin
    expected[0]  = 8'hA5;
    expected[1]  = 8'h01;
    expected[2]  = 8'h03;
    expected[3]  = 8'h0B;
    expected[4]  = 8'h0B;
    expected[5]  = 8'h00;
    expected[6]  = 8'h00;
    expected[7]  = 8'h00;
    expected[8]  = 8'h01;
    expected[9]  = 8'h10;
    expected[10] = 8'h01;
    expected[11] = 8'h78;
    expected[12] = 8'h56;
    expected[13] = 8'h34;
    expected[14] = 8'h12;
    expected[15] = 8'h1A;

    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (10) @(posedge clk);

    event_id = 16'h1001;
    event_level = 8'd1;
    event_arg0 = 32'h12345678;
    event_valid = 1'b1;
    @(posedge clk);
    event_valid = 1'b0;

    for (i = 0; i < 16; i = i + 1) begin
        uart_read_byte(rx_byte);
        if (rx_byte !== expected[i]) begin
            $display("ERROR: byte %0d expected %02x got %02x", i, expected[i], rx_byte);
            errors = errors + 1;
        end
    end

    repeat (5) @(posedge clk);
    if (packet_count !== 16'd1) begin
        $display("ERROR: packet_count expected 1 got %0d", packet_count);
        errors = errors + 1;
    end
    if (drop_count !== 16'd0) begin
        $display("ERROR: drop_count expected 0 got %0d", drop_count);
        errors = errors + 1;
    end

    if (errors == 0) begin
        $display("PASS: YiFPGA Debug Protocol M2 UART frame matched expected bytes");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
