`timescale 1ns / 1ps
module ila_test(
input   wire                clk_in_50M,
//input   wire                rst_n, // FPGA reset pin
input   wire                start_key,
//input   wire                rst_n_from_chip,
input   wire                hsync,
input   wire   [3:0]        data,
input   wire                en,
output  wire                clk_2_5M,
output  wire                clk_200K,
//input   wire                wave_start_en,
output  wire                dac_clk1,
output  wire   [11:0]       dac_data1,
output  wire                pulse_16ms_1ms
    );

(*MARK_DEBUG="true"*)reg hsync_ila;
(*MARK_DEBUG="true"*)reg [3:0] data_ila;
(*MARK_DEBUG="true"*)reg en_ila;
(*MARK_DEBUG="true"*)reg [16:0] pulse_16ms_1ms_cnt;

wire clk_125M_unused;   // 保留原命名风格，实际不再用于DAC状态机
wire clk_32M;           // DAC状态机实际使用的32MHz时钟
wire locked;
wire rst_n;
wire clk_5M;
wire wave_start_en;

(*MARK_DEBUG="true"*)reg [11:0] dac_data;
reg [11:0] data_buf1;

reg clk_8M = 0;

(*MARK_DEBUG="true"*)reg  clk_2_5M;
(*MARK_DEBUG="true"*)reg  clk_200K;
(*MARK_DEBUG="true"*)reg  working_state;
wire nege_start_key;
wire pose_wave_start;
(*MARK_DEBUG="true"*)reg  [7:0] start_key_delay_shift = 8'b1111_1111;
(*MARK_DEBUG="true"*)reg  [7:0] wave_start_en_shift   = 8'b0000_0000;
reg [7:0] clk_200K_cnt;

(*MARK_DEBUG="true"*)reg [15:0] clk_cnt; 
(*MARK_DEBUG="true"*)reg [15:0] cycle_7_cnt;
(*MARK_DEBUG="true"*)reg [15:0] cycle_89_cnt;
(*MARK_DEBUG="true"*)reg [3:0]  state;

// 12bit DAC码值定义（由14bit等比例缩放）
// 原14bit:
//   700mV平台: 16383
//   400mV平台: 12872
// 缩放到12bit:
//   DAC_MAX   = 4095
//   DAC_400MV ≈ round(12872 * 4095 / 16383) = 3217
localparam [11:0] DAC_MAX   = 12'd4095;
localparam [11:0] DAC_400MV = 12'd3217;

// 32MHz下的更新时间参数
// 原先125MHz下是 3 / 4 / 5 clk 更新一次
// 理论换算到32MHz并考虑14bit->12bit后，约对应 3 / 4 / 5
// 所以这里保持 3 / 4 / 5 不变即可，时间特性已经比较接近
localparam integer SLOT3_CLK = 3;
localparam integer SLOT4_CLK = 4;
localparam integer SLOT5_CLK = 5;

// 状态定义
localparam [3:0]
    S_IDLE             = 4'd0,
    S_700MV            = 4'd1,
    S_SLOT_3CLK_UPDATE = 4'd2,
    S_SLOT_4CLK_UPDATE = 4'd3,
    S_SLOT_5CLK_UPDATE = 4'd4,
    S_400MV            = 4'd5;

// 低频脉冲
always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    pulse_16ms_1ms_cnt <= 'd0;
else if(pulse_16ms_1ms_cnt == 'd80000)
    pulse_16ms_1ms_cnt <= 'd0;
else
    pulse_16ms_1ms_cnt <= pulse_16ms_1ms_cnt + 1'b1;

assign pulse_16ms_1ms = (pulse_16ms_1ms_cnt <= 5000);
// assign pulse_16ms_1ms = (pulse_16ms_1ms_cnt <= 20000);

// 外部触发源
clk_div_50M_to_8K x(
    .clk_50M(clk_in_50M),
    .rst_n(locked),
    .clk_8K(clk_8K)
);
assign wave_start_en = clk_8K;
assign dac_data1     = data_buf1;
assign rst_n         = locked;

// 时钟模块
// 这里要求你把 clk_wiz_0_5M 的 clk_out3 配置成 32MHz
// clk_out2 即使还是125MHz也没关系，这里不再用它驱动DAC状态机
clk_wiz_0_5M instance_name
(
    .clk_out1(clk_5M),          // 5MHz
    .clk_out2(clk_125M_unused), // 原125MHz保留但不使用
    .clk_out3(clk_32M),         // 这里请在IP里改成32MHz
    .locked(locked),
    .clk_in1(clk_in_50M)
);

assign dac_clk1 = clk_32M;

// start_key / wave_start_en 边沿检测
always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    start_key_delay_shift <= 8'b1111_1111;
else
    start_key_delay_shift <= {start_key_delay_shift[6:0], start_key};

always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    wave_start_en_shift <= 8'b0000_0000;
else
    wave_start_en_shift <= {wave_start_en_shift[6:0], wave_start_en};

assign nege_start_key = start_key_delay_shift[7] & !start_key_delay_shift[6];
assign pose_wave_start = !wave_start_en_shift[7] & wave_start_en_shift[6];

// 工作使能
always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    working_state <= 1'b0;
else if(nege_start_key)
    working_state <= 1'b1;

// clk_2_5M
always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    clk_2_5M <= 1'b0;
else if(working_state)
    clk_2_5M <= ~clk_2_5M;

// clk_200K
always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    clk_200K <= 1'b0;
else if(working_state) begin
    if(clk_200K_cnt <= 'd12)
        clk_200K <= 1'b0;
    else
        clk_200K <= 1'b1;
end
else
    clk_200K <= clk_200K;

always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    clk_200K_cnt <= 'd0;
else if(working_state) begin
    if(clk_200K_cnt == ('d25 - 1))
        clk_200K_cnt <= 'd0;
    else
        clk_200K_cnt <= clk_200K_cnt + 1'b1;
end
else
    clk_200K_cnt <= clk_200K_cnt;

// DAC波形状态机
// 现在改为在32MHz时钟下运行
always @(posedge clk_32M or negedge rst_n)
if (!rst_n) begin
    clk_cnt      <= 'd0;
    state        <= S_IDLE;
    cycle_7_cnt  <= 'd0;
    cycle_89_cnt <= 'd0;
    dac_data     <= DAC_MAX;
end
else begin
    case(state)
        S_IDLE: begin
            clk_cnt      <= 'd0;
            cycle_7_cnt  <= 'd0;
            cycle_89_cnt <= 'd0;
            if (pose_wave_start)
                state <= S_700MV;
            else
                state <= S_IDLE;
        end

        S_700MV: begin
            dac_data <= DAC_MAX;
            if (clk_cnt == (32*15 - 1))
                clk_cnt <= 'd0;
            else
                clk_cnt <= clk_cnt + 1'b1;

            if (clk_cnt == (32*15 - 1))
                state <= S_SLOT_3CLK_UPDATE;
            else
                state <= S_700MV;
        end

        S_SLOT_3CLK_UPDATE: begin
            if (clk_cnt == (SLOT3_CLK - 1))
                dac_data <= dac_data - 1'b1;
            else
                dac_data <= dac_data;

            if (clk_cnt == (SLOT3_CLK - 1))
                clk_cnt <= 'd0;
            else
                clk_cnt <= clk_cnt + 1'b1;

            if (clk_cnt == (SLOT3_CLK - 1))
                state <= S_SLOT_4CLK_UPDATE;
            else
                state <= S_SLOT_3CLK_UPDATE;
        end

        S_SLOT_4CLK_UPDATE: begin
            if (clk_cnt == (SLOT4_CLK - 1))
                dac_data <= dac_data - 1'b1;
            else
                dac_data <= dac_data;

            if (clk_cnt == (SLOT4_CLK - 1) && cycle_7_cnt == (12 - 1))
                cycle_7_cnt <= 'd0;
            else if (clk_cnt == (SLOT4_CLK - 1))
                cycle_7_cnt <= cycle_7_cnt + 1'b1;
            else
                cycle_7_cnt <= cycle_7_cnt;

            if (clk_cnt == (SLOT4_CLK - 1))
                clk_cnt <= 'd0;
            else
                clk_cnt <= clk_cnt + 1'b1;

            if (clk_cnt == (SLOT4_CLK - 1) && cycle_7_cnt == (12 - 1))
                state <= S_SLOT_5CLK_UPDATE;
            else if (clk_cnt == (SLOT4_CLK - 1))
                state <= S_SLOT_3CLK_UPDATE;
            else
                state <= S_SLOT_4CLK_UPDATE;
        end

        S_SLOT_5CLK_UPDATE: begin
            if (clk_cnt == (SLOT5_CLK - 1))
                dac_data <= dac_data - 1'b1;
            else
                dac_data <= dac_data;

            if (clk_cnt == (SLOT5_CLK - 1) && cycle_89_cnt == (35 - 1))
                cycle_89_cnt <= 'd0;
            else if (clk_cnt == (SLOT5_CLK - 1))
                cycle_89_cnt <= cycle_89_cnt + 1'b1;
            else
                cycle_89_cnt <= cycle_89_cnt;

            if (clk_cnt == (SLOT5_CLK - 1))
                clk_cnt <= 'd0;
            else
                clk_cnt <= clk_cnt + 1'b1;

            if (clk_cnt == (SLOT5_CLK - 1) && cycle_89_cnt == (35 - 1))
                state <= S_400MV;
            else if (clk_cnt == (SLOT5_CLK - 1))
                state <= S_SLOT_3CLK_UPDATE;
            else
                state <= S_SLOT_5CLK_UPDATE;
        end

        S_400MV: begin
            dac_data <= DAC_400MV;
            if (pose_wave_start)
                state <= S_700MV;
            else
                state <= S_400MV;
        end

        default: begin
            state        <= S_IDLE;
            clk_cnt      <= 'd0;
            cycle_7_cnt  <= 'd0;
            cycle_89_cnt <= 'd0;
            dac_data     <= DAC_MAX;
        end
    endcase
end

// DAC输出反相
always @(posedge clk_32M)
begin
    data_buf1 <= DAC_MAX - dac_data;
end

// ILA采样
always @(posedge clk_5M)
begin
    hsync_ila <= hsync;
    data_ila  <= data;
    en_ila    <= en;
end

endmodule