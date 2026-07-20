`timescale 1ns / 1ps

module tb_yifpga_debug_board_demo;

localparam integer CLK_FREQ_HZ = 10000000;
localparam integer UART_BAUD = 1000000;
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;

localparam [7:0] YFD_SOF = 8'hA5;
localparam [7:0] YFD_VERSION = 8'h01;
localparam [7:0] YFD_TYPE_HEARTBEAT = 8'h01;
localparam [7:0] YFD_TYPE_DEBUG_PRINT = 8'h02;
localparam [7:0] YFD_TYPE_EVENT = 8'h03;
localparam [7:0] YFD_TYPE_WATCH = 8'h04;
localparam [7:0] YFD_TYPE_STATUS = 8'h05;
localparam [7:0] YFD_TYPE_TRACE_SPAN_BEGIN = 8'h10;
localparam [7:0] YFD_TYPE_TRACE_SPAN_END = 8'h11;
localparam [7:0] YFD_TYPE_TRACE_MARK = 8'h12;
localparam [7:0] YFD_TYPE_TRACE_VALUE = 8'h13;

reg clk_p = 1'b0;
wire clk_n = ~clk_p;
reg reset_n = 1'b0;
reg demo_trigger = 1'b0;
reg uart_rx = 1'b1;
wire uart_tx;
wire led0;
wire led1;

integer errors = 0;
integer i;
reg got_heartbeat = 1'b0;
reg got_print = 1'b0;
reg got_event = 1'b0;
reg got_watch = 1'b0;
reg got_status = 1'b0;
reg got_trace_span_begin = 1'b0;
reg got_trace_span_end = 1'b0;
reg got_trace_mark = 1'b0;
reg got_trace_value = 1'b0;
reg [7:0] frame_type;
reg [7:0] frame_len;
reg [7:0] frame_checksum;
reg [7:0] rx_byte;

always #5 clk_p = ~clk_p;

yifpga_debug_board_demo #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .UART_BAUD(UART_BAUD),
    .BUFFER_ADDR_WIDTH(3),
    // Preserve the board image's relationship between producer rate and UART
    // capacity. Tiny tens-of-cycle intervals permanently overload the UART and
    // turn this coexistence test into an artificial starvation test.
    .HEARTBEAT_INTERVAL_TICKS(100000),
    .EVENT_INTERVAL_TICKS(4000),
    .WATCH_INTERVAL_TICKS(20000),
    .PRINT_INTERVAL_TICKS(60000),
    .STATUS_INTERVAL_TICKS(30000),
    .TRACE_SCENARIO_INTERVAL_TICKS(12000),
    .LED_HOLD_TICKS(10)
) dut (
    .clk_p(clk_p),
    .clk_n(clk_n),
    .reset_n(reset_n),
    .demo_trigger(demo_trigger),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .led0(led0),
    .led1(led1)
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

task uart_read_byte;
    output [7:0] value;
    integer bit_index;
    begin
        value = 8'd0;
        wait (uart_tx == 1'b0);
        repeat (CLKS_PER_BIT + (CLKS_PER_BIT / 2)) @(posedge clk_p);

        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            value[bit_index] = uart_tx;
            repeat (CLKS_PER_BIT) @(posedge clk_p);
        end

        check(uart_tx == 1'b1, "UART stop bit should be high");
        repeat (CLKS_PER_BIT / 2) @(posedge clk_p);
    end
endtask

task read_frame;
    output [7:0] msg_type;
    output [7:0] msg_len;
    integer payload_index;
    begin
        uart_read_byte(rx_byte);
        check(rx_byte == YFD_SOF, "frame SOF mismatch");
        uart_read_byte(rx_byte);
        check(rx_byte == YFD_VERSION, "frame version mismatch");
        frame_checksum = rx_byte;

        uart_read_byte(msg_type);
        frame_checksum = frame_checksum ^ msg_type;
        uart_read_byte(msg_len);
        frame_checksum = frame_checksum ^ msg_len;

        for (payload_index = 0; payload_index < msg_len; payload_index = payload_index + 1) begin
            uart_read_byte(rx_byte);
            frame_checksum = frame_checksum ^ rx_byte;
        end

        uart_read_byte(rx_byte);
        check(rx_byte == frame_checksum, "frame checksum mismatch");
    end
endtask

initial begin
    repeat (5) @(posedge clk_p);
    reset_n = 1'b1;

    for (i = 0; i < 36; i = i + 1) begin
        if (i == 4) begin
            demo_trigger = 1'b1;
        end else begin
            demo_trigger = 1'b0;
        end

        read_frame(frame_type, frame_len);
        if (frame_type == YFD_TYPE_HEARTBEAT) begin
            got_heartbeat = 1'b1;
            check(frame_len == 8'd4, "heartbeat length mismatch");
        end else if (frame_type == YFD_TYPE_DEBUG_PRINT) begin
            got_print = 1'b1;
            check(frame_len == 8'd14, "debug print length mismatch");
        end else if (frame_type == YFD_TYPE_EVENT) begin
            got_event = 1'b1;
            check(frame_len == 8'd11, "event length mismatch");
        end else if (frame_type == YFD_TYPE_WATCH) begin
            got_watch = 1'b1;
            check(frame_len == 8'd10, "watch length mismatch");
        end else if (frame_type == YFD_TYPE_STATUS) begin
            got_status = 1'b1;
            check(frame_len == 8'd10, "status length mismatch");
        end else if (frame_type == YFD_TYPE_TRACE_SPAN_BEGIN) begin
            got_trace_span_begin = 1'b1;
            check(frame_len == 8'd12, "trace span begin length mismatch");
        end else if (frame_type == YFD_TYPE_TRACE_SPAN_END) begin
            got_trace_span_end = 1'b1;
            check(frame_len == 8'd13, "trace span end length mismatch");
        end else if (frame_type == YFD_TYPE_TRACE_MARK) begin
            got_trace_mark = 1'b1;
            check(frame_len == 8'd11, "trace mark length mismatch");
        end else if (frame_type == YFD_TYPE_TRACE_VALUE) begin
            got_trace_value = 1'b1;
            check(frame_len == 8'd12, "trace value length mismatch");
        end else begin
            $display("ERROR: unexpected frame type %02x", frame_type);
            errors = errors + 1;
        end
    end

    check(got_heartbeat, "demo should emit heartbeat frames");
    check(got_print, "demo should emit debug print frames");
    check(got_event, "demo should emit event frames");
    check(got_watch, "demo should emit watch frames");
    check(got_status, "demo should emit status frames");
    check(got_trace_span_begin, "demo should emit trace span begin frames");
    check(got_trace_span_end, "demo should emit trace span end frames");
    check(got_trace_mark, "demo should emit trace mark frames");
    check(got_trace_value, "demo should emit trace value frames");
    check(led0 || led1, "demo LEDs should expose activity");

    if (errors == 0) begin
        $display("PASS: YiFPGA Debug board demo emitted debug and trace frames");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
