`timescale 1ns/1ps
// top_system.v - wires CPU -> L1 -> L2 -> main memory
module top_system (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  cpu_req_valid,
    input  wire                  cpu_req_write,
    input  wire [31:0]           cpu_addr,
    input  wire [31:0]           cpu_wdata,
    output wire                  cpu_resp_valid,
    output wire [31:0]           cpu_rdata
);
    // wires L1 <-> L2
    wire l1_mem_req_valid;
    wire l1_mem_req_write;
    wire [31:0] l1_mem_addr;
    wire [31:0] l1_mem_wdata;
    wire l1_mem_resp_valid;
    wire [31:0] l1_mem_rdata;

    // wires L2 <-> MEM
    wire l2_mem_req_valid;
    wire l2_mem_req_write;
    wire [31:0] l2_mem_addr;
    wire [31:0] l2_mem_wdata;
    wire l2_mem_resp_valid;
    wire [31:0] l2_mem_rdata;

    l1_cache l1u(
        .clk(clk), .rst_n(rst_n),
        .cpu_req_valid(cpu_req_valid), .cpu_req_write(cpu_req_write), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_resp_valid(cpu_resp_valid), .cpu_rdata(cpu_rdata),
        .mem_req_valid(l1_mem_req_valid), .mem_req_write(l1_mem_req_write), .mem_addr(l1_mem_addr), .mem_wdata(l1_mem_wdata),
        .mem_resp_valid(l1_mem_resp_valid), .mem_rdata(l1_mem_rdata)
    );

    l2_cache l2u(
        .clk(clk), .rst_n(rst_n),
        .req_valid(l1_mem_req_valid), .req_write(l1_mem_req_write), .req_addr(l1_mem_addr), .req_wdata(l1_mem_wdata),
        .resp_valid(l1_mem_resp_valid), .resp_rdata(l1_mem_rdata),
        .mem_req_valid(l2_mem_req_valid), .mem_req_write(l2_mem_req_write), .mem_addr(l2_mem_addr), .mem_wdata(l2_mem_wdata),
        .mem_resp_valid(l2_mem_resp_valid), .mem_rdata(l2_mem_rdata)
    );

    main_memory memu(
        .clk(clk), .rst_n(rst_n),
        .req_valid(l2_mem_req_valid), .req_write(l2_mem_req_write), .req_addr(l2_mem_addr), .req_wdata(l2_mem_wdata),
        .resp_valid(l2_mem_resp_valid), .resp_rdata(l2_mem_rdata)
    );

endmodule
