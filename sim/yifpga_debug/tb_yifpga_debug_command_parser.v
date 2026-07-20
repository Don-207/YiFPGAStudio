`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_monitor_pkg.vh"

module tb_yifpga_debug_command_parser;

localparam integer CLK_FREQ_HZ = 10000000;
localparam integer UART_BAUD = 1000000;
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / UART_BAUD;

reg clk = 1'b0;
reg rst = 1'b1;
reg uart_rx = 1'b1;
wire byte_valid;
wire [7:0] byte_data;
wire frame_error;
wire monitor_req_valid;
reg monitor_req_ready = 1'b1;
wire [15:0] monitor_req_seq;
wire [15:0] monitor_req_addr;
wire monitor_req_write;
wire [7:0] monitor_req_width;
wire [31:0] monitor_req_wdata;
wire [31:0] monitor_req_wmask;
wire checksum_error;
wire bad_len_error;
wire unsupported_error;
reg had_checksum_error = 1'b0;

integer errors = 0;

always #5 clk = ~clk;

always @(posedge clk) begin
    if (rst) begin
        had_checksum_error <= 1'b0;
    end else if (checksum_error) begin
        had_checksum_error <= 1'b1;
    end
end

yifpga_debug_uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD(UART_BAUD)
) u_uart_rx (
    .clk(clk),
    .rst(rst),
    .rx(uart_rx),
    .data_valid(byte_valid),
    .data(byte_data),
    .frame_error(frame_error)
);

yifpga_debug_command_parser u_parser (
    .clk(clk),
    .rst(rst),
    .byte_valid(byte_valid),
    .byte_data(byte_data),
    .monitor_req_valid(monitor_req_valid),
    .monitor_req_ready(monitor_req_ready),
    .monitor_req_seq(monitor_req_seq),
    .monitor_req_addr(monitor_req_addr),
    .monitor_req_write(monitor_req_write),
    .monitor_req_width(monitor_req_width),
    .monitor_req_wdata(monitor_req_wdata),
    .monitor_req_wmask(monitor_req_wmask),
    .checksum_error(checksum_error),
    .bad_len_error(bad_len_error),
    .unsupported_error(unsupported_error),
    .debug_state()
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

task wait_monitor_req_valid;
    input [8 * 96 - 1:0] message;
    integer wait_cycles;
    begin
        wait_cycles = 0;
        while (!monitor_req_valid && wait_cycles < (CLKS_PER_BIT * 200)) begin
            wait_cycles = wait_cycles + 1;
            @(posedge clk);
        end
        check(monitor_req_valid, message);
    end
endtask

task uart_write_byte;
    input [7:0] value;
    integer bit_index;
    begin
        uart_rx = 1'b0;
        repeat (CLKS_PER_BIT) @(posedge clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            uart_rx = value[bit_index];
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
        uart_rx = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
    end
endtask

task send_read_req;
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

task send_write_req;
    input [15:0] seq;
    input [15:0] addr;
    input [31:0] value;
    input [31:0] mask;
    input corrupt_checksum;
    reg [7:0] sum;
    begin
        sum = `YFD_VERSION ^ `YFD_TYPE_MONITOR_WRITE_REQ ^ 8'd13 ^
              seq[7:0] ^ seq[15:8] ^ addr[7:0] ^ addr[15:8] ^ 8'd4 ^
              value[7:0] ^ value[15:8] ^ value[23:16] ^ value[31:24] ^
              mask[7:0] ^ mask[15:8] ^ mask[23:16] ^ mask[31:24];
        if (corrupt_checksum) begin
            sum = sum ^ 8'h55;
        end
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

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (CLKS_PER_BIT * 4) @(posedge clk);

    fork
        send_read_req(16'h1234, `YFD_MON_ADDR_LED_CONTROL);
        wait_monitor_req_valid("read request should produce monitor_req_valid");
    join
    check(!monitor_req_write, "read request should decode as read");
    check(monitor_req_seq == 16'h1234, "read seq mismatch");
    check(monitor_req_addr == `YFD_MON_ADDR_LED_CONTROL, "read addr mismatch");
    check(monitor_req_width == 8'd4, "read width mismatch");
    @(posedge clk);

    fork
        send_write_req(16'h2345, `YFD_MON_ADDR_LED_CONTROL, 32'h00000005, 32'h0000000F, 1'b0);
        wait_monitor_req_valid("write request should produce monitor_req_valid");
    join
    check(monitor_req_write, "write request should decode as write");
    check(monitor_req_seq == 16'h2345, "write seq mismatch");
    check(monitor_req_wdata == 32'h00000005, "write value mismatch");
    check(monitor_req_wmask == 32'h0000000F, "write mask mismatch");
    @(posedge clk);

    send_write_req(16'h3456, `YFD_MON_ADDR_LED_CONTROL, 32'h0000000A, 32'h0000000F, 1'b1);
    repeat (30) @(posedge clk);
    check(!monitor_req_valid, "bad checksum should not emit request");
    check(had_checksum_error, "bad checksum should pulse checksum_error");

    rst = 1'b1;
    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3) @(posedge clk);
    check(!monitor_req_valid, "reset should clear pending parser request");

    if (errors == 0) begin
        $display("PASS: YiFPGA Monitor M13 UART RX command parser checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
