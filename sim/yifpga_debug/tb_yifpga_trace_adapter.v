`timescale 1ns / 1ps

`include "yifpga_trace_pkg.vh"

module tb_yifpga_trace_adapter;

reg clk = 1'b0;
reg rst = 1'b1;

reg [31:0] timestamp = 32'h00000064;

reg        span_begin_valid = 1'b0;
reg [15:0] span_begin_trace_id = 16'd0;
reg [15:0] span_begin_instance_id = 16'd0;
reg [31:0] span_begin_arg0 = 32'd0;

reg        span_end_valid = 1'b0;
reg [15:0] span_end_trace_id = 16'd0;
reg [15:0] span_end_instance_id = 16'd0;
reg [7:0]  span_end_status = 8'd0;
reg [31:0] span_end_arg0 = 32'd0;

reg        mark_valid = 1'b0;
reg [15:0] mark_trace_id = 16'd0;
reg [7:0]  mark_level = 8'd0;
reg [31:0] mark_arg0 = 32'd0;

reg        value_valid = 1'b0;
reg [15:0] value_trace_id = 16'd0;
reg [15:0] value_id = 16'd0;
reg [31:0] value_data = 32'd0;

reg        drop_valid = 1'b0;
reg [15:0] drop_trace_id = 16'd0;
reg [31:0] drop_count = 32'd0;

reg msg_ready = 1'b1;

wire trace_ready;
wire trace_accepted;
wire trace_dropped;
wire msg_valid;
wire [7:0] msg_type;
wire [7:0] payload_len;
wire [255:0] payload_flat;

integer errors = 0;

always #5 clk = ~clk;

