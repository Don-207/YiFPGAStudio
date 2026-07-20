`timescale 1ns / 1ps

`include "yifpga_debug_pkg.vh"
`include "yifpga_monitor_pkg.vh"

module yifpga_debug_command_parser (
    input  wire        clk,
    input  wire        rst,

    input  wire        byte_valid,
    input  wire [7:0]  byte_data,

    output reg         monitor_req_valid,
    input  wire        monitor_req_ready,
    output reg  [15:0] monitor_req_seq,
    output reg  [15:0] monitor_req_addr,
    output reg         monitor_req_write,
    output reg  [7:0]  monitor_req_width,
    output reg  [31:0] monitor_req_wdata,
    output reg  [31:0] monitor_req_wmask,

    output reg         checksum_error,
    output reg         bad_len_error,
    output reg         unsupported_error,
    output wire [2:0]  debug_state
);

localparam STATE_SOF      = 3'd0;
localparam STATE_VERSION  = 3'd1;
localparam STATE_TYPE     = 3'd2;
localparam STATE_LEN      = 3'd3;
localparam STATE_PAYLOAD  = 3'd4;
localparam STATE_CHECKSUM = 3'd5;

reg [2:0] state = STATE_SOF;
reg [7:0] frame_type = 8'd0;
reg [7:0] frame_len = 8'd0;
reg [7:0] payload_index = 8'd0;
reg [7:0] checksum = 8'd0;
reg [255:0] payload = 256'd0;

assign debug_state = state;

wire pending_block = monitor_req_valid && !monitor_req_ready;
wire is_read_req = frame_type == `YFD_TYPE_MONITOR_READ_REQ;
wire is_write_req = frame_type == `YFD_TYPE_MONITOR_WRITE_REQ;
wire len_ok = (is_read_req && frame_len == 8'd5) || (is_write_req && frame_len == 8'd13);
wire width_ok = (payload[39:32] == 8'd1) || (payload[39:32] == 8'd2) || (payload[39:32] == 8'd4);

always @(posedge clk) begin
    if (rst) begin
        state <= STATE_SOF;
        frame_type <= 8'd0;
        frame_len <= 8'd0;
        payload_index <= 8'd0;
        checksum <= 8'd0;
        payload <= 256'd0;
        monitor_req_valid <= 1'b0;
        monitor_req_seq <= 16'd0;
        monitor_req_addr <= 16'd0;
        monitor_req_write <= 1'b0;
        monitor_req_width <= 8'd0;
        monitor_req_wdata <= 32'd0;
        monitor_req_wmask <= 32'd0;
        checksum_error <= 1'b0;
        bad_len_error <= 1'b0;
        unsupported_error <= 1'b0;
    end else begin
        checksum_error <= 1'b0;
        bad_len_error <= 1'b0;
        unsupported_error <= 1'b0;

        if (monitor_req_valid && monitor_req_ready) begin
            monitor_req_valid <= 1'b0;
        end

        if (byte_valid && !pending_block) begin
            case (state)
                STATE_SOF: begin
                    if (byte_data == `YFD_SOF) begin
                        state <= STATE_VERSION;
                        checksum <= 8'd0;
                        payload <= 256'd0;
                    end
                end
                STATE_VERSION: begin
                    if (byte_data == `YFD_VERSION) begin
                        checksum <= byte_data;
                        state <= STATE_TYPE;
                    end else if (byte_data == `YFD_SOF) begin
                        state <= STATE_VERSION;
                        checksum <= 8'd0;
                    end else begin
                        state <= STATE_SOF;
                    end
                end
                STATE_TYPE: begin
                    frame_type <= byte_data;
                    checksum <= checksum ^ byte_data;
                    state <= STATE_LEN;
                end
                STATE_LEN: begin
                    frame_len <= byte_data;
                    payload_index <= 8'd0;
                    checksum <= checksum ^ byte_data;
                    if (byte_data > `YFD_MAX_PAYLOAD_BYTES) begin
                        bad_len_error <= 1'b1;
                        state <= STATE_SOF;
                    end else if (byte_data == 8'd0) begin
                        state <= STATE_CHECKSUM;
                    end else begin
                        state <= STATE_PAYLOAD;
                    end
                end
                STATE_PAYLOAD: begin
                    payload[(payload_index * 8) +: 8] <= byte_data;
                    checksum <= checksum ^ byte_data;
                    if (payload_index == frame_len - 8'd1) begin
                        state <= STATE_CHECKSUM;
                    end
                    payload_index <= payload_index + 8'd1;
                end
                STATE_CHECKSUM: begin
                    state <= STATE_SOF;
                    if (byte_data != checksum) begin
                        checksum_error <= 1'b1;
                    end else if (!is_read_req && !is_write_req) begin
                        unsupported_error <= 1'b1;
                    end else if (!len_ok || !width_ok) begin
                        bad_len_error <= 1'b1;
                    end else begin
                        monitor_req_valid <= 1'b1;
                        monitor_req_seq <= payload[15:0];
                        monitor_req_addr <= payload[31:16];
                        monitor_req_width <= payload[39:32];
                        monitor_req_write <= is_write_req;
                        monitor_req_wdata <= is_write_req ? payload[71:40] : 32'd0;
                        monitor_req_wmask <= is_write_req ? payload[103:72] : 32'd0;
                    end
                end
                default: state <= STATE_SOF;
            endcase
        end
    end
end

endmodule
