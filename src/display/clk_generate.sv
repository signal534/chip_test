module clk_generate (
    input  logic clk_in,
    input  logic reset,
    output logic lcd_clk,
    output logic locked
);

    clk_wiz_0 u_clk (
        .clk_in1 (clk_in),
        .reset   (reset),
        .clk_out1(lcd_clk),
        .locked  (locked)
    );

endmodule
