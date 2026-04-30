module snapshot_copy_ctrl (
    input  logic        clk,
    input  logic        rst,
    // 用户截图请求（单拍）
    input  logic        snapshot_req,
    // 跨到lcd域
    input  logic        frame_done_pulse_lcd,// frame_done 跨域到 lcd_clk
    input  logic        frame_bank_sync2,    // bank 跨域到 lcd_clk
    // 来自 reg_file 第二读口的数据
    input  logic [7:0]  src_r_data,
    // shot_tx_ctrl 发送完成后清空当前 snapshot
    input  logic        snapshot_clear,
    // 驱动 reg_file 第二读口
    output logic        src_r_en,
    output logic [13:0] src_r_addr,
    output logic        src_r_bank,
    // 写入独立 snapshot_ram
    output logic        snap_w_en,
    output logic [13:0] snap_w_addr,
    output logic [7:0]  snap_w_data,
    // 状态输出
    output logic        snapshot_valid,
    output logic        copy_busy
);

    localparam logic [2:0]
        S_IDLE       = 3'd0,
        S_WAIT_FRAME = 3'd1,
        S_COPY_REQ   = 3'd2,
        S_COPY_WAIT1 = 3'd3,
        S_COPY_WAIT2 = 3'd4,
        S_COPY_WRITE = 3'd5,
        S_DONE       = 3'd6;

    localparam logic [13:0] IMG_LAST_ADDR = 14'd16383;

    logic [2:0]  state;
    logic        snapshot_pending;//有截图请求挂起
    logic [13:0] copy_idx;        //当前正在拷贝的像素地址，范围 0~16383
    logic        src_bank_latched;//锁存下来的源 bank，保证整次拷贝始终从同一个 bank 读

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= S_IDLE;
            snapshot_pending <= 1'b0;
            snapshot_valid   <= 1'b0;
            copy_busy        <= 1'b0;

            copy_idx         <= 14'd0;
            src_bank_latched <= 1'b0;

            src_r_en         <= 1'b0;
            src_r_addr       <= 14'd0;
            src_r_bank       <= 1'b0;

            snap_w_en        <= 1'b0;
            snap_w_addr      <= 14'd0;
            snap_w_data      <= 8'd0;
        end
        else begin
            src_r_en  <= 1'b0;//复制使能为0
            snap_w_en <= 1'b0;//写使能为0

            // 用户按键：只要按过一次，就挂起一次截图请求
            if (snapshot_req)
                snapshot_pending <= 1'b1;

            // 发送链路通知：当前 snapshot 已发送完，可以释放
            if (snapshot_clear)
                snapshot_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    copy_busy <= 1'b0;

                    if (snapshot_pending && !snapshot_valid)
                        state <= S_WAIT_FRAME;
                end

                // 等待采集模块下一张完整帧稳定完成，再锁定其对应的 bank
                S_WAIT_FRAME: begin
                    if (frame_done_pulse_lcd) begin
                        copy_busy        <= 1'b1;
                        copy_idx         <= 14'd0;
                        src_bank_latched <= frame_bank_sync2;
                        src_r_bank       <= frame_bank_sync2;
                        state            <= S_COPY_REQ;
                    end
                end

                // 复制 reg_file中的对应的 bank 的数据
                S_COPY_REQ: begin
                    src_r_en   <= 1'b1;
                    src_r_addr <= copy_idx;
                    src_r_bank <= src_bank_latched;
                    state      <= S_COPY_WAIT1;
                end

                // reg_file 为同步读口，保守等两拍
                S_COPY_WAIT1: begin
                    state <= S_COPY_WAIT2;
                end

                S_COPY_WAIT2: begin
                    state <= S_COPY_WRITE;
                end

                // 把该字节写入独立 snapshot_ram
                S_COPY_WRITE: begin
                    snap_w_en   <= 1'b1;
                    snap_w_addr <= copy_idx;
                    snap_w_data <= src_r_data;

                    if (copy_idx == IMG_LAST_ADDR)
                        state <= S_DONE;
                    else begin
                        copy_idx <= copy_idx + 14'd1;
                        state    <= S_COPY_REQ;
                    end
                end

                S_DONE: begin
                    snapshot_valid   <= 1'b1;
                    snapshot_pending <= 1'b0;
                    copy_busy        <= 1'b0;
                    state            <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule