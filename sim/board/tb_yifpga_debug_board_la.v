`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_monitor_pkg.vh"
`include "yifpga_la_pkg.vh"

module tb_yifpga_debug_board_la;

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
integer la_header_count = 0;
integer la_trigger_count = 0;
integer la_data_count = 0;
integer la_status_count = 0;
integer monitor_count = 0;
reg saw_trace = 1'b0;
reg saw_profiler = 1'b0;

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

task check;
    input condition;
    input [8 * 120 - 1:0] message;
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
        while (uart_tx == 1'b1 && wait_count < 300000) begin
            wait_count = wait_count + 1;
            @(posedge clk_p);
        end
        check(wait_count < 300000, "UART TX byte timeout");
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
    integer sync_count;
    begin
        sync_count = 0;
        uart_read_byte(rx_byte);
        while (rx_byte != `YFD_SOF && sync_count < 64) begin
            sync_count = sync_count + 1;
            uart_read_byte(rx_byte);
        end
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

task read_until_monitor_response;
    input [15:0] seq;
    input [7:0] expected_type;
    integer i;
    reg found;
    begin
        found = 1'b0;
        for (i = 0; i < 80 && !found; i = i + 1) begin
            read_frame(frame_type, frame_len);
            if (frame_type == `YFD_TYPE_MONITOR_READ_RESP || frame_type == `YFD_TYPE_MONITOR_WRITE_RESP) begin
                monitor_count = monitor_count + 1;
                if (payload_u16(4) == seq) begin
                    check(frame_type == expected_type, "monitor response type mismatch");
                    found = 1'b1;
                end
            end else if (frame_type >= 8'h10 && frame_type <= 8'h14) begin
                saw_trace = 1'b1;
            end else if (frame_type >= 8'h30 && frame_type <= 8'h31) begin
                saw_profiler = 1'b1;
            end
        end
        check(found, "monitor response seq not observed");
    end
endtask

task read_until_la_readout;
    integer i;
    begin
        for (i = 0; i < 120 && la_status_count == 0; i = i + 1) begin
            read_frame(frame_type, frame_len);
            if (frame_type == `YFD_TYPE_LA_CAPTURE_HEADER) begin
                la_header_count = la_header_count + 1;
                check(frame_len == `YFD_LA_LEN_CAPTURE_HEADER, "LA header length mismatch");
                check(payload_u16(8) == 16'd32, "LA sample width mismatch");
                check(payload_u16(10) != 16'd0, "LA sample count should be nonzero");
            end else if (frame_type == `YFD_TYPE_LA_TRIGGER_EVENT) begin
                la_trigger_count = la_trigger_count + 1;
                check(frame_len == `YFD_LA_LEN_TRIGGER_EVENT, "LA trigger length mismatch");
            end else if (frame_type == `YFD_TYPE_LA_SAMPLE_DATA) begin
                la_data_count = la_data_count + 1;
                check(frame_len == `YFD_LA_LEN_SAMPLE_DATA, "LA data length mismatch");
                check(payload[9] != 8'd0, "LA data chunk should contain samples");
            end else if (frame_type == `YFD_TYPE_LA_CAPTURE_STATUS) begin
                la_status_count = la_status_count + 1;
                check(frame_len == `YFD_LA_LEN_CAPTURE_STATUS, "LA status length mismatch");
                check(payload[8] == `YFD_LA_STATE_READOUT || payload[8] == `YFD_LA_STATE_DONE, "LA status state mismatch");
            end else if (frame_type == `YFD_TYPE_MONITOR_READ_RESP || frame_type == `YFD_TYPE_MONITOR_WRITE_RESP) begin
                monitor_count = monitor_count + 1;
            end else if (frame_type >= 8'h10 && frame_type <= 8'h14) begin
                saw_trace = 1'b1;
            end else if (frame_type >= 8'h30 && frame_type <= 8'h31) begin
                saw_profiler = 1'b1;
            end
        end
    end
endtask

initial begin
    repeat (5) @(posedge clk_p);
    reset_n = 1'b1;
    repeat (10000) @(posedge clk_p);
    wait_uart_idle();

    fork
        send_monitor_read(16'h2501, `YFD_MON_ADDR_LA_ID);
        read_until_monitor_response(16'h2501, `YFD_TYPE_MONITOR_READ_RESP);
    join
    check(payload[8] == `YFD_MON_STATUS_OK, "LA_ID read should be OK");
    check(payload_u32(10) == `YFD_LA_ID_VALUE, "LA_ID value mismatch");

    fork
        send_monitor_write(16'h2503, `YFD_MON_ADDR_LA_CAPTURE_DEPTH, 32'd8, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2503, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    fork
        send_monitor_write(16'h2504, `YFD_MON_ADDR_LA_PRETRIGGER_DEPTH, 32'd3, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2504, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    // Use a deterministic non-matching trigger so the Monitor status read can
    // distinguish live ARMED(1) from a sticky OR of ARMED(1)/CAPTURING(2).
    fork
        send_monitor_write(16'h250A, `YFD_MON_ADDR_LA_TRIGGER_MODE, `YFD_LA_TRIGGER_LEVEL, 32'hFFFFFFFF);
        read_until_monitor_response(16'h250A, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    fork
        send_monitor_write(16'h250B, `YFD_MON_ADDR_LA_TRIGGER_CHANNEL, 32'd31, 32'hFFFFFFFF);
        read_until_monitor_response(16'h250B, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    fork
        send_monitor_write(16'h250C, `YFD_MON_ADDR_LA_TRIGGER_VALUE, 32'd1, 32'hFFFFFFFF);
        read_until_monitor_response(16'h250C, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    fork
        send_monitor_write(16'h2505, `YFD_MON_ADDR_LA_CONTROL, 32'h00000005, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2505, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    fork
        send_monitor_write(16'h2506, `YFD_MON_ADDR_LA_COMMAND, 32'h00000001, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2506, `YFD_TYPE_MONITOR_WRITE_RESP);
    join

    repeat (20) @(posedge clk_p);
    fork
        send_monitor_read(16'h250D, `YFD_MON_ADDR_LA_STATUS);
        read_until_monitor_response(16'h250D, `YFD_TYPE_MONITOR_READ_RESP);
    join
    check((payload_u32(10) & 32'h00000007) == `YFD_LA_STATE_ARMED,
          "LA_STATUS state must reflect live ARMED state without sticky OR corruption");
    fork
        send_monitor_write(16'h2507, `YFD_MON_ADDR_LA_COMMAND, 32'h00000008, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2507, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    repeat (200) @(posedge clk_p);
    check(dut.la_done, "LA capture should complete after force trigger");

    fork
        send_monitor_write(16'h2508, `YFD_MON_ADDR_LA_COMMAND, 32'h00000010, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2508, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    read_until_la_readout();

    check(la_header_count != 0, "LA header frame should be transmitted");
    check(la_trigger_count != 0, "LA trigger frame should be transmitted");
    check(la_data_count != 0, "LA data chunk should be transmitted");
    check(la_status_count != 0, "LA status frame should be transmitted");
    check(monitor_count != 0, "Monitor frames should coexist with LA frames");
    check(dut.la_msg_valid == 1'b0 || dut.la_msg_ready == 1'b1, "LA TX backpressure should be observable");

    fork
        send_monitor_write(16'h2509, `YFD_MON_ADDR_LA_COMMAND, 32'h00000004, 32'hFFFFFFFF);
        read_until_monitor_response(16'h2509, `YFD_TYPE_MONITOR_WRITE_RESP);
    join
    repeat (10) @(posedge clk_p);
    check(dut.la_core_state == `YFD_LA_STATE_IDLE, "LA clear should return core to IDLE");

    if (errors == 0) begin
        $display("PASS: YiFPGA Logic Analyzer M25 board demo checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
