`timescale 1ns/1ps
module tb_yifpga_jtag_transport;
localparam int ADDR_WIDTH = 4;
logic debug_clk = 0, jtag_clk = 0;
logic debug_rst_n = 0, jtag_rst_n = 0;
logic [7:0] debug_data;
logic debug_valid, debug_ready;
logic header_req, payload_req, payload_ready, payload_commit, payload_abort;
logic [5:0] header_addr;
logic [7:0] header_data, payload_data;
logic header_valid, payload_valid;
logic [31:0] overflow_count, dropped_bytes;
logic [31:0] session_id;
logic [7:0] router_in_data, router_uart_data, router_jtag_data;
logic router_in_valid, router_uart_valid, router_jtag_valid;
logic router_uart_ready, router_jtag_ready;
logic [31:0] router_uart_drop, router_jtag_drop;
byte expected[$];
int errors = 0;

always #5 debug_clk = ~debug_clk;
always #7 jtag_clk = ~jtag_clk;

yifpga_jtag_transport #(.ADDR_WIDTH(ADDR_WIDTH), .BUILD_ID(32'h12345678)) dut (.*);
yifpga_transport_router router (
    .clk(debug_clk), .rst_n(debug_rst_n), .in_data(router_in_data),
    .in_valid(router_in_valid), .in_ready(), .uart_data(router_uart_data),
    .uart_valid(router_uart_valid), .uart_ready(router_uart_ready),
    .jtag_data(router_jtag_data), .jtag_valid(router_jtag_valid),
    .jtag_ready(router_jtag_ready), .uart_dropped_bytes(router_uart_drop),
    .jtag_dropped_bytes(router_jtag_drop)
);

task automatic send_byte(input byte value);
    @(negedge debug_clk);
    debug_data = value;
    debug_valid = 1;
    @(negedge debug_clk);
    debug_valid = 0;
endtask

task automatic receive_byte;
    byte value;
    begin
        payload_req = 1;
        payload_ready = 1;
        do @(posedge jtag_clk); while (!payload_valid);
        value = payload_data;
        if (expected.size() == 0 || value !== expected.pop_front()) begin
            $display("ERROR payload %02x", value);
            errors++;
        end
        @(negedge jtag_clk);
        payload_req = 0;
        payload_ready = 0;
        payload_commit = 1;
        @(negedge jtag_clk);
        payload_commit = 0;
    end
endtask

initial begin
    debug_data = 0; debug_valid = 0; header_req = 0; header_addr = 0;
    payload_req = 0; payload_ready = 0; payload_commit = 0; payload_abort = 0;
    session_id = 32'd1;
    router_in_data = 0; router_in_valid = 0;
    router_uart_ready = 0; router_jtag_ready = 1;
    #31; debug_rst_n = 1; jtag_rst_n = 1;

    @(negedge debug_clk); router_in_data = 8'ha5; router_in_valid = 1;
    @(posedge debug_clk); #1;
    if (!router_jtag_valid || router_uart_valid) errors++;
    @(negedge debug_clk); router_in_valid = 0;
    if (router_uart_drop != 1 || router_jtag_drop != 0) begin
        $display("ERROR router independent drop accounting"); errors++;
    end

    for (int i = 0; i < 12; i++) begin
        expected.push_back(i);
        send_byte(i);
    end
    repeat (5) @(posedge jtag_clk);
    for (int i = 0; i < 12; i++) receive_byte();

    // An aborted speculative read must return the same byte and not consume it.
    expected.push_back(8'h55);
    send_byte(8'h55);
    repeat (3) @(posedge jtag_clk);
    payload_req = 1; payload_ready = 1;
    do @(posedge jtag_clk); while (!payload_valid);
    if (dut.read_count != 12) begin
        $display("ERROR speculative read changed committed count"); errors++;
    end
    @(negedge jtag_clk); payload_req = 0; payload_ready = 0; payload_abort = 1;
    @(negedge jtag_clk); payload_abort = 0;
    if (dut.read_count != 12) begin
        $display("ERROR abort changed committed count"); errors++;
    end
    receive_byte();

    // Force a full ring and verify drop-newest visibility.
    for (int i = 0; i < 20; i++) send_byte(8'h80 + i);
    repeat (3) @(posedge debug_clk);
    if (dropped_bytes == 0 || overflow_count == 0) begin
        $display("ERROR overflow counters did not increment");
        errors++;
    end

    header_req = 1; header_addr = 0; #1;
    if (!header_valid || header_data !== 8'h4f) begin
        $display("ERROR mailbox magic byte");
        errors++;
    end

    session_id = 32'd2;
    header_addr = 6'h08; #1;
    if (header_data !== 8'h02) begin
        $display("ERROR session id update"); errors++;
    end

    if (errors == 0) $display("PASS: tb_yifpga_jtag_transport");
    else $fatal(1, "FAIL: %0d errors", errors);
    $finish;
end
endmodule
