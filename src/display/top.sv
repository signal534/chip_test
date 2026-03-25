module top (
    input  logic       clk_in,
    input  logic       sys_rst_n,

    input  logic       clk_counter,
    input  logic       read_enable,
    input  logic [3:0] vout,

    output logic       lcd_hsync,
    output logic       lcd_vsync,
    output logic       lcd_de,
    output logic       lcd_bl,
    output logic       lcd_pclk,
    output logic       lcd_rst,

    output logic [7:0] lcd_r,
    output logic [7:0] lcd_g,
    output logic [7:0] lcd_b
);

    logic lcd_clk;
    logic pll_locked;
    logic rst;

    logic        mem_w_en;
    logic [13:0] mem_w_addr;
    logic [7:0]  mem_w_data;

    logic        mem_r_en;
    logic [13:0] mem_r_addr;
    logic [7:0]  mem_r_data;

    logic        frame_start_capture;
    logic        frame_done_capture;
    logic        busy;

    logic        wr_bank_capture;
    logic        rd_bank_lcd;

    logic        frame_done_sync1;
    logic        frame_done_sync2;
    logic        frame_done_lcd;

    clk_generate u_clk_generate (
        .clk_in  (clk_in),
        .reset   (~sys_rst_n),
        .lcd_clk (lcd_clk),
        .locked  (pll_locked)
    );

    assign rst      = ~sys_rst_n | ~pll_locked;
    assign lcd_pclk = lcd_clk;
    assign lcd_bl   = 1'b1;
    assign lcd_rst  = sys_rst_n & pll_locked;

    // 采集模块：clk_counter 域
    frame_capture_pingpong u_frame_capture (
        .clk_counter (clk_counter),
        .rst_n       (~rst),
        .read_enable (read_enable),
        .vout        (vout),

        .mem_w_en    (mem_w_en),
        .mem_w_addr  (mem_w_addr),
        .mem_w_data  (mem_w_data),

        .busy        (busy),
        .frame_start (frame_start_capture),
        .frame_done  (frame_done_capture)
    );

    // 双帧 reg_file
    reg_file #(
        .ADDR_WIDTH(14),
        .DATA_WIDTH(8)
    ) u_frame_mem (
        .wr_clk  (clk_counter),
        .rd_clk  (lcd_clk),
        .w_en    (mem_w_en),
        .r_en    (mem_r_en),
        .wr_bank (wr_bank_capture),
        .rd_bank (rd_bank_lcd),
        .w_addr  (mem_w_addr),
        .r_addr  (mem_r_addr),
        .w_data  (mem_w_data),
        .r_data  (mem_r_data)
    );

    // 写 bank：每完成一帧就切到另一块
    always_ff @(posedge clk_counter or posedge rst) begin
        if (rst)
            wr_bank_capture <= 1'b0;
        else if (frame_done_capture)
            wr_bank_capture <= ~wr_bank_capture;
    end

    // frame_done 跨到 lcd_clk 域
    always_ff @(posedge lcd_clk or posedge rst) begin
        if (rst) begin
            frame_done_sync1 <= 1'b0;
            frame_done_sync2 <= 1'b0;
        end
        else begin
            frame_done_sync1 <= frame_done_capture;
            frame_done_sync2 <= frame_done_sync1;
        end
    end

    assign frame_done_lcd = frame_done_sync1 & ~frame_done_sync2;

    // 读 bank：每收到一帧完成脉冲，就切到刚写完的那一块
    always_ff @(posedge lcd_clk or posedge rst) begin
        if (rst)
            rd_bank_lcd <= 1'b0;
        else if (frame_done_lcd)
            rd_bank_lcd <= ~rd_bank_lcd;
    end

    // 显示模块：lcd_clk 域
    display u_display (
        .lcd_clk    (lcd_clk),
        .reset      (rst),
        .frame_done (frame_done_lcd),

        .mem_r_data (mem_r_data),
        .mem_r_en   (mem_r_en),
        .mem_r_addr (mem_r_addr),

        .lcd_hsync  (lcd_hsync),
        .lcd_vsync  (lcd_vsync),
        .lcd_de     (lcd_de),
        .lcd_r      (lcd_r),
        .lcd_g      (lcd_g),
        .lcd_b      (lcd_b)
    );

endmodule