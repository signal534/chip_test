module shot_tx_ctrl (
    input  logic        clk,
    input  logic        rst,

    // snapshot_copy_ctrl 已经准备好一张完整截图
    input  logic        snapshot_valid,

    // 来自 snapshot_ram 的数据
    input  logic [7:0]  mem_r_data,

    // uart_tx 接口
    input  logic        uart_busy,
    output logic        uart_wr_en,
    output logic [7:0]  uart_wr_data,

    // 驱动 snapshot_ram 读口
    output logic        mem_r_en,
    output logic [13:0] mem_r_addr,

    // 通知 snapshot_copy_ctrl：本张图已发送完
    output logic        snapshot_clear,
    output logic        tx_active
);

    localparam logic [4:0]
        S_IDLE           = 5'd0,
        S_HEAD_SEND      = 5'd1,
        S_HEAD_BUSY_H    = 5'd2,
        S_HEAD_BUSY_L    = 5'd3,
        S_PAYLOAD_REQ    = 5'd4,
        S_PAYLOAD_WAIT1  = 5'd5,
        S_PAYLOAD_WAIT2  = 5'd6,
        S_PAYLOAD_LATCH  = 5'd7,
        S_PAYLOAD_SEND   = 5'd8,
        S_PAYLOAD_BUSY_H = 5'd9,
        S_PAYLOAD_BUSY_L = 5'd10,
        S_DONE           = 5'd11;

    localparam logic [13:0] IMG_LAST_ADDR = 14'd16383;

    logic [4:0]  state;
    logic [1:0]  head_idx;
    logic [13:0] payload_idx;
    logic [7:0]  payload_byte;

    // 新增：只在 snapshot_valid 上升沿启动一次
    logic        snapshot_valid_d;
    logic        snapshot_start_pulse;

    function automatic logic [7:0] head_byte(input logic [1:0] idx);
        begin
            case (idx)
                2'd0: head_byte = 8'h55;
                2'd1: head_byte = 8'hAA;
                2'd2: head_byte = 8'h5A;
                2'd3: head_byte = 8'hA5;
                default: head_byte = 8'h55;
            endcase
        end
    endfunction

    assign snapshot_start_pulse = snapshot_valid & ~snapshot_valid_d;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= S_IDLE;
            head_idx         <= 2'd0;
            payload_idx      <= 14'd0;
            payload_byte     <= 8'd0;

            snapshot_valid_d <= 1'b0;

            uart_wr_en       <= 1'b0;
            uart_wr_data     <= 8'd0;
            mem_r_en         <= 1'b0;
            mem_r_addr       <= 14'd0;
            snapshot_clear   <= 1'b0;
            tx_active        <= 1'b0;
        end
        else begin
            snapshot_valid_d <= snapshot_valid;

            uart_wr_en       <= 1'b0;
            mem_r_en         <= 1'b0;
            snapshot_clear   <= 1'b0;

            case (state)
                S_IDLE: begin
                    tx_active   <= 1'b0;
                    head_idx    <= 2'd0;
                    payload_idx <= 14'd0;

                    if (snapshot_start_pulse) begin
                        tx_active <= 1'b1;
                        state     <= S_HEAD_SEND;
                    end
                end

                S_HEAD_SEND: begin
                    uart_wr_en   <= 1'b1;
                    uart_wr_data <= head_byte(head_idx);
                    state        <= S_HEAD_BUSY_H;
                end

                S_HEAD_BUSY_H: begin
                    if (uart_busy)
                        state <= S_HEAD_BUSY_L;
                end

                S_HEAD_BUSY_L: begin
                    if (!uart_busy) begin
                        if (head_idx == 2'd3) begin
                            payload_idx <= 14'd0;
                            state       <= S_PAYLOAD_REQ;
                        end
                        else begin
                            head_idx <= head_idx + 2'd1;
                            state    <= S_HEAD_SEND;
                        end
                    end
                end

                S_PAYLOAD_REQ: begin
                    mem_r_en   <= 1'b1;
                    mem_r_addr <= payload_idx;
                    state      <= S_PAYLOAD_WAIT1;
                end

                S_PAYLOAD_WAIT1: begin
                    state <= S_PAYLOAD_WAIT2;
                end

                S_PAYLOAD_WAIT2: begin
                    state <= S_PAYLOAD_LATCH;
                end

                S_PAYLOAD_LATCH: begin
                    payload_byte <= mem_r_data;
                    state        <= S_PAYLOAD_SEND;
                end

                S_PAYLOAD_SEND: begin
                    uart_wr_en   <= 1'b1;
                    uart_wr_data <= payload_byte;
                    state        <= S_PAYLOAD_BUSY_H;
                end

                S_PAYLOAD_BUSY_H: begin
                    if (uart_busy)
                        state <= S_PAYLOAD_BUSY_L;
                end

                S_PAYLOAD_BUSY_L: begin
                    if (!uart_busy) begin
                        if (payload_idx == IMG_LAST_ADDR)
                            state <= S_DONE;
                        else begin
                            payload_idx <= payload_idx + 14'd1;
                            state       <= S_PAYLOAD_REQ;
                        end
                    end
                end

                S_DONE: begin
                    snapshot_clear <= 1'b1;
                    tx_active      <= 1'b0;
                    state          <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule