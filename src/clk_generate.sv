module clk_generate (
    input  logic clk_in,
    input  logic reset,
    output logic lcd_clk,
    output logic clk_5M,
    output logic clk_125M,
    output logic locked
);

    // 这里默认你工程里的 clk_wiz_0 已经配置了 3 个输出：
    // clk_out1 -> lcd_clk
    // clk_out2 -> clk_5M
    // clk_out3 -> clk_125M
    clk_wiz_0 u_clk (
        .clk_in1  (clk_in),
        .reset    (reset),
        .clk_out1 (lcd_clk),
        .clk_out2 (clk_5M),
        .clk_out3 (clk_125M),
        .locked   (locked)
    );

endmodule