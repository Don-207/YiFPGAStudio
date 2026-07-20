`timescale 1ns / 1ps

`include "yifpga_la_pkg.vh"

module yifpga_la_adapter (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] timestamp,
    input  wire        start_readout_pulse,
    output reg         core_start_readout_pulse,
    output reg         core_readout_done_pulse,
    input  wire [2:0]  core_state,
    input  wire [7:0]  core_error_code,
    input  wire [15:0] core_samples_written,
    input  wire [15:0] core_trigger_index,
    input  wire [31:0] core_capture_id,
    input  wire [15:0] core_capture_flags,
    input  wire [31:0] core_sample_period_cycles,
    input  wire [4:0]  core_trigger_channel,
    input  wire [31:0] core_trigger_sample_value,
    input  wire [31:0] core_trigger_value,
    output reg         core_read_req,
    output reg  [15:0] core_read_index,
    input  wire [31:0] core_read_sample,
    input  wire        core_read_valid,
    output reg         msg_valid,
    input  wire        msg_ready,
    output reg  [7:0]  msg_type,
    output reg  [7:0]  payload_len,
    output reg  [255:0] payload_flat
);

localparam ST_IDLE = 3'd0;
localparam ST_HEADER = 3'd1;
localparam ST_TRIGGER = 3'd2;
localparam ST_READ = 3'd3;
localparam ST_DATA = 3'd4;
localparam ST_STATUS = 3'd5;
localparam ST_DONE = 3'd6;

reg [2:0] state = ST_IDLE;
reg [15:0] chunk_index = 16'd0;
reg [15:0] sample_index = 16'd0;
reg [15:0] chunks_total = 16'd0;
reg [15:0] samples_in_chunk = 16'd0;
reg [15:0] chunks_sent = 16'd0;
reg [255:0] data_payload = 256'd0;

