module reg_file #(
    parameter ADDR_WIDTH = 14,
    parameter DATA_WIDTH = 8
)(
    input  logic                    wr_clk,
    input  logic                    rd_clk,

    // 写口
    input  logic                    w_en,
    input  logic                    wr_bank,
    input  logic [ADDR_WIDTH-1:0]   w_addr,
    input  logic [DATA_WIDTH-1:0]   w_data,

    // 读口 A：给 display
    input  logic                    r0_en,
    input  logic                    rd0_bank,
    input  logic [ADDR_WIDTH-1:0]   r0_addr,
    output logic [DATA_WIDTH-1:0]   r0_data,

    // 读口 B：给 snapshot
    input  logic                    r1_en,
    input  logic                    rd1_bank,
    input  logic [ADDR_WIDTH-1:0]   r1_addr,
    output logic [DATA_WIDTH-1:0]   r1_data
);

    localparam int DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem0 [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] mem1 [0:DEPTH-1];

    // 写口
    always_ff @(posedge wr_clk) begin
        if (w_en) begin
            if (wr_bank == 1'b0)
                mem0[w_addr] <= w_data;
            else
                mem1[w_addr] <= w_data;
        end
    end

    // 读口 A（display）
    always_ff @(posedge rd_clk) begin
        if (r0_en) begin
            if (rd0_bank == 1'b0)
                r0_data <= mem0[r0_addr];
            else
                r0_data <= mem1[r0_addr];
        end
    end

    // 读口 B（snapshot）
    always_ff @(posedge rd_clk) begin
        if (r1_en) begin
            if (rd1_bank == 1'b0)
                r1_data <= mem0[r1_addr];
            else
                r1_data <= mem1[r1_addr];
        end
    end

endmodule
