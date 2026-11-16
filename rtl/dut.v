module dut #(
    parameter DW = 16,
    parameter DEPTH = 8,
    parameter AW = $clog2(DEPTH)
    )
    (
        input clk,
        input rstn,
        input wr_en,
        input rd_en,
        input [DW-1:0] din,
        output reg [DW-1:0] dout,
        output full,
        output empty
     );
     
     reg [AW:0] wptr;
     reg [AW:0] rptr;
     
     reg [DW-1:0] mem [0:DEPTH-1];

     wire wrap_around;
     
     always @(posedge clk) begin
        if(!rstn) begin
            wptr <= 0;
            rptr <= 0;
            dout <= 0;
        end
            else begin
                if(wr_en && !full) begin
                    mem[wptr[AW-1:0]] <= din;
                    wptr <= wptr + 1;
                end
                
                if(rd_en && !empty) begin
                    dout <= mem[rptr[AW-1:0]];
                    rptr <= rptr + 1;
                end
            end
     end


    assign wrap_around = wptr[AW] ^ rptr[AW];
     assign full = wrap_around & (wptr[AW-1:0] == rptr[AW-1:0]);
     assign empty = wptr == rptr;
endmodule