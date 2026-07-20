`timescale 1ns / 1ps

`include "yifpga_profiler_pkg.vh"

module tb_yifpga_profiler_probes;

reg clk = 1'b0;
reg rst = 1'b1;
reg clear = 1'b0;
reg enable = 1'b1;
integer errors = 0;

reg axis_valid = 1'b0;
reg axis_ready = 1'b0;
reg [3:0] axis_keep = 4'h0;
reg axis_last = 1'b0;
wire axis_metric_valid;
wire [15:0] axis_metric_id;
wire [31:0] axis_value0;
wire [31:0] axis_value1;
wire [31:0] axis_value2;
wire [31:0] axis_value3;
wire axis_overflow;

reg [7:0] fifo_level = 8'd0;
reg fifo_wr_en = 1'b0;
reg fifo_rd_en = 1'b0;
reg fifo_full = 1'b0;
reg fifo_empty = 1'b1;
reg fifo_overflow = 1'b0;
reg fifo_underflow = 1'b0;
wire fifo_metric_valid;
wire [15:0] fifo_metric_id;
wire [31:0] fifo_value0;
wire [31:0] fifo_value1;
wire [31:0] fifo_value2;
wire [31:0] fifo_value3;
wire fifo_metric_overflow;

reg frame_start = 1'b0;
reg frame_done = 1'b0;
reg frame_drop = 1'b0;
reg frame_error = 1'b0;
wire frame_metric_valid;
wire [15:0] frame_metric_id;
wire [31:0] frame_value0;
wire [31:0] frame_value1;
wire [31:0] frame_value2;
wire [31:0] frame_value3;
wire frame_metric_overflow;

reg start_valid = 1'b0;
reg end_valid = 1'b0;
reg timeout_clear = 1'b0;
wire latency_busy;
wire latency_metric_valid;
wire [15:0] latency_metric_id;
wire [31:0] latency_value0;
wire [31:0] latency_value1;
wire [31:0] latency_value2;
wire [31:0] latency_value3;
wire latency_metric_overflow;

always #5 clk = ~clk;

initial begin
    #30000;
    $display("ERROR: M19 profiler probe testbench timeout");
    $finish;
end

yifpga_profiler_axis_probe #(
    .DATA_WIDTH(32),
    .STALL_MODE(2)
) u_axis_probe (
    .clk(clk),
    .rst(rst),
    .clear(clear),
    .enable(enable),
    .axis_valid(axis_valid),
    .axis_ready(axis_ready),
    .axis_keep(axis_keep),
    .axis_last(axis_last),
    .metric_valid(axis_metric_valid),
    .metric_id(axis_metric_id),
    .metric_value0(axis_value0),
    .metric_value1(axis_value1),
    .metric_value2(axis_value2),
    .metric_value3(axis_value3),
    .metric_overflow(axis_overflow)
);

yifpga_profiler_fifo_probe #(
    .LEVEL_WIDTH(8)
) u_fifo_probe (
    .clk(clk),
    .rst(rst),
    .clear(clear),
    .enable(enable),
    .fifo_level(fifo_level),
    .fifo_wr_en(fifo_wr_en),
    .fifo_rd_en(fifo_rd_en),
    .fifo_full(fifo_full),
    .fifo_empty(fifo_empty),
    .fifo_overflow(fifo_overflow),
    .fifo_underflow(fifo_underflow),
    .metric_valid(fifo_metric_valid),
    .metric_id(fifo_metric_id),
    .metric_value0(fifo_value0),
    .metric_value1(fifo_value1),
    .metric_value2(fifo_value2),
    .metric_value3(fifo_value3),
    .metric_overflow(fifo_metric_overflow)
);

yifpga_profiler_frame_probe u_frame_probe (
    .clk(clk),
    .rst(rst),
    .clear(clear),
    .enable(enable),
    .frame_start(frame_start),
    .frame_done(frame_done),
    .frame_drop(frame_drop),
    .frame_error(frame_error),
    .metric_valid(frame_metric_valid),
    .metric_id(frame_metric_id),
    .metric_value0(frame_value0),
    .metric_value1(frame_value1),
    .metric_value2(frame_value2),
    .metric_value3(frame_value3),
    .metric_overflow(frame_metric_overflow)
);

