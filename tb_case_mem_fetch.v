`timescale 1ns/1ps
// tb_case_mem_fetch.v -- evict from both L1 and L2 so access goes to memory
module tb_case_mem_fetch;
    reg clk=0, rst_n=0;
    reg cpu_req_valid=0, cpu_req_write=0;
    reg [31:0] cpu_addr=0, cpu_wdata=0;
    wire cpu_resp_valid; wire [31:0] cpu_rdata;

    top_system dut(.clk(clk),.rst_n(rst_n),
        .cpu_req_valid(cpu_req_valid), .cpu_req_write(cpu_req_write),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_resp_valid(cpu_resp_valid), .cpu_rdata(cpu_rdata)
    );

    localparam LINE_BYTES = 16;
    localparam L1_ASSOC = 2;
    localparam L1_SETS  = 4;
    localparam L2_SETS  = 16;
    localparam L2_ASSOC = 4;
    localparam L1_STRIDE = LINE_BYTES * L1_SETS; // 64
    localparam L2_STRIDE = LINE_BYTES * L2_SETS; // 256

    always #5 clk = ~clk;

    task send_read(input [31:0] addr);
    begin
        @(posedge clk); cpu_addr<=addr; cpu_req_write<=0; cpu_req_valid<=1;
        @(posedge clk); cpu_req_valid<=0;
        wait(cpu_resp_valid);
        $display("%0t: READ addr=%08h -> %08h", $time, addr, cpu_rdata);
        #2;
    end endtask

    integer i;
    initial begin
        $dumpfile("waves_case_mem.vcd"); $dumpvars(0,tb_case_mem_fetch);
        rst_n=0; #20; rst_n=1; #10;
        $display("=== CASE C: BOTH MISS -> MEMORY ===");
        // 1) bring target into caches
        send_read(32'h0000_4000);
        // 2) evict from L1 by accessing several lines that map to same L1 set
        for (i=1; i<= (L1_ASSOC+1); i=i+1) send_read(32'h0000_4000 + i*L1_STRIDE);
        // 3) evict from L2 by accessing a different address that maps to same L2 set (direct-mapped)
        for (i=0; i<= L2_ASSOC; i=i+1) begin
            send_read(32'h0000_4000 + i*L2_STRIDE);
        end // this replaces the L2 line that held target
        // 4) now read original target -> should miss L1 & L2 and fetch from memory
        send_read(32'h0000_4000);
        $display("CASE C COMPLETE");
        #50 $finish;
    end
endmodule
