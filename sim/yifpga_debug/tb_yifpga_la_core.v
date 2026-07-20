`timescale 1ns / 1ps

`include "yifpga_la_pkg.vh"

module tb_yifpga_la_core;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b0;
reg arm_pulse = 1'b0;
reg stop_pulse = 1'b0;
reg clear_pulse = 1'b0;
reg force_trigger_pulse = 1'b0;
wire core_start_readout_pulse;
wire core_readout_done_pulse;
reg [15:0] sample_divisor = 16'd1;
reg [15:0] capture_depth = 16'd8;
reg [15:0] pretrigger_depth = 16'd3;
reg [3:0] trigger_mode = `YFD_LA_TRIGGER_MASK_MATCH;
reg [4:0] trigger_channel = 5'd2;
reg [31:0] trigger_value = 32'd8;
reg [31:0] trigger_mask = 32'd8;
reg [31:0] sample_bus = 32'd0;
wire [2:0] state;
wire [15:0] samples_written;
wire [15:0] trigger_index;
wire [31:0] capture_id;
wire done;
wire overflow;
wire config_error;
wire [7:0] error_code;
wire [15:0] capture_flags;
wire [31:0] trigger_sample_value;
wire [4:0] trigger_hit_channel;
reg read_req = 1'b0;
reg [15:0] read_index = 16'd0;
wire [31:0] read_sample;
wire read_valid;

reg [31:0] timestamp = 32'h12345800;
reg adapter_start_readout_pulse = 1'b0;
wire adapter_read_req;
wire [15:0] adapter_read_index;
wire msg_valid;
reg msg_ready = 1'b1;
wire [7:0] msg_type;
wire [7:0] payload_len;
wire [255:0] payload_flat;

integer errors = 0;
integer i;

always #5 clk = ~clk;

always @(posedge clk) begin
    if (rst) begin
        timestamp <= 32'h12345800;
    end else begin
        timestamp <= timestamp + 32'd1;
    end
end

yifpga_la_core dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .arm_pulse(arm_pulse),
    .stop_pulse(stop_pulse),
    .clear_pulse(clear_pulse),
    .force_trigger_pulse(force_trigger_pulse),
    .start_readout_pulse(core_start_readout_pulse),
    .readout_done_pulse(core_readout_done_pulse),
    .sample_divisor(sample_divisor),
    .capture_depth(capture_depth),
    .pretrigger_depth(pretrigger_depth),
    .trigger_mode(trigger_mode),
    .trigger_channel(trigger_channel),
    .trigger_value(trigger_value),
    .trigger_mask(trigger_mask),
    .sample_bus(sample_bus),
    .state(state),
    .samples_written(samples_written),
    .trigger_index(trigger_index),
    .capture_id(capture_id),
    .done(done),
    .overflow(overflow),
    .config_error(config_error),
    .error_code(error_code),
    .capture_flags(capture_flags),
    .trigger_sample_value(trigger_sample_value),
    .trigger_hit_channel(trigger_hit_channel),
    .read_req(read_req || adapter_read_req),
    .read_index(adapter_read_req ? adapter_read_index : read_index),
    .read_sample(read_sample),
    .read_valid(read_valid)
);

yifpga_la_adapter u_adapter (
    .clk(clk),
    .rst(rst),
    .timestamp(timestamp),
    .start_readout_pulse(adapter_start_readout_pulse),
    .core_start_readout_pulse(core_start_readout_pulse),
    .core_readout_done_pulse(core_readout_done_pulse),
    .core_state(state),
    .core_error_code(error_code),
    .core_samples_written(samples_written),
    .core_trigger_index(trigger_index),
    .core_capture_id(capture_id),
    .core_capture_flags(capture_flags),
    .core_sample_period_cycles({16'd0, sample_divisor}),
    .core_trigger_channel(trigger_hit_channel),
    .core_trigger_sample_value(trigger_sample_value),
    .core_trigger_value(trigger_value),
    .core_read_req(adapter_read_req),
    .core_read_index(adapter_read_index),
    .core_read_sample(read_sample),
    .core_read_valid(read_valid),
    .msg_valid(msg_valid),
    .msg_ready(msg_ready),
    .msg_type(msg_type),
    .payload_len(payload_len),
    .payload_flat(payload_flat)
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

task pulse_arm;
    begin
        arm_pulse = 1'b1;
        @(posedge clk);
        #1;
        arm_pulse = 1'b0;
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

task pulse_force;
    begin
        force_trigger_pulse = 1'b1;
        @(posedge clk);
        #1;
        force_trigger_pulse = 1'b0;
    end
endtask

task drive_sample;
    input [31:0] value;
    begin
        sample_bus = value;
        @(posedge clk);
        #1;
    end
endtask

task wait_done;
    begin
        while (!done) begin
            @(posedge clk);
            #1;
        end
    end
endtask

task read_and_check;
    input [15:0] index;
    input [31:0] expected;
    begin
        read_index = index;
        read_req = 1'b1;
        @(posedge clk);
        #1;
        read_req = 1'b0;
        check(read_valid, "read_valid should assert");
        check(read_sample == expected, "read_sample mismatch");
    end
endtask

task wait_msg;
    input [7:0] expected_type;
    begin
        while (!msg_valid) begin
            @(posedge clk);
            #1;
        end
        check(msg_type == expected_type, "adapter message type mismatch");
    end
endtask

task accept_msg;
    begin
        @(posedge clk);
        #1;
    end
endtask

initial begin
    #50000;
    $display("ERROR: M23 logic analyzer testbench timeout");
    $finish;
end

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    pulse_arm();
    repeat (4) drive_sample(32'h000000FF);
    check(state == `YFD_LA_STATE_IDLE, "disabled core should ignore arm");

    enable = 1'b1;
    pulse_arm();
    check(state == `YFD_LA_STATE_ARMED, "arm should enter ARMED");
    drive_sample(32'd1);
    drive_sample(32'd2);
    drive_sample(32'd3);
    drive_sample(32'd4);
    drive_sample(32'd8);
    drive_sample(32'd16);
    drive_sample(32'd32);
    drive_sample(32'd64);
    wait_done();
    check(samples_written == 16'd8, "mask capture sample count mismatch");
    check(trigger_index == 16'd3, "mask trigger index mismatch");
    check(trigger_sample_value == 32'd8, "trigger sample value mismatch");
    check((capture_flags & `YFD_LA_FLAG_TRIGGERED) != 16'd0, "triggered flag missing");
    read_and_check(16'd0, 32'd2);
    read_and_check(16'd1, 32'd3);
    read_and_check(16'd2, 32'd4);
    read_and_check(16'd3, 32'd8);
    read_and_check(16'd7, 32'd64);
    $display("INFO: mask trigger capture checked");

    adapter_start_readout_pulse = 1'b1;
    @(posedge clk);
    #1;
    adapter_start_readout_pulse = 1'b0;
    wait_msg(`YFD_TYPE_LA_CAPTURE_HEADER);
    check(payload_len == `YFD_LA_LEN_CAPTURE_HEADER, "header length mismatch");
    check(payload_flat[31:0] == capture_id, "header capture id mismatch");
    check(payload_flat[95:80] == 16'd8, "header sample count mismatch");
    check(payload_flat[111:96] == 16'd3, "header trigger index mismatch");
    accept_msg();
    wait_msg(`YFD_TYPE_LA_TRIGGER_EVENT);
    check(payload_len == `YFD_LA_LEN_TRIGGER_EVENT, "trigger event length mismatch");
    check(payload_flat[127:96] == 32'd8, "trigger event sample mismatch");
    accept_msg();
    wait_msg(`YFD_TYPE_LA_SAMPLE_DATA);
    check(payload_len == `YFD_LA_LEN_SAMPLE_DATA, "sample data length mismatch");
    check(payload_flat[79:72] == 8'd5, "first chunk sample count mismatch");
    check(payload_flat[127:96] == 32'd2, "first chunk sample0 mismatch");
    accept_msg();
    wait_msg(`YFD_TYPE_LA_SAMPLE_DATA);
    check(payload_flat[79:72] == 8'd3, "second chunk sample count mismatch");
    accept_msg();
    wait_msg(`YFD_TYPE_LA_CAPTURE_STATUS);
    check(payload_len == `YFD_LA_LEN_CAPTURE_STATUS, "status length mismatch");
    check(payload_flat[111:96] == 16'd2, "status chunks sent mismatch");
    accept_msg();
    repeat (2) @(posedge clk);
    check(state == `YFD_LA_STATE_DONE, "core should return to DONE after readout");
    $display("INFO: adapter readout checked");

    msg_ready = 1'b0;
    adapter_start_readout_pulse = 1'b1;
    @(posedge clk);
    #1;
    adapter_start_readout_pulse = 1'b0;
    repeat (3) @(posedge clk);
    check(msg_valid, "adapter should hold message while ready is low");
    check(msg_type == `YFD_TYPE_LA_CAPTURE_HEADER, "held message type mismatch");
    msg_ready = 1'b1;
    wait_msg(`YFD_TYPE_LA_CAPTURE_HEADER);
    accept_msg();
    while (msg_valid || state == `YFD_LA_STATE_READOUT) begin
        @(posedge clk);
        #1;
    end
    $display("INFO: adapter backpressure checked");

    pulse_clear();
    check(state == `YFD_LA_STATE_IDLE, "clear should return to IDLE");
    check(samples_written == 16'd0, "clear should reset sample count");

    trigger_mode = `YFD_LA_TRIGGER_EDGE_RISING;
    trigger_channel = 5'd0;
    trigger_value = 32'd1;
    trigger_mask = 32'd1;
    capture_depth = 16'd5;
    pretrigger_depth = 16'd2;
    pulse_arm();
    drive_sample(32'd0);
    drive_sample(32'd0);
    drive_sample(32'd1);
    drive_sample(32'd1);
    drive_sample(32'd1);
    wait_done();
    check(trigger_index == 16'd2, "rising edge trigger index mismatch");
    check(trigger_sample_value == 32'd1, "rising edge trigger value mismatch");
    $display("INFO: edge trigger checked");

    pulse_clear();
    trigger_mode = `YFD_LA_TRIGGER_DISABLED;
    capture_depth = 16'd4;
    pretrigger_depth = 16'd2;
    pulse_arm();
    drive_sample(32'd11);
    drive_sample(32'd12);
    pulse_force();
    drive_sample(32'd13);
    drive_sample(32'd14);
    wait_done();
    check((capture_flags & `YFD_LA_FLAG_FORCED) != 16'd0, "forced flag missing");
    check(samples_written == 16'd4, "force capture depth mismatch");
    $display("INFO: force trigger checked");

    pulse_clear();
    capture_depth = 16'd200;
    pretrigger_depth = 16'd3;
    pulse_arm();
    check(state == `YFD_LA_STATE_ERROR, "bad depth should enter ERROR");
    check(config_error, "config error flag missing");
    check(error_code == `YFD_LA_ERROR_CONFIG, "config error code mismatch");

    if (errors == 0) begin
        $display("PASS: YiFPGA Logic Analyzer M23 core capture checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
