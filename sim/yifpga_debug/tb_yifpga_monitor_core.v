`timescale 1ns / 1ps

`include "yifpga_monitor_pkg.vh"
`include "yifpga_profiler_pkg.vh"

module tb_yifpga_monitor_core;

reg clk = 1'b0;
reg rst = 1'b1;
reg req_valid = 1'b0;
wire req_ready;
reg [15:0] req_seq = 16'd0;
reg [15:0] req_addr = 16'd0;
reg req_write = 1'b0;
reg [7:0] req_width = 8'd4;
reg [31:0] req_wdata = 32'd0;
reg [31:0] req_wmask = 32'hFFFFFFFF;
wire resp_valid;
reg resp_ready = 1'b1;
wire [15:0] resp_seq;
wire [15:0] resp_addr;
wire resp_write;
wire [7:0] resp_width;
wire [7:0] resp_status;
wire [31:0] resp_rdata;
wire [31:0] resp_old_value;
wire [31:0] resp_new_value;
reg [31:0] counter0 = 32'h00001234;
wire [31:0] control;
wire [31:0] led_control;
wire [31:0] demo_period;
wire [31:0] error_status;
wire clear_counters_pulse;
wire [31:0] profiler_control;
wire [31:0] profiler_sample_period;
wire profiler_clear_pulse;
wire [31:0] profiler_status;
wire [31:0] profiler_metric_mask0;
wire [31:0] profiler_alert_threshold0;
reg saw_clear_counters_pulse = 1'b0;
reg saw_profiler_clear_pulse = 1'b0;
integer errors = 0;

always #5 clk = ~clk;

always @(posedge clk) begin
    if (rst) begin
        saw_clear_counters_pulse <= 1'b0;
    end else if (clear_counters_pulse) begin
        saw_clear_counters_pulse <= 1'b1;
    end
    if (rst) begin
        saw_profiler_clear_pulse <= 1'b0;
    end else if (profiler_clear_pulse) begin
        saw_profiler_clear_pulse <= 1'b1;
    end
end

yifpga_monitor_core #(
    .DEFAULT_DEMO_PERIOD(32'd100)
) dut (
    .clk(clk),
    .rst(rst),
    .req_valid(req_valid),
    .req_ready(req_ready),
    .req_seq(req_seq),
    .req_addr(req_addr),
    .req_write(req_write),
    .req_width(req_width),
    .req_wdata(req_wdata),
    .req_wmask(req_wmask),
    .resp_valid(resp_valid),
    .resp_ready(resp_ready),
    .resp_seq(resp_seq),
    .resp_addr(resp_addr),
    .resp_write(resp_write),
    .resp_width(resp_width),
    .resp_status(resp_status),
    .resp_rdata(resp_rdata),
    .resp_old_value(resp_old_value),
    .resp_new_value(resp_new_value),
    .counter0(counter0),
    .profiler_status_set(32'd0),
    .control(control),
    .led_control(led_control),
    .demo_period(demo_period),
    .error_status(error_status),
    .clear_counters_pulse(clear_counters_pulse),
    .profiler_control(profiler_control),
    .profiler_sample_period(profiler_sample_period),
    .profiler_clear_pulse(profiler_clear_pulse),
    .profiler_status(profiler_status),
    .profiler_metric_mask0(profiler_metric_mask0),
    .profiler_alert_threshold0(profiler_alert_threshold0)
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

task request;
    input [15:0] seq;
    input [15:0] addr;
    input write;
    input [31:0] value;
    input [31:0] mask;
    begin
        while (resp_valid) begin
            @(posedge clk);
            #1;
        end
        req_seq = seq;
        req_addr = addr;
        req_write = write;
        req_width = 8'd4;
        req_wdata = value;
        req_wmask = mask;
        req_valid = 1'b1;
        @(posedge clk);
        #1;
        while (!req_ready) @(posedge clk);
        req_valid = 1'b0;
        wait (resp_valid);
        #1;
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (3) @(posedge clk);

    request(16'd1, `YFD_MON_ADDR_ID, 1'b0, 32'd0, 32'd0);
    check(resp_status == `YFD_MON_STATUS_OK, "MONITOR_ID read should pass");
    check(resp_rdata == `YFD_MONITOR_ID_VALUE, "MONITOR_ID value mismatch");

    request(16'd2, `YFD_MON_ADDR_LED_CONTROL, 1'b1, 32'h0000000F, 32'h0000000F);
    check(resp_status == `YFD_MON_STATUS_OK, "LED_CONTROL write should pass");
    check(led_control == 32'h0000000F, "LED_CONTROL should update");
    request(16'd3, `YFD_MON_ADDR_LED_CONTROL, 1'b1, 32'h00000005, 32'h0000000A);
    check(resp_new_value == 32'h00000005, "mask write should merge bits");
    check(led_control == 32'h00000005, "mask write should store merged bits");

    request(16'd4, `YFD_MON_ADDR_ID, 1'b1, 32'hFFFFFFFF, 32'hFFFFFFFF);
    check(resp_status == `YFD_MON_STATUS_DENIED, "write to RO should be denied");

    dut.u_reg_bank.error_status = 32'h0000000F;
    request(16'd5, `YFD_MON_ADDR_ERROR_STATUS, 1'b1, 32'h00000005, 32'hFFFFFFFF);
    check(resp_status == `YFD_MON_STATUS_OK, "W1C write should pass");
    check(error_status == 32'h0000000A, "W1C should clear written one bits");

    request(16'd6, `YFD_MON_ADDR_CLEAR_COUNTERS, 1'b1, 32'h00000001, 32'hFFFFFFFF);
    check(resp_status == `YFD_MON_STATUS_OK, "TRIGGER write should pass");
    check(saw_clear_counters_pulse, "TRIGGER should pulse for one cycle");
    @(posedge clk);
    check(!clear_counters_pulse, "TRIGGER pulse should be one cycle");

    request(16'd7, 16'h00F0, 1'b0, 32'd0, 32'd0);
    check(resp_status == `YFD_MON_STATUS_BAD_ADDR, "bad address should be rejected");

    request(16'd8, `YFD_MON_ADDR_DEMO_PERIOD, 1'b1, 32'd0, 32'hFFFFFFFF);
    check(resp_status == `YFD_MON_STATUS_BAD_VALUE, "zero demo period should be rejected");

    request(16'd9, `YFD_MON_ADDR_PROFILER_ID, 1'b0, 32'd0, 32'd0);
    check(resp_status == `YFD_MON_STATUS_OK, "PROFILER_ID read should pass");
    check(resp_rdata == `YFD_PROFILER_ID_VALUE, "PROFILER_ID value mismatch");

    request(16'd10, `YFD_MON_ADDR_PROFILER_CONTROL, 1'b1, 32'h00000001, 32'h00000001);
    check(resp_status == `YFD_MON_STATUS_OK, "PROFILER_CONTROL write should pass");
    check(profiler_control[0], "PROFILER_CONTROL enable should update");

    request(16'd11, `YFD_MON_ADDR_PROFILER_SAMPLE_PERIOD, 1'b1, 32'd12, 32'hFFFFFFFF);
    check(resp_status == `YFD_MON_STATUS_OK, "PROFILER_SAMPLE_PERIOD write should pass");
    check(profiler_sample_period == 32'd12, "PROFILER_SAMPLE_PERIOD should update");

    request(16'd12, `YFD_MON_ADDR_PROFILER_SAMPLE_PERIOD, 1'b1, 32'd0, 32'hFFFFFFFF);
    check(resp_status == `YFD_MON_STATUS_BAD_VALUE, "zero profiler period should be rejected");

    request(16'd13, `YFD_MON_ADDR_PROFILER_CLEAR, 1'b1, 32'h00000001, 32'hFFFFFFFF);
    check(resp_status == `YFD_MON_STATUS_OK, "PROFILER_CLEAR trigger should pass");
    check(saw_profiler_clear_pulse, "PROFILER_CLEAR should pulse for one cycle");

    if (errors == 0) begin
        $display("PASS: YiFPGA Monitor M14 core register checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
