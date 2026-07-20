`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_monitor_pkg.vh"
`include "yifpga_profiler_pkg.vh"

module tb_yifpga_debug_board_profiler;

localparam integer CLK_FREQ_HZ = 10000000;
localparam integer UART_BAUD = 1000000;
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;

reg clk_p = 1'b0;
wire clk_n = ~clk_p;
reg reset_n = 1'b0;
reg demo_trigger = 1'b0;
reg uart_rx = 1'b1;
wire uart_tx;
wire led0;
wire led1;

integer errors = 0;
integer frame_count = 0;
integer snapshot_count = 0;
integer alert_count = 0;
reg saw_axis = 1'b0;
reg saw_fifo = 1'b0;
reg saw_latency = 1'b0;
reg saw_frame = 1'b0;
reg saw_trace = 1'b0;
reg saw_monitor = 1'b0;
reg saw_masked_axis = 1'b0;
reg saw_profiler_tx = 1'b0;

reg [7:0] frame_type;
reg [7:0] frame_len;
reg [7:0] payload [0:31];
reg [7:0] rx_byte;
reg [7:0] frame_checksum;

always #5 clk_p = ~clk_p;

yifpga_debug_board_demo #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .UART_BAUD(UART_BAUD),
    .BUFFER_ADDR_WIDTH(6),
    .HEARTBEAT_INTERVAL_TICKS(1000000),
    .EVENT_INTERVAL_TICKS(1000000),
    .WATCH_INTERVAL_TICKS(1000000),
    .PRINT_INTERVAL_TICKS(1000000),
    .STATUS_INTERVAL_TICKS(1000000),
    .TRACE_SCENARIO_INTERVAL_TICKS(4),
    .LED_HOLD_TICKS(20)
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

always @(posedge clk_p) begin
    if (dut.profiler_snapshot_valid && dut.profiler_snapshot_ready) begin
        snapshot_count = snapshot_count + 1;
        if (dut.profiler_snapshot_metric_id == `YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT) saw_axis = 1'b1;
        if (dut.profiler_snapshot_metric_id == `YFD_PROFILER_METRIC_FIFO_DEMO_LEVEL) saw_fifo = 1'b1;
        if (dut.profiler_snapshot_metric_id == `YFD_PROFILER_METRIC_DEMO_LATENCY) saw_latency = 1'b1;
        if (dut.profiler_snapshot_metric_id == `YFD_PROFILER_METRIC_FRAME_RATE) saw_frame = 1'b1;
    end
    if (dut.profiler_alert_valid && dut.profiler_alert_ready) begin
        alert_count = alert_count + 1;
    end
    if (dut.profiler_msg_valid && dut.profiler_msg_ready) begin
        saw_profiler_tx = 1'b1;
    end
    if (dut.trace_span_begin_valid || dut.trace_span_end_valid || dut.trace_mark_valid || dut.trace_value_valid) begin
        saw_trace = 1'b1;
    end
end

task check;
    input condition;
    input [8 * 96 - 1:0] message;
    begin
        if (!condition) begin
            $display("ERROR: %0s", message);
            errors = errors + 1;
        end
    end
endtask

task uart_write_byte;
    input [7:0] value;
    integer bit_index;
    begin
        uart_rx = 1'b0;
        repeat (CLKS_PER_BIT) @(posedge clk_p);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            uart_rx = value[bit_index];
            repeat (CLKS_PER_BIT) @(posedge clk_p);
        end
        uart_rx = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk_p);
    end
endtask

