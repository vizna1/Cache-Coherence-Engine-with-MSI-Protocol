`timescale 1ns/1ps
// l1_cache.v - simple 2-way set-assoc L1 cache (write-back, write-allocate)
// Stores one word per cache line for simplicity.
module l1_cache #(
    parameter ADDR_BITS = 32,
    parameter SETS = 4,
    parameter ASSOC = 2,
    parameter LINE_BYTES = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    // CPU side
    input  wire                  cpu_req_valid,
    input  wire                  cpu_req_write, // 1 = write, 0 = read
    input  wire [ADDR_BITS-1:0]  cpu_addr,
    input  wire [31:0]           cpu_wdata,
    output reg                   cpu_resp_valid,
    output reg  [31:0]           cpu_rdata,
    // L2 side (request/response)
    output reg                   mem_req_valid,
    output reg                   mem_req_write,
    output reg  [ADDR_BITS-1:0]  mem_addr,
    output reg  [31:0]           mem_wdata,
    input  wire                  mem_resp_valid,
    input  wire [31:0]           mem_rdata
);

    // Parameters fixed for simplicity
    localparam OFFSET_BITS = 4; // 16 bytes
    localparam SET_BITS = $clog2(SETS);
    localparam TAG_BITS = ADDR_BITS - OFFSET_BITS - SET_BITS;
    localparam WORDS_PER_LINE = 1; // simplified (one word per line)
    localparam TOTAL_LINES = SETS * ASSOC;

    // Metadata arrays
    reg [TAG_BITS-1:0] tag_array [0:TOTAL_LINES-1];
    reg               valid     [0:TOTAL_LINES-1];
    reg               dirty     [0:TOTAL_LINES-1];
    reg [7:0]         lru_counter[0:TOTAL_LINES-1];
    reg [31:0]        data_array [0:TOTAL_LINES*WORDS_PER_LINE-1];

    integer i, way;
    reg [SET_BITS-1:0] set_index;
    reg [TAG_BITS-1:0] addr_tag;

    // Decode address for CPU requests (combinational)
    always @(*) begin
        set_index = cpu_addr[OFFSET_BITS +: SET_BITS];
        addr_tag  = cpu_addr[OFFSET_BITS + SET_BITS +: TAG_BITS];
    end

    // find way with tag (returns -1 if not found)
    function integer find_way;
        input [TAG_BITS-1:0] t;
        input [SET_BITS-1:0] s;
        integer w; integer base;
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
        integer w; integer base; integer maxc; reg found_invalid;
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
                        maxc = lru_counter[base + w];
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
        integer w; integer base;
        begin
            base = s * ASSOC;
            for (w = 0; w < ASSOC; w = w + 1) begin
                if (w == accessed) lru_counter[base + w] <= 0;
                else lru_counter[base + w] <= lru_counter[base + w] + 1;
            end
        end
    endtask

    // FSM states
    reg [1:0] state;
    localparam S_IDLE = 0;
    localparam S_WRITEBACK = 1;
    localparam S_WAIT_FILL = 2;

    integer way_idx, victim_way;
    reg pending_is_write;
    reg [ADDR_BITS-1:0] pending_addr;

    initial begin
        cpu_resp_valid = 0; cpu_rdata = 0;
        mem_req_valid = 0; mem_req_write = 0; mem_addr = 0; mem_wdata = 0;
        state = S_IDLE;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < TOTAL_LINES; i = i + 1) begin
                valid[i] <= 0;
                dirty[i] <= 0;
                tag_array[i] <= 0;
                lru_counter[i] <= i;
                data_array[i] <= 0;
            end
            cpu_resp_valid <= 0;
            mem_req_valid <= 0;
            mem_req_write <= 0;
            state <= S_IDLE;
        end else begin
            // defaults each cycle
            cpu_resp_valid <= 0;
            mem_req_valid <= 0;
            mem_req_write <= 0;

            case (state)
                S_IDLE: begin
                    if (cpu_req_valid) begin
                        way_idx = find_way(addr_tag, set_index);
                        if (way_idx != -1) begin
                            // L1 HIT
                            cpu_resp_valid <= 1;
                            if (cpu_req_write) begin
                                // write-through L1 (write-back behavior: mark dirty, update data)
                                data_array[(set_index * ASSOC + way_idx) * WORDS_PER_LINE + 0] <= cpu_wdata;
                                dirty[set_index * ASSOC + way_idx] <= 1;
                                $display($time, "ns: L1 HIT write addr=%h set=%0d way=%0d", cpu_addr, set_index, way_idx);
                            end else begin
                                cpu_rdata <= data_array[(set_index * ASSOC + way_idx) * WORDS_PER_LINE + 0];
                                $display($time, "ns: L1 HIT read addr=%h data=%h", cpu_addr, cpu_rdata);
                            end
                            update_lru(set_index, way_idx);
                        end else begin
                            // L1 MISS: select victim
                            victim_way = lru_victim(set_index);
                            if (valid[set_index * ASSOC + victim_way] && dirty[set_index * ASSOC + victim_way]) begin
                                // writeback victim to L2 (mem interface)
                                mem_req_valid <= 1;
                                mem_req_write <= 1;
                                mem_addr <= {tag_array[set_index*ASSOC + victim_way], set_index, {OFFSET_BITS{1'b0}}};
                                mem_wdata <= data_array[(set_index*ASSOC + victim_way)*WORDS_PER_LINE + 0];
                                $display($time, "ns: L1 writeback addr=%h", mem_addr);
                                pending_addr <= cpu_addr;
                                pending_is_write <= cpu_req_write;
                                state <= S_WRITEBACK;
                            end else begin
                                // request line from L2
                                mem_req_valid <= 1;
                                mem_req_write <= 0;
                                mem_addr <= {addr_tag, set_index, {OFFSET_BITS{1'b0}}};
                                $display($time, "ns: L1 miss -> request L2 addr=%h", mem_addr);
                                pending_addr <= cpu_addr;
                                pending_is_write <= cpu_req_write;
                                state <= S_WAIT_FILL;
                            end
                        end
                    end
                end

                S_WRITEBACK: begin
                    // after issuing writeback, next cycle request fill from L2 for the pending address
                    mem_req_valid <= 1;
                    mem_req_write <= 0;
                    // construct address for pending_addr (tag + set + offset=0)
                    mem_addr <= {pending_addr[ADDR_BITS-1:OFFSET_BITS+SET_BITS], pending_addr[OFFSET_BITS +: SET_BITS], {OFFSET_BITS{1'b0}}};
                    $display($time, "ns: After wb request fill addr=%h", mem_addr);
                    state <= S_WAIT_FILL;
                end

                S_WAIT_FILL: begin
                    if (mem_resp_valid) begin
                        // install into victim way (recompute victim)
                        victim_way = lru_victim(set_index);
                        tag_array[set_index * ASSOC + victim_way] <= pending_addr[ADDR_BITS-1:OFFSET_BITS+SET_BITS];
                        valid[set_index * ASSOC + victim_way] <= 1;
                        dirty[set_index * ASSOC + victim_way] <= pending_is_write ? 1 : 0;
                        data_array[(set_index * ASSOC + victim_way) * WORDS_PER_LINE + 0] <= mem_rdata;
                        cpu_resp_valid <= 1;
                        if (!pending_is_write) cpu_rdata <= mem_rdata;
                        $display($time, "ns: L1 filled from L2/mem addr=%h data=%h", pending_addr, mem_rdata);
                        update_lru(set_index, victim_way);
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
