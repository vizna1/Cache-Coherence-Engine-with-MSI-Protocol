`timescale 1ns/1ps
// tb_case_l2_hit.v -- force L1 eviction while keeping line in L2
module tb_case_l2_hit;
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
    localparam L1_STRIDE = LINE_BYTES * L1_SETS; // 64

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
        $dumpfile("waves_case_l2.vcd"); $dumpvars(0,tb_case_l2_hit);
        rst_n=0; #20; rst_n=1; #10;
        $display("=== CASE B: L1 MISS but L2 HIT ===");
        // 1) bring target into caches
        send_read(32'h0000_2000);
        // 2) access (ASSOC + 1) different lines that map to same L1 set to evict target from L1
        for (i=1; i<= (L1_ASSOC+1); i=i+1) begin
            send_read(32'h0000_2000 + i*L1_STRIDE);
        end
        // 3) read target again -> should be L1 miss then L2 hit (L2 supplies data)
        send_read(32'h0000_2000);
        $display("CASE B COMPLETE");
        #50 $finish;
    end
endmodule
