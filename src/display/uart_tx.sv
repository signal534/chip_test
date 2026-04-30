`timescale 1ns / 1ps

module uart_tx # (
    parameter  int CLK_COUNT = 868,
    localparam int BIT_COUNT = 8//与RX模块相同
) (
    input  logic                 clk,
    input  logic                 rst_n,
    output logic                 o_busy,//正在发送
    input  logic                 i_write_en,//请求发送
    input  logic [BIT_COUNT-1:0] i_data,//并行输入
    output logic                 o_tx//串行输出
);

    logic [BIT_COUNT-1:0] memory;//发送数据缓存
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memory <= 'x;//复位
        end else begin
            if (i_write_en) begin
                memory <= i_data;//请求发送，将并行输入锁存
            end
        end
    end

    enum logic [1:0] {
        IDLE,
        START_BIT,
        DATA_BIT,
        STOP_BIT
    } state;//枚举URAT发送流程状态：空闲 → 起始位 → 数据位 → 停止位 → 空闲，持续10个bit时间

    reg [$clog2(CLK_COUNT)-1:0] clk_count;//bit内计时
    reg [$clog2(BIT_COUNT)-1:0] bit_count;//第几bit

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            clk_count <= 'x;
            bit_count <= 'x;//复位
        end else begin
            case (state)
                IDLE: begin
                    if (i_write_en) begin
                        state     <= START_BIT;
                        clk_count <= 0;
                    end
                end//检测到输入使能为1开始起始位，计数归零
                START_BIT: begin
                    if (clk_count == CLK_COUNT - 1) begin//持续1bit时间
                        state     <= DATA_BIT;
                        clk_count <= 0;
                        bit_count <= 0;
                    end else begin
                        clk_count <= clk_count + 1;//bit内计数器上升沿计数+1
                    end
                end
                DATA_BIT: begin
                    if (clk_count == CLK_COUNT - 1) begin//持续8bit时间
                        if (bit_count == BIT_COUNT - 1) begin//反复进行8次
                            state     <= STOP_BIT;
                            clk_count <= 0;
                            bit_count <= 'x;
                        end else begin
                            clk_count <= 0;
                            bit_count <= bit_count + 1;//bit循环计数器上升沿计数+1
                        end
                    end else begin
                        clk_count <= clk_count + 1;//bit内计数器上升沿计数+1
                    end
                end
                STOP_BIT: begin
                    if (clk_count == CLK_COUNT - 1) begin//持续1bit时间
                        state     <= IDLE;
                        clk_count <= 'x;
                    end else begin
                        clk_count <= clk_count + 1;//bit内计数器上升沿计数+1
                    end
                end
            endcase
        end
    end

    assign o_tx = (state == START_BIT)? 1'b0:
                  (state == DATA_BIT)?  memory[bit_count]: 1'b1;//描述串行输出对应状态：IDLE-1，START-0，DATA-data，STOP-1

    assign o_busy = (state != IDLE);//只要不处于IDLE状态，就不能写入

endmodule