task uart_read_byte;
    output [7:0] value;
    integer wait_count;
    integer bit_index;
    begin
        wait_count = 0;
        while (uart_tx == 1'b1 && wait_count < 200000) begin
            wait_count = wait_count + 1;
            @(posedge clk_p);
        end
        check(wait_count < 200000, "UART TX byte timeout");
        value = 8'd0;
        repeat (CLKS_PER_BIT + (CLKS_PER_BIT / 2)) @(posedge clk_p);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            value[bit_index] = uart_tx;
            repeat (CLKS_PER_BIT) @(posedge clk_p);
        end
        check(uart_tx == 1'b1, "UART TX stop bit should be high");
        repeat (CLKS_PER_BIT / 2) @(posedge clk_p);
    end
endtask

task read_frame;
    output [7:0] msg_type;
    output [7:0] msg_len;
    integer index;
    begin
        uart_read_byte(rx_byte);
        check(rx_byte == `YFD_SOF, "frame SOF mismatch");
        uart_read_byte(rx_byte);
        check(rx_byte == `YFD_VERSION, "frame version mismatch");
        frame_checksum = rx_byte;
        uart_read_byte(msg_type);
        frame_checksum = frame_checksum ^ msg_type;
        uart_read_byte(msg_len);
        frame_checksum = frame_checksum ^ msg_len;
        for (index = 0; index < msg_len; index = index + 1) begin
            uart_read_byte(payload[index]);
            frame_checksum = frame_checksum ^ payload[index];
        end
        uart_read_byte(rx_byte);
        check(rx_byte == frame_checksum, "frame checksum mismatch");
        frame_count = frame_count + 1;
    end
endtask

task wait_uart_idle;
    integer idle_count;
    begin
        idle_count = 0;
        while (idle_count < (CLKS_PER_BIT * 20)) begin
            @(posedge clk_p);
            if (uart_tx == 1'b1) begin
                idle_count = idle_count + 1;
            end else begin
                idle_count = 0;
            end
        end
    end
endtask

task send_monitor_write;
    input [15:0] seq;
    input [15:0] addr;
    input [31:0] value;
    input [31:0] mask;
    reg [7:0] sum;
    begin
        sum = `YFD_VERSION ^ `YFD_TYPE_MONITOR_WRITE_REQ ^ 8'd13 ^
              seq[7:0] ^ seq[15:8] ^ addr[7:0] ^ addr[15:8] ^ 8'd4 ^
              value[7:0] ^ value[15:8] ^ value[23:16] ^ value[31:24] ^
              mask[7:0] ^ mask[15:8] ^ mask[23:16] ^ mask[31:24];
        uart_write_byte(`YFD_SOF);
        uart_write_byte(`YFD_VERSION);
        uart_write_byte(`YFD_TYPE_MONITOR_WRITE_REQ);
        uart_write_byte(8'd13);
        uart_write_byte(seq[7:0]);
        uart_write_byte(seq[15:8]);
        uart_write_byte(addr[7:0]);
        uart_write_byte(addr[15:8]);
        uart_write_byte(8'd4);
        uart_write_byte(value[7:0]);
        uart_write_byte(value[15:8]);
        uart_write_byte(value[23:16]);
        uart_write_byte(value[31:24]);
        uart_write_byte(mask[7:0]);
        uart_write_byte(mask[15:8]);
        uart_write_byte(mask[23:16]);
        uart_write_byte(mask[31:24]);
        uart_write_byte(sum);
    end
endtask

task send_monitor_read;
    input [15:0] seq;
    input [15:0] addr;
    reg [7:0] sum;
    begin
        sum = `YFD_VERSION ^ `YFD_TYPE_MONITOR_READ_REQ ^ 8'd5 ^
              seq[7:0] ^ seq[15:8] ^ addr[7:0] ^ addr[15:8] ^ 8'd4;
        uart_write_byte(`YFD_SOF);
        uart_write_byte(`YFD_VERSION);
        uart_write_byte(`YFD_TYPE_MONITOR_READ_REQ);
        uart_write_byte(8'd5);
        uart_write_byte(seq[7:0]);
        uart_write_byte(seq[15:8]);
        uart_write_byte(addr[7:0]);
        uart_write_byte(addr[15:8]);
        uart_write_byte(8'd4);
        uart_write_byte(sum);
    end
endtask

function [15:0] payload_u16;
    input integer offset;
    begin
        payload_u16 = {payload[offset + 1], payload[offset]};
    end
endfunction

function [31:0] payload_u32;
    input integer offset;
    begin
        payload_u32 = {payload[offset + 3], payload[offset + 2], payload[offset + 1], payload[offset]};
    end
endfunction

task read_until_activity;
    input integer max_frames;
    integer i;
    reg [15:0] metric_id;
    begin
        for (i = 0; i < max_frames; i = i + 1) begin
            read_frame(frame_type, frame_len);
            if (frame_type == `YFD_TYPE_MONITOR_READ_RESP || frame_type == `YFD_TYPE_MONITOR_WRITE_RESP) begin
                saw_monitor = 1'b1;
            end else if (frame_type >= 8'h10 && frame_type <= 8'h14) begin
                saw_trace = 1'b1;
            end else if (frame_type == `YFD_TYPE_PROFILER_SNAPSHOT) begin
                snapshot_count = snapshot_count + 1;
                check(frame_len == `YFD_PROFILER_LEN_SNAPSHOT, "profiler snapshot length mismatch");
                metric_id = payload_u16(4);
                if (metric_id == `YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT) begin
                    saw_axis = 1'b1;
                    saw_masked_axis = 1'b1;
                end
                if (metric_id == `YFD_PROFILER_METRIC_FIFO_DEMO_LEVEL) saw_fifo = 1'b1;
                if (metric_id == `YFD_PROFILER_METRIC_DEMO_LATENCY) saw_latency = 1'b1;
                if (metric_id == `YFD_PROFILER_METRIC_FRAME_RATE) saw_frame = 1'b1;
                check(payload_u32(8) != 32'd0, "profiler sample window should be nonzero");
            end else if (frame_type == `YFD_TYPE_PROFILER_ALERT) begin
                alert_count = alert_count + 1;
                check(frame_len == `YFD_PROFILER_LEN_ALERT, "profiler alert length mismatch");
            end
        end
    end
endtask

task read_until_monitor_response;
    input [15:0] seq;
    input [7:0] expected_type;
    integer i;
    begin
        for (i = 0; i < 40; i = i + 1) begin
            read_frame(frame_type, frame_len);
            if (frame_type == `YFD_TYPE_MONITOR_READ_RESP || frame_type == `YFD_TYPE_MONITOR_WRITE_RESP) begin
                saw_monitor = 1'b1;
                if (payload_u16(4) == seq) begin
                    check(frame_type == expected_type, "monitor response type mismatch");
                    i = 40;
                end
            end else if (frame_type >= 8'h10 && frame_type <= 8'h14) begin
                saw_trace = 1'b1;
            end
        end
        check(payload_u16(4) == seq, "monitor response seq not observed");
    end
endtask

initial begin
    repeat (5) @(posedge clk_p);
    reset_n = 1'b1;
    repeat (100000) @(posedge clk_p);
    wait_uart_idle();

    fork
        send_monitor_read(16'h2101, `YFD_MON_ADDR_PROFILER_ID);
        read_until_monitor_response(16'h2101, `YFD_TYPE_MONITOR_READ_RESP);
    join
    check(payload_u16(4) == 16'h2101, "PROFILER_ID response seq mismatch");
    check(payload[8] == `YFD_MON_STATUS_OK, "PROFILER_ID read should be OK");
    check(payload_u32(10) == `YFD_PROFILER_ID_VALUE, "PROFILER_ID value mismatch");

    fork
        send_monitor_write(16'h2103, `YFD_MON_ADDR_PROFILER_SAMPLE_PERIOD, 32'd8, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2103, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    check(payload[8] == `YFD_MON_STATUS_OK, "PROFILER_SAMPLE_PERIOD write should be OK");

    fork
        send_monitor_write(16'h2104, `YFD_MON_ADDR_PROFILER_ALERT_THRESHOLD0, 32'd16, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2104, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    check(payload[8] == `YFD_MON_STATUS_OK, "PROFILER_ALERT_THRESHOLD0 write should be OK");

    fork
        send_monitor_write(16'h2105, `YFD_MON_ADDR_PROFILER_CONTROL, 32'd1, 32'h00000001);
        read_until_monitor_response(16'h2105, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    check(payload[8] == `YFD_MON_STATUS_OK, "PROFILER_CONTROL enable should be OK");

    dut.u_debug_top.u_monitor_core.u_reg_bank.demo_period = 32'd20;
    repeat (20000) @(posedge clk_p);
    check(saw_axis, "AXIS profiler snapshot should appear");
    check(saw_fifo, "FIFO profiler snapshot should appear");
    check(saw_latency, "Latency profiler snapshot should appear");
    check(saw_frame, "Frame profiler snapshot should appear");
    check(alert_count != 0, "Profiler alert should appear after low threshold");
    check(saw_trace, "Trace frames should coexist with profiler frames");
    check(saw_monitor, "Monitor frames should coexist with profiler frames");
    check(saw_profiler_tx, "Profiler messages should enter debug TX path");

    if (errors == 0) begin
        $display("PASS: YiFPGA Profiler M21 board demo checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
