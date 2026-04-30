module display (
    input  logic        lcd_clk,
    input  logic        reset,

    input  logic        frame_done,
    input  logic [7:0]  fps_value,

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

    // FPS显示区：左上角空白区，不压在图片上
    localparam integer FPS_X0   = 40;
    localparam integer FPS_Y0   = 40;
    localparam integer DIGIT_W  = 8;
    localparam integer DIGIT_H  = 16;
    localparam integer DIGIT_GAP= 2;

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

    logic [3:0] fps_hundreds;
    logic [3:0] fps_tens;
    logic [3:0] fps_ones;

    logic       fps_area;
    logic [1:0] digit_sel;
    logic [3:0] digit_now;
    logic [3:0] char_x;
    logic [4:0] char_y;
    logic       fps_pixel_on;

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

    assign fps_hundreds = fps_value / 8'd100;
    assign fps_tens     = (fps_value % 8'd100) / 8'd10;
    assign fps_ones     = fps_value % 8'd10;

    assign fps_area =
        lcd_de &&
        (act_x >= FPS_X0) &&
        (act_x < FPS_X0 + DIGIT_W*3 + DIGIT_GAP*2) &&
        (act_y >= FPS_Y0) &&
        (act_y < FPS_Y0 + DIGIT_H);

    always_comb begin
        if (act_x < FPS_X0 + DIGIT_W) begin
            digit_sel = 2'd0;
            char_x    = act_x - FPS_X0;
        end
        else if (act_x < FPS_X0 + DIGIT_W + DIGIT_GAP + DIGIT_W) begin
            digit_sel = 2'd1;
            char_x    = act_x - (FPS_X0 + DIGIT_W + DIGIT_GAP);
        end
        else begin
            digit_sel = 2'd2;
            char_x    = act_x - (FPS_X0 + (DIGIT_W + DIGIT_GAP) * 2);
        end
    end

    assign char_y = act_y - FPS_Y0;

    always_comb begin
        case (digit_sel)
            2'd0: digit_now = fps_hundreds;
            2'd1: digit_now = fps_tens;
            default: digit_now = fps_ones;
        endcase
    end

    function automatic logic digit_pixel(
        input logic [3:0] digit,
        input logic [3:0] x,
        input logic [4:0] y
    );
        logic a,b,c,d,e,f,g;
        begin
            a = 1'b0; b = 1'b0; c = 1'b0; d = 1'b0;
            e = 1'b0; f = 1'b0; g = 1'b0;

            case (digit)
                4'd0: begin a=1; b=1; c=1; d=1; e=1; f=1; end
                4'd1: begin b=1; c=1; end
                4'd2: begin a=1; b=1; d=1; e=1; g=1; end
                4'd3: begin a=1; b=1; c=1; d=1; g=1; end
                4'd4: begin b=1; c=1; f=1; g=1; end
                4'd5: begin a=1; c=1; d=1; f=1; g=1; end
                4'd6: begin a=1; c=1; d=1; e=1; f=1; g=1; end
                4'd7: begin a=1; b=1; c=1; end
                4'd8: begin a=1; b=1; c=1; d=1; e=1; f=1; g=1; end
                4'd9: begin a=1; b=1; c=1; d=1; f=1; g=1; end
                default: begin end
            endcase

            digit_pixel =
                (a && (y <= 1)              && (x >= 1 && x <= 6)) ||
                (d && (y >= 14)             && (x >= 1 && x <= 6)) ||
                (g && (y >= 7 && y <= 8)    && (x >= 1 && x <= 6)) ||
                (f && (x <= 1)              && (y >= 1 && y <= 7)) ||
                (e && (x <= 1)              && (y >= 8 && y <= 14)) ||
                (b && (x >= 6)              && (y >= 1 && y <= 7)) ||
                (c && (x >= 6)              && (y >= 8 && y <= 14));
        end
    endfunction

    assign fps_pixel_on = fps_area && digit_pixel(digit_now, char_x, char_y);

    always_ff @(posedge lcd_clk or posedge reset) begin
        if (reset) begin
            lcd_r <= 8'd0;
            lcd_g <= 8'd0;
            lcd_b <= 8'd0;
        end
        else begin
            if (fps_pixel_on) begin
                lcd_r <= 8'hff;
                lcd_g <= 8'hff;
                lcd_b <= 8'hff;
            end
            else if (frame_ready_d1 && img_area_d1 && de_d1) begin
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