wire can_load_msg = !msg_valid || msg_ready;
wire [15:0] remaining_samples = core_samples_written - sample_index;
wire [15:0] next_samples_in_chunk =
    (remaining_samples > {8'd0, `YFD_LA_SAMPLES_PER_CHUNK}) ? {8'd0, `YFD_LA_SAMPLES_PER_CHUNK} : remaining_samples;
wire capture_has_trigger = (core_capture_flags & `YFD_LA_FLAG_TRIGGERED) != 16'd0;

always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        chunk_index <= 16'd0;
        sample_index <= 16'd0;
        chunks_total <= 16'd0;
        samples_in_chunk <= 16'd0;
        chunks_sent <= 16'd0;
        data_payload <= 256'd0;
        core_start_readout_pulse <= 1'b0;
        core_readout_done_pulse <= 1'b0;
        core_read_req <= 1'b0;
        core_read_index <= 16'd0;
        msg_valid <= 1'b0;
        msg_type <= 8'd0;
        payload_len <= 8'd0;
        payload_flat <= 256'd0;
    end else begin
        core_start_readout_pulse <= 1'b0;
        core_readout_done_pulse <= 1'b0;
        core_read_req <= 1'b0;

        if (msg_valid && msg_ready) begin
            msg_valid <= 1'b0;
        end

        case (state)
            ST_IDLE: begin
                if (start_readout_pulse && (core_state == `YFD_LA_STATE_DONE)) begin
                    core_start_readout_pulse <= 1'b1;
                    chunks_total <= (core_samples_written + {8'd0, `YFD_LA_SAMPLES_PER_CHUNK} - 16'd1) /
                                    {8'd0, `YFD_LA_SAMPLES_PER_CHUNK};
                    chunk_index <= 16'd0;
                    sample_index <= 16'd0;
                    chunks_sent <= 16'd0;
                    state <= ST_HEADER;
                end
            end

            ST_HEADER: begin
                if (can_load_msg) begin
                    msg_valid <= 1'b1;
                    msg_type <= `YFD_TYPE_LA_CAPTURE_HEADER;
                    payload_len <= `YFD_LA_LEN_CAPTURE_HEADER;
                    payload_flat <= 256'd0;
                    payload_flat[31:0] <= core_capture_id;
                    payload_flat[63:32] <= timestamp;
                    payload_flat[79:64] <= `YFD_LA_SAMPLE_WIDTH_BITS;
                    payload_flat[95:80] <= core_samples_written;
                    payload_flat[111:96] <= core_trigger_index;
                    payload_flat[127:112] <= core_capture_flags;
                    payload_flat[159:128] <= core_sample_period_cycles;
                    payload_flat[175:160] <= `YFD_LA_CHANNEL_COUNT;
                    payload_flat[191:176] <= 16'd0;
                    state <= capture_has_trigger ? ST_TRIGGER : ST_READ;
                end
            end

            ST_TRIGGER: begin
                if (can_load_msg) begin
                    msg_valid <= 1'b1;
                    msg_type <= `YFD_TYPE_LA_TRIGGER_EVENT;
                    payload_len <= `YFD_LA_LEN_TRIGGER_EVENT;
                    payload_flat <= 256'd0;
                    payload_flat[31:0] <= timestamp;
                    payload_flat[63:32] <= core_capture_id;
                    payload_flat[79:64] <= core_trigger_index;
                    payload_flat[95:80] <= {11'd0, core_trigger_channel};
                    payload_flat[127:96] <= core_trigger_sample_value;
                    payload_flat[159:128] <= core_trigger_value;
                    state <= ST_READ;
                end
            end

            ST_READ: begin
                if (sample_index >= core_samples_written) begin
                    state <= ST_STATUS;
                end else begin
                    samples_in_chunk <= next_samples_in_chunk;
                    data_payload <= 256'd0;
                    data_payload[31:0] <= core_capture_id;
                    data_payload[47:32] <= chunk_index;
                    data_payload[63:48] <= sample_index;
                    data_payload[71:64] <= `YFD_LA_SAMPLE_BYTES;
                    data_payload[79:72] <= next_samples_in_chunk[7:0];
                    data_payload[95:80] <= 16'd0;
                    core_read_index <= sample_index;
                    core_read_req <= 1'b1;
                    state <= ST_DATA;
                end
            end

            ST_DATA: begin
                if (core_read_valid) begin
                    case (core_read_index - sample_index)
                        16'd0: data_payload[127:96] <= core_read_sample;
                        16'd1: data_payload[159:128] <= core_read_sample;
                        16'd2: data_payload[191:160] <= core_read_sample;
                        16'd3: data_payload[223:192] <= core_read_sample;
                        16'd4: data_payload[255:224] <= core_read_sample;
                        default: data_payload <= data_payload;
                    endcase

                    if ((core_read_index - sample_index + 16'd1) >= samples_in_chunk) begin
                        if (can_load_msg) begin
                            msg_valid <= 1'b1;
                            msg_type <= `YFD_TYPE_LA_SAMPLE_DATA;
                            payload_len <= `YFD_LA_LEN_SAMPLE_DATA;
                            payload_flat <= data_payload;
                            case (core_read_index - sample_index)
                                16'd0: payload_flat[127:96] <= core_read_sample;
                                16'd1: payload_flat[159:128] <= core_read_sample;
                                16'd2: payload_flat[191:160] <= core_read_sample;
                                16'd3: payload_flat[223:192] <= core_read_sample;
                                16'd4: payload_flat[255:224] <= core_read_sample;
                                default: payload_flat <= data_payload;
                            endcase
                            sample_index <= sample_index + samples_in_chunk;
                            chunk_index <= chunk_index + 16'd1;
                            chunks_sent <= chunks_sent + 16'd1;
                            state <= ST_READ;
                        end
                    end else begin
                        core_read_index <= core_read_index + 16'd1;
                        core_read_req <= 1'b1;
                    end
                end
            end

            ST_STATUS: begin
                if (can_load_msg) begin
                    msg_valid <= 1'b1;
                    msg_type <= `YFD_TYPE_LA_CAPTURE_STATUS;
                    payload_len <= `YFD_LA_LEN_CAPTURE_STATUS;
                    payload_flat <= 256'd0;
                    payload_flat[31:0] <= timestamp;
                    payload_flat[63:32] <= core_capture_id;
                    payload_flat[71:64] <= core_state;
                    payload_flat[79:72] <= core_error_code;
                    payload_flat[95:80] <= core_samples_written;
                    payload_flat[111:96] <= chunks_sent;
                    payload_flat[127:112] <= chunks_total;
                    payload_flat[159:128] <= {16'd0, core_capture_flags};
                    state <= ST_DONE;
                end
            end

            ST_DONE: begin
                core_readout_done_pulse <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
