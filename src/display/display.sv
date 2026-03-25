module display (
    input  logic        lcd_clk,
    input  logic        reset,

    input  logic        frame_done,

    input  logic [7:0]  mem_r_data,
    output logic        mem_r_en,
    output logic [13:0] mem_r_addr,

    output logic        lcd_hsync,
    output logic        lcd_vsync,
    output logic        lcd_de,
    output logic [7:0]  lcd_r,
    output logic [7:0]  lcd_g,
    output logic [7:0]  lcd_b
);

    localparam integer H_SYNC   = 128;
    localparam integer H_BP     = 88;
    localparam integer H_ACTIVE = 800;
    localparam integer H_FP     = 40;
    localparam integer H_TOTAL  = H_SYNC + H_BP + H_ACTIVE + H_FP;

    localparam integer V_SYNC   = 2;
    localparam integer V_BP     = 33;
    localparam integer V_ACTIVE = 480;
    localparam integer V_FP     = 10;
    localparam integer V_TOTAL  = V_SYNC + V_BP + V_ACTIVE + V_FP;

    localparam integer IMG_W    = 128;
    localparam integer IMG_H    = 128;
    localparam integer IMG_X0   = 336;
    localparam integer IMG_Y0   = 176;

    logic [10:0] h_cnt;
    logic [9:0]  v_cnt;

    logic [10:0] act_x;
    logic [9:0]  act_y;

    logic        img_area;
    logic [6:0]  img_x;
    logic [6:0]  img_y;

    logic [13:0] rd_addr;

    logic img_area_d1;
    logic de_d1;
    logic frame_ready;
    logic frame_ready_d1;

    always_ff @(posedge lcd_clk or posedge reset) begin
        if (reset) begin
            h_cnt <= 11'd0;
            v_cnt <= 10'd0;
        end
        else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 11'd0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end
            else begin
                h_cnt <= h_cnt + 11'd1;
            end
        end
    end

    assign lcd_hsync = (h_cnt < H_SYNC) ? 1'b0 : 1'b1;
    assign lcd_vsync = (v_cnt < V_SYNC) ? 1'b0 : 1'b1;

    assign lcd_de =
        (h_cnt >= H_SYNC + H_BP) && (h_cnt < H_SYNC + H_BP + H_ACTIVE) &&
        (v_cnt >= V_SYNC + V_BP) && (v_cnt < V_SYNC + V_BP + V_ACTIVE);

    assign act_x = h_cnt - (H_SYNC + H_BP);
    assign act_y = v_cnt - (V_SYNC + V_BP);

    assign img_area =
        lcd_de &&
        (act_x >= IMG_X0) && (act_x < IMG_X0 + IMG_W) &&
        (act_y >= IMG_Y0) && (act_y < IMG_Y0 + IMG_H);

    assign img_x = act_x - IMG_X0;
    assign img_y = act_y - IMG_Y0;

    always_ff @(posedge lcd_clk or posedge reset) begin
        if (reset) begin
            frame_ready    <= 1'b0;
            frame_ready_d1 <= 1'b0;
            rd_addr        <= 14'd0;
            img_area_d1    <= 1'b0;
            de_d1          <= 1'b0;
        end
        else begin
            if (frame_done)
                frame_ready <= 1'b1;

            frame_ready_d1 <= frame_ready;
            img_area_d1    <= img_area;
            de_d1          <= lcd_de;

            if (frame_ready && img_area)
                rd_addr <= {img_y, img_x};
            else
                rd_addr <= 14'd0;
        end
    end

    assign mem_r_en   = frame_ready && img_area;
    assign mem_r_addr = rd_addr;

    always_ff @(posedge lcd_clk or posedge reset) begin
        if (reset) begin
            lcd_r <= 8'd0;
            lcd_g <= 8'd0;
            lcd_b <= 8'd0;
        end
        else begin
            if (frame_ready_d1 && img_area_d1 && de_d1) begin
                lcd_r <= mem_r_data;
                lcd_g <= mem_r_data;
                lcd_b <= mem_r_data;
            end
            else begin
                lcd_r <= 8'd0;
                lcd_g <= 8'd0;
                lcd_b <= 8'd0;
            end
        end
    end

endmodule