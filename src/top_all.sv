module top_all (
    input  logic        clk_in_50M,
    input  logic        sys_rst_n,

    // 显示模块输入（来自芯片/采样链路）
    input  logic        read_enable,
    input  logic        clk_row,
    input  logic        row_0,
    input  logic        row_127,
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
    output logic [13:0] dac_data1,
    output logic        pulse_16ms_1ms,
    // 截图扩展
    input  logic        key_snapshot,
    output logic        uart_tx_o
);

    logic clk_2_5M_int;
    logic lcd_clk_int;
    logic pll_locked_int;
    logic clk_5M_int;
    logic clk_125M_int;

    // 顶层只保留唯一一套时钟IP
    clk_generate u_clk_generate (
        .clk_in    (clk_in_50M),
        .reset     (~sys_rst_n),
        .lcd_clk   (lcd_clk_int),
        .clk_5M    (clk_5M_int),
        .clk_125M  (clk_125M_int),
        .locked    (pll_locked_int)
    );

    // 显示模块顶层
    top u_display_top (
        .lcd_clk      (lcd_clk_int),
        .pll_locked   (pll_locked_int),
        .sys_rst_n    (sys_rst_n),

        .row_0        (row_0),
        .row_127      (row_127),
        .clk_counter  (clk_2_5M_int),
        .read_enable  (read_enable),
        .vout         (vout),

        .lcd_hsync    (lcd_hsync),
        .lcd_vsync    (lcd_vsync),
        .lcd_de       (lcd_de),
        .lcd_bl       (lcd_bl),
        .lcd_pclk     (lcd_pclk),
        .lcd_rst      (lcd_rst),

        .lcd_r        (lcd_r),
        .lcd_g        (lcd_g),
        .lcd_b        (lcd_b),

        .key_snapshot (key_snapshot),
        .uart_tx_o    (uart_tx_o)
    );

    // 波形发生模块：直接使用顶层分发下来的时钟，不再内部例化 clk_wiz_0
    ila_test u_wave_top (
        .clk_5M           (clk_5M_int),
        .clk_125M         (clk_125M_int),
        .locked           (pll_locked_int),
        .start_key        (start_key),
        .hsync            (hsync),
        .clk_row          (clk_row),
        .row0             (row_0),
        .data             (data),
        .en               (en),
        .clk_2_5M         (clk_2_5M_int),
        .clk_200K         (clk_200K),
        .dac_clk1         (dac_clk1),
        .dac_data1        (dac_data1),
        .pulse_16ms_1ms   (pulse_16ms_1ms)
    );

    assign clk_2_5M = clk_2_5M_int;

endmodule