yifpga_trace_adapter dut (
    .clk(clk),
    .rst(rst),
    .timestamp(timestamp),
    .span_begin_valid(span_begin_valid),
    .span_begin_trace_id(span_begin_trace_id),
    .span_begin_instance_id(span_begin_instance_id),
    .span_begin_arg0(span_begin_arg0),
    .span_end_valid(span_end_valid),
    .span_end_trace_id(span_end_trace_id),
    .span_end_instance_id(span_end_instance_id),
    .span_end_status(span_end_status),
    .span_end_arg0(span_end_arg0),
    .mark_valid(mark_valid),
    .mark_trace_id(mark_trace_id),
    .mark_level(mark_level),
    .mark_arg0(mark_arg0),
    .value_valid(value_valid),
    .value_trace_id(value_trace_id),
    .value_id(value_id),
    .value_data(value_data),
    .drop_valid(drop_valid),
    .drop_trace_id(drop_trace_id),
    .drop_count(drop_count),
    .trace_ready(trace_ready),
    .trace_accepted(trace_accepted),
    .trace_dropped(trace_dropped),
    .msg_valid(msg_valid),
    .msg_type(msg_type),
    .payload_len(payload_len),
    .payload_flat(payload_flat),
    .msg_ready(msg_ready)
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

task clear_inputs;
    begin
        span_begin_valid = 1'b0;
        span_end_valid = 1'b0;
        mark_valid = 1'b0;
        value_valid = 1'b0;
        drop_valid = 1'b0;
    end
endtask

initial begin
    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    span_begin_trace_id = `YFD_TRACE_ID_DMA;
    span_begin_instance_id = 16'h0042;
    span_begin_arg0 = 32'h00000010;
    span_begin_valid = 1'b1;
    #1;
    check(msg_valid, "span begin should assert msg_valid");
    check(msg_type == `YFD_TYPE_TRACE_SPAN_BEGIN, "span begin type mismatch");
    check(payload_len == `YFD_TRACE_LEN_SPAN_BEGIN, "span begin length mismatch");
    check(payload_flat[31:0] == 32'h00000064, "span begin timestamp mismatch");
    check(payload_flat[47:32] == `YFD_TRACE_ID_DMA, "span begin trace_id mismatch");
    check(payload_flat[63:48] == 16'h0042, "span begin instance_id mismatch");
    check(payload_flat[95:64] == 32'h00000010, "span begin arg0 mismatch");
    check(trace_ready, "single ready input should assert trace_ready");
    check(trace_accepted, "ready span begin should be accepted");
    clear_inputs();

    timestamp = 32'h000000A0;
    span_end_trace_id = `YFD_TRACE_ID_DMA;
    span_end_instance_id = 16'h0042;
    span_end_status = `YFD_TRACE_STATUS_TIMEOUT;
    span_end_arg0 = 32'h00000020;
    span_end_valid = 1'b1;
    #1;
    check(msg_type == `YFD_TYPE_TRACE_SPAN_END, "span end type mismatch");
    check(payload_len == `YFD_TRACE_LEN_SPAN_END, "span end length mismatch");
    check(payload_flat[71:64] == `YFD_TRACE_STATUS_TIMEOUT, "span end status mismatch");
    check(payload_flat[103:72] == 32'h00000020, "span end arg0 mismatch");
    clear_inputs();

    timestamp = 32'h00000078;
    mark_trace_id = `YFD_TRACE_ID_FIFO;
    mark_level = 8'd2;
    mark_arg0 = 32'h00000080;
    mark_valid = 1'b1;
    #1;
    check(msg_type == `YFD_TYPE_TRACE_MARK, "mark type mismatch");
    check(payload_len == `YFD_TRACE_LEN_MARK, "mark length mismatch");
    check(payload_flat[55:48] == 8'd2, "mark level mismatch");
    check(payload_flat[87:56] == 32'h00000080, "mark arg0 mismatch");
    clear_inputs();

    timestamp = 32'h00000082;
    value_trace_id = `YFD_TRACE_ID_FIFO;
    value_id = 16'h0001;
    value_data = 32'h0000007C;
    value_valid = 1'b1;
    #1;
    check(msg_type == `YFD_TYPE_TRACE_VALUE, "value type mismatch");
    check(payload_len == `YFD_TRACE_LEN_VALUE, "value length mismatch");
    check(payload_flat[63:48] == 16'h0001, "value id mismatch");
    check(payload_flat[95:64] == 32'h0000007C, "value data mismatch");
    clear_inputs();

    timestamp = 32'h0000008C;
    drop_trace_id = `YFD_TRACE_ID_GLOBAL;
    drop_count = 32'd3;
    drop_valid = 1'b1;
    #1;
    check(msg_type == `YFD_TYPE_TRACE_DROP, "drop type mismatch");
    check(payload_len == `YFD_TRACE_LEN_DROP, "drop length mismatch");
    check(payload_flat[47:32] == `YFD_TRACE_ID_GLOBAL, "drop trace id mismatch");
    check(payload_flat[79:48] == 32'd3, "drop count mismatch");
    clear_inputs();

    msg_ready = 1'b0;
    span_begin_valid = 1'b1;
    #1;
    check(!trace_ready, "backpressure should deassert trace_ready");
    check(!trace_accepted, "backpressure should block acceptance");
    check(trace_dropped, "backpressure should flag a dropped pulse");
    clear_inputs();
    msg_ready = 1'b1;

    span_begin_valid = 1'b1;
    mark_valid = 1'b1;
    #1;
    check(msg_type == `YFD_TYPE_TRACE_SPAN_BEGIN, "priority should select span begin before mark");
    check(!trace_ready, "multiple same-cycle inputs should deassert trace_ready");
    check(trace_accepted, "priority message should still be accepted");
    check(trace_dropped, "non-selected same-cycle input should be reported dropped");
    clear_inputs();

    if (errors == 0) begin
        $display("PASS: YiFPGA Trace Adapter payload and handshake checks passed");
    end else begin
        $display("FAIL: %0d errors", errors);
    end
    $finish;
end

endmodule
