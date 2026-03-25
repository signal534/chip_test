module clk_div_50M_to_8K (
    input wire clk_50M,    
    input wire rst_n,      
    output reg clk_8K      
);

reg [12:0] cnt;  

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
        cnt    <= 13'd0;
        clk_8K <= 1'b0;
    end
    else begin
        if (cnt == 13'd3124) begin  
            cnt    <= 13'd0;
            clk_8K <= ~clk_8K;      
        end
        else begin
            cnt <= cnt + 1'b1;
        end
    end
end

endmodule
