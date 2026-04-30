module top (
    input  logic       lcd_clk,
    input  logic       pll_locked,
    input  logic       sys_rst_n,

    input  logic       clk_counter,
    input  logic       read_enable,
    input  logic [3:0] vout,
    input  logic       row_0,
    input  logic       row_127,

    input  logic       key_snapshot,
    output logic       uart_tx_o,

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

    logic rst;

    // reg_file 写口
    logic        mem_w_en;
    logic [13:0] mem_w_addr;
    logic [7:0]  mem_w_data;

    // 来自 frame_capture 模块的输出
    logic        fc_mem_w_en;
    logic [13:0] fc_mem_w_addr;
    logic [7:0]  fc_mem_w_data;

    // display 模块读口 A
    logic        disp_mem_r_en;
    logic [13:0] disp_mem_r_addr;
    logic [7:0]  disp_mem_r_data;

    // snapshot copy 模块读口 B
    logic        copy_src_r_en;
    logic [13:0] copy_src_r_addr;
    logic [7:0]  copy_src_r_data;
    logic        copy_src_r_bank;

    // snapshot_ram 写口
    logic        snap_buf_w_en;
    logic [13:0] snap_buf_w_addr;
    logic [7:0]  snap_buf_w_data;

    // snapshot_ram 读口
    logic        snap_buf_r_en;
    logic [13:0] snap_buf_r_addr;
    logic [7:0]  snap_buf_r_data;

    // capture / bank / 跨域
    logic        frame_start_capture;
    logic        frame_done_capture;
    logic        busy;

    logic        wr_bank_capture;
    logic        rd_bank_lcd;

    logic        frame_done_sync1;
    logic        frame_done_sync2;
    logic        frame_done_pulse_lcd;

    logic        frame_done_bank_capture;
    logic        frame_bank_sync1;
    logic        frame_bank_sync2;

    logic        swap_pending;
    logic        pending_bank_lcd;
    logic        lcd_vsync_d1;
    logic        lcd_frame_boundary;
    logic        frame_done_lcd;

    // FPS统计
    logic [25:0] fps_sec_cnt;
    logic [7:0]  fps_cnt_1s;
    logic [7:0]  fps_value;

    // key / snapshot / uart
    logic        snapshot_req_pulse;
    logic        snapshot_valid;
    logic        snapshot_clear;
    logic        copy_busy;
    logic        tx_active;

    logic        uart_wr_en;
    logic [7:0]  uart_wr_data;
    logic        uart_busy;

    assign rst      = ~sys_rst_n | ~pll_locked;
    assign lcd_pclk = lcd_clk;
    assign lcd_bl   = 1'b1;
    assign lcd_rst  = sys_rst_n & pll_locked;

    frame_capture_pingpong u_frame_capture (
        .clk_counter (clk_counter),
        .rst_n       (~rst),

        .read_enable (read_enable),
        .vout        (vout),
        .row_0       (row_0),
        .row_127     (row_127),

        .mem_w_en    (fc_mem_w_en),
        .mem_w_addr  (fc_mem_w_addr),
        .mem_w_data  (fc_mem_w_data),

        .busy        (busy),
        .frame_start (frame_start_capture),
        .frame_done  (frame_done_capture)
    );

    assign mem_w_en   = fc_mem_w_en;
    assign mem_w_addr = fc_mem_w_addr;
    assign mem_w_data = fc_mem_w_data;

    reg_file #(
        .ADDR_WIDTH(14),
        .DATA_WIDTH(8)
    ) u_frame_mem (
        .wr_clk   (clk_counter),
        .rd_clk   (lcd_clk),

        .w_en     (mem_w_en),
        .wr_bank  (wr_bank_capture),
        .w_addr   (mem_w_addr),
        .w_data   (mem_w_data),

        .r0_en    (disp_mem_r_en),
        .rd0_bank (rd_bank_lcd),
        .r0_addr  (disp_mem_r_addr),
        .r0_data  (disp_mem_r_data),

        .r1_en    (copy_src_r_en),
        .rd1_bank (copy_src_r_bank),
        .r1_addr  (copy_src_r_addr),
        .r1_data  (copy_src_r_data)
    );

    // 每完成一帧，写 bank 翻转；并记住刚写完的是哪块 bank
    always_ff @(posedge clk_counter or posedge rst) begin
        if (rst) begin
            wr_bank_capture         <= 1'b0;
            frame_done_bank_capture <= 1'b0;
        end
        else if (frame_done_capture) begin
            frame_done_bank_capture <= wr_bank_capture;
            wr_bank_capture         <= ~wr_bank_capture;
        end
    end

    // frame_done 跨域到 lcd_clk，产生一个脉冲
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

    assign frame_done_pulse_lcd = frame_done_sync1 & ~frame_done_sync2;

    // 刚写完的 bank 跨域到 lcd_clk
    always_ff @(posedge lcd_clk or posedge rst) begin
        if (rst) begin
            frame_bank_sync1 <= 1'b0;
            frame_bank_sync2 <= 1'b0;
        end
        else begin
            frame_bank_sync1 <= frame_done_bank_capture;
            frame_bank_sync2 <= frame_bank_sync1;
        end
    end

    // 检测 LCD 帧边界：lcd_vsync 下降沿
    always_ff @(posedge lcd_clk or posedge rst) begin
        if (rst)
            lcd_vsync_d1 <= 1'b1;
        else
            lcd_vsync_d1 <= lcd_vsync;
    end

    assign lcd_frame_boundary = lcd_vsync_d1 & ~lcd_vsync;

    // 显示侧按 LCD 帧边界切换读 bank
    always_ff @(posedge lcd_clk or posedge rst) begin
        if (rst) begin
            swap_pending     <= 1'b0;
            pending_bank_lcd <= 1'b0;
            rd_bank_lcd      <= 1'b0;
            frame_done_lcd   <= 1'b0;
        end
        else begin
            frame_done_lcd <= 1'b0;

            if (frame_done_pulse_lcd) begin
                swap_pending     <= 1'b1;
                pending_bank_lcd <= frame_bank_sync2;
            end

            if (lcd_frame_boundary && swap_pending) begin
                rd_bank_lcd    <= pending_bank_lcd;
                swap_pending   <= 1'b0;
                frame_done_lcd <= 1'b1;
            end
        end
    end

    // 统计实际显示帧率：1秒内切了多少次新帧
    // 这里按 lcd_clk = 40MHz 写；若你的 lcd_clk 不是40MHz，要改这个常数
    always_ff @(posedge lcd_clk or posedge rst) begin
        if (rst) begin
            fps_sec_cnt <= 26'd0;
            fps_cnt_1s  <= 8'd0;
            fps_value   <= 8'd0;
        end
        else begin
            if (frame_done_lcd)
                fps_cnt_1s <= fps_cnt_1s + 8'd1;

            if (fps_sec_cnt == 26'd39_999_999) begin
                fps_sec_cnt <= 26'd0;
                fps_value   <= fps_cnt_1s;
                fps_cnt_1s  <= 8'd0;
            end
            else begin
                fps_sec_cnt <= fps_sec_cnt + 26'd1;
            end
        end
    end

    display u_display (
        .lcd_clk    (lcd_clk),
        .reset      (rst),
        .frame_done (frame_done_lcd),
        .fps_value  (fps_value),

        .mem_r_data (disp_mem_r_data),
        .mem_r_en   (disp_mem_r_en),
        .mem_r_addr (disp_mem_r_addr),

        .lcd_hsync  (lcd_hsync),
        .lcd_vsync  (lcd_vsync),
        .lcd_de     (lcd_de),
        .lcd_r      (lcd_r),
        .lcd_g      (lcd_g),
        .lcd_b      (lcd_b)
    );

    key #(
        .DEBOUNCE_CNT(20'd800_000)
    ) u_key_snapshot (
        .clk       (lcd_clk),
        .rst       (rst),
        .key_in    (~key_snapshot),
        .key_pulse (snapshot_req_pulse)
    );

    snapshot_copy_ctrl u_snapshot_copy_ctrl (
        .clk                  (lcd_clk),
        .rst                  (rst),
        .snapshot_req         (snapshot_req_pulse),
        .frame_done_pulse_lcd (frame_done_pulse_lcd),
        .frame_bank_sync2     (frame_bank_sync2),
        .src_r_data           (copy_src_r_data),
        .snapshot_clear       (snapshot_clear),
        .src_r_en             (copy_src_r_en),
        .src_r_addr           (copy_src_r_addr),
        .src_r_bank           (copy_src_r_bank),
        .snap_w_en            (snap_buf_w_en),
        .snap_w_addr          (snap_buf_w_addr),
        .snap_w_data          (snap_buf_w_data),
        .snapshot_valid       (snapshot_valid),
        .copy_busy            (copy_busy)
    );

    snapshot_ram #(
        .ADDR_WIDTH(14),
        .DATA_WIDTH(8)
    ) u_snapshot_ram (
        .clk    (lcd_clk),
        .w_en   (snap_buf_w_en),
        .w_addr (snap_buf_w_addr),
        .w_data (snap_buf_w_data),
        .r_en   (snap_buf_r_en),
        .r_addr (snap_buf_r_addr),
        .r_data (snap_buf_r_data)
    );

    shot_tx_ctrl u_shot_tx_ctrl (
        .clk            (lcd_clk),
        .rst            (rst),
        .snapshot_valid (snapshot_valid),
        .mem_r_data     (snap_buf_r_data),
        .uart_busy      (uart_busy),
        .uart_wr_en     (uart_wr_en),
        .uart_wr_data   (uart_wr_data),
        .mem_r_en       (snap_buf_r_en),
        .mem_r_addr     (snap_buf_r_addr),
        .snapshot_clear (snapshot_clear),
        .tx_active      (tx_active)
    );

    uart_tx #(
        .CLK_COUNT(40)
    ) u_uart_tx (
        .clk        (lcd_clk),
        .rst_n      (~rst),
        .o_busy     (uart_busy),
        .i_write_en (uart_wr_en),
        .i_data     (uart_wr_data),
        .o_tx       (uart_tx_o)
    );

endmodule
