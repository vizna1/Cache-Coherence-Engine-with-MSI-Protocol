`timescale 1ns/1ps
// main_memory.v - simple synchronous memory with 1-cycle capture + 1-cycle respond latency
module main_memory (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  req_valid,
    input  wire                  req_write,
    input  wire [31:0]           req_addr,
    input  wire [31:0]           req_wdata,
    output reg                   resp_valid,
    output reg  [31:0]           resp_rdata
);
    reg [31:0] mem [0:1023];
    integer i;
    // pending slot
    reg pending;
    reg [31:0] lat_addr;
    reg [31:0] lat_wdata;
    reg lat_write;

    initial begin
        resp_valid = 0; resp_rdata = 0; pending = 0;
        for (i = 0; i < 1024; i = i + 1) mem[i] = i;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 0;
            pending <= 0;
        end else begin
            resp_valid <= 0;
            if (pending) begin
                if (lat_write) begin
                    mem[lat_addr[11:2]] <= lat_wdata;
                    resp_rdata <= 32'h0;
                end else begin
                    resp_rdata <= mem[lat_addr[11:2]];
                end
                resp_valid <= 1;
                pending <= 0;
                $display($time, "ns: MEM respond addr=%h data=%h write=%0d", lat_addr, resp_rdata, lat_write);
            end
            if (req_valid) begin
                lat_addr <= req_addr;
                lat_wdata <= req_wdata;
                lat_write <= req_write;
                pending <= 1;
                $display($time, "ns: MEM received req addr=%h write=%0d", req_addr, req_write);
            end
        end
    end
endmodule
