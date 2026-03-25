module frame_capture_pingpong (
    input  logic        clk_counter,
    input  logic        rst_n,

    input  logic        read_enable,
    input  logic [3:0]  vout,

    output logic        mem_w_en,
    output logic [13:0] mem_w_addr,
    output logic [7:0]  mem_w_data,

    output logic        busy,
    output logic        frame_start,
    output logic        frame_done
);

    localparam int LINE_BITS   = 1024;
    localparam int LINE_CYCLES = 256;

    logic [LINE_BITS-1:0] line_buf0;
    logic [LINE_BITS-1:0] line_buf1;

    logic capture_sel;
    logic store_sel;

    logic buf0_full, buf1_full;

    logic read_enable_d;
    logic capture_active;

    logic [7:0] sample_cnt;

    logic       store_active;
    logic [6:0] store_byte_cnt;

    logic [6:0] buf0_line_idx;
    logic [6:0] buf1_line_idx;

    logic [6:0] capture_line_idx;
    logic [7:0] stored_line_count;

    logic [3:0] vout_sampled;
    logic       sample_pending;

    always_ff @(negedge clk_counter or negedge rst_n) begin
        if (!rst_n) begin
            vout_sampled   <= 4'd0;
            sample_pending <= 1'b0;
        end
        else begin
            if (capture_active) begin
                vout_sampled   <= vout;
                sample_pending <= 1'b1;
            end
            else begin
                sample_pending <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_counter or negedge rst_n) begin
        if (!rst_n) begin
            read_enable_d      <= 1'b0;
            capture_active     <= 1'b0;
            sample_cnt         <= 8'd0;

            capture_sel        <= 1'b0;
            store_sel          <= 1'b0;

            buf0_full          <= 1'b0;
            buf1_full          <= 1'b0;
            buf0_line_idx      <= 7'd0;
            buf1_line_idx      <= 7'd0;

            capture_line_idx   <= 7'd0;
            stored_line_count  <= 8'd0;

            store_active       <= 1'b0;
            store_byte_cnt     <= 7'd0;

            mem_w_en           <= 1'b0;
            mem_w_addr         <= 14'd0;
            mem_w_data         <= 8'd0;

            busy               <= 1'b0;
            frame_start        <= 1'b0;
            frame_done         <= 1'b0;

            line_buf0          <= '0;
            line_buf1          <= '0;
        end
        else begin
            read_enable_d <= read_enable;
            mem_w_en      <= 1'b0;
            frame_start   <= 1'b0;
            frame_done    <= 1'b0;

            busy <= capture_active | store_active;

            // 一行开始：按你当前逻辑仍然用 read_enable 下降沿
            if (read_enable_d && !read_enable) begin
                capture_active <= 1'b1;
                sample_cnt     <= 8'd0;

                if (capture_line_idx == 7'd0)
                    frame_start <= 1'b1;
            end

            if (capture_active && sample_pending) begin
                if (capture_sel == 1'b0) begin
                    line_buf0[sample_cnt]       <= vout_sampled[0];
                    line_buf0[256 + sample_cnt] <= vout_sampled[1];
                    line_buf0[512 + sample_cnt] <= vout_sampled[2];
                    line_buf0[768 + sample_cnt] <= vout_sampled[3];
                end
                else begin
                    line_buf1[sample_cnt]       <= vout_sampled[0];
                    line_buf1[256 + sample_cnt] <= vout_sampled[1];
                    line_buf1[512 + sample_cnt] <= vout_sampled[2];
                    line_buf1[768 + sample_cnt] <= vout_sampled[3];
                end

                if (sample_cnt == 8'd255) begin
                    capture_active <= 1'b0;

                    if (capture_sel == 1'b0) begin
                        buf0_full     <= 1'b1;
                        buf0_line_idx <= capture_line_idx;
                    end
                    else begin
                        buf1_full     <= 1'b1;
                        buf1_line_idx <= capture_line_idx;
                    end

                    capture_sel <= ~capture_sel;

                    if (capture_line_idx == 7'd127)
                        capture_line_idx <= 7'd0;
                    else
                        capture_line_idx <= capture_line_idx + 7'd1;
                end
                else begin
                    sample_cnt <= sample_cnt + 8'd1;
                end
            end

            if (!store_active) begin
                if (buf0_full) begin
                    store_active   <= 1'b1;
                    store_sel      <= 1'b0;
                    store_byte_cnt <= 7'd0;
                end
                else if (buf1_full) begin
                    store_active   <= 1'b1;
                    store_sel      <= 1'b1;
                    store_byte_cnt <= 7'd0;
                end
            end

            if (store_active) begin
                mem_w_en <= 1'b1;

                if (store_sel == 1'b0) begin
                    mem_w_addr <= (buf0_line_idx << 7) + store_byte_cnt;
                    mem_w_data <= line_buf0[store_byte_cnt*8 +: 8];
                end
                else begin
                    mem_w_addr <= (buf1_line_idx << 7) + store_byte_cnt;
                    mem_w_data <= line_buf1[store_byte_cnt*8 +: 8];
                end

                if (store_byte_cnt == 7'd127) begin
                    store_active <= 1'b0;

                    if (store_sel == 1'b0)
                        buf0_full <= 1'b0;
                    else
                        buf1_full <= 1'b0;

                    if (stored_line_count == 8'd127) begin
                        stored_line_count <= 8'd0;
                        frame_done        <= 1'b1;
                    end
                    else begin
                        stored_line_count <= stored_line_count + 8'd1;
                    end
                end
                else begin
                    store_byte_cnt <= store_byte_cnt + 7'd1;
                end
            end
        end
    end

endmodule