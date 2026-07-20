`timescale 1ns / 1ps

module yifpga_debug_ring_buffer #(
    parameter ADDR_WIDTH = 4
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        wr_valid,
    input  wire [7:0]  wr_type,
    input  wire [7:0]  wr_len,
    input  wire [255:0] wr_payload,
    output wire        wr_ready,

    output wire        rd_valid,
    output wire [7:0]  rd_type,
    output wire [7:0]  rd_len,
    output wire [255:0] rd_payload,
    input  wire        rd_ready,

    output wire [ADDR_WIDTH:0] used_count
);

localparam DEPTH = (1 << ADDR_WIDTH);
localparam ENTRY_WIDTH = 272;

reg [ENTRY_WIDTH-1:0] mem [0:DEPTH-1];
reg [ADDR_WIDTH-1:0] wr_ptr;
reg [ADDR_WIDTH-1:0] rd_ptr;
reg [ADDR_WIDTH:0]   count;

wire full;
wire empty;
wire do_read;
wire do_write;

assign full = (count == DEPTH[ADDR_WIDTH:0]);
assign empty = (count == {ADDR_WIDTH + 1{1'b0}});
assign wr_ready = !full || rd_ready;
assign rd_valid = !empty;
assign do_read = rd_valid && rd_ready;
assign do_write = wr_valid && wr_ready;
assign used_count = count;

assign rd_type = mem[rd_ptr][271:264];
assign rd_len = mem[rd_ptr][263:256];
assign rd_payload = mem[rd_ptr][255:0];

always @(posedge clk) begin
    if (rst) begin
        wr_ptr <= {ADDR_WIDTH{1'b0}};
        rd_ptr <= {ADDR_WIDTH{1'b0}};
        count <= {ADDR_WIDTH + 1{1'b0}};
    end else begin
        if (do_write) begin
            mem[wr_ptr] <= {wr_type, wr_len, wr_payload};
            wr_ptr <= wr_ptr + {{ADDR_WIDTH-1{1'b0}}, 1'b1};
        end

        if (do_read) begin
            rd_ptr <= rd_ptr + {{ADDR_WIDTH-1{1'b0}}, 1'b1};
        end

        case ({do_write, do_read})
            2'b10: count <= count + {{ADDR_WIDTH{1'b0}}, 1'b1};
            2'b01: count <= count - {{ADDR_WIDTH{1'b0}}, 1'b1};
            default: count <= count;
        endcase
    end
end

endmodule
