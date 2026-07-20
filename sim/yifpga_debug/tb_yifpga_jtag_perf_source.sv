`timescale 1ns/1ps
module tb_yifpga_jtag_perf_source;
logic clk = 0, rst_n = 0, ready = 0;
logic [7:0] data;
logic valid;
logic [7:0] stalled_data;
byte frame [0:8];
integer index = 0;
integer frames = 0;
integer i;
byte checksum;

always #5 clk = ~clk;

yifpga_jtag_perf_source #(.BYTE_INTERVAL_TICKS(2)) dut (
    .clk(clk), .rst_n(rst_n), .data(data), .valid(valid), .ready(ready)
);

always @(posedge clk) begin
    if (rst_n && valid && ready) begin
        frame[index] = data;
        if (index == 8) begin
            $display("FRAME %02x %02x %02x %02x %02x %02x %02x %02x %02x",
                     frame[0], frame[1], frame[2], frame[3], frame[4], frame[5],
                     frame[6], frame[7], data);
            if (frame[0] !== 8'hA5 || frame[1] !== 1 || frame[2] !== 1 || frame[3] !== 4)
                $fatal(1, "invalid frame header");
            checksum = 0;
            for (i = 1; i < 8; i = i + 1) checksum = checksum ^ frame[i];
            if (checksum !== data) $fatal(1, "invalid checksum");
            frames = frames + 1;
            index = 0;
        end else index = index + 1;
    end
end

initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    wait(dut.pending);
    stalled_data = data;
    repeat (5) begin
        @(posedge clk);
        if (valid) $fatal(1, "source submitted while ring was not ready");
        if (data !== stalled_data) $fatal(1, "data changed under backpressure");
    end
    @(negedge clk);
    ready = 1;
    wait(frames == 4);
    $display("PASS: JTAG performance source emitted four valid frames");
    $finish;
end
endmodule
