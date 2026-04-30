module snapshot_ram #(
    parameter ADDR_WIDTH = 14,
    parameter DATA_WIDTH = 8
)(
    input  logic                    clk,

    // 写口：给 snapshot_copy_ctrl
    input  logic                    w_en,
    input  logic [ADDR_WIDTH-1:0]   w_addr,
    input  logic [DATA_WIDTH-1:0]   w_data,

    // 读口：给 shot_tx_ctrl
    input  logic                    r_en,
    input  logic [ADDR_WIDTH-1:0]   r_addr,
    output logic [DATA_WIDTH-1:0]   r_data
);

    localparam int DEPTH = (1 << ADDR_WIDTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (w_en)
            mem[w_addr] <= w_data;

        if (r_en)
            r_data <= mem[r_addr];
    end

endmodule
