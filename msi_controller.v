`timescale 1ns/1ps
// msi_controller.v
// Simple per-line MSI cache controller.
//
// Models coherence between a single core and the shared bus.
// You can think of this as the state machine for one cache line.
// Extend by having one instance per line, or by storing 'state_array' in your cache.
//
// States:
//   2'b00 = I (Invalid)
//   2'b01 = S (Shared)
//   2'b10 = M (Modified)

module msi_controller (
    input  wire clk,
    input  wire rst_n,

    // CPU side events (for THIS cache)
    input  wire cpu_read,     // CPU issues a read to this line
    input  wire cpu_write,    // CPU issues a write to this line

    // Snooped bus events caused by OTHER caches
    input  wire snoop_bus_rd,   // Another core does BusRd to this line
    input  wire snoop_bus_rdx,  // Another core does BusRdX / BusUpgr to this line

    // Outputs to the bus from THIS cache
    output reg  bus_req_valid,
    output reg  [1:0] bus_req_cmd,   // 2'b00=NONE, 01=BusRd, 10=BusRdX, 11=BusUpgr
    output reg  bus_flush,          // Asserted when we need to write back dirty data

    // For visibility
    output reg  [1:0] state         // 00=I, 01=S, 10=M
);

    localparam I  = 2'b00;
    localparam S  = 2'b01;
    localparam M  = 2'b10;

    localparam CMD_NONE  = 2'b00;
    localparam CMD_BUSRD = 2'b01;
    localparam CMD_RDX   = 2'b10;
    localparam CMD_UPGR  = 2'b11;

    // State register
    reg [1:0] next_state;
    reg       next_flush;
    reg [1:0] next_cmd;
    reg       next_req_valid;

    // Combinational next-state logic
    always @(*) begin
        // defaults
        next_state      = state;
        next_flush      = 1'b0;
        next_cmd        = CMD_NONE;
        next_req_valid  = 1'b0;

        case (state)
            I: begin
                // CPU read miss -> BusRd, go to S
                if (cpu_read) begin
                    next_state     = S;
                    next_req_valid = 1'b1;
                    next_cmd       = CMD_BUSRD;
                end
                // CPU write miss -> BusRdX, go to M
                else if (cpu_write) begin
                    next_state     = M;
                    next_req_valid = 1'b1;
                    next_cmd       = CMD_RDX;
                end
                // snoops ignored in I
            end

            S: begin
                // CPU read hit: no bus activity, remain S
                if (cpu_read) begin
                    next_state = S;
                end
                // CPU write hit in S -> BusUpgr, go to M
                else if (cpu_write) begin
                    next_state     = M;
                    next_req_valid = 1'b1;
                    next_cmd       = CMD_UPGR;
                end

                // Snoops:
                // Another core issues BusRd: line remains Shared
                if (snoop_bus_rd) begin
                    next_state = S;
                end
                // Another core issues BusRdX (or upgrade): our copy becomes Invalid
                if (snoop_bus_rdx) begin
                    next_state = I;
                end
            end

            M: begin
                // CPU read/write hits: stay M, silent to bus
                if (cpu_read || cpu_write) begin
                    next_state = M;
                end

                // Snoops from other cores:
                if (snoop_bus_rd) begin
                    // Another core wants a shared copy.
                    // We must supply data (Flush), downgrade M->S.
                    next_state = S;
                    next_flush = 1'b1;
                end

                if (snoop_bus_rdx) begin
                    // Another core wants exclusive ownership.
                    // We flush and invalidate our copy (M->I).
                    next_state = I;
                    next_flush = 1'b1;
                end
            end

            default: begin
                next_state = I;
            end
        endcase
    end

    // Sequential update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= I;
            bus_req_valid <= 1'b0;
            bus_req_cmd   <= CMD_NONE;
            bus_flush     <= 1'b0;
        end else begin
            state         <= next_state;
            bus_req_valid <= next_req_valid;
            bus_req_cmd   <= next_cmd;
            bus_flush     <= next_flush;

            if (next_req_valid) begin
                $display("%0t [MSI] bus_req: cmd=%0d (0:none 1:BusRd 2:BusRdX 3:Upgr) from state=%0d -> next_state=%0d",
                         $time, next_cmd, state, next_state);
            end
            if (next_flush) begin
                $display("%0t [MSI] FLUSH triggered from state=%0d", $time, state);
            end
        end
    end

endmodule
