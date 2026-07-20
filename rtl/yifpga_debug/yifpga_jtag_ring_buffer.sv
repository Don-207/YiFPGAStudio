`timescale 1ns/1ps
module yifpga_jtag_ring_buffer #(
    parameter int ADDR_WIDTH = 12
) (
    input  logic        wr_clk,
    input  logic        wr_rst_n,
    input  logic [7:0]  wr_data,
    input  logic        wr_valid,
    output logic        wr_ready,
    output logic [31:0] write_count,
    output logic [31:0] overflow_count,
    output logic [31:0] dropped_bytes,

    input  logic        rd_clk,
    input  logic        rd_rst_n,
    output logic [7:0]  rd_data,
    output logic        rd_valid,
    input  logic        rd_ready,
    input  logic        rd_commit,
    input  logic        rd_abort,
    output logic [31:0] read_count,
    output logic [ADDR_WIDTH:0] available_bytes,
    output logic [31:0] rd_write_count,
    output logic [31:0] rd_overflow_count,
    output logic [31:0] rd_dropped_bytes
);

localparam int PTR_WIDTH = ADDR_WIDTH + 1;
(* ram_style = "block" *) logic [7:0] mem [0:(1 << ADDR_WIDTH)-1];
logic [PTR_WIDTH-1:0] wr_bin, wr_gray, rd_bin, rd_gray, rd_work_bin;
(* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] rd_gray_wr1, rd_gray_wr2;
(* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] wr_gray_rd1, wr_gray_rd2;
logic [31:0] write_count_gray, overflow_count_gray, dropped_bytes_gray;
(* ASYNC_REG = "TRUE" *) logic [31:0] write_count_gray_rd1, write_count_gray_rd2;
(* ASYNC_REG = "TRUE" *) logic [31:0] overflow_count_gray_rd1, overflow_count_gray_rd2;
(* ASYNC_REG = "TRUE" *) logic [31:0] dropped_bytes_gray_rd1, dropped_bytes_gray_rd2;
logic [PTR_WIDTH-1:0] wr_bin_next, wr_gray_next;
logic [PTR_WIDTH-1:0] committed_bytes;
logic full;

function automatic logic [PTR_WIDTH-1:0] bin_to_gray(input logic [PTR_WIDTH-1:0] value);
    return (value >> 1) ^ value;
endfunction

function automatic logic [PTR_WIDTH-1:0] gray_to_bin(input logic [PTR_WIDTH-1:0] value);
    logic [PTR_WIDTH-1:0] result;
    int i;
    begin
        result[PTR_WIDTH-1] = value[PTR_WIDTH-1];
        for (i = PTR_WIDTH-2; i >= 0; i = i-1)
            result[i] = result[i+1] ^ value[i];
        return result;
    end
endfunction

function automatic logic [31:0] gray32_to_bin(input logic [31:0] value);
    logic [31:0] result;
    int i;
    begin
        result[31] = value[31];
        for (i = 30; i >= 0; i = i-1)
            result[i] = result[i+1] ^ value[i];
        return result;
    end
endfunction

always_comb begin
    wr_bin_next  = wr_bin + 1'b1;
    wr_gray_next = bin_to_gray(wr_bin_next);
    full = (wr_gray_next == {~rd_gray_wr2[PTR_WIDTH-1:PTR_WIDTH-2],
                             rd_gray_wr2[PTR_WIDTH-3:0]});
end

assign wr_ready = !full;
assign rd_valid = (bin_to_gray(rd_work_bin) != wr_gray_rd2);
assign available_bytes = gray_to_bin(wr_gray_rd2) - rd_bin;
assign rd_write_count = gray32_to_bin(write_count_gray_rd2);
assign rd_overflow_count = gray32_to_bin(overflow_count_gray_rd2);
assign rd_dropped_bytes = gray32_to_bin(dropped_bytes_gray_rd2);
assign committed_bytes = rd_work_bin - rd_bin;

always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        wr_bin <= '0;
        wr_gray <= '0;
        rd_gray_wr1 <= '0;
        rd_gray_wr2 <= '0;
        write_count <= 32'd0;
        overflow_count <= 32'd0;
        dropped_bytes <= 32'd0;
        write_count_gray <= 32'd0;
        overflow_count_gray <= 32'd0;
        dropped_bytes_gray <= 32'd0;
    end else begin
        rd_gray_wr1 <= rd_gray;
        rd_gray_wr2 <= rd_gray_wr1;
        // Register each Gray value in its source domain so no combinational
        // logic or glitches feed the first-stage CDC synchronizers.
        write_count_gray <= (write_count >> 1) ^ write_count;
        overflow_count_gray <= (overflow_count >> 1) ^ overflow_count;
        dropped_bytes_gray <= (dropped_bytes >> 1) ^ dropped_bytes;
        if (wr_valid && wr_ready) begin
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
            write_count <= write_count + 1'b1;
        end else if (wr_valid) begin
            if (overflow_count != 32'hffff_ffff)
                overflow_count <= overflow_count + 1'b1;
            if (dropped_bytes != 32'hffff_ffff)
                dropped_bytes <= dropped_bytes + 1'b1;
        end
    end
end

// Keep memory writes out of the asynchronously-reset pointer process. Combined
// with the registered second port below, this is the supported simple dual-port
// BRAM inference template for unrelated clocks.
always_ff @(posedge wr_clk) begin
    if (wr_rst_n && wr_valid && wr_ready)
        mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
end

always_ff @(posedge rd_clk) begin
    if (rd_valid && rd_ready)
        rd_data <= mem[(rd_work_bin + 1'b1) & ((1 << ADDR_WIDTH)-1)];
    else
        rd_data <= mem[rd_work_bin[ADDR_WIDTH-1:0]];
end

always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        rd_bin <= '0;
        rd_gray <= '0;
        rd_work_bin <= '0;
        wr_gray_rd1 <= '0;
        wr_gray_rd2 <= '0;
        write_count_gray_rd1 <= '0;
        write_count_gray_rd2 <= '0;
        overflow_count_gray_rd1 <= '0;
        overflow_count_gray_rd2 <= '0;
        dropped_bytes_gray_rd1 <= '0;
        dropped_bytes_gray_rd2 <= '0;
        read_count <= 32'd0;
    end else begin
        wr_gray_rd1 <= wr_gray;
        wr_gray_rd2 <= wr_gray_rd1;
        write_count_gray_rd1 <= write_count_gray;
        write_count_gray_rd2 <= write_count_gray_rd1;
        overflow_count_gray_rd1 <= overflow_count_gray;
        overflow_count_gray_rd2 <= overflow_count_gray_rd1;
        dropped_bytes_gray_rd1 <= dropped_bytes_gray;
        dropped_bytes_gray_rd2 <= dropped_bytes_gray_rd1;
        // Reads advance only the speculative pointer. UPDATE/commit publishes
        // the complete transaction to the writer domain; abort rolls it back.
        if (rd_abort)
            rd_work_bin <= rd_bin;
        else if (rd_valid && rd_ready)
            rd_work_bin <= rd_work_bin + 1'b1;
        if (rd_commit) begin
            rd_bin <= rd_work_bin;
            rd_gray <= bin_to_gray(rd_work_bin);
            // Explicitly widen the pointer delta before addition. Keeping the
            // subtraction's PTR_WIDTH out of the accumulator expression avoids
            // synthesis truncating read_count at the ring-pointer wrap boundary.
            read_count <= read_count + {{(32-PTR_WIDTH){1'b0}}, committed_bytes};
        end
    end
end

endmodule
