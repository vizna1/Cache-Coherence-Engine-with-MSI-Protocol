`timescale 1ns/1ps
// tb_case_l1_hit.v -- L1 hit: populate then immediate re-read
module tb_case_l1_hit;
    reg clk = 0; reg rst_n = 0;
    reg cpu_req_valid=0, cpu_req_write=0;
    reg [31:0] cpu_addr=0, cpu_wdata=0;
    wire cpu_resp_valid; wire [31:0] cpu_rdata;

    top_system dut(
      .clk(clk), .rst_n(rst_n),
      .cpu_req_valid(cpu_req_valid), .cpu_req_write(cpu_req_write),
      .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
      .cpu_resp_valid(cpu_resp_valid), .cpu_rdata(cpu_rdata)
    );

    localparam LINE_BYTES = 16;
    always #5 clk = ~clk;

    task send_read(input [31:0] addr);
    begin
        @(posedge clk); cpu_addr <= addr; cpu_req_write <= 0; cpu_req_valid <= 1;
        @(posedge clk); cpu_req_valid <= 0;
        wait(cpu_resp_valid);
        $display("%0t: READ addr=%08h -> data=%08h", $time, addr, cpu_rdata);
        #2;
    end endtask

    initial begin
        $dumpfile("waves_case_l1.vcd"); $dumpvars(0,tb_case_l1_hit);
        rst_n = 0; #20; rst_n = 1; #10;
        $display("=== CASE A: L1 HIT ===");
        // cold read -> populate caches
        send_read(32'h0000_1000);
        // immediate second read should be served by L1 (L1 hit)
        send_read(32'h0000_1000);
        $display("CASE A COMPLETE");
        #50 $finish;
    end
endmodule
