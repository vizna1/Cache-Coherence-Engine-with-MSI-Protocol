`timescale 1ns/1ps
// tb_mem_writeback.v
// Make a write in L1, push it down to L2, evict from L2 so memory is written, then verify mem holds the value.

module tb_mem_writeback;
    reg clk=0, rst_n=0;
    reg cpu_req_valid=0, cpu_req_write=0;
    reg [31:0] cpu_addr=0, cpu_wdata=0;
    wire cpu_resp_valid; wire [31:0] cpu_rdata;

    top_system dut(.clk(clk),.rst_n(rst_n),
        .cpu_req_valid(cpu_req_valid),.cpu_req_write(cpu_req_write),
        .cpu_addr(cpu_addr),.cpu_wdata(cpu_wdata),
        .cpu_resp_valid(cpu_resp_valid),.cpu_rdata(cpu_rdata)
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
    reg [31:0] test_addr = 32'h0000_3000;
    reg [31:0] test_data = 32'hFEEDFACE;

    initial begin
        $dumpfile("waves_mem_writeback.vcd"); $dumpvars(0,tb_mem_writeback);
        rst_n=0; #20; rst_n=1; #10;
        $display("=== TB_MEM_WRITEBACK START ===");

        // populate and dirty
        send_read(test_addr);
        send_write(test_addr, test_data);

        // evict from L1 so L2 gets dirty copy
        for (i=1; i <= (L1_ASSOC + 1); i=i+1) send_read(test_addr + i * L1_STRIDE);
        #100;

        // evict L2 by accessing an address mapping to same L2 set
        for (i = 0; i <= L2_ASSOC; i = i + 1) begin
            send_read(test_addr + i * L2_STRIDE);
        end
        #200;

        // now the memory should have data; read back original address (will go to mem)
        send_read(test_addr);

        if (cpu_rdata === test_data) $display("MEM TEST PASS: memory held %08h", test_data);
        else $display("MEM TEST FAIL: memory returned %08h (expected %08h)", cpu_rdata, test_data);

        $display("=== TB_MEM_WRITEBACK COMPLETE ===");
        #50 $finish;
    end
endmodule
