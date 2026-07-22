`timescale 1ns/1ps
// tb_l2_writeback.v
// ensure L1 writeback -> L2 dirty; then evict L2 so it writes back to memory, verify persistence.

module tb_l2_writeback;
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
    localparam L2_SETS    = 16;
    localparam L2_ASSOC   = 4; 
    localparam L1_STRIDE  = LINE_BYTES * L1_SETS; // 64
    localparam L2_STRIDE  = LINE_BYTES * L2_SETS; // 256

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
        $dumpfile("waves_l2_writeback.vcd");
        $dumpvars(0, tb_l2_writeback);

        rst_n = 0; #20; rst_n = 1; #10;
        $display("=== TB_L2_WRITEBACK START ===");

        test_addr = 32'h0000_2000;       // line-aligned base
        test_data = 32'hCAFEBABE;

        // 1) cold read to populate L1 & L2
        $display("--- Step 1: cold read to populate caches ---");
        send_read(test_addr);

        // 2) write to make L1 dirty
        $display("--- Step 2: write to same line (dirty in L1) ---");
        send_write(test_addr, test_data);

        // 3) evict from L1 (L1 will writeback to L2) by accessing (L1_ASSOC+1) addresses in same L1 set
        $display("--- Step 3: evict from L1 (expect L1 -> L2 writeback) ---");
        for (i = 1; i <= (L1_ASSOC + 1); i = i + 1) begin
            send_read(test_addr + i * L1_STRIDE);
        end

        // Allow some cycles for L1->L2 writeback to be processed
        #100;

        // 4) Evict that L2 line (direct-mapped): access addr that maps to same L2 set
        //    This should force L2 to write the dirty data to memory.
        $display("--- Step 4: evict from L2 (expect L2 -> MEM writeback) ---");
        for (i = 0; i <= L2_ASSOC; i = i + 1) begin
            send_read(test_addr + i * L2_STRIDE);
        end

        // Wait a bit for L2->MEM writeback to complete
        #200;

        // 5) Read original address again: if memory received the writeback, it should return test_data
        $display("--- Step 5: read original addr back from memory to verify persistence ---");
        send_read(test_addr);

        // check
        if (cpu_rdata === test_data) $display("TEST PASS: final read returned written data %08h", test_data);
        else $display("TEST FAIL: final read returned %08h (expected %08h)", cpu_rdata, test_data);

        $display("=== TB_L2_WRITEBACK COMPLETE ===");
        #50 $finish;
    end
endmodule
