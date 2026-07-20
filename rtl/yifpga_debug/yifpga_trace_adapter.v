`timescale 1ns / 1ps

`include "yifpga_trace_pkg.vh"

module yifpga_trace_adapter (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] timestamp,

    input  wire        span_begin_valid,
    input  wire [15:0] span_begin_trace_id,
    input  wire [15:0] span_begin_instance_id,
    input  wire [31:0] span_begin_arg0,

    input  wire        span_end_valid,
    input  wire [15:0] span_end_trace_id,
    input  wire [15:0] span_end_instance_id,
    input  wire [7:0]  span_end_status,
    input  wire [31:0] span_end_arg0,

    input  wire        mark_valid,
    input  wire [15:0] mark_trace_id,
    input  wire [7:0]  mark_level,
    input  wire [31:0] mark_arg0,

    input  wire        value_valid,
    input  wire [15:0] value_trace_id,
    input  wire [15:0] value_id,
    input  wire [31:0] value_data,

    input  wire        drop_valid,
    input  wire [15:0] drop_trace_id,
    input  wire [31:0] drop_count,

    output wire        trace_ready,
    output wire        trace_accepted,
    output wire        trace_dropped,

    output reg         msg_valid,
    output reg  [7:0]  msg_type,
    output reg  [7:0]  payload_len,
    output reg  [255:0] payload_flat,
    input  wire        msg_ready
);

wire [2:0] input_count;
reg        incoming_valid;
reg [7:0]  incoming_type;
reg [7:0]  incoming_len;
reg [255:0] incoming_payload;

assign input_count = {2'b0, span_begin_valid} + {2'b0, span_end_valid} +
                     {2'b0, mark_valid} + {2'b0, value_valid} +
                     {2'b0, drop_valid};
assign trace_ready = (!msg_valid || msg_ready) && (input_count <= 3'd1);
assign trace_accepted = msg_valid && msg_ready;
assign trace_dropped = (input_count > 3'd1) ||
                       ((input_count != 3'd0) && msg_valid && !msg_ready);

always @(*) begin
    incoming_valid = 1'b0;
    incoming_type = 8'd0;
    incoming_len = 8'd0;
    incoming_payload = 256'd0;

    if (span_begin_valid) begin
        incoming_valid = 1'b1;
        incoming_type = `YFD_TYPE_TRACE_SPAN_BEGIN;
        incoming_len = `YFD_TRACE_LEN_SPAN_BEGIN;
        incoming_payload[31:0] = timestamp;
        incoming_payload[47:32] = span_begin_trace_id;
        incoming_payload[63:48] = span_begin_instance_id;
        incoming_payload[95:64] = span_begin_arg0;
    end else if (span_end_valid) begin
        incoming_valid = 1'b1;
        incoming_type = `YFD_TYPE_TRACE_SPAN_END;
        incoming_len = `YFD_TRACE_LEN_SPAN_END;
        incoming_payload[31:0] = timestamp;
        incoming_payload[47:32] = span_end_trace_id;
        incoming_payload[63:48] = span_end_instance_id;
        incoming_payload[71:64] = span_end_status;
        incoming_payload[103:72] = span_end_arg0;
    end else if (mark_valid) begin
        incoming_valid = 1'b1;
        incoming_type = `YFD_TYPE_TRACE_MARK;
        incoming_len = `YFD_TRACE_LEN_MARK;
        incoming_payload[31:0] = timestamp;
        incoming_payload[47:32] = mark_trace_id;
        incoming_payload[55:48] = mark_level;
        incoming_payload[87:56] = mark_arg0;
    end else if (value_valid) begin
        incoming_valid = 1'b1;
        incoming_type = `YFD_TYPE_TRACE_VALUE;
        incoming_len = `YFD_TRACE_LEN_VALUE;
        incoming_payload[31:0] = timestamp;
        incoming_payload[47:32] = value_trace_id;
        incoming_payload[63:48] = value_id;
        incoming_payload[95:64] = value_data;
    end else if (drop_valid) begin
        incoming_valid = 1'b1;
        incoming_type = `YFD_TYPE_TRACE_DROP;
        incoming_len = `YFD_TRACE_LEN_DROP;
        incoming_payload[31:0] = timestamp;
        incoming_payload[47:32] = drop_trace_id;
        incoming_payload[79:48] = drop_count;
    end
end

always @(posedge clk) begin
    if (rst) begin
        msg_valid <= 1'b0;
        msg_type <= 8'd0;
        payload_len <= 8'd0;
        payload_flat <= 256'd0;
    end else if (!msg_valid || msg_ready) begin
        msg_valid <= incoming_valid;
        if (incoming_valid) begin
            msg_type <= incoming_type;
            payload_len <= incoming_len;
            payload_flat <= incoming_payload;
        end
    end
end

endmodule
