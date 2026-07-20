`timescale 1ns/1ps
module tb_yifpga_jtag_user_dr;
logic tck = 0, rst_n = 0, sel = 0, capture = 0, shift = 0, update = 0, tdi = 0;
logic tdo, header_req, payload_req, payload_ready, payload_commit, payload_abort;
logic [5:0] header_addr;
logic [7:0] header_data, payload_data;
logic header_valid, payload_valid;
logic [7:0] payload_mem [0:15];
integer payload_index = 0;
integer errors = 0;
always #5 tck = ~tck;
assign header_data = header_addr;
assign header_valid = header_req && header_addr < 40;
assign payload_data = payload_mem[payload_index];
assign payload_valid = payload_req && payload_index < 16;
always @(posedge tck) if (payload_ready) payload_index <= payload_index + 1;

yifpga_jtag_user_dr dut (.*);

task automatic pulse_capture;
    @(negedge tck); sel=1; capture=1; @(negedge tck); capture=0;
endtask
task automatic pulse_update;
    shift=0; update=1; @(negedge tck); update=0;
endtask
task automatic send_request(input [7:0] opcode, input [15:0] length);
    logic [31:0] request;
    begin
        request = {length, opcode, 8'ha6};
        pulse_capture(); shift=1;
        for (int i=0; i<32; i++) begin
            tdi=request[i]; @(negedge tck);
        end
        pulse_update();
    end
endtask
task automatic read_bits(input int count);
    begin
        pulse_capture(); shift=1;
        repeat (count) @(negedge tck);
        pulse_update();
    end
endtask

initial begin
    for (int i=0; i<16; i++) payload_mem[i] = 8'h80+i;
    #17; rst_n=1; sel=1;

    send_request(8'h01, 16'd40);
    pulse_capture(); shift=1;
    for (int bitno=0; bitno<320; bitno++) begin
        #1;
        if (tdo !== header_addr[bitno%8]) begin
            $display("ERROR header bit %0d", bitno); errors++;
        end
        @(negedge tck);
    end
    pulse_update();
    if (payload_commit || payload_abort) begin
        $display("ERROR header altered payload transaction"); errors++;
    end

    send_request(8'h02, 16'd4);
    read_bits(16); // partial response must abort
    if (!payload_abort || payload_commit || payload_index != 2) begin
        $display("ERROR partial payload transaction"); errors++;
    end
    // The ring-buffer layer consumes the abort pulse and rewinds its work pointer.
    payload_index = 0;
    send_request(8'h02, 16'd4);
    read_bits(32);
    if (!payload_commit || payload_abort || payload_index != 4) begin
        $display("ERROR complete payload transaction"); errors++;
    end

    send_request(8'h02, 16'd0);
    read_bits(8);
    if (payload_commit || payload_abort) begin
        $display("ERROR malformed request accepted"); errors++;
    end

    if (errors == 0) $display("PASS: tb_yifpga_jtag_user_dr");
    else $fatal(1, "FAIL: %0d errors", errors);
    $finish;
end
endmodule
