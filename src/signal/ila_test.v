`timescale 1ns / 1ps
module ila_test(
input   wire                clk_5M,
input   wire                clk_125M,
input   wire                locked,
input   wire                start_key,
input   wire                hsync,
input   wire                clk_row,
input   wire                row0,            // 芯片 row[0] 信号
input   wire   [3:0]        data,
input   wire                en,
output  reg                 clk_2_5M,
output  reg                 clk_200K,
output  wire                dac_clk1,
output  wire   [13:0]       dac_data1,
output  wire                pulse_16ms_1ms   // = VPD_RESET
    );

reg hsync_ila;
reg [3:0] data_ila;
reg en_ila;

wire rst_n;

reg [15:0] dac_data;
reg [15:0] data_buf1;

reg  working_state;
wire nege_start_key;
reg  [7:0] start_key_delay_shift = 8'b1111_1111;
reg  [7:0] clk_200K_cnt;

// clk_row同步到125MHz域并检测上升沿（用于125us斜坡）
reg clk_row_d0;
reg clk_row_d1;
wire clk_row_rise_125M;

// row[0]同步到125MHz域并检测上升沿（用于VPD_RESET帧起点）
reg row0_d0;
reg row0_d1;
wire row0_rise_125M;

// 125us斜坡控制
reg        ramp_active;
reg [15:0] ramp_cnt;

// VPD_RESET控制：以row[0]上升沿开启一帧，前1ms低、后15ms高
reg [20:0] frame_cnt;
reg        vpd_reset_reg;

localparam [15:0] DAC_MAX   = 14'd16383;
localparam [15:0] DAC_400MV = 14'd9381;
localparam integer RAMP_PERIOD_CLKS = 16'd15625;    // 125us @ 125MHz
localparam integer DAC_STEP_TOTAL   = DAC_MAX - DAC_400MV;
// localparam integer DAC_STEP_TOTAL_OLD = DAC_MAX - DAC_400MV;
// localparam integer DAC_STEP_TOTAL     = DAC_STEP_TOTAL_OLD / 2; 
// localparam [15:0] DAC_END             = DAC_MAX - DAC_STEP_TOTAL; 
localparam integer ONE_MS_CLKS      = 21'd125000;   // 1ms   @ 125MHz
localparam integer FRAME_CLKS       = 21'd2000000;  // 16ms  @ 125MHz

assign dac_data1        = data_buf1[13:0];
assign rst_n            = locked;
assign dac_clk1         = clk_125M;
assign pulse_16ms_1ms   = vpd_reset_reg;

// start_key下降沿检测
always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    start_key_delay_shift <= 8'b1111_1111;
else
    start_key_delay_shift <= {start_key_delay_shift[6:0], start_key};

assign nege_start_key = start_key_delay_shift[7] & !start_key_delay_shift[6];

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
else
    clk_2_5M <= 1'b0;

// clk_200K
always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    clk_200K <= 1'b0;
else if(working_state) begin
    if(clk_200K_cnt <= 8'd12)
        clk_200K <= 1'b0;
    else
        clk_200K <= 1'b1;
end
else
    clk_200K <= 1'b0;

always @(posedge clk_5M or negedge rst_n)
if(!rst_n)
    clk_200K_cnt <= 8'd0;
else if(working_state) begin
    if(clk_200K_cnt == 8'd24)
        clk_200K_cnt <= 8'd0;
    else
        clk_200K_cnt <= clk_200K_cnt + 1'b1;
end
else
    clk_200K_cnt <= 8'd0;

// clk_row同步到clk_125M域
always @(posedge clk_125M or negedge rst_n) begin
    if(!rst_n) begin
        clk_row_d0 <= 1'b0;
        clk_row_d1 <= 1'b0;
    end
    else begin
        clk_row_d0 <= clk_row;
        clk_row_d1 <= clk_row_d0;
    end
end

assign clk_row_rise_125M = clk_row_d0 & ~clk_row_d1;

// row[0]同步到clk_125M域
always @(posedge clk_125M or negedge rst_n) begin
    if(!rst_n) begin
        row0_d0 <= 1'b0;
        row0_d1 <= 1'b0;
    end
    else begin
        row0_d0 <= row0;
        row0_d1 <= row0_d0;
    end
end

assign row0_rise_125M = row0_d0 & ~row0_d1;

// VPD_RESET：以row[0]上升沿为每帧起点
// 每帧16ms：前1ms低，后15ms高
always @(posedge clk_125M or negedge rst_n) begin
    if(!rst_n) begin
        frame_cnt     <= 21'd0;
        vpd_reset_reg <= 1'b0;
    end
    else if(row0_rise_125M) begin
        // frame_cnt     <= 21'd0;
        // vpd_reset_reg <= 1'b0;
        frame_cnt     <= 21'd1;
        vpd_reset_reg <= 1'b1;
    end
    else begin
        if(frame_cnt < FRAME_CLKS - 1)
            frame_cnt <= frame_cnt + 1'b1;
        else
            frame_cnt <= frame_cnt;

        if(frame_cnt < ONE_MS_CLKS)
            vpd_reset_reg <= 1'b1;
            // vpd_reset_reg <= 1'b0;
        else
            vpd_reset_reg <= 1'b0;
            // vpd_reset_reg <= 1'b1;
    end
end

// 125us线性斜坡：由clk_row上升沿触发
always @(posedge clk_125M or negedge rst_n) begin
    if (!rst_n) begin
        ramp_active <= 1'b0;
        ramp_cnt    <= 16'd0;
        dac_data    <= DAC_MAX;
    end
    else if (clk_row_rise_125M) begin
        ramp_active <= 1'b1;
        ramp_cnt    <= 16'd0;
        dac_data    <= DAC_MAX;
    end
    else if (ramp_active) begin
        if (ramp_cnt < RAMP_PERIOD_CLKS - 1) begin
            ramp_cnt <= ramp_cnt + 1'b1;
            dac_data <= DAC_MAX - ((DAC_STEP_TOTAL * (ramp_cnt + 1'b1)) / RAMP_PERIOD_CLKS);
        end
        else begin
            ramp_active <= 1'b0;
            // dac_data <= DAC_END;
            dac_data <= DAC_400MV;
        end
    end
    else begin
        // dac_data <= DAC_END;
        dac_data <= DAC_400MV;
    end
end

// DAC输出反相
always @(posedge clk_125M or negedge rst_n)
begin
    if(!rst_n)
        data_buf1 <= 16'd0;
    else
        data_buf1 <= DAC_MAX - dac_data;
end

// ILA采样
always @(posedge clk_5M or negedge rst_n)
begin
    if(!rst_n) begin
        hsync_ila <= 1'b0;
        data_ila  <= 4'd0;
        en_ila    <= 1'b0;
    end
    else begin
        hsync_ila <= hsync;
        data_ila  <= data;
        en_ila    <= en;
    end
end

endmodule
