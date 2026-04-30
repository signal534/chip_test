module frame_capture_pingpong (
    input  logic        clk_counter,
    input  logic        rst_n,
    input  logic        read_enable,
    input  logic [3:0]  vout,
    input  logic        row_0,
    input  logic        row_127,      
    output logic        mem_w_en,
    output logic [13:0] mem_w_addr,
    output logic [7:0]  mem_w_data,
    output logic        busy,
    output logic        frame_start,
    output logic        frame_done
);

    localparam int LINE_CYCLES = 256;
    localparam int LINE_BYTES  = 128;

    logic [1023:0] line_buf0;          //用于暂存一整行采样得到的 1024 bit 数据的第 0 个行缓冲
    logic [1023:0] line_buf1;          //用于暂存一整行采样得到的 1024 bit 数据的第 1 个行缓冲
    logic          capture_sel;        //表示当前新采到的一行要写进 buf0 还是 buf1
    logic          store_sel;          //表示当前准备从 buf0 还是 buf1 取数据写入帧存
    logic          buf0_full;          //表示 line_buf0 里已经有一整行有效数据等待写 RAM
    logic          buf1_full;          //表示 line_buf1 里已经有一整行有效数据等待写 RAM
    logic [6:0]    buf0_line_idx;      //记录 line_buf0 这整行数据属于图像的第几行
    logic [6:0]    buf1_line_idx;      //记录 line_buf1 这整行数据属于图像的第几行
    logic          read_enable_d;      //read_enable 的打一拍延迟版本，用来做边沿检测
    logic [3:0]    vout_d;             //vout[3:0] 的打一拍延迟版本，用来更稳地采串行数据
    logic          capture_active;     //表示当前正在从芯片串行采一整行数据
    logic [7:0]    sample_cnt;         //记录当前这一行已经采了多少个 4bit 采样拍
    logic [6:0]    capture_line_idx;   //记录当前正在采集的这行应当写到图像的哪一行位置
    logic [6:0]    stored_line_count;  //记录当前这一帧已经成功写入帧存了多少行
    logic          store_active;       //表示当前正在把某个行缓冲拆成字节写入帧存
    logic [6:0]    store_byte_cnt;     //记录当前这一行已经写入帧存多少个字节   
    logic          frame_start_pending;// row_0 当拍采到的是 line127，真正的 frame_start 放到下一行（line0）再拉高

    // 检测READ_ENABLE 下降沿：开始一行串行采样
    wire read_enable_fall = ~read_enable & read_enable_d;
    // 当前将要采入的 buffer 是否空闲
    wire capture_buf_ready =
        ((capture_sel == 1'b0) && !buf0_full) || ((capture_sel == 1'b1) && !buf1_full);

    // read_enable 打拍
    always_ff @(posedge clk_counter or negedge rst_n) begin
        if (!rst_n) begin
            read_enable_d <= 1'b0;
        end else begin
            read_enable_d <= read_enable;
        end
    end

    // vout 打拍
    always_ff @(posedge clk_counter or negedge rst_n) begin
        if (!rst_n)
            vout_d <= 4'd0;
        else
            vout_d <= vout;
    end

    always_ff @(posedge clk_counter or negedge rst_n) begin
        if (!rst_n) begin
            capture_sel         <= 1'b0;
            store_sel           <= 1'b0;
            buf0_full           <= 1'b0;
            buf1_full           <= 1'b0;
            buf0_line_idx       <= 7'd0;
            buf1_line_idx       <= 7'd0;
            capture_active      <= 1'b0;
            sample_cnt          <= 8'd0;
            capture_line_idx    <= 7'd0;
            stored_line_count   <= 7'd0;
            store_active        <= 1'b0;
            store_byte_cnt      <= 7'd0;
            frame_start_pending <= 1'b0;
            line_buf0           <= 1024'd0;
            line_buf1           <= 1024'd0;
            mem_w_en            <= 1'b0;
            mem_w_addr          <= 14'd0;
            mem_w_data          <= 8'd0;
            busy                <= 1'b0;
            frame_start         <= 1'b0;
            frame_done          <= 1'b0;
        end else begin
            mem_w_en    <= 1'b0;
            frame_start <= 1'b0;
            frame_done  <= 1'b0;

            busy <= capture_active | store_active | buf0_full | buf1_full;

            // 在 READ_ENABLE 下降沿启动一行采集
            if (read_enable_fall && !capture_active && capture_buf_ready) begin
                // 上一个 row_0 对应的 line127 已经结束，
                // 这一行才是真正的 line0，frame_start 在这里拉高
                if (frame_start_pending) begin
                    frame_start         <= 1'b1;
                    frame_start_pending <= 1'b0;
                end
                // row_0 高时，当前吐出的并不是 line0，而是上一行 line127
                // 所以把当前这一行编号成 127，而不是 0
                if (row_0) begin
                    capture_line_idx    <= 7'd127;
                    stored_line_count   <= 7'd127;
                    frame_start_pending <= 1'b1;
                end

                capture_active <= 1'b1;//开始表示正在采集行数据
                sample_cnt     <= 8'd0;//开始采集时将采集计数器归零
                //将行缓存归零
                if (capture_sel == 1'b0) //行缓存选择
                    line_buf0 <= 1024'd0;
                else
                    line_buf1 <= 1024'd0;
            end

            // READ_ENABLE 拉低后，在 clk_counter 下连续采 256 个 4bit
            if (capture_active && (read_enable == 1'b0)) begin
                //将采集的256拍4bit数据重新编排放入行缓存
                if (capture_sel == 1'b0) begin
                    line_buf0[sample_cnt]       <= vout_d[0];
                    line_buf0[256 + sample_cnt] <= vout_d[1];
                    line_buf0[512 + sample_cnt] <= vout_d[2];
                    line_buf0[768 + sample_cnt] <= vout_d[3];
                end else begin
                    line_buf1[sample_cnt]       <= vout_d[0];
                    line_buf1[256 + sample_cnt] <= vout_d[1];
                    line_buf1[512 + sample_cnt] <= vout_d[2];
                    line_buf1[768 + sample_cnt] <= vout_d[3];
                end
                //256拍4bit数据采满
                if (sample_cnt == LINE_CYCLES-1) begin
                    capture_active <= 1'b0;//结束采集行数据
                    //表示行缓存已满
                    if (capture_sel == 1'b0) begin
                        buf0_full     <= 1'b1;
                        buf0_line_idx <= capture_line_idx;
                    end else begin
                        buf1_full     <= 1'b1;
                        buf1_line_idx <= capture_line_idx;
                    end

                    capture_sel <= ~capture_sel;//交叉使用行缓存

                    if (capture_line_idx == 7'd127)
                        capture_line_idx <= 7'd0;
                    else
                        capture_line_idx <= capture_line_idx + 7'd1;
                end else begin
                    sample_cnt <= sample_cnt + 8'd1;
                end
            end

            // 启动写 RAM：哪块 buffer 满了先写哪块
            if (!store_active) begin
                if (buf0_full) begin
                    store_active   <= 1'b1;
                    store_sel      <= 1'b0;
                    store_byte_cnt <= 7'd0;
                end else if (buf1_full) begin
                    store_active   <= 1'b1;
                    store_sel      <= 1'b1;
                    store_byte_cnt <= 7'd0;
                end
            end

            // 把一整行拆成 128 个字节写 RAM
            if (store_active) begin
                mem_w_en <= 1'b1;

                if (store_sel == 1'b0) begin
                    mem_w_addr <= {buf0_line_idx, store_byte_cnt};
                    mem_w_data <= line_buf0[store_byte_cnt*8 +: 8];
                end else begin
                    mem_w_addr <= {buf1_line_idx, store_byte_cnt};
                    mem_w_data <= line_buf1[store_byte_cnt*8 +: 8];
                end

                if (store_byte_cnt == LINE_BYTES-1) begin
                    store_active <= 1'b0;

                    if (store_sel == 1'b0)
                        buf0_full <= 1'b0;
                    else
                        buf1_full <= 1'b0;

                    if (stored_line_count == 7'd127) begin
                        stored_line_count <= 7'd0;
                        frame_done        <= 1'b1;
                    end else begin
                        stored_line_count <= stored_line_count + 7'd1;
                    end
                end else begin
                    store_byte_cnt <= store_byte_cnt + 7'd1;
                end
            end
        end
    end
endmodule
