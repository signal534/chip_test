module key #(
    parameter integer DEBOUNCE_CNT = 20'd660_000   // 按你的时钟改
)(
    input  logic clk,
    input  logic rst,
    input  logic key_in,        
    output logic key_pulse      // 单拍脉冲
);

    logic key_sync0, key_sync1;
    logic key_stable, key_stable_d;
    logic [19:0] db_cnt;

    // 先同步
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            key_sync0 <= 1'b0;
            key_sync1 <= 1'b0;
        end else begin
            key_sync0 <= key_in;
            key_sync1 <= key_sync0;
        end
    end

    // 消抖：输入持续保持不同达到一定计数才更新 stable
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            key_stable <= 1'b0;
            db_cnt     <= 20'd0;
        end else begin
            if (key_sync1 == key_stable) begin
                db_cnt <= 20'd0;
            end else begin
                if (db_cnt == DEBOUNCE_CNT) begin
                    key_stable <= key_sync1;
                    db_cnt     <= 20'd0;
                end else begin
                    db_cnt <= db_cnt + 20'd1;
                end
            end
        end
    end

    // 上升沿打一拍
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            key_stable_d <= 1'b0;
        else
            key_stable_d <= key_stable;
    end

    assign key_pulse = key_stable & ~key_stable_d;

endmodule