yifpga_profiler_latency #(
    .TIMEOUT_CYCLES(32'd6)
) u_latency_probe (
    .clk(clk),
    .rst(rst),
    .clear(clear),
    .enable(enable),
    .start_valid(start_valid),
    .end_valid(end_valid),
    .timeout_clear(timeout_clear),
    .busy(latency_busy),
    .metric_valid(latency_metric_valid),
    .metric_id(latency_metric_id),
    .metric_value0(latency_value0),
    .metric_value1(latency_value1),
    .metric_value2(latency_value2),
    .metric_value3(latency_value3),
    .metric_overflow(latency_metric_overflow)
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

task tick;
    begin
        @(posedge clk);
        #1;
    end
endtask

task pulse_clear;
    begin
        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();
    end
endtask

task drive_axis;
    input valid;
    input ready;
    input [3:0] keep;
    input last;
    begin
        axis_valid = valid;
        axis_ready = ready;
        axis_keep = keep;
        axis_last = last;
        tick();
        axis_valid = 1'b0;
        axis_ready = 1'b0;
        axis_keep = 4'h0;
        axis_last = 1'b0;
    end
endtask

task drive_fifo;
    input [7:0] level;
    input overflow;
    input underflow;
    begin
        fifo_level = level;
        fifo_overflow = overflow;
        fifo_underflow = underflow;
        tick();
        fifo_overflow = 1'b0;
        fifo_underflow = 1'b0;
    end
endtask

task pulse_frame_done;
    begin
        frame_done = 1'b1;
        tick();
        frame_done = 1'b0;
    end
endtask

task pulse_frame_drop_error;
    input drop;
    input error_bit;
    begin
        frame_drop = drop;
        frame_error = error_bit;
        tick();
        frame_drop = 1'b0;
        frame_error = 1'b0;
    end
endtask

task pulse_latency_start;
    begin
        start_valid = 1'b1;
        tick();
        start_valid = 1'b0;
    end
endtask

task pulse_latency_end;
    begin
        end_valid = 1'b1;
        tick();
        end_valid = 1'b0;
    end
endtask

task wait_latency_metric;
    integer wait_cycles;
    begin
        wait_cycles = 0;
        while (!latency_metric_valid && wait_cycles < 40) begin
            tick();
            wait_cycles = wait_cycles + 1;
        end
        check(latency_metric_valid, "Latency divider result timeout");
    end
endtask

initial begin
    repeat (5) tick();
    rst = 1'b0;
    repeat (2) tick();

    drive_axis(1'b1, 1'b1, 4'hF, 1'b0);
    check(axis_metric_valid, "AXIS handshake should emit metric");
    check(axis_metric_id == `YFD_PROFILER_METRIC_AXIS_DEMO_THROUGHPUT, "AXIS metric id mismatch");
    check(axis_value0 == 32'd4, "AXIS byte count mismatch");
    check(axis_value1 == 32'd1, "AXIS beat count mismatch");
    check(axis_value2 == 32'd1, "AXIS active cycle mismatch");
    check(axis_value3 == 32'd0, "AXIS no-stall mismatch");

    drive_axis(1'b1, 1'b0, 4'hF, 1'b0);
    check(axis_metric_valid, "AXIS valid stall should emit metric");
    check(axis_value0 == 32'd0, "AXIS stalled byte count should be zero");
    check(axis_value3 == 32'd1, "AXIS valid stall count mismatch");

    drive_axis(1'b0, 1'b1, 4'h0, 1'b0);
    check(axis_metric_valid, "AXIS ready stall should emit metric");
    check(axis_value3 == 32'd1, "AXIS ready stall count mismatch");

    drive_axis(1'b1, 1'b1, 4'h5, 1'b1);
    check(axis_value0 == 32'd2, "AXIS keep mask byte count mismatch");
    check(!axis_overflow, "AXIS should not mark overflow");
    $display("INFO: AXIS probe checked");

    fifo_level = 8'd10;
    pulse_clear();
    check(fifo_metric_valid, "FIFO level should emit metric");
    check(fifo_value0 == 32'd10, "FIFO current level mismatch");
    check(fifo_value1 == 32'd10, "FIFO first max level mismatch");
    check(fifo_value2 == 32'd10, "FIFO first min level mismatch");
    tick();
    check(!fifo_metric_valid, "Stable FIFO level must not re-emit cumulative metric");
    drive_fifo(8'd18, 1'b1, 1'b0);
    check(fifo_value1 == 32'd18, "FIFO max level mismatch");
    check(fifo_value2 == 32'd10, "FIFO min should hold");
    check(fifo_value3[31:16] == 16'd1, "FIFO overflow count mismatch");
    check(fifo_metric_overflow, "FIFO overflow should set metric overflow");
    drive_fifo(8'd3, 1'b0, 1'b1);
    check(fifo_value1 == 32'd18, "FIFO max should hold");
    check(fifo_value2 == 32'd3, "FIFO min level mismatch");
    check(fifo_value3[15:0] == 16'd1, "FIFO underflow count mismatch");
    fifo_level = 8'd7;
    pulse_clear();
    check(fifo_value1 == 32'd7 && fifo_value2 == 32'd7, "FIFO clear should reset window extrema");
    $display("INFO: FIFO probe checked");

    pulse_clear();
    repeat (3) tick();
    pulse_frame_done();
    check(frame_metric_valid, "Frame done should emit metric");
    check(frame_value0 == 32'd1, "Frame done count mismatch");
    check(frame_value2 == frame_value3, "First frame interval min/max should match");
    repeat (5) tick();
    pulse_frame_done();
    check(frame_value0 == 32'd2, "Second frame done count mismatch");
    check(frame_value2 <= frame_value3, "Frame min/max interval ordering mismatch");
    pulse_frame_drop_error(1'b1, 1'b1);
    check(frame_value1[31:16] == 16'd1, "Frame drop count mismatch");
    check(frame_value1[15:0] == 16'd1, "Frame error count mismatch");
    check(frame_metric_overflow, "Frame drop/error should set metric overflow");
    pulse_clear();
    pulse_frame_done();
    check(frame_value0 == 32'd1, "Frame clear should reset done count");
    $display("INFO: Frame probe checked");

    pulse_clear();
    pulse_latency_start();
    repeat (3) tick();
    pulse_latency_end();
    wait_latency_metric();
    check(latency_metric_valid, "Latency end should emit metric");
    check(latency_value0 == 32'd1, "Latency complete count mismatch");
    check(latency_value1 == latency_value2, "First latency min/max should match");
    check(latency_value3 == latency_value1, "First latency average mismatch");

    pulse_latency_start();
    repeat (5) tick();
    pulse_latency_end();
    wait_latency_metric();
    check(latency_value0 == 32'd2, "Latency second complete count mismatch");
    check(latency_value1 <= latency_value2, "Latency min/max ordering mismatch");
    check(latency_value3 >= latency_value1 && latency_value3 <= latency_value2, "Latency average should be bounded");

    pulse_latency_start();
    pulse_latency_start();
    check(latency_metric_valid, "Latency repeated start should emit busy metric");
    check(latency_metric_overflow, "Latency repeated start should set overflow");
    check(latency_value3[31:16] == 16'd1, "Latency busy count mismatch");
    timeout_clear = 1'b1;
    tick();
    timeout_clear = 1'b0;
    check(latency_metric_valid, "Latency timeout clear should emit metric");
    check(latency_metric_overflow, "Latency timeout clear should set overflow");
    check(latency_value3[15:0] == 16'd1, "Latency timeout count mismatch");
    pulse_clear();
    pulse_latency_start();
    repeat (2) tick();
    pulse_latency_end();
    wait_latency_metric();
    check(latency_value0 == 32'd1, "Latency clear should reset complete count");
    $display("INFO: Latency probe checked");

    if (errors == 0) begin
        $display("PASS: YiFPGA Profiler M19 probe checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
