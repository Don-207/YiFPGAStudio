`timescale 1ns/1ps
// Legal Debug Protocol heartbeat stream for sustained JTAG transport testing.
module yifpga_jtag_perf_source #(
    parameter int BYTE_INTERVAL_TICKS = 50
) (
    input  logic       clk,
    input  logic       rst_n,
    output logic [7:0] data,
    output logic       valid,
    input  logic       ready
);

logic [31:0] frame_counter;
logic [3:0] byte_index;
logic [31:0] interval_count;
logic pending;
logic [7:0] payload_xor;

always_comb begin
    payload_xor = frame_counter[7:0] ^ frame_counter[15:8] ^ frame_counter[23:16] ^ frame_counter[31:24];
    case (byte_index)
        4'd0: data = 8'hA5;
        4'd1: data = 8'h01;
        4'd2: data = 8'h01;
        4'd3: data = 8'h04;
        4'd4: data = frame_counter[7:0];
        4'd5: data = frame_counter[15:8];
        4'd6: data = frame_counter[23:16];
        4'd7: data = frame_counter[31:24];
        default: data = 8'h04 ^ payload_xor;
    endcase
    // The JTAG ring is drop-newest rather than a backpressured stream: only
    // present a transfer when space exists, while retaining the byte locally.
    valid = pending && ready;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_counter <= 32'd0;
        byte_index <= 4'd0;
        interval_count <= 32'd0;
        pending <= 1'b0;
    end else if (pending) begin
        if (ready) begin
            pending <= 1'b0;
            if (byte_index == 4'd8) begin
                byte_index <= 4'd0;
                frame_counter <= frame_counter + 1'b1;
            end else begin
                byte_index <= byte_index + 1'b1;
            end
        end
    end else if (interval_count == BYTE_INTERVAL_TICKS - 1) begin
        interval_count <= 32'd0;
        pending <= 1'b1;
    end else begin
        interval_count <= interval_count + 1'b1;
    end
end

endmodule
