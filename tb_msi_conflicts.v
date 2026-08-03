`timescale 1ns/1ps
// tb_msi_conflicts.v
// Exercises the MSI controller through all important conflict scenarios
// between a core and the shared bus.

module tb_msi_conflicts;
    reg clk = 0;
    reg rst_n = 0;

    reg cpu_read = 0;
    reg cpu_write = 0;
    reg snoop_bus_rd = 0;
    reg snoop_bus_rdx = 0;

    wire bus_req_valid;
    wire [1:0] bus_req_cmd;
    wire bus_flush;
    wire [1:0] state;

    // Instantiate DUT
    msi_controller dut(
        .clk(clk),
        .rst_n(rst_n),
        .cpu_read(cpu_read),
        .cpu_write(cpu_write),
        .snoop_bus_rd(snoop_bus_rd),
        .snoop_bus_rdx(snoop_bus_rdx),
        .bus_req_valid(bus_req_valid),
        .bus_req_cmd(bus_req_cmd),
        .bus_flush(bus_flush),
        .state(state)
    );

    // Clock
    always #5 clk = ~clk;

    // Helpers
    task clear_signals;
    begin
        cpu_read      = 0;
        cpu_write     = 0;
        snoop_bus_rd  = 0;
        snoop_bus_rdx = 0;
    end
    endtask

    task tick;
    begin
        @(posedge clk);
        #1;
        $display("%0t STATE=%0d (0=I,1=S,2=M) bus_req_valid=%0d cmd=%0d flush=%0d",
                 $time, state, bus_req_valid, bus_req_cmd, bus_flush);
    end
    endtask

    initial begin
        $dumpfile("waves_msi_conflicts.vcd");
        $dumpvars(0, tb_msi_conflicts);

        clear_signals();
        rst_n = 0;
        tick();
        tick();
        rst_n = 1;
        $display("=== MSI CONFLICT TEST START ===");
        tick();

        // 1) CPU read miss in I -> BusRd, I->S
        $display("\n[SCENARIO 1] CPU read miss in I (I -> S, BusRd)");
        clear_signals();
        cpu_read = 1;
        tick();
        clear_signals();
        tick();

        // 2) CPU write miss in I (after reset) -> BusRdX, I->M
        $display("\n[SCENARIO 2] CPU write miss in I (I -> M, BusRdX)");
        rst_n = 0; tick(); rst_n = 1; tick();  // reset back to I
        clear_signals();
        cpu_write = 1;
        tick();
        clear_signals();
        tick();

        // 3) CPU write hit in S: S->M via BusUpgr
        $display("\n[SCENARIO 3] CPU write hit in S (S -> M, BusUpgr)");
        rst_n = 0; tick(); rst_n = 1; tick();  // back to I
        // get to S by read
        clear_signals();
        cpu_read = 1;
        tick();
        clear_signals();
        tick();
        // now in S, do write
        cpu_write = 1;
        tick();
        clear_signals();
        tick();

        // 4) Snooped read when in M: M->S with Flush
        $display("\n[SCENARIO 4] Snooped BusRd in M (M -> S, Flush)");
        rst_n = 0; tick(); rst_n = 1; tick();
        // get to M: write miss from I
        clear_signals();
        cpu_write = 1;
        tick();
        clear_signals();
        tick();
        // now in M, snoop read
        snoop_bus_rd = 1;
        tick();
        clear_signals();
        tick();

        // 5) Snooped write when in S: S->I (BusRdX from other core)
        $display("\n[SCENARIO 5] Snooped BusRdX in S (S -> I)");
        rst_n = 0; tick(); rst_n = 1; tick();
        // get to S
        clear_signals();
        cpu_read = 1;
        tick();
        clear_signals();
        tick();
        // now in S, snoop write
        snoop_bus_rdx = 1;
        tick();
        clear_signals();
        tick();

        // 6) Snooped write when in M: M->I with Flush
        $display("\n[SCENARIO 6] Snooped BusRdX in M (M -> I, Flush)");
        rst_n = 0; tick(); rst_n = 1; tick();
        // get to M
        clear_signals();
        cpu_write = 1;
        tick();
        clear_signals();
        tick();
        // snoop BusRdX
        snoop_bus_rdx = 1;
        tick();
        clear_signals();
        tick();

        $display("\n=== MSI CONFLICT TEST COMPLETE ===");
        #20;
        $finish;
    end

endmodule
