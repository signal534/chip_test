module reg_file #(
    parameter ADDR_WIDTH = 14,
    parameter DATA_WIDTH = 8
)(
    input  logic                    wr_clk,
    input  logic                    rd_clk,
    input  logic                    w_en,
    input  logic                    r_en,
    input  logic                    wr_bank,
    input  logic                    rd_bank,
    input  logic [ADDR_WIDTH-1:0]   w_addr,
    input  logic [ADDR_WIDTH-1:0]   r_addr,
    input  logic [DATA_WIDTH-1:0]   w_data,
    output logic [DATA_WIDTH-1:0]   r_data
);

    localparam int DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem0 [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] mem1 [0:DEPTH-1];

    always_ff @(posedge wr_clk) begin
        if (w_en) begin
            if (wr_bank == 1'b0)
                mem0[w_addr] <= w_data;
            else
                mem1[w_addr] <= w_data;
        end
    end

    always_ff @(posedge rd_clk) begin
        if (r_en) begin
            if (rd_bank == 1'b0)
                r_data <= mem0[r_addr];
            else
                r_data <= mem1[r_addr];
        end
    end

endmodule