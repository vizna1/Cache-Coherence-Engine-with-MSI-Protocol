`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 19.07.2026 10:18:50
// Design Name: 
// Module Name: tb_I1_writeback
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns/1ps
// tb_l1_writeback.v
// Make an L1 line dirty, then evict it from L1 (forcing L1 -> L2 writeback).
// Verify the dirty data survived by reading the same address back
// (L1 will miss and refill from L2, which should hold the written value).
module tb_l1_writeback;
    reg clk = 0, rst_n = 0;
    reg cpu_req_valid=0, cpu_req_write=0;
    reg [31:0] cpu_addr=0, cpu_wdata=0;
    wire cpu_resp_valid; wire [31:0] cpu_rdata;
    top_system dut(
      .clk(clk), .rst_n(rst_n),
      .cpu_req_valid(cpu_req_valid), .cpu_req_write(cpu_req_write),
      .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
      .cpu_resp_valid(cpu_resp_valid), .cpu_rdata(cpu_rdata)
    );
    // parameters matching your design
    localparam LINE_BYTES = 16;
    localparam L1_ASSOC   = 2;
    localparam L1_SETS    = 4;
    localparam L1_STRIDE  = LINE_BYTES * L1_SETS; // 64

    always #5 clk = ~clk;

    task send_read(input [31:0] addr);
    begin
        @(posedge clk);
        cpu_addr <= addr; cpu_req_write <= 0; cpu_req_valid <= 1;
        @(posedge clk); cpu_req_valid <= 0;
        wait(cpu_resp_valid);
        $display("%0t: READ  addr=%08h -> data=%08h", $time, addr, cpu_rdata);
        #2;
    end endtask

    task send_write(input [31:0] addr, input [31:0] data);
    begin
        @(posedge clk);
        cpu_addr <= addr; cpu_wdata <= data; cpu_req_write <= 1; cpu_req_valid <= 1;
        @(posedge clk); cpu_req_valid <= 0;
        wait(cpu_resp_valid);
        $display("%0t: WRITE addr=%08h data=%08h DONE", $time, addr, data);
        #2;
    end endtask

    integer i;
    reg [31:0] test_addr, test_data;

    initial begin
        $dumpfile("waves_l1_writeback.vcd");
        $dumpvars(0, tb_l1_writeback);

        rst_n = 0; #20; rst_n = 1; #10;

        $display("=== TB_L1_WRITEBACK START ===");
        test_addr = 32'h0000_1000;       // line-aligned base
        test_data = 32'hDEADBEEF;

        // 1) cold read to populate L1 (and L2 behind it)
        $display("--- Step 1: cold read to populate L1 ---");
        send_read(test_addr);

        // 2) write to make the L1 line dirty (Modified)
        $display("--- Step 2: write to same line (dirty in L1) ---");
        send_write(test_addr, test_data);

        // 3) evict from L1 by accessing (L1_ASSOC+1) other addresses
        //    that map to the same L1 set -> forces L1 -> L2 writeback
        $display("--- Step 3: evict from L1 (expect L1 -> L2 writeback) ---");
        for (i = 1; i <= (L1_ASSOC + 1); i = i + 1) begin
            send_read(test_addr + i * L1_STRIDE);
        end

        // allow a few cycles for the L1 -> L2 writeback to complete
        #100;

        // 4) read the original address again: L1 will miss (it was evicted),
        //    request goes to L2, which should still hold the dirty data
        //    if the writeback in step 3 worked correctly.
        $display("--- Step 4: re-read original addr (expect L2 to serve dirty data) ---");
        send_read(test_addr);

        if (cpu_rdata === test_data)
            $display("TEST PASS: L1->L2 writeback verified, got %08h", test_data);
        else
            $display("TEST FAIL: got %08h (expected %08h)", cpu_rdata, test_data);

        $display("=== TB_L1_WRITEBACK COMPLETE ===");
        #50 $finish;
    end
endmodule