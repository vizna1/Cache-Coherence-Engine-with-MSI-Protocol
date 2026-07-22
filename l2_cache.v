`timescale 1ns/1ps
// l2_cache.v - 4-way set-associative L2 cache (write-back, write-allocate)
// Single-word-per-line model for clarity.
module l2_cache #(
    parameter ADDR_BITS  = 32,
    parameter SETS       = 16,   // 16 sets
    parameter ASSOC      = 4,    // 4-way associative
    parameter LINE_BYTES = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    // request interface from L1
    input  wire                  req_valid,
    input  wire                  req_write,
    input  wire [ADDR_BITS-1:0]  req_addr,
    input  wire [31:0]           req_wdata,
    output reg                   resp_valid,
    output reg  [31:0]           resp_rdata,
    // main memory interface
    output reg                   mem_req_valid,
    output reg                   mem_req_write,
    output reg  [ADDR_BITS-1:0]  mem_addr,
    output reg  [31:0]           mem_wdata,
    input  wire                  mem_resp_valid,
    input  wire [31:0]           mem_rdata
);
    localparam OFFSET_BITS    = 4;
    localparam SET_BITS       = $clog2(SETS);
    localparam TAG_BITS       = ADDR_BITS - OFFSET_BITS - SET_BITS;
    localparam WORDS_PER_LINE = 1;
    localparam TOTAL_LINES    = SETS * ASSOC;

    // Tag & state
    reg [TAG_BITS-1:0] tag_array [0:TOTAL_LINES-1];
    reg                valid     [0:TOTAL_LINES-1];
    reg                dirty     [0:TOTAL_LINES-1];
    reg [7:0]          lru_counter[0:TOTAL_LINES-1];

    // Data
    reg [31:0] data_array [0:TOTAL_LINES*WORDS_PER_LINE-1];

    // Debug-friendly signals for VCD
    reg l2_hit;
    reg l2_miss;

    integer i;

    // Decode address
    wire [SET_BITS-1:0] cur_set_index =
        req_addr[OFFSET_BITS +: SET_BITS];
    wire [TAG_BITS-1:0] cur_addr_tag  =
        req_addr[OFFSET_BITS + SET_BITS +: TAG_BITS];

    // For pending miss
    reg                  pending_is_write;
    reg [ADDR_BITS-1:0]  pending_addr;

    wire [SET_BITS-1:0]  pend_set_index =
        pending_addr[OFFSET_BITS +: SET_BITS];
    wire [TAG_BITS-1:0]  pend_tag =
        pending_addr[ADDR_BITS-1:OFFSET_BITS+SET_BITS];

    // FSM
    reg [1:0] state;
    localparam S_IDLE      = 2'd0;
    localparam S_WRITEBACK = 2'd1;
    localparam S_WAIT_MEM  = 2'd2;

    integer way_idx;
    integer victim_way;

    // === Helper functions/tasks ===

    // find way with tag (returns -1 if not found)
    function integer find_way;
        input [TAG_BITS-1:0] t;
        input [SET_BITS-1:0] s;
        integer w;
        integer base;
        begin
            find_way = -1;
            base = s * ASSOC;
            for (w = 0; w < ASSOC; w = w + 1) begin
                if (valid[base + w] && tag_array[base + w] == t) begin
                    find_way = w;
                end
            end
        end
    endfunction

    // choose LRU victim (prefer first invalid)
    function integer lru_victim;
        input [SET_BITS-1:0] s;
        integer w;
        integer base;
        integer maxc;
        reg    found_invalid;
        begin
            base = s * ASSOC;
            maxc = -1;
            found_invalid = 0;
            lru_victim = 0;
            for (w = 0; w < ASSOC; w = w + 1) begin
                if (!valid[base + w] && !found_invalid) begin
                    lru_victim = w;
                    found_invalid = 1;
                end
                if (!found_invalid) begin
                    if (lru_counter[base + w] > maxc) begin
                        maxc       = lru_counter[base + w];
                        lru_victim = w;
                    end
                end
            end
        end
    endfunction

    // update LRU counters: accessed -> 0, others ++
    task update_lru;
        input [SET_BITS-1:0] s;
        input integer accessed;
        integer w;
        integer base;
        begin
            base = s * ASSOC;
            for (w = 0; w < ASSOC; w = w + 1) begin
                if (w == accessed) lru_counter[base + w] <= 0;
                else               lru_counter[base + w] <= lru_counter[base + w] + 1;
            end
        end
    endtask

    // === Initial ===
    initial begin
        resp_valid    = 0;
        resp_rdata    = 0;
        mem_req_valid = 0;
        mem_req_write = 0;
        mem_addr      = 0;
        mem_wdata     = 0;
        l2_hit        = 0;
        l2_miss       = 0;
        state         = S_IDLE;
    end

    // === Sequential logic ===
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TOTAL_LINES; i = i + 1) begin
                valid[i]       <= 0;
                dirty[i]       <= 0;
                tag_array[i]   <= 0;
                data_array[i]  <= 0;
                lru_counter[i] <= i[7:0];
            end
            resp_valid    <= 0;
            mem_req_valid <= 0;
            mem_req_write <= 0;
            l2_hit        <= 0;
            l2_miss       <= 0;
            state         <= S_IDLE;
        end else begin
            // defaults each cycle
            resp_valid    <= 0;
            mem_req_valid <= 0;
            mem_req_write <= 0;
            l2_hit        <= 0;
            l2_miss       <= 0;

            case (state)
                // ================= S_IDLE =================
                S_IDLE: begin
                    if (req_valid) begin
                        // lookup
                        way_idx = find_way(cur_addr_tag, cur_set_index);

                        if (way_idx != -1) begin
                            // L2 HIT
                            l2_hit <= 1;
                            resp_valid <= 1;

                            if (req_write) begin
                                data_array[(cur_set_index*ASSOC + way_idx)*WORDS_PER_LINE + 0]
                                    <= req_wdata;
                                dirty[cur_set_index*ASSOC + way_idx] <= 1;
                                $display($time, "ns: L2 HIT write addr=%h set=%0d way=%0d",
                                         req_addr, cur_set_index, way_idx);
                            end else begin
                                resp_rdata <= data_array[(cur_set_index*ASSOC + way_idx)*WORDS_PER_LINE + 0];
                                $display($time, "ns: L2 HIT read addr=%h set=%0d way=%0d data=%h",
                                         req_addr, cur_set_index, way_idx, resp_rdata);
                            end
                            update_lru(cur_set_index, way_idx);
                        end else begin
                            // L2 MISS
                            l2_miss        <= 1;
                            pending_addr    <= req_addr;
                            pending_is_write<= req_write;

                            // choose victim
                            victim_way = lru_victim(cur_set_index);

                            // if victim is valid & dirty: write it back to memory
                            if (valid[cur_set_index*ASSOC + victim_way] &&
                                dirty[cur_set_index*ASSOC + victim_way]) begin
                                mem_req_valid <= 1;
                                mem_req_write <= 1;
                                mem_addr      <= {tag_array[cur_set_index*ASSOC + victim_way],
                                                  cur_set_index,
                                                  {OFFSET_BITS{1'b0}}};
                                mem_wdata     <= data_array[(cur_set_index*ASSOC + victim_way)*WORDS_PER_LINE + 0];
                                $display($time, "ns: L2 writeback addr=%h set=%0d way=%0d",
                                         mem_addr, cur_set_index, victim_way);
                                state <= S_WRITEBACK;
                            end else begin
                                // otherwise request line from memory
                                mem_req_valid <= 1;
                                mem_req_write <= 0;
                                mem_addr      <= {cur_addr_tag, cur_set_index, {OFFSET_BITS{1'b0}}};
                                $display($time, "ns: L2 MISS -> request MEM addr=%h set=%0d",
                                         mem_addr, cur_set_index);
                                state <= S_WAIT_MEM;
                            end
                        end
                    end
                end

                // ================= S_WRITEBACK =================
                S_WRITEBACK: begin
                    // after issuing writeback, next cycle request fill from MEM
                    mem_req_valid <= 1;
                    mem_req_write <= 0;
                    mem_addr      <= {pend_tag, pend_set_index, {OFFSET_BITS{1'b0}}};
                    $display($time, "ns: L2 after WB -> request MEM addr=%h set=%0d",
                             mem_addr, pend_set_index);
                    state <= S_WAIT_MEM;
                end

                // ================= S_WAIT_MEM =================
                S_WAIT_MEM: begin
                    if (mem_resp_valid) begin
                        // choose victim again based on pending set
                        victim_way = lru_victim(pend_set_index);

                        tag_array[pend_set_index*ASSOC + victim_way] <= pend_tag;
                        valid[pend_set_index*ASSOC + victim_way]     <= 1;
                        dirty[pend_set_index*ASSOC + victim_way]     <= pending_is_write ? 1 : 0;
                        data_array[(pend_set_index*ASSOC + victim_way)*WORDS_PER_LINE + 0]
                            <= mem_rdata;

                        resp_valid <= 1;
                        if (!pending_is_write) resp_rdata <= mem_rdata;

                        $display($time, "ns: L2 filled from MEM addr=%h set=%0d way=%0d data=%h",
                                 pending_addr, pend_set_index, victim_way, mem_rdata);

                        update_lru(pend_set_index, victim_way);
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
