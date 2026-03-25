module top_all (
    input  logic        clk_in_50M,
    input  logic        sys_rst_n,

    // 显示模块输入（来自芯片/采样链路）
    input  logic        read_enable,
    input  logic [3:0]  vout,

    // 波形发生模块输入
    input  logic        start_key,
    input  logic        hsync,
    input  logic [3:0]  data,
    input  logic        en,

    // 显示模块输出
    output logic        lcd_hsync,
    output logic        lcd_vsync,
    output logic        lcd_de,
    output logic        lcd_bl,
    output logic        lcd_pclk,
    output logic        lcd_rst,
    output logic [7:0]  lcd_r,
    output logic [7:0]  lcd_g,
    output logic [7:0]  lcd_b,

    // 波形发生模块输出
    output logic        clk_2_5M,
    output logic        clk_200K,
    output logic        dac_clk1,
    output logic [11:0] dac_data1,
    output logic        pulse_16ms_1ms
);

    logic clk_2_5M_int;
    // 显示模块顶层
    // 原文件：top.sv
    top u_display_top (
        .clk_in      (clk_in_50M),
        .sys_rst_n   (sys_rst_n),

        .clk_counter (clk_2_5M_int),
        .read_enable (read_enable),
        .vout        (vout),

        .lcd_hsync   (lcd_hsync),
        .lcd_vsync   (lcd_vsync),
        .lcd_de      (lcd_de),
        .lcd_bl      (lcd_bl),
        .lcd_pclk    (lcd_pclk),
        .lcd_rst     (lcd_rst),

        .lcd_r       (lcd_r),
        .lcd_g       (lcd_g),
        .lcd_b       (lcd_b)
    );

    // 波形发生模块顶层
    // 原文件：ila_test.v
    ila_test u_wave_top (
        .clk_in_50M      (clk_in_50M),
        .start_key       (start_key),
        .hsync           (hsync),
        .data            (data),
        .en              (en),
        .clk_2_5M        (clk_2_5M_int),
        .clk_200K        (clk_200K),
        .dac_clk1        (dac_clk1),
        .dac_data1       (dac_data1),
        .pulse_16ms_1ms  (pulse_16ms_1ms)
    );

    assign clk_2_5M = clk_2_5M_int;   // 再导出到外部
endmodule