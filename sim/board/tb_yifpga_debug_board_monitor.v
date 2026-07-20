`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_monitor_pkg.vh"

module tb_yifpga_debug_board_monitor;

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
reg [7:0] frame_type;
reg [7:0] frame_len;
reg [7:0] payload [0:31];
reg [7:0] rx_byte;
reg [7:0] frame_checksum;

always #5 clk_p = ~clk_p;

yifpga_debug_board_demo #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .UART_BAUD(UART_BAUD),
    .BUFFER_ADDR_WIDTH(4),
    .HEARTBEAT_INTERVAL_TICKS(1000000),
    .EVENT_INTERVAL_TICKS(1000000),
    .WATCH_INTERVAL_TICKS(1000000),
    .PRINT_INTERVAL_TICKS(1000000),
    .STATUS_INTERVAL_TICKS(1000000),
    .TRACE_SCENARIO_INTERVAL_TICKS(1000000),
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
    integer bit_index;
    begin
        value = 8'd0;
        wait (uart_tx == 1'b0);
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

initial begin
    repeat (5) @(posedge clk_p);
    reset_n = 1'b1;
    repeat (100000) @(posedge clk_p);

    fork
        send_monitor_read(16'h1001, `YFD_MON_ADDR_ID);
        read_frame(frame_type, frame_len);
    join
    check(frame_type == `YFD_TYPE_MONITOR_READ_RESP, "MONITOR_ID should return read response");
    check(frame_len == 8'd14, "read response length mismatch");
    check(payload_u16(4) == 16'h1001, "read response seq mismatch");
    check(payload[8] == `YFD_MON_STATUS_OK, "MONITOR_ID read should be OK");
    check(payload_u32(10) == `YFD_MONITOR_ID_VALUE, "MONITOR_ID response value mismatch");

    fork
        send_monitor_write(16'h1002, `YFD_MON_ADDR_LED_CONTROL, 32'h00000003, 32'hFFFFFFFF);
        read_frame(frame_type, frame_len);
    join
    check(frame_type == `YFD_TYPE_MONITOR_WRITE_RESP, "LED_CONTROL should return write response");
    check(frame_len == 8'd17, "write response length mismatch");
    check(payload_u16(4) == 16'h1002, "write response seq mismatch");
    check(payload[8] == `YFD_MON_STATUS_OK, "LED_CONTROL write should be OK");
    repeat (5) @(posedge clk_p);
    check(led0 && led1, "LED_CONTROL should drive both board LEDs");

    fork
        send_monitor_write(16'h1003, `YFD_MON_ADDR_ID, 32'hFFFFFFFF, 32'hFFFFFFFF);
        read_frame(frame_type, frame_len);
    join
    check(frame_type == `YFD_TYPE_MONITOR_WRITE_RESP, "RO write should return write response");
    check(payload[8] == `YFD_MON_STATUS_DENIED, "RO write should be denied");

    if (errors == 0) begin
        $display("PASS: YiFPGA Monitor M16 board UART RX to response path checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
