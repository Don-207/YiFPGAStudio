`timescale 1ns / 1ps

`include "yifpga_profiler_pkg.vh"

module tb_yifpga_profiler_core;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b0;
reg clear_pulse = 1'b0;
reg [31:0] sample_period = 32'd4;
reg [31:0] metric_mask = 32'hFFFFFFFF;
reg metric_valid = 1'b0;
wire metric_ready;
reg [15:0] metric_id = `YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT;
reg [31:0] metric_value0 = 32'd0;
reg [31:0] metric_value1 = 32'd0;
reg [31:0] metric_value2 = 32'd0;
reg [31:0] metric_value3 = 32'd0;
reg metric_overflow = 1'b0;
wire snapshot_valid;
reg snapshot_ready = 1'b1;
wire [15:0] snapshot_metric_id;
wire [15:0] snapshot_flags;
wire [31:0] snapshot_sample_cycles;
wire [31:0] snapshot_value0;
wire [31:0] snapshot_value1;
wire [31:0] snapshot_value2;
wire [31:0] snapshot_value3;
wire [15:0] snapshot_overflow_count;
wire alert_valid;
reg alert_ready = 1'b1;
wire [15:0] alert_metric_id;
wire [7:0] alert_level;
wire [7:0] alert_code;
wire [31:0] alert_arg0;
wire [31:0] alert_arg1;
reg [31:0] timestamp = 32'h12345678;
wire adapter_snapshot_ready;
wire adapter_alert_ready;
wire msg_valid;
reg msg_ready = 1'b1;
wire [7:0] msg_type;
wire [7:0] payload_len;
wire [255:0] payload_flat;
integer errors = 0;

always #5 clk = ~clk;

initial begin
    #20000;
    $display("ERROR: M18 profiler testbench timeout");
    $finish;
end

always @(posedge clk) begin
    if (rst) begin
        timestamp <= 32'h12345678;
    end else begin
        timestamp <= timestamp + 32'd1;
    end
end

yifpga_profiler_core #(
    .DEFAULT_SAMPLE_PERIOD(32'd4)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .clear_pulse(clear_pulse),
    .sample_period(sample_period),
    .metric_mask(metric_mask),
    .metric_valid(metric_valid),
    .metric_ready(metric_ready),
    .metric_id(metric_id),
    .metric_value0(metric_value0),
    .metric_value1(metric_value1),
    .metric_value2(metric_value2),
    .metric_value3(metric_value3),
    .metric_overflow(metric_overflow),
    .snapshot_valid(snapshot_valid),
    .snapshot_ready(snapshot_ready),
    .snapshot_metric_id(snapshot_metric_id),
    .snapshot_flags(snapshot_flags),
    .snapshot_sample_cycles(snapshot_sample_cycles),
    .snapshot_value0(snapshot_value0),
    .snapshot_value1(snapshot_value1),
    .snapshot_value2(snapshot_value2),
    .snapshot_value3(snapshot_value3),
    .snapshot_overflow_count(snapshot_overflow_count),
    .alert_valid(alert_valid),
    .alert_ready(alert_ready),
    .alert_metric_id(alert_metric_id),
    .alert_level(alert_level),
    .alert_code(alert_code),
    .alert_arg0(alert_arg0),
    .alert_arg1(alert_arg1)
);

yifpga_profiler_adapter u_adapter (
    .clk(clk),
    .rst(rst),
    .timestamp(timestamp),
    .snapshot_valid(snapshot_valid),
    .snapshot_ready(adapter_snapshot_ready),
    .snapshot_metric_id(snapshot_metric_id),
    .snapshot_flags(snapshot_flags),
    .snapshot_sample_cycles(snapshot_sample_cycles),
    .snapshot_value0(snapshot_value0),
    .snapshot_value1(snapshot_value1),
    .snapshot_value2(snapshot_value2),
    .snapshot_value3(snapshot_value3),
    .snapshot_overflow_count(snapshot_overflow_count),
    .alert_valid(alert_valid),
    .alert_ready(adapter_alert_ready),
    .alert_metric_id(alert_metric_id),
    .alert_level(alert_level),
    .alert_code(alert_code),
    .alert_arg0(alert_arg0),
    .alert_arg1(alert_arg1),
    .msg_valid(msg_valid),
    .msg_ready(msg_ready),
    .msg_type(msg_type),
    .payload_len(payload_len),
    .payload_flat(payload_flat)
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

task send_metric;
    input [15:0] id;
    input [31:0] v0;
    input [31:0] v1;
    input [31:0] v2;
    input [31:0] v3;
    input ovf;
    begin
        metric_id = id;
        metric_value0 = v0;
        metric_value1 = v1;
        metric_value2 = v2;
        metric_value3 = v3;
        metric_overflow = ovf;
        while (!metric_ready) begin
            @(posedge clk);
            #1;
        end
        metric_valid = 1'b1;
        @(posedge clk);
        #1;
        metric_valid = 1'b0;
        metric_overflow = 1'b0;
    end
endtask

task wait_snapshot;
    begin
        while (!snapshot_valid) begin
            @(posedge clk);
            #1;
        end
    end
endtask

task pulse_clear;
    begin
        clear_pulse = 1'b1;
        @(posedge clk);
        #1;
        clear_pulse = 1'b0;
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    metric_id = `YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT;
    metric_value0 = 32'd10;
    metric_value1 = 32'd1;
    metric_value2 = 32'd2;
    metric_value3 = 32'd3;
    metric_valid = 1'b1;
    @(posedge clk);
    #1;
    metric_valid = 1'b0;
    repeat (8) @(posedge clk);
    check(!snapshot_valid, "disabled profiler should not emit snapshot");
    $display("INFO: disabled path checked");

    enable = 1'b1;
    send_metric(`YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT, 32'd10, 32'd1, 32'd2, 32'd3, 1'b0);
    send_metric(`YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT, 32'd5, 32'd2, 32'd3, 32'd4, 1'b0);
    wait_snapshot();
    check(snapshot_metric_id == `YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT, "snapshot metric id mismatch");
    check(snapshot_flags[0], "snapshot VALID flag missing");
    check(snapshot_flags[2], "snapshot WINDOW_RESET flag missing");
    check(snapshot_sample_cycles == 32'd4, "snapshot sample cycles mismatch");
    check(snapshot_value0 == 32'd15, "snapshot value0 accumulation mismatch");
    check(snapshot_value1 == 32'd3, "snapshot value1 accumulation mismatch");
    check(snapshot_value2 == 32'd5, "snapshot value2 accumulation mismatch");
    check(snapshot_value3 == 32'd7, "snapshot value3 accumulation mismatch");
    @(posedge clk);
    #1;
    $display("INFO: accumulation snapshot checked");

    metric_mask = 32'hFFFFFFFD;
    send_metric(`YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT, 32'd100, 32'd0, 32'd0, 32'd0, 1'b0);
    repeat (8) @(posedge clk);
    check(!snapshot_valid, "masked metric should not emit snapshot");
    metric_mask = 32'hFFFFFFFF;
    $display("INFO: metric mask checked");

    send_metric(`YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT, 32'd7, 32'd0, 32'd0, 32'd0, 1'b0);
    pulse_clear();
    repeat (6) @(posedge clk);
    check(!snapshot_valid, "clear should remove pending window data");
    $display("INFO: clear path checked");

    snapshot_ready = 1'b0;
    send_metric(`YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT, 32'd1, 32'd1, 32'd1, 32'd1, 1'b0);
    wait_snapshot();
    check(snapshot_valid, "snapshot should hold while ready is low");
    repeat (3) @(posedge clk);
    check(snapshot_valid, "snapshot should remain valid under backpressure");
    snapshot_ready = 1'b1;
    @(posedge clk);
    #1;
    check(!snapshot_valid, "snapshot should clear after ready");
    $display("INFO: snapshot backpressure checked");

    alert_ready = 1'b0;
    send_metric(`YFD_PROFILER_METRIC_FIFO_DEMO_LEVEL, 32'd60, 32'd0, 32'd0, 32'd0, 1'b1);
    check(alert_valid, "metric overflow should emit alert");
    check(alert_metric_id == `YFD_PROFILER_METRIC_FIFO_DEMO_LEVEL, "alert metric id mismatch");
    check(alert_code == `YFD_PROFILER_ALERT_OVERFLOW, "alert code mismatch");
    wait_snapshot();
    check(snapshot_flags[1], "overflow snapshot should set SATURATED");
    check(snapshot_overflow_count != 16'd0, "overflow count should be nonzero");
    $display("INFO: overflow and alert checked");

    alert_ready = adapter_alert_ready;
    snapshot_ready = adapter_snapshot_ready;
    @(posedge clk);
    #1;
    if (msg_valid && msg_type == `YFD_TYPE_PROFILER_ALERT) begin
        check(payload_len == `YFD_PROFILER_LEN_ALERT, "alert payload length mismatch");
        check(payload_flat[47:32] == `YFD_PROFILER_METRIC_FIFO_DEMO_LEVEL, "alert payload metric mismatch");
        check(payload_flat[63:56] == `YFD_PROFILER_ALERT_OVERFLOW, "alert payload code mismatch");
        @(posedge clk);
        #1;
    end
    wait_snapshot();
    @(posedge clk);
    #1;
    check(msg_valid, "adapter should emit profiler message");
    check(msg_type == `YFD_TYPE_PROFILER_SNAPSHOT, "adapter snapshot type mismatch");
    check(payload_len == `YFD_PROFILER_LEN_SNAPSHOT, "snapshot payload length mismatch");
    check(payload_flat[47:32] == `YFD_PROFILER_METRIC_FIFO_DEMO_LEVEL, "snapshot payload metric mismatch");
    check(payload_flat[63:48] & `YFD_PROFILER_FLAG_VALID, "snapshot payload VALID flag mismatch");
    check(payload_flat[239:224] != 16'd0, "snapshot payload overflow count mismatch");

    if (errors == 0) begin
        $display("PASS: YiFPGA Profiler M18 core snapshot checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
