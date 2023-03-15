`include "define.v"
module polar_decoder (
    clk,
    rst_n,
    module_en,
    proc_done,
    raddr,
    rdata,
    waddr,
    wdata
);
// IO description
    input  wire         clk;
    input  wire         rst_n;
    input  wire         module_en;
    input  wire [191:0] rdata;
    output wire [ 10:0] raddr;
    output wire [  5:0] waddr;
    output wire [139:0] wdata;
    output wire         proc_done;


reg  [2:0]  stt_c;
reg  [2:0]  stt_n;



reg  [6:0]  num_p;
reg  [9:0]  N;
reg  [7:0]  K;

reg         dec_begin;
reg         addr_ctr;
reg  [4:0]  dec_ctr;
reg         reg_ctr;
reg         read_end;
reg  [10:0] addr_r ; 

reg [4:0] stage, total_stage;
reg       next_stage; 
reg       skip, skip_next;
// reg       stage_n;
reg [139:0] u;


reg stage_n;

reg [4:0] addr_end;

reg       sel;
reg       proc_done_r;
reg [7:0] u_ctr;
reg [6:0] packet;
reg [1:0] ctr;

//reg [4:0] addr_ctr;


assign waddr = num_p;
assign wdata = u;
assign raddr = addr_r;
assign proc_done = proc_done_r;
// always@(*)begin
//     if (end_p) 
// end




reg [1:0] N_type;

reg [3:0] stage_c; 
reg       end_p;

        


//------------------------- reliability  --------------------------------
reg         frozen_ready;
reg  [511:0]  reliability;
wire [511:0]  reliability_w;
wire        endlist;

always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        frozen_ready <= 0;
    else begin
        if (endlist)
            frozen_ready <= 0;
        else if ( stt_c == `DATA_FRO|| (stt_c == `INFO && ctr == 3))
            frozen_ready <= 1;
        else
            frozen_ready <= 0;  
    end
end

always @(*) begin
    case(N)
    128: begin
        N_type = 0;
        if (stt_c==`DATA_DEC && read_end==1) begin
            if (stage == 0) addr_end = 3;
            else if (stage == 1) addr_end = 1;
            else addr_end = 0;
        end 
        else addr_end = 0;
    end
    256: begin
        N_type = 1;
        if (stt_c==`DATA_DEC && read_end==1) begin
            if (stage == 0) addr_end = 7;
            else if (stage == 1) addr_end = 3;
            else if (stage == 2) addr_end = 1;
            else addr_end = 0;
        end 
        else addr_end = 0;
    end
    512: begin
        N_type = 2;
        if (stt_c==`DATA_DEC && read_end==1) begin
            if (stage == 0) addr_end = 15;
            else if (stage == 1) addr_end = 7;
            else if (stage == 2) addr_end = 3;
            else if (stage == 3) addr_end = 1;
            else addr_end = 0;
        end
        else addr_end = 0;
    end
    default: begin
        N_type = 3;
        addr_end = 0;
    end
    endcase
end




reliability_list R1 (.N(N_type),
                    .K(K),
                    .clk(clk),
                    .state(frozen_ready),
                    .rst_n(rst_n),
                    .endlist(endlist),
                    .reliability(reliability_w));

always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        reliability <= 0;
    else begin
        if (endlist)
            reliability <= reliability_w;
        else 
            reliability <= reliability;  
    end
end

//-----------------------state machine------------------------------
always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        stt_c <= `IDLE;
    else
        stt_c <= stt_n;
end

always@(*)begin //check
    case(stt_c)
        `IDLE: begin
            stt_n = (module_en || !proc_done) ? `INFO : `IDLE;
        end
        `INFO:begin
            stt_n = ( ctr == 3) ? `DATA_FRO : `INFO;
        end
        `DATA_FRO: begin
            stt_n = (endlist) ? `DATA_DEC : `DATA_FRO; 
        end
        `DATA_DEC: begin
            stt_n = ((u_ctr == K) && (num_p == (packet - 1))) ? `DONE : ((end_p) ? `INFO : `DATA_DEC);
        end
        `DONE:begin
            stt_n = `IDLE;
        end
        default: stt_n = stt_c; 
    endcase
end



always@(posedge clk or negedge rst_n)begin  //// ctr
    if(!rst_n )begin
        ctr <= 0;
    end
    else begin
        if(stt_c == `INFO)begin
            ctr <= ctr + 1;
        end
        else if(stt_c == `INFO && !dec_begin)begin
            ctr <= 3;
        end
        else if(stt_c == `DATA_DEC && end_p)begin
            ctr <= 1;
        end
        else begin
            ctr <= ctr;
        end
    end
end

//-----------------------------stage_n----------------------------
    always@(*) begin
    if (stt_c==`DATA_DEC && read_end==1)
        if (!next_stage)
            stage_n = ((stage_c == addr_end) || skip);
        else 
            stage_n = 1;
    else
        stage_n = 0;
end
//skip

always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        stage <= 0;
    else begin
        if (stt_c==`DATA_DEC && read_end==1)begin
            if (stage_n && next_stage) begin
                stage <= stage - 1;
            end
            else if (stage_n && ((stage == total_stage) || skip)) begin
                stage <= stage;
            end
            else if (stage_n) begin
                stage <= stage + 1;
            end
            else begin 
                stage <= stage;
            end
            end
            else begin
                stage <= 0;
            end
    end
end

//----------------------K N-------------------
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n) begin
        N <= 0;
        K <= 0;
    end
    else if(stt_c==`INFO && ctr == 3)begin
        N <= rdata[9:0];
        K <= rdata[17:10];
    end
    else begin
        N <= N;
        K <= K;
    end
end

//--------------------------------read address-----------------------
always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        addr_r <= 0;
    else begin
        if (stt_c == `IDLE)
            addr_r <= 0;
        else if(stt_c==`INFO && ctr == 1)begin
            addr_r <= ((num_p<<5) + num_p+'d1);
        end
        else if (stt_c==`INFO && ctr == 2)
            addr_r <= ((num_p<<5) + num_p+'d1);
        else if (stt_c==`INFO && ctr == 3)
            addr_r <= addr_r+'d1;
        else if(stt_c==`DATA_DEC && (dec_ctr <(N>>5)-1))begin
            case({N_type, addr_ctr})
            3'b000:
                addr_r <= addr_r +'d4;
            3'b001:
                addr_r <= addr_r -'d3;
            3'b010:
                addr_r <= addr_r +'d8;
            3'b011:
                addr_r <= addr_r -'d7;
            3'b100:
                addr_r <= addr_r +'d16;
            3'b101:
                addr_r <= addr_r -'d15;
            3'b110:
                addr_r <= 0;
            3'b111:
                addr_r <= 0;
            default:
                addr_r <= 0;
            endcase
        end
        else if(stt_c == `DONE)begin
                addr_r <= 0;
        end
        else begin
            addr_r <= addr_r;
        end
    end
end
//--------------------address ctr------------------------
always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        addr_ctr <= 0;
    else begin
        if (stt_c == `INFO && &ctr == 1)
            addr_ctr <= 0;
        else if(stt_c==`DATA_DEC)
            addr_ctr <= addr_ctr+1;
        else
            addr_ctr <= addr_ctr;
    end
end

reg reliable, reliable_n;
reg       stage0;
reg [1:0] stage1;
reg [2:0] stage2;
reg [3:0] stage3;
reg [4:0] stage4;
reg [5:0] stage5;
reg [6:0] stage6;
reg [7:0] stage7;
reg [8:0] stage8;


    
//---------------------proc_done--------------------------
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)
        proc_done_r <= 0;
    else begin
        if (stt_c == `DATA_DEC)
            proc_done_r <= ((u_ctr == K) && (num_p == (packet - 1)));
        else
            proc_done_r <= 0;
    end
end


always@(*) begin
    if (stt_c==`DATA_DEC && read_end==1) begin
        if (stage==0)begin
            sel = stage0;
        end
        else if (stage==1)begin
            sel = stage1[0];
        end
        else if (stage==2)begin
            sel = stage2[0];
        end
        else if (stage==3)begin
            sel = stage3[0];
        end
        else if (stage==4)begin
            sel = stage4[0];
        end
        else if (stage==5)begin
            sel = stage5[0];
        end
        else if (stage==6)begin
            sel = stage6[0];
        end
        else if (stage==7)begin
            sel = stage7[0];
        end
        else if (stage==8)begin
            sel = stage8[0];
        end
        else begin
            sel = 0;
        end
    end
    else
        sel = 0;
end


reg get_frozen, get_frozen_next;
// always @(*) begin
//     skip = !get_frozen;
// end


//------------------------decoder---------------------------------
always@(*) begin
        if (stt_c==`DATA_DEC && read_end) begin
            get_frozen = reliable;
            get_frozen_next = reliable_n;
        end
        else begin
            get_frozen = 0;
            get_frozen_next = 0;
        end
        skip = !get_frozen;
        skip_next = !get_frozen_next;
end
  
always@(*) begin
        if (stt_c==`DATA_DEC && read_end)
            case(N)
             128: begin
                if (stage == 0) begin
                    reliable  = | reliability[(stage0 *64) +: 64];
                end
                else if (stage == 1) begin
                    reliable = | reliability[(stage1 *32) +: 32];
                end
                else if (stage == 2) begin
                    reliable = | reliability[(stage2 *16) +: 16];
                end
                else if (stage == 3) begin
                    reliable = | reliability[(stage3 *8) +: 8];
                end
                else if (stage == 4) begin
                    reliable = | reliability[(stage4 *4) +: 4];
                end
                else if (stage == 5) begin
                    reliable = | reliability[(stage5 *2) +: 2];
                end
                else if (stage == 6) begin
                    reliable = | reliability[stage6];
                end
                else begin
                    reliable = 1;
                end
            end
            256: begin
                if (stage == 0) begin
                    reliable = | reliability[(stage0 *128) +: 128];
                end
                else if (stage == 1) begin
                    reliable = | reliability[(stage1 *64) +: 64];
                end
                else if (stage == 2) begin
                    reliable = | reliability[(stage2 *32) +: 32];
                end
                else if (stage == 3) begin
                    reliable = | reliability[(stage3 *16) +: 16];
                end
                else if (stage == 4) begin
                    reliable = | reliability[(stage4 *8) +: 8];
                end
                else if (stage == 5) begin
                    reliable = | reliability[(stage5 *4) +: 4];
                end
                else if (stage == 6) begin
                    reliable = | reliability[(stage6 *2) +: 2];
                end
                else if (stage == 7) begin
                    reliable = | reliability[(stage7) +: 1];
                end
                else begin
                    reliable = 0;
                end
            end
            512: begin
                if (stage == 0) begin
                    reliable = | reliability[(stage0 *256) +: 256];
                end
                else if (stage == 1) begin
                    reliable = | reliability[(stage1 *128) +: 128];
                end
                else if (stage == 2) begin
                    reliable = | reliability[(stage2 *64) +: 64];
                end
                else if (stage == 3) begin
                    reliable = | reliability[(stage3 *32) +: 32];
                end
                else if (stage == 4) begin
                    reliable = | reliability[(stage4 *16) +: 16];
                end
                else if (stage == 5) begin
                    reliable = | reliability[(stage5 *8) +: 8];
                end
                else if (stage == 6) begin
                    reliable = | reliability[(stage6 *4) +: 4];
                end
                else if (stage == 7) begin
                    reliable = | reliability[(stage7 *2) +: 2];
                end
                else if (stage == 8) begin
                    reliable = | reliability[(stage8) +: 1];
                end
                else begin
                    reliable = 0;
                end
            end
            default: 
            begin
                reliable = 0;
            end
            endcase  
    else begin
        reliable = 0;
    end
end

 
always@(*) begin
    if (stt_c==`DATA_DEC && read_end)
        case(N)
            128: begin
            if (stage == 0) begin
                reliable_n = 1;
            end
            else if (stage == 1) begin
                reliable_n = | reliability[(stage1 *32) +: 32];
            end
            else if (stage == 2) begin
                reliable_n = | reliability[(stage1 *32) +: 32];
            end
            else if (stage == 3) begin
                reliable_n = | reliability[(stage2 *16) +: 16];
            end
            else if (stage == 4) begin
                reliable_n = | reliability[(stage3 *8) +: 8];
            end
            else if (stage == 5) begin
                reliable_n = | reliability[(stage4 *4) +: 4];
            end
            else if (stage == 6) begin
                reliable_n = | reliability[(stage5 *2) +: 2];
            end
            else begin
                reliable_n = 1;
            end
        end
        256: begin
            if (stage == 0) begin
                reliable_n = 0;
            end
            else if (stage == 1) begin
                reliable_n = | reliability[(stage0 *128) +: 128];
            end
            else if (stage == 2) begin
                reliable_n = | reliability[(stage1 *64) +: 64];
            end
            else if (stage == 3) begin
                reliable_n = | reliability[(stage2 *32) +: 32];
            end
            else if (stage == 4) begin
                reliable_n = | reliability[(stage3 *16) +: 16];
            end
            else if (stage == 5) begin
                reliable_n = | reliability[(stage4 *8) +: 8];
            end
            else if (stage == 6) begin
                reliable_n = | reliability[(stage5 *4) +: 4];
            end
            else if (stage == 7) begin
                reliable_n = | reliability[(stage6 *2) +: 2];
            end
            else begin
                reliable_n = 0;
            end
        end
        512: begin
            if (stage == 0) begin
                reliable_n = 0;
            end
            else if (stage == 1) begin
                reliable_n = | reliability[(stage0 *256) +: 256];
            end
            else if (stage == 2) begin
                reliable_n = | reliability[(stage1 *128) +: 128];
            end
            else if (stage == 3) begin
                reliable_n = | reliability[(stage2 *64) +: 64];
            end
            else if (stage == 4) begin
                reliable_n = | reliability[(stage3 *32) +: 32];
            end
            else if (stage == 5) begin
                reliable_n = | reliability[(stage4 *16) +: 16];
            end
            else if (stage == 6) begin
                reliable_n = | reliability[(stage5 *8) +: 8];
            end
            else if (stage == 7) begin
                reliable_n = | reliability[(stage6 *4) +: 4];
            end
            else if (stage == 8) begin
                reliable_n = | reliability[(stage7 *2) +: 2];
            end
            else begin
                reliable_n = 0;
            end
        end
        default: 
        begin
            reliable_n = 0;
        end
        endcase
    else begin
        reliable_n = 0;
    end  
end

//stage


//--------------------------------total_stage---------------------------
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        total_stage <= 0;
    end
    else begin
        if (N==128) total_stage <= 6;
        else if (N==256)  total_stage <= 7;
        else if (N==512)  total_stage <= 8;
        else  total_stage <= 0;
    end
end
//------------------------------next_stage------------------------------
always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        next_stage <= 0;
    else begin
        if (stt_c == `DATA_DEC && read_end)
        case (stage)
            0: begin 
                next_stage <= (!next_stage)? (skip && stage0):0;
            end
            1: begin 
                next_stage <= (!next_stage)? (skip && stage1[0]):0;
            end
            2: begin 
                next_stage <= (!next_stage)? (skip && stage2[0]):((!skip_next) && (stage1[0]))? 0 : 1;
            end
            3: begin 
                next_stage <= (!next_stage)? (skip && stage3[0]):((!skip_next) && (stage2[0]))? 0 : 1;
            end
            4: begin 
                next_stage <= (!next_stage)? (skip && stage4[0]):((!skip_next) && (stage3[0]))? 0 : 1;
            end
            5: begin 
                next_stage <= (!next_stage)? (skip && stage5[0]):((!skip_next) && (stage4[0]))? 0 : 1;
            end
            6: begin 
                if (N == 128) begin
                    next_stage <= (!next_stage)? (!stage6[0]):((!skip_next) && (stage5[0]))? 0 : 1;
                end 
                else begin
                    next_stage <= (!next_stage)? (skip && stage6[0]):((!skip_next) && (stage5[0]))? 0 : 1;
                end
            end
            7: begin 
                if (N == 256) 
                    next_stage <= (!next_stage)? (!stage7[0]):((!skip_next) && (stage6[0]))? 0 : 1;
                else
                    next_stage <= (!next_stage)? (skip && stage7[0]):((!skip_next) && (stage6[0]))? 0 : 1;
            end
            8: begin 
                next_stage <= (!next_stage)? (!stage8[0]):((!skip_next) && (stage7[0]))? 0 : 1;
            end
            default: next_stage <= 0;
        endcase
        else begin
            next_stage <= 0;
        end
    end
end

wire s1 = next_stage && !stage1[0];
wire s2 = next_stage && !stage2[0];
wire s3 = next_stage && !stage3[0];
wire s4 = next_stage && !stage4[0];
wire s5 = next_stage && !stage5[0];
wire s6 = next_stage && !stage6[0];
wire s7 = next_stage && !stage7[0];
wire s8 = next_stage & !stage8[0];



//s0
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage0 <= 0;
    end else if (stt_c==`DATA_DEC && read_end) begin
        if (stage==0) begin
            if (next_stage && stage0) stage0 <= stage0 + 1;
            else if (next_stage && !stage0) stage0 <= stage0;
            else if ((stage_c == addr_end) || skip) stage0 <= stage0 + 1;
            else stage0 <= stage0;
        end
    end
    else begin
        stage0 <= 0;
    end
end

//s1
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage1 <= 0; 
    end else if (stt_c==`DATA_DEC && read_end)
        if (stage==0) begin
            if (skip && (next_stage && !stage0)) stage1 <= stage1;
            else if (skip && !(next_stage && !stage0)) stage1 <= stage1 + 2;
            else stage1 <= stage1;
        end
        else if (stage==1) begin
            if (next_stage && stage1[0]) stage1 <= stage1 + 1;
            else if (next_stage && !stage1[0]) stage1 <= stage1;
            else if ((stage_c == addr_end) || skip) stage1 <= stage1 + 1;
            else stage1 <= stage1;
        end
        else stage1 <= stage1;
    else stage1 <= 0;           
end

//s2
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage2 <= 0; 
    end else if (stt_c==`DATA_DEC && read_end)
        if (stage==0) begin
            if (skip && (next_stage && !stage0)) stage2 <= stage2;
            else if (skip && !(next_stage && !stage0)) stage2 <= stage2 + 4;
            else stage2 <= stage2;
        end
        else if (stage==1) begin
            if (skip && s1) stage2 <= stage2;
            else if (skip && !s1) stage2 <= stage2 + 2;
            else stage2 <= stage2;
        end
        else if (stage==2) begin
            if (next_stage && stage2[0]) stage2 <= stage2 + 1;
            else if (next_stage && !stage2[0]) stage2 <= stage2;
            else if ((stage_c == addr_end) || skip) stage2 <= stage2 + 1;
            else stage2 <= stage2;
        end
        else stage2 <= stage2;
    else stage2 <= 0;           
end

//s3
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage3 <= 0; 
    end else if (stt_c==`DATA_DEC && read_end)
        if (stage==0) begin
            if (skip && (next_stage && !stage0)) stage3 <= stage3;
            else if (skip && !(next_stage && !stage0)) stage3 <= stage3 + 8;
            else stage3 <= stage3;
        end
        else if (stage==1) begin
            if (skip && s1) stage3 <= stage3;
            else if (skip && !s1) stage3 <= stage3 + 4;
            else stage3 <= stage3;
        end
        else if (stage==2) begin
            if (skip && s2) stage3 <= stage3;
            else if (skip && !s2) stage3 <= stage3 + 2;
            else stage3 <= stage3;
        end else if (stage==3) begin
            if (next_stage && stage3[0]) stage3 <= stage3 + 1;
            else if (next_stage && !stage3[0]) stage3 <= stage3;
            else if ((stage_c == addr_end) || skip) stage3 <= stage3 + 1;
            else stage3 <= stage3;
        end
        else stage3 <= stage3;
    else stage3 <= 0;           
end

//s4
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage4 <= 0; 
    end else if (stt_c==`DATA_DEC && read_end)
        if (stage==0) begin
            if (skip && (next_stage && !stage0)) stage4 <= stage4;
            else if (skip && !(next_stage && !stage0)) stage4 <= stage4 + 16;
            else stage4 <= stage4;
        end
        else if (stage==1) begin
            if (skip && s1) stage4 <= stage4;
            else if (skip && !s1) stage4 <= stage4 + 8;
            else stage4 <= stage4;
        end
        else if (stage==2) begin
            if (skip && s2) stage4 <= stage4;
            else if (skip && !s2) stage4 <= stage4 + 4;
            else stage4 <= stage4;
        end 
        else if (stage==3) begin
            if (skip && s3) stage4 <= stage4;
            else if (skip && !s3) stage4 <= stage4 + 2;
            else stage4 <= stage4;
        end
        else if (stage==4) begin
            if (next_stage && stage4[0]) stage4 <= stage4 + 1;
            else if (next_stage && !stage4[0]) stage4 <= stage4;
            else if ((stage_c == addr_end) || skip) stage4 <= stage4 + 1;
            else stage4 <= stage4;
        end
        else stage4 <= stage4;
    else stage4 <= 0;           
end


//s5
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage5 <= 0; 
    end else if (stt_c==`DATA_DEC && read_end)
        if (stage==0) begin
            if (skip && (next_stage && !stage0)) stage5 <= stage5;
            else if (skip && !(next_stage && !stage0)) stage5 <= stage5 + 32;
            else stage5 <= stage5;
        end
        else if (stage==1) begin
            if (skip && s1) stage5 <= stage5;
            else if (skip && !s1) stage5 <= stage5 + 16;
            else stage5 <= stage5;
        end
        else if (stage==2) begin
            if (skip && s2) stage5 <= stage5;
            else if (skip && !s2) stage5 <= stage5 + 8;
            else stage5 <= stage5;
        end 
        else if (stage==3) begin
            if (skip && s3) stage5 <= stage5;
            else if (skip && !s3) stage5 <= stage5 + 4;
            else stage5 <= stage5;
        end
        else if (stage==4) begin
            if (skip && s4) stage5 <= stage5;
            else if (skip && !s4) stage5 <= stage5 + 2;
            else stage5 <= stage5;
        end
        else if (stage==5) begin
            if (next_stage && stage5[0]) stage5 <= stage5 + 1;
            else if (next_stage && !stage5[0]) stage5 <= stage5;
            else if ((stage_c == addr_end) || skip) stage5 <= stage5 + 1;
            else stage5 <= stage5;
        end
        else stage5 <= stage5;
    else stage5 <= 0;           
end

//s6
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage6 <= 0; 
    end else if (stt_c==`DATA_DEC && read_end)
        if (stage==0) begin
            if (skip && (next_stage && !stage0)) stage6 <= stage6;
            else if (skip && !(next_stage && !stage0)) stage6 <= stage6 + 64;
            else stage6 <= stage6;
        end
        else if (stage==1) begin
            if (skip && s1) stage6 <= stage6;
            else if (skip && !s1) stage6 <= stage6 + 32;
            else stage6 <= stage6;
        end
        else if (stage==2) begin
            if (skip && s2) stage6 <= stage6;
            else if (skip && !s2) stage6 <= stage6 + 16;
            else stage6 <= stage6;
        end 
        else if (stage==3) begin
            if (skip && s3) stage6 <= stage6;
            else if (skip && !s3) stage6 <= stage6 + 8;
            else stage6 <= stage6;
        end
        else if (stage==4) begin
            if (skip && s4) stage6 <= stage6;
            else if (skip && !s4) stage6 <= stage6 + 4;
            else stage6 <= stage6;
        end
        else if (stage==5) begin
            if (skip && s5) stage6 <= stage6;
            else if (skip && !s5) stage6 <= stage6 + 2;
            else stage6 <= stage6;            
        end
        else if (stage==6) begin
            if (next_stage && stage6[0]) stage6 <= stage6 + 1;
            else if (next_stage && !stage6[0]) stage6 <= stage6;
            else if ((stage_c == addr_end) || skip) stage6 <= stage6 + 1;
            else stage6 <= stage6;
        end
        else stage6 <= stage6;
    else stage6 <= 0;           
end

//s7
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage7 <= 0; 
    end else if (stt_c==`DATA_DEC && read_end)
        if (stage==0) begin
            if (skip && (next_stage && !stage0)) stage7 <= stage7;
            else if (skip && !(next_stage && !stage0)) stage7 <= stage7 + 128;
            else stage7 <= stage7;
        end
        else if (stage==1) begin
            if (skip && s1) stage7 <= stage7;
            else if (skip && !s1) stage7 <= stage7 + 64;
            else stage7 <= stage7;
        end
        else if (stage==2) begin
            if (skip && s2) stage7 <= stage7;
            else if (skip && !s2) stage7 <= stage7 + 32;
            else stage7 <= stage7;
        end 
        else if (stage==3) begin
            if (skip && s3) stage7 <= stage7;
            else if (skip && !s3) stage7 <= stage7 + 16;
            else stage7 <= stage7;
        end
        else if (stage==4) begin
            if (skip && s4) stage7 <= stage7;
            else if (skip && !s4) stage7 <= stage7 + 8;
            else stage7 <= stage7;
        end
        else if (stage==5) begin
            if (skip && s5) stage7 <= stage7;
            else if (skip && !s5) stage7 <= stage7 + 4;
            else stage7 <= stage7;            
        end
        else if (stage==6) begin
            if (skip && s6) stage7 <= stage7;
            else if (skip && !s6) stage7 <= stage7 + 2;
            else stage7 <= stage7;              
        end
        else if (stage==7) begin
            if (next_stage && stage7[0]) stage7 <= stage7 + 1;
            else if (next_stage && !stage7[0]) stage7<= stage7;
            else if ((stage_c == addr_end) || skip) stage7 <= stage7 + 1;
            else stage7 <= stage7;
        end
        else stage7 <= stage7;
    else stage7 <= 0;           
end

//s8
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        stage8 <= 0; 
    end else if (stt_c==`DATA_DEC && read_end)
        if (stage==0) begin
            if (skip && (next_stage && !stage0)) stage8 <= stage8;
            else if (skip && !(next_stage && !stage0)) stage8 <= stage8 + 256;
            else stage8 <= stage8;
        end
        else if (stage==1) begin
            if (skip && s1) stage8 <= stage8;
            else if (skip && !s1) stage8 <= stage8 + 128;
            else stage8 <= stage8;
        end
        else if (stage==2) begin
            if (skip && s2) stage8 <= stage8;
            else if (skip && !s2) stage8 <= stage8 + 64;
            else stage8 <= stage8;
        end 
        else if (stage==3) begin
            if (skip && s3) stage8 <= stage8;
            else if (skip && !s3) stage8 <= stage8 + 32;
            else stage8 <= stage8;
        end
        else if (stage==4) begin
            if (skip && s4) stage8 <= stage8;
            else if (skip && !s4) stage8 <= stage8 + 16;
            else stage8 <= stage8;
        end
        else if (stage==5) begin
            if (skip && s5) stage8 <= stage8;
            else if (skip && !s5) stage8 <= stage8 + 8;
            else stage8 <= stage8;            
        end
        else if (stage==6) begin
            if (skip && s6) stage8 <= stage8;
            else if (skip && !s6) stage8 <= stage8 + 4;
            else stage8 <= stage8;              
        end
        else if (stage==7) begin
            if (skip && s7) stage8 <= stage8;
            else if (skip && !s7) stage8 <= stage8 + 2;
            else stage8 <= stage8;                
        end
        else if (stage==8) begin
            if (next_stage && stage8[0]) stage8 <= stage8 + 1;
            else if (next_stage && !stage8[0]) stage8 <= stage8;
            else if ((stage_c == addr_end) || skip) stage8 <= stage8 + 1;
            else stage8 <= stage8;
        end
        else stage8 <= stage8;
    else stage8 <= 0;           
end

reg     u8 [0:255];
reg     u7 [0:127];
reg     u6 [0:63];
reg     u5 [0:31];
reg     u4 [0:15];
reg     u3 [0:7];
reg     u2 [0:3];
reg     u1 [0:1];
reg     u0 ;


wire [18:0] output_val [0:15];
reg [18:0] abs_a [0:15]; 
reg [18:0] abs_b [0:15];
wire output_sign [0:15];
reg sign_a [0:15], sign_b [0:15];
reg g_u [0:15];
//u0
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        u0 <= 0;
    end 
    else begin
        if (stt_c == `DATA_DEC && read_end) begin
            if (stage==6 && (stage == total_stage)) begin
                if (!skip && !stage6[0]) u0 <= (output_sign[0]);
                else if (!skip) u0 <= u0;
                else u0 <= 0;
            end 
            else if (stage==7 && (stage == total_stage)) begin
                if (!skip && !stage7[0]) u0 <= (output_sign[0]);
                else if (!skip) u0 <= u0;
                else u0 <= 0;
            end
            else if (stage==8 && (stage == total_stage)) begin
                if (!skip && !stage8[0]) u0 <= (output_sign[0]);
                else if (!skip) u0 <= u0;
                else u0 <= 0;
            end
            else begin
                u0 <= 0;
            end
        end
        else begin
            u0 <= 0;
        end
    end

end

integer i;
integer j;

//u1
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        u1[0] <= 0;
        u1[1] <= 0;
    end 
    else begin
        if (stt_c == `DATA_DEC && read_end) begin
            if (stage==6 && (stage == total_stage)) begin
                if (!skip && !stage6[0]) begin
                    u1[0] <= output_sign[0];
                    u1[1] <= u1[1];
                end
                else if (!skip) begin
                    u1[0] <= u1[0] ^ output_sign[0];
                    u1[1] <= output_sign[0];
                end
                else if (skip && !stage6[0]) begin
                    u1[0] <= 0;
                    u1[1] <= u1[1];
                end
                else begin
                    u1[0] <= (u1[0] ^ 0);
                    u1[1] <= 0;
                end
            end 
            else if (stage==7 && (stage == total_stage)) begin
                if (!skip && !stage7[0]) begin
                    u1[0] <= output_sign[0];
                    u1[1] <= u1[1];
                end
                else if (!skip) begin
                    u1[0] <= u1[0] ^ output_sign[0];
                    u1[1] <= output_sign[0];
                end
                else if (skip && !stage7[0]) begin
                    u1[0] <= 0;
                    u1[1] <= u1[1];
                end
                else begin
                    u1[0] <= u1[0] ^ 0;
                    u1[1] <= 0;
                end
            end
            else if (stage==8 && (stage == total_stage)) begin
                if (!skip && !stage8[0]) begin
                    u1[0] <= output_sign[0];
                    u1[1] <= u1[1];
                end
                else if (!skip) begin
                    u1[0] <= u1[0] ^ output_sign[0];
                    u1[1] <= output_sign[0];
                end
                else if (skip && !stage8[0]) begin
                    u1[0] <= 0;
                    u1[1] <= u1[1];
                end
                else begin
                    u1[0] <= u1[0] ^ 0;
                    u1[1] <= 0;
                end
            end
            else begin
                case(N)
                128:begin
                    if (stage==5 && !next_stage) begin
                        if (skip && (!stage5[0])) begin
                            for (i=0;i<2;i=i+1) begin
                                u1[i] <= 0 ;
                            end 
                        end
                        else begin
                            for (i=0;i<2;i=i+1) begin
                                u1[i] <= u1[i];
                            end 
                        end
                    end
                    else begin
                        u1[0] <= 0;
                        u1[1] <= 0;
                    end 

                end
                256:begin
                    if (stage==6 && !next_stage) begin
                        if (skip && (!stage6[0])) begin
                            for (i=0;i<2;i=i+1) begin
                                u1[i] <= 0;
                            end 
                        end
                        else begin
                            for (i=0;i<2;i=i+1) begin
                                u1[i] <= u1[i];
                            end 
                        end
                    end
                    else begin
                        u1[0] <= 0;
                        u1[1] <= 0;
                    end 
                end
                512:begin
                    if (stage==7 && !next_stage) begin
                        if (skip && (!stage7[0])) begin
                            for (i=0;i<2;i=i+1) begin
                                u1[i] <= 0;
                            end 
                        end
                        else begin
                            for (i=0;i<2;i=i+1) begin
                                u1[i] <= u1[i];
                            end 
                        end
                    end
                    else begin
                        u1[0] <= 0;
                        u1[1] <= 0;
                    end 
                end
                default:begin
                    u1[0] <= 0;
                    u1[1] <= 0;
                end
                endcase
            end
        end
        else begin
            u0 <= 0;
            u1[0] <= 0;
            u1[1] <= 0;
        end
    end

end

//u2
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        for (i=0;i<4;i=i+1)begin
            u2[i] <= 0;
        end
    end 
    else begin
        if (stt_c == `DATA_DEC && read_end) begin
            if (stage != total_stage) begin
                case(N)
                128:begin
                    if (stage==0) begin
                        for (i=0;i<4;i=i+1)begin
                            u2[i] <= 0;
                        end
                    end
                    else if (stage==4) begin
                        if (!next_stage)begin
                            for (i=0;i<4;i=i+1) begin
                                if (skip && (!stage4[0])) u2[i] <= 0;
                                else u2[i] <= u2[i];
                            end 
                        end
                        else begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= u2[i];
                            end
                        end
                    end
                    else if (stage==5) begin
                        if (!next_stage)begin
                            for (i=0;i<2;i=i+1) begin
                                if (stage5[0]) u2[i] <= u1[i];
                                else u2[i] <= u2[i];
                            end 
                        end
                        else if (stage5[0]) begin
                            for (i=0;i<2;i=i+1) begin
                                u2[i] <= 0 ^ u1[i];
                                u2[i+2] <= 0;
                            end
                        end
                        else begin
                            for (i=0;i<2;i=i+1) begin
                                u2[i] <= u1[i] ^ u2[i];
                                u2[i+2] <= u1[i];
                            end 
                        end   
                    end
                    else begin
                        for (i=0;i<4;i=i+1) begin
                            u2[i] <= 0;
                        end 
                    end
                end
                256:begin

                    if (stage==5 && !next_stage) begin
                        if (skip && (!stage5[0])) begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= 0;
                            end 
                        end
                        else begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= u2[i];
                            end 
                        end
                    end
                    else if (stage==6 && !next_stage) begin
                        if (stage6[0]) begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= u1[i];
                            end 
                        end
                        else begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= u2[i];
                            end
                        end
                    end 
                    else if (stage==6 && stage6[0]) begin
                        for (i=0;i<2;i=i+1) begin
                            u2[i] <= u1[i] ^ 0;
                            u2[i+2] <= 0;
                        end
                    end
                    else if (stage==6) begin
                        for (i=0;i<2;i=i+1) begin
                            u2[i] <= u2[i] ^ u1[i];
                            u2[i+2] <= u1[i];
                        end 
                    end
                    else begin
                        for (i=0;i<4;i=i+1) begin
                            u2[i] <= u2[i];
                        end 
                    end
                end

                512:begin
                    if (stage==6 && !next_stage) begin
                        if (skip && (!stage6[0])) begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= 0;
                            end 
                        end
                        else begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= u2[i];
                            end 
                        end
                    end
                    else if (stage==7 && !next_stage) begin
                        if (stage7[0]) begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= u1[i];
                            end 
                        end
                        else begin
                            for (i=0;i<4;i=i+1) begin
                                u2[i] <= u2[i];
                            end 
                        end
                    end else if (stage==7 && stage7[0]) begin
                        for (i=0;i<2;i=i+1) begin
                            u2[i] <= u1[i] ^ 0;
                            u2[i+2] <= 0;
                        end
                    end 
                    else if (stage==7) begin
                        for (i=0;i<2;i=i+1) begin
                            u2[i] <= u2[i] ^ u1[i];
                            u2[i+2] <= u1[i];
                        end 
                    end
                    else begin
                        for (i=0;i<4;i=i+1) begin
                            u2[i] <= u2[i];
                        end 
                    end
                end
                default:begin
                    for (i=0;i<4;i=i+1) begin
                        u2[i] <= 0;
                    end 
                end
                endcase
            end
        end
        else begin
            for (i=0;i<4;i=i+1) begin
                u2[i] <= 0;
            end 
        end
    end
end

//u3
// always@(posedge clk or negedge rst_n)begin
//     if(!rst_n) begin
//         for (i=0;i<8;i=i+1)begin
//             u3[i] <= 0;
//         end
//     end 
//     else begin
//         if (stt_c == `DATA_DEC && read_end) begin
//             if (stage != total_stage) begin
//                 case(N)
//                 128:begin
//                     if (stage==3)begin
//                         if (!next_stage)begin
//                             for (i=0;i<8;i=i+1) begin
//                                 u3[i] <= (skip && (!stage3[0])) ? 0 : u3[i];
//                                 // u4[i] <= (stage3[0]) ? u3[i] : u4[i];
//                             end 
//                         end
//                         else begin
//                             for (i=0;i<8;i=i+1) begin
//                                 u3[i] <= u3[i];
//                             end  
//                         end
//                     end
//                     else if (stage==4) begin
//                         if (!next_stage)begin
//                             for (i=0;i<4;i=i+1) begin
//                                 u3[i] <= (stage4[0]) ? u2[i] : u3[i];
//                             end 
//                         end
//                         else if (stage4[0]) begin
//                             for (i=0;i<4;i=i+1) begin
//                                 u3[i] <=  u2[i] ^ 0;
//                                 u3[i+4] <= 0;
//                             end
//                         end
//                         else begin
//                             for (i=0;i<4;i=i+1) begin
//                                 u3[i] <= u2[i] ^ u3[i];
//                                 u3[i+4] <= u2[i];
//                             end 
//                         end  
//                     end

//                     // 3: begin
//                     //     if (!next_stage)begin
//                     //         for (i=0;i<8;i=i+1) begin
//                     //             u3[i] <= (skip && (!stage3[0])) ? 0 : u3[i];
//                     //             u4[i] <= (stage3[0]) ? u3[i] : u4[i];
//                     //         end 
//                     //     end
//                     //     else if (stage3[0]) begin
//                     //         for (i=0;i<8;i=i+1) begin
//                     //             u4[i] <= 0 ^ u3[i];
//                     //             u4[i+8] <= 0;
//                     //         end
//                     //     end
//                     //     else begin
//                     //         for (i=0;i<8;i=i+1) begin
//                     //             u4[i] <= u3[i] ^ u4[i];
//                     //             u4[i+8] <= u3[i];
//                     //         end  
//                     //     end
//                     // end
//                     // 4: begin
//                     //     if (!next_stage)begin
//                     //         for (i=0;i<4;i=i+1) begin
//                     //             // u2[i] <= (skip && (!stage4[0])) ? 0 : u2[i];
//                     //             u3[i] <= (stage4[0]) ? u2[i] : u3[i];
//                     //         end 
//                     //     end
//                     //     else if (stage4[0]) begin
//                     //         for (i=0;i<4;i=i+1) begin
//                     //             u3[i] <= 0 ^ u2[i];
//                     //             u3[i+4] <= 0;
//                     //         end
//                     //     end
//                     //     else begin
//                     //         for (i=0;i<4;i=i+1) begin
//                     //             u3[i] <= u2[i] ^ u3[i];
//                     //             u3[i+4] <= u2[i];
//                     //         end 
//                     //     end  
//                     // end



//                     else begin
//                         for (i=0;i<8;i=i+1) begin
//                             u3[i] <= 0;
//                         end 
//                     end
//                 end
//                 256:begin

//                     if (stage==4 && !next_stage) begin
//                         if (skip && (!stage4[0])) begin
//                             for (i=0;i<8;i=i+1) begin
//                                 u3[i] <= 0;
//                             end 
//                         end
//                         else begin
//                             for (i=0;i<8;i=i+1) begin
//                                 u3[i] <= u3[i];
//                             end 
//                         end
//                     end
//                     else if (stage==5 && !next_stage) begin
//                         if (stage5[0]) begin
//                             for (i=0;i<4;i=i+1) begin
//                                 u3[i] <= u2[i];
//                             end 
//                         end
//                         else begin
//                             for (i=0;i<4;i=i+1) begin
//                                 u3[i] <= u3[i];
//                             end
//                         end
//                     end 
//                     else if (stage==5 && stage5[0]) begin
//                         for (i=0;i<4;i=i+1) begin
//                             u3[i] <= u2[i] ^ 0;
//                             u3[i+4] <= 0;
//                         end
//                     end
//                     else if (stage==5) begin
//                         for (i=0;i<4;i=i+1) begin
//                             u3[i] <= u3[i] ^ u2[i];
//                             u3[i+4] <= u2[i];
//                         end 
//                     end
//                     else begin
//                         for (i=0;i<8;i=i+1) begin
//                             u3[i] <= 0;
//                         end  
//                     end
//                 end

//                 // 4:begin
//                 //         if (!next_stage)begin
//                 //             for (i=0;i<8;i=i+1) begin
//                 //                 u3[i] <= (skip && (!stage4[0])) ? 0 : u3[i];
//                 //                 u4[i] <= (stage4[0]) ? u3[i] : u4[i];
//                 //             end 
//                 //         end 
//                 //         else if (stage4[0]) begin
//                 //             for (i=0;i<8;i=i+1) begin
//                 //                 u4[i] <= u3[i] ^ 0;
//                 //                 u4[i+8] <= 0;
//                 //             end
//                 //         end 
//                 //         else begin
//                 //             for (i=0;i<8;i=i+1) begin
//                 //                 u4[i] <= u4[i] ^ u3[i];
//                 //                 u4[i+8] <= u3[i];
//                 //             end  
//                 //         end 
//                 //     end
//                     // 5:begin
//                     //     if (!next_stage)begin
//                     //         for (i=0;i<4;i=i+1) begin
//                     //             // u2[i] <= (skip && (!stage5[0])) ? 0 : u2[i];
//                     //             u3[i] <= (stage5[0]) ? u2[i] : u3[i];
//                     //         end 
//                     //     end
//                     //     else if (stage5[0]) begin
//                     //         for (i=0;i<4;i=i+1) begin
//                     //             u3[i] <= u2[i] ^ 0;
//                     //             u3[i+4] <= 0;
//                     //         end
//                     //     end
//                     //     else begin
//                     //         for (i=0;i<4;i=i+1) begin
//                     //             u3[i] <= u3[i] ^ u2[i];
//                     //             u3[i+4] <= u2[i];
//                     //         end  
//                     //     end 
//                     // end

//                 512:begin
//                     if (stage==5 && !next_stage) begin
//                         if (skip && (!stage5[0])) begin
//                             for (i=0;i<8;i=i+1) begin
//                                 u3[i] <= 0;
//                             end 
//                         end
//                         else begin
//                             for (i=0;i<8;i=i+1) begin
//                                 u3[i] <= u3[i];
//                             end 
//                         end
//                     end
//                     else if (stage==6 && !next_stage) begin
//                         if (stage6[0]) begin
//                             for (i=0;i<4;i=i+1) begin
//                                 u3[i] <= u2[i];
//                             end 
//                         end
//                         else begin
//                             for (i=0;i<4;i=i+1) begin
//                                 u3[i] <= u3[i];
//                             end 
//                         end
//                     end 
//                     else if (stage==6 && stage6[0]) begin
//                         for (i=0;i<4;i=i+1) begin
//                             u3[i] <= u2[i] ^ 0;
//                             u3[i+4] <= 0;
//                         end
//                     end 
//                     else if (stage==6) begin
//                         for (i=0;i<4;i=i+1) begin
//                             u3[i] <= u2[i] ^ u3[i];
//                             u3[i+4] <= u2[i];
//                         end 
//                     end
//                     else begin
//                         for (i=0;i<8;i=i+1) begin
//                             u3[i] <= u3[i];
//                         end 
//                     end
//                 end
//                 // 5:begin
//                 //         if (!next_stage)begin
//                 //             for (i=0;i<8;i=i+1) begin
//                 //                 u3[i] <= (skip && (!stage5[0])) ? 0 : u3[i];
//                 //                 // u4[i] <= (stage5[0]) ? u3[i] : u4[i];
//                 //             end 
//                 //         end
//                 //         // else if (stage5[0])begin 
//                 //         //     for (i=0;i<8;i=i+1) begin
//                 //         //         u4[i] <= u3[i] ^ 0;
//                 //         //         u4[i+8] <= 0;
                            
//                 //         //     end
//                 //         // end
//                 //         // else begin
//                 //         //     for (i=0;i<8;i=i+1) begin
//                 //         //         u4[i] <= u4[i] ^ u3[i];
//                 //         //         u4[i+8] <= u3[i];
//                 //         //     end  
//                 //         // end
//                 //     end
//                 //     6:begin
//                 //         if (!next_stage)begin
//                 //             for (i=0;i<4;i=i+1) begin
//                 //                 // u2[i] <= (skip && (!stage6[0])) ? 0 : u2[i];
//                 //                 u3[i] <= (stage6[0]) ? u2[i] : u3[i];
//                 //             end 
//                 //         end
//                 //         else if (stage6[0]) begin
//                 //             for (i=0;i<4;i=i+1) begin
//                 //                 u3[i] <= u2[i] ^ 0;
//                 //                 u3[i+4] <= 0;
//                 //             end
//                 //         end
//                 //         else begin
//                 //             for (i=0;i<4;i=i+1) begin
//                 //                 u3[i] <= u3[i] ^ u2[i];
//                 //                 u3[i+4] <= u2[i];
//                 //             end  
//                 //         end
//                 //     end


//                 default:begin
//                     for (i=0;i<8;i=i+1) begin
//                         u3[i] <= 0;
//                     end 
//                 end
//                 endcase
//             end
//         end
//         else begin
//             for (i=0;i<8;i=i+1) begin
//                 u3[i] <= 0;
//             end 
//         end
//     end
// end



always@(posedge clk or negedge rst_n)begin
        if(!rst_n) begin
            for (i=0;i<8;i=i+1)begin
                 u3[i] <= 0;
            end
            for (i=0;i<16;i=i+1)begin
                 u4[i] <= 0;
            end
            for (i=0;i<32;i=i+1)begin
                 u5[i] <= 0;
            end
            for (i=0;i<64;i=i+1)begin
                 u6[i] <= 0;
            end
            for (i=0;i<128;i=i+1)begin
                 u7[i] <= 0;
            end
            for (i=0;i<256;i=i+1)begin
                 u8[i] <= 0;
            end
        end 
        else if (stt_c == `DATA_DEC && read_end) begin
            if ((stage != total_stage)) begin
                if (N==128) begin
                    case(stage)
                        0: begin
                            for (i=0;i<8;i=i+1)begin
                                u3[i] <= 0;
                            end
                            for (i=0;i<16;i=i+1)begin
                                u4[i] <= 0;
                            end
                            for (i=0;i<32;i=i+1)begin
                                u5[i] <= 0;
                            end
                            for (i=0;i<64;i=i+1)begin
                                u6[i] <= u6[i];
                            end
                            for (i=0;i<128;i=i+1)begin
                                u7[i] <= 0;
                            end
                            for (i=0;i<256;i=i+1)begin
                                u8[i] <= 0;
                            end      
                        end
                        1: begin
                            if (!next_stage)begin
                                for (i=0;i<32;i=i+1) begin
                                    u5[i] <= (skip && (!stage1[0])) ? 0 : u5[i];
                                    u6[i] <= (stage1[0]) ? u5[i] : u6[i];
                                end    
                            end
                            else if (stage1[0])begin 
                                for (i=0;i<32;i=i+1) begin
                                    u6[i] <= 0 ^ u5[i];
                                    u6[i+32] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<32;i=i+1) begin
                                    u6[i] <= u5[i] ^ u6[i];
                                    u6[i+32] <= u5[i];
                                end   
                            end         
                        end
                        2: begin
                            if (!next_stage)begin
                                for (i=0;i<16;i=i+1) begin
                                    u4[i] <= (skip && (!stage2[0])) ? 0 : u4[i];
                                    u5[i] <= (stage2[0]) ? u4[i] : u5[i];
                                end 
                            end
                            else if (stage2[0]) begin
                                for (i=0;i<16;i=i+1) begin
                                    u5[i] <= 0 ^ u4[i] ;
                                    u5[i+16] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<16;i=i+1) begin
                                    u5[i] <= u4[i] ^ u5[i];
                                    u5[i+16] <= u4[i];
                                end 
                            end 
                        end
                        3: begin
                            if (!next_stage)begin
                                for (i=0;i<8;i=i+1) begin
                                    u3[i] <= (skip && (!stage3[0])) ? 0 : u3[i];
                                    u4[i] <= (stage3[0]) ? u3[i] : u4[i];
                                end 
                            end
                            else if (stage3[0]) begin
                                for (i=0;i<8;i=i+1) begin
                                    u4[i] <= 0 ^ u3[i];
                                    u4[i+8] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<8;i=i+1) begin
                                    u4[i] <= u3[i] ^ u4[i];
                                    u4[i+8] <= u3[i];
                                end  
                            end
                        end
                        4: begin
                            if (!next_stage)begin
                                for (i=0;i<4;i=i+1) begin
                                    u3[i] <= (stage4[0]) ? u2[i] : u3[i];
                                end 
                            end
                            else if (stage4[0]) begin
                                for (i=0;i<4;i=i+1) begin
                                    u3[i] <= 0 ^ u2[i];
                                    u3[i+4] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<4;i=i+1) begin
                                    u3[i] <= u2[i] ^ u3[i];
                                    u3[i+4] <= u2[i];
                                end 
                            end  
                        end
                        5: begin
                            for (i=0;i<8;i=i+1) begin
                                u3[i] <= u3[i];
                            end
                            for (i=0;i<16;i=i+1)begin 
                                u4[i] <= u4[i];
                            end
                            for (i=0;i<32;i=i+1)begin 
                                u5[i] <= u5[i];
                            end
                            for (i=0;i<64;i=i+1) begin
                                u6[i] <= u6[i];
                            end
                            for (i=0;i<128;i=i+1) begin
                                u7[i] <= u7[i];
                            end
                            for (i=0;i<256;i=i+1) begin
                                u8[i] <= u8[i];
                            end
                        end
                        default: begin
                            for (i=0;i<8;i=i+1) begin
                                u3[i] <= 0;
                            end
                            for (i=0;i<16;i=i+1)begin 
                                u4[i] <= 0;
                            end
                            for (i=0;i<32;i=i+1)begin 
                                u5[i] <= 0;
                            end
                            for (i=0;i<64;i=i+1) begin
                                u6[i] <= 0;
                            end
                            for (i=0;i<128;i=i+1) begin
                                u7[i] <= 0;
                            end
                            for (i=0;i<256;i=i+1) begin
                                u8[i] <= 0;
                            end 
                        end
                    endcase
                end 
                else if (N == 256) begin
                    case(stage)
                        0: begin
                            for (i=0;i<8;i=i+1) begin
                                u3[i] <= 0;
                            end
                            for (i=0;i<16;i=i+1)begin 
                                u4[i] <= 0;
                            end
                            for (i=0;i<32;i=i+1)begin 
                                u5[i] <= 0;
                            end
                            for (i=0;i<64;i=i+1) begin
                                u6[i] <= 0;
                            end
                            for (i=0;i<128;i=i+1) begin
                                u7[i] <= u7[i];
                            end
                            for (i=0;i<256;i=i+1) begin
                                u8[i] <= 0;
                            end        
                            end
                        1:begin
                            if (!next_stage)begin
                                for (i=0;i<64;i=i+1) begin
                                    u6[i] <= (skip && (!stage1[0])) ? 0 : u6[i];
                                    u7[i] <= (stage1[0]) ? u6[i] : u7[i];
                                end 
                            end   
                            else if (stage1[0]) begin
                                for (i=0;i<64;i=i+1) begin
                                    u7[i] <= u6[i] ^ 0;
                                    u7[i+64] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<64;i=i+1) begin
                                    u7[i] <= u7[i] ^ u6[i];
                                    u7[i+64] <= u6[i];
                                end 
                            end  
                        end
                        2:begin
                            if (!next_stage)begin
                                for (i=0;i<32;i=i+1) begin
                                    u5[i] <= (skip && (!stage2[0])) ? 0 : u5[i];
                                    u6[i] <= (stage2[0]) ? u5[i] : u6[i];
                                end    
                            end
                            else if (stage2[0]) begin
                                for (i=0;i<32;i=i+1) begin
                                    u6[i] <= u5[i] ^ 0;
                                    u6[i+32] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<32;i=i+1) begin
                                    u6[i] <= u6[i] ^ u5[i];
                                    u6[i+32] <= u5[i];
                                end
                            end   
                        end
                        3:begin
                            if (!next_stage)begin
                                for (i=0;i<16;i=i+1) begin
                                    u4[i] <= (skip && (!stage3[0])) ? 0 : u4[i];
                                    u5[i] <= (stage3[0]) ? u4[i] : u5[i];
                                end 
                            end
                            else if (stage3[0]) begin
                                for (i=0;i<16;i=i+1) begin
                                    u5[i] <= u4[i] ^ 0;
                                    u5[i+16] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<16;i=i+1) begin
                                    u5[i] <= u5[i] ^ u4[i];
                                    u5[i+16] <= u4[i];
                                end 
                            end
                        end
                        4:begin
                            if (!next_stage)begin
                                for (i=0;i<8;i=i+1) begin
                                    u3[i] <= (skip && (!stage4[0])) ? 0 : u3[i];
                                    u4[i] <= (stage4[0]) ? u3[i] : u4[i];
                                end 
                            end 
                            else if (stage4[0]) begin
                                for (i=0;i<8;i=i+1) begin
                                    u4[i] <= u3[i] ^ 0;
                                    u4[i+8] <= 0;
                                end
                            end 
                            else begin
                                for (i=0;i<8;i=i+1) begin
                                    u4[i] <= u4[i] ^ u3[i];
                                    u4[i+8] <= u3[i];
                                end  
                            end 
                        end
                        5:begin
                            if (!next_stage)begin
                                for (i=0;i<4;i=i+1) begin
                                    // u2[i] <= (skip && (!stage5[0])) ? 0 : u2[i];
                                    u3[i] <= (stage5[0]) ? u2[i] : u3[i];
                                end 
                            end
                            else if (stage5[0]) begin
                                for (i=0;i<4;i=i+1) begin
                                    u3[i] <= u2[i] ^ 0;
                                    u3[i+4] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<4;i=i+1) begin
                                    u3[i] <= u3[i] ^ u2[i];
                                    u3[i+4] <= u2[i];
                                end  
                            end 
                        end
                        6:begin
                            for (i=0;i<8;i=i+1) begin
                                u3[i] <= u3[i];
                            end
                            for (i=0;i<16;i=i+1)begin 
                                u4[i] <= u4[i];
                            end
                            for (i=0;i<32;i=i+1)begin 
                                u5[i] <= u5[i];
                            end
                            for (i=0;i<64;i=i+1) begin
                                u6[i] <= u6[i];
                            end
                            for (i=0;i<128;i=i+1) begin
                                u7[i] <= u7[i];
                            end
                            for (i=0;i<256;i=i+1) begin
                                u8[i] <= u8[i];
                            end
                        end
                        default: begin
                            for (i=0;i<8;i=i+1) begin
                                u3[i] <= 0;
                            end
                            for (i=0;i<16;i=i+1)begin 
                                u4[i] <= 0;
                            end
                            for (i=0;i<32;i=i+1)begin 
                                u5[i] <= 0;
                            end
                            for (i=0;i<64;i=i+1) begin
                                u6[i] <= 0;
                            end
                            for (i=0;i<128;i=i+1) begin
                                u7[i] <= 0;
                            end
                            for (i=0;i<256;i=i+1) begin
                                u8[i] <= 0;
                            end 
                        end
                    endcase
                end 
                else begin
                    case(stage)
                        0: begin
                            for (i=0;i<8;i=i+1) begin
                                u3[i] <= 0;
                            end
                            for (i=0;i<16;i=i+1)begin 
                                u4[i] <= 0;
                            end
                            for (i=0;i<32;i=i+1)begin 
                                u5[i] <= 0;
                            end
                            for (i=0;i<64;i=i+1) begin
                                u6[i] <= 0;
                            end
                            for (i=0;i<128;i=i+1) begin
                                u7[i] <= 0;
                            end
                            for (i=0;i<256;i=i+1) begin
                                u8[i] <= u8[i];
                            end  
                        end
                        1:begin
                            if (!next_stage)begin
                                for (i=0;i<128;i=i+1) begin
                                    u7[i] <= (skip && (!stage1[0])) ? 0 : u7[i];
                                    u8[i] <= (stage1[0]) ? u7[i] : u8[i];
                                end    
                            end
                            else if (stage1[0]) begin
                                for (i=0;i<128;i=i+1) begin
                                    u8[i] <= u7[i] ^ 0;
                                    u8[i+128] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<128;i=i+1) begin
                                    u8[i] <= u8[i] ^ u7[i];
                                    u8[i+128] <= u7[i];
                                end   
                            end
                        end
                        2:begin
                            if (!next_stage)begin
                                for (i=0;i<64;i=i+1) begin
                                    u6[i] <= (skip && (!stage2[0])) ? 0 : u6[i];
                                    u7[i] <= (stage2[0]) ? u6[i] : u7[i];
                                end    
                            end
                            else if (stage2[0]) begin
                                for (i=0;i<64;i=i+1) begin
                                    u7[i] <= u6[i] ^ 0;
                                    u7[i+64] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<64;i=i+1) begin
                                    u7[i] <= u7[i] ^ u6[i];
                                    u7[i+64] <= u6[i];
                                end 
                            end  
                        end
                        3:begin
                            if (!next_stage)begin
                                for (i=0;i<32;i=i+1) begin
                                    u5[i] <= (skip && (!stage3[0])) ? 0 : u5[i];
                                    u6[i] <= (stage3[0]) ? u5[i] : u6[i];
                                end    
                            end
                            else if (stage3[0]) begin
                                for (i=0;i<32;i=i+1) begin
                                    u6[i] <= u5[i] ^ 0;
                                    u6[i+32] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<32;i=i+1) begin
                                    u6[i] <= u6[i] ^ u5[i];
                                    u6[i+32] <= u5[i];
                                end  
                            end 
                        end
                        4:begin
                            if (!next_stage)begin
                                for (i=0;i<16;i=i+1) begin
                                    u4[i] <= (skip && (!stage4[0])) ? 0 : u4[i];
                                    u5[i] <= (stage4[0]) ? u4[i] : u5[i];
                                end 
                            end
                            else if (stage4[0]) begin
                                for (i=0;i<16;i=i+1) begin
                                    u5[i] <= u4[i] ^ 0;
                                    u5[i+16] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<16;i=i+1) begin
                                    u5[i] <= u5[i] ^ u4[i];
                                    u5[i+16] <= u4[i];
                                end 
                            end
                        end
                        5:begin
                            if (!next_stage)begin
                                for (i=0;i<8;i=i+1) begin
                                    u3[i] <= (skip && (!stage5[0])) ? 0 : u3[i];
                                    u4[i] <= (stage5[0]) ? u3[i] : u4[i];
                                end 
                            end
                            else if (stage5[0])begin 
                                for (i=0;i<8;i=i+1) begin
                                    u4[i] <= u3[i] ^ 0;
                                    u4[i+8] <= 0;
                                
                                end
                            end
                            else begin
                                for (i=0;i<8;i=i+1) begin
                                    u4[i] <= u4[i] ^ u3[i];
                                    u4[i+8] <= u3[i];
                                end  
                            end
                        end
                        6:begin
                            if (!next_stage)begin
                                for (i=0;i<4;i=i+1) begin
                                    // u2[i] <= (skip && (!stage6[0])) ? 0 : u2[i];
                                    u3[i] <= (stage6[0]) ? u2[i] : u3[i];
                                end 
                            end
                            else if (stage6[0]) begin
                                for (i=0;i<4;i=i+1) begin
                                    u3[i] <= u2[i] ^ 0;
                                    u3[i+4] <= 0;
                                end
                            end
                            else begin
                                for (i=0;i<4;i=i+1) begin
                                    u3[i] <= u3[i] ^ u2[i];
                                    u3[i+4] <= u2[i];
                                end  
                            end
                        end
                        7:begin
                            for (i=0;i<8;i=i+1) begin
                                u3[i] <= u3[i];
                            end
                            for (i=0;i<16;i=i+1)begin 
                                u4[i] <= u4[i];
                            end
                            for (i=0;i<32;i=i+1)begin 
                                u5[i] <= u5[i];
                            end
                            for (i=0;i<64;i=i+1) begin
                                u6[i] <= u6[i];
                            end
                            for (i=0;i<128;i=i+1) begin
                                u7[i] <= u7[i];
                            end
                            for (i=0;i<256;i=i+1) begin
                                u8[i] <= u8[i];
                            end
                        end
                        default: begin
                            for (i=0;i<8;i=i+1) begin
                                u3[i] <= 0;
                            end
                            for (i=0;i<16;i=i+1)begin 
                                u4[i] <= 0;
                            end
                            for (i=0;i<32;i=i+1)begin 
                                u5[i] <= 0;
                            end
                            for (i=0;i<64;i=i+1) begin
                                u6[i] <= 0;
                            end
                            for (i=0;i<128;i=i+1) begin
                                u7[i] <= 0;
                            end
                            for (i=0;i<256;i=i+1) begin
                                u8[i] <= 0;
                            end
                        end
                endcase
                end
            end
        end else begin
            for (i=0;i<8;i=i+1) begin
                u3[i] <= 0;
            end
            for (i=0;i<16;i=i+1)begin 
                u4[i] <= 0;
            end
            for (i=0;i<32;i=i+1)begin 
                u5[i] <= 0;
            end
            for (i=0;i<64;i=i+1) begin
                u6[i] <= 0;
            end
            for (i=0;i<128;i=i+1) begin
                u7[i] <= 0;
            end
            for (i=0;i<256;i=i+1) begin
                u8[i] <= 0;
            end
        end
    end
///////////////////////////////////////////here 2/////////////////////////////////////////////////////////////////////////
    

//-----------------------------------generate----------------------------------
    
    //g_u
always@(*) begin
    if ((stt_c==`DATA_DEC) && (read_end==1) && (N == 128))
        case(stage)
            0: begin
                if (!stage0)
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u6[(stage_c *16) + i];
                    end
            end
            1: begin
                if (!stage1[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u5[(stage_c *16) + i];
                    end
            end
            2: begin
                if (!stage2[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u4[i];
                    end
            end
            3: begin
                if (!stage3[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<8;i=i+1) begin
                        g_u[i] = u3[i];
                    end
                    for (i=8;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            4: begin
                if (!stage4[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<4;i=i+1) begin
                        g_u[i] = u2[i];
                    end
                    for (i=4;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            5: begin
                if (!stage5[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<2;i=i+1) begin
                        g_u[i] = u1[i];
                    end
                    for (i=2;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            6: begin
                if (!stage6[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u0;
                    end
            end
            default: begin
                for (i=0;i<16;i=i+1) begin
                    g_u[i] = 0;
                end
            end
        endcase
    else if ((stt_c==`DATA_DEC) && (read_end==1) && (N == 256))
        case(stage)
            0: begin
                if (!stage0)
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u7[(stage_c *16) + i];
                    end
            end
            1: begin
                if (!stage1[0])
                    for (i=0;i<16;i=i+1) begin
                    g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u6[(stage_c *16) + i];
                    end
            end
            2: begin
                if (!stage2[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u5[(stage_c *16) + i];
                    end
            end
            3: begin
                if (!stage3[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u4[i];
                    end
            end
            4: begin
                if (!stage4[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<8;i=i+1) begin
                        g_u[i] = u3[i];
                    end
                    for (i=8;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            5: begin
                if (!stage5[0])
                    for (i=0;i<16;i=i+1) begin
                    g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<4;i=i+1) begin
                        g_u[i] = u2[i];
                    end
                    for (i=4;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            6: begin
                if (!stage6[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<2;i=i+1) begin
                        g_u[i] = u1[i];
                    end
                    for (i=2;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            7: begin
                if (!stage7[0])
                    for (i=0;i<16;i=i+1) begin
                    g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u0;
                    end
            end
            default: begin
                for (i=0;i<16;i=i+1) begin
                    g_u[i] = 0;
                end
            end
        endcase
    else if ((stt_c==`DATA_DEC) && (read_end==1) && (N == 512))
        case(stage)
            0: begin
                if (!stage0)
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u8[(stage_c *16) + i];
                    end
            end
            1: begin
                if (!stage1[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u7[(stage_c *16) + i];
                    end
            end
            2: begin
                if (!stage2[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u6[(stage_c *16) + i];
                    end
            end
            3: begin
                if (!stage3[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u5[(stage_c *16) + i];
                    end
            end
            4: begin
                if (!stage4[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u4[i];
                    end
            end
            5: begin
                if (!stage5[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<8;i=i+1) begin
                        g_u[i] = u3[i];
                    end
                    for (i=8;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            6: begin
                if (!stage6[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<4;i=i+1) begin
                        g_u[i] = u2[i];
                    end
                    for (i=4;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            7: begin
                if (!stage7[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else begin
                    for (i=0;i<2;i=i+1) begin
                        g_u[i] = u1[i];
                    end
                    for (i=2;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                end
            end
            8: begin
                if (!stage8[0])
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = 0;
                    end
                else
                    for (i=0;i<16;i=i+1) begin
                        g_u[i] = u0;
                    end
            end
            default: begin
                for (i=0;i<16;i=i+1) begin
                    g_u[i] = 0;
                end
            end
        endcase
    else
        for (i=0;i<16;i=i+1) begin
            g_u[i] = 0;
        end
end





//---------------------abs-------------------------
reg     [11:0]      out_s0 [0:15][0:15];
reg     [12:0]      out_s1 [0:7][0:15];
reg     [13:0]      out_s2 [0:3][0:15];
reg     [14:0]      out_s3 [0:1][0:15];
reg     [15:0]      out_s4 [0:15];
reg     [16:0]      out_s5 [0:7];
reg     [17:0]      out_s6 [0:3];
reg     [18:0]      out_s7 [0:1]; 
//--------------------sign-------------------------
reg                 sign_s0 [0:15][0:15];
reg                 sign_s1 [0:7][0:15];
reg                 sign_s2 [0:3][0:15];
reg                 sign_s3 [0:1][0:15];
reg                 sign_s4 [0:15];
reg                 sign_s5 [0:7];
reg                 sign_s6 [0:3];
reg                 sign_s7 [0:1];

reg [10:0] LLR_A_abs [0:15];
reg [10:0] LLR_B_abs [0:15];
reg     [191:0]     LLR_A [0:15];
reg     [191:0]     LLR_B [0:15];

//-------------------h_out--------------------


always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        u_ctr <= 0;
        u <= 0;
    end
    else begin
        if ((stt_c==`DATA_DEC) && read_end)begin
            if (stage == total_stage) begin
                if (!skip) begin
                    u[u_ctr] <= output_sign[0];
                    u_ctr <= u_ctr + 1;
                end
                else begin
                    u[u_ctr] <= u[u_ctr];
                    u_ctr <= u_ctr;
                end
                // u_ctr <= (skip) ? u_ctr : u_ctr + 1;
            end
            else begin
                u_ctr <= u_ctr;
                u <= u;
            end
        end
        else begin
            u_ctr <= 0;
            u <= 0;
        end
    end
end



always@(*)begin 
    if (stage==0) begin
        for (i=0;i<16;i=i+1) begin
            LLR_A_abs[i] =  (LLR_A[stage_c][((i<<2)+(i<<3))+11]) ? ((~LLR_A[stage_c][((i<<2)+(i<<3))+:11]) + 1) : LLR_A[stage_c][((i<<2)+(i<<3))+:11];
            LLR_B_abs[i] = (LLR_B[stage_c][((i<<2)+(i<<3))+11]) ? ((~LLR_B[stage_c][((i<<2)+(i<<3))+:11]) + 1) : LLR_B[stage_c][((i<<2)+(i<<3))+:11];
        end
    end
    else begin
        for (i=0;i<16;i=i+1) begin
            LLR_A_abs[i] = 0;
            LLR_B_abs[i] = 0;
        end
    end
end

always@(*)begin 
    if (stage==0) begin
        for (i=0;i<16;i=i+1) begin
            sign_a[i] = LLR_A[stage_c][((i<<2)+(i<<3))+11];
            sign_b[i] = LLR_B[stage_c][((i<<2)+(i<<3))+11];
        end
    end
    else if (stage==1) begin
        for (i=0;i<16;i=i+1) begin                    
            sign_a[i] = sign_s0[stage_c][i];
            sign_b[i] = sign_s0[stage_c+(N>>6)][i];
        end
    end
    else if (stage==2) begin
        for (i=0;i<16;i=i+1) begin                                  
            sign_a[i] = sign_s1[stage_c][i];
            sign_b[i] = sign_s1[stage_c+(N>>7)][i]; 
        end
    end
    else if (stage==3) begin
        if (N==128) begin
            for (i=0;i<8;i=i+1) begin
                sign_a[i] = sign_s2[0][i];
                sign_b[i] = sign_s2[0][i+8];
            end
            for (i=8;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end
        end 
        else begin
            for (i=0;i<16;i=i+1) begin
                sign_a[i] = sign_s2[stage_c][i];
                sign_b[i] = sign_s2[stage_c+(N>>8)][i];
            end
        end
    end 
    else if (stage==4) begin
        if (N==128) begin
            for (i=0;i<4;i=i+1) begin
                sign_a[i] = sign_s3[0][i];
                sign_b[i] = sign_s3[0][i+(N>>5)];
            end
            for (i=4;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end
        end 
        else if (N==256) begin
            for (i=0;i<8;i=i+1) begin
                sign_a[i] = sign_s3[0][i];
                sign_b[i] = sign_s3[0][i+(N>>5)];
            end
            for (i=8;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end
        end
        else begin
            for (i=0;i<16;i=i+1) begin
                sign_a[i] = sign_s3[stage_c][i];
                sign_b[i] = sign_s3[stage_c+1][i];
            end
        end
    end 
    else if (stage==5) begin
        if (N==128) begin
            for (i=0;i<2;i=i+1) begin
                sign_a[i] = sign_s4[i];
                sign_b[i] = sign_s4[i+(N>>6)];
            end
            for (i=2;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end
        end
        else if (N==256) begin
            for (i=0;i<4;i=i+1) begin
                sign_a[i] = sign_s4[i];
                sign_b[i] = sign_s4[i+(N>>6)];
            end
            for (i=4;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end   
        end
        else begin
            for (i=0;i<8;i=i+1) begin
                    sign_a[i] = sign_s4[i];
                    sign_b[i] = sign_s4[i+(N>>6)];
            end
            for (i=8;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
        end
        end

    end 
    else if (stage==6) begin
        if(N==128)begin
            for (i=0;i<1;i=i+1) begin
                sign_a[i] = sign_s5[i];
                sign_b[i] = sign_s5[i+(N>>7)];
            end
            for (i=1;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end   
        end
        else if (N==256)begin
            for (i=0;i<2;i=i+1) begin
                sign_a[i] = sign_s5[i];
                sign_b[i] = sign_s5[i+(N>>7)];
            end
            for (i=2;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
                end   
        end
        else begin
            for (i=0;i<4;i=i+1) begin
                sign_a[i] = sign_s5[i];
                sign_b[i] = sign_s5[i+(N>>7)];
            end
            for (i=4;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end   
        end
    end
    else if (stage==7) begin
        if (N==256)begin
            for (i=0;i<1;i=i+1) begin
                sign_a[i] = sign_s6[i];
                sign_b[i] = sign_s6[i+(N>>8)];
            end
            for (i=1;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end   
        end
        else  begin
            for (i=0;i<2;i=i+1) begin
                sign_a[i] = sign_s6[i];
                sign_b[i] = sign_s6[i+(N>>8)];
            end
            for (i=2;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end   
        end
    end
    else if (stage==8) begin
        sign_a[0] = sign_s7[0];
        sign_b[0] = sign_s7[1];
        for (i=1;i<16;i=i+1) begin
            sign_a[i] = 0;
            sign_b[i] = 0;
        end
    end
    else begin
        for (i=0;i<16;i=i+1) begin
            sign_a[i] = 0;
            sign_b[i] = 0;
        end
    end
end

always@(*)begin 
    if (stage==0) begin
        for (i=0;i<16;i=i+1) begin
            abs_a[i] = {8'b0, LLR_A_abs[i]};
            abs_b[i] = {8'b0, LLR_B_abs[i]};
        end
    end
    else if (stage==1) begin
        for (i=0;i<16;i=i+1) begin                                
                abs_a[i] = out_s0[stage_c][i];       
                abs_b[i] = out_s0[stage_c+(N>>6)][i];
        end
    end
    else if (stage==2) begin
        for (i=0;i<16;i=i+1) begin                                  
            abs_a[i] = out_s1[stage_c][i];
            abs_b[i] = out_s1[stage_c+(N>>7)][i];  
        end
    end
    else if (stage==3) begin
        if (N==128) begin
            for (i=0;i<8;i=i+1) begin
                abs_a[i] = out_s2[0][i];
                abs_b[i] = out_s2[0][i+8];
            end
            for (i=8;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end
        end 
        else begin
            for (i=0;i<16;i=i+1) begin
                abs_a[i] = out_s2[stage_c][i];
                abs_b[i] = out_s2[stage_c+(N>>8)][i];
            end
        end
    end 
    else if (stage==4) begin
        if (N==128) begin
            for (i=0;i<4;i=i+1) begin
                abs_a[i] = out_s3[0][i];
                abs_b[i] = out_s3[0][i+(N>>5)];
            end
            for (i=4;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end
        end 
        else if (N==256) begin
            for (i=0;i<8;i=i+1) begin
                abs_a[i] = out_s3[0][i];
                abs_b[i] = out_s3[0][i+(N>>5)];
            end
            for (i=8;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end
        end
        else begin
            for (i=0;i<16;i=i+1) begin
                abs_a[i] = out_s3[stage_c][i];
                abs_b[i] = out_s3[stage_c+1][i];
            end
        end
    end 
    else if (stage==5) begin
        if (N==128) begin
            for (i=0;i<2;i=i+1) begin
                abs_a[i] = out_s4[i];
                abs_b[i] = out_s4[i+(N>>6)];
            end
            for (i=2;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end    
        end
        else if (N==256) begin
            for (i=0;i<4;i=i+1) begin
                abs_a[i] = out_s4[i];
                abs_b[i] = out_s4[i+(N>>6)];
            end
            for (i=4;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end  
        end
        else begin
            for (i=0;i<8;i=i+1) begin
                abs_a[i] = out_s4[i];
                abs_b[i] = out_s4[i+(N>>6)];
            end
            for (i=8;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end
        end

    end 
    else if (stage==6) begin
        if(N==128)begin
            for (i=0;i<1;i=i+1) begin
                abs_a[i] = out_s5[i];
                abs_b[i] = out_s5[i+(N>>7)];
            end
            for (i=1;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end    
        end
        else if (N==256)begin
            for (i=0;i<2;i=i+1) begin
                abs_a[i] = out_s5[i];
                abs_b[i] = out_s5[i+(N>>7)];
            end
            for (i=2;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end  
        end
        else begin
            for (i=0;i<4;i=i+1) begin
                abs_a[i] = out_s5[i];
                abs_b[i] = out_s5[i+(N>>7)];
            end
            for (i=4;i<16;i=i+1) begin
                abs_a[i] = 0;
                abs_b[i] = 0;
            end 
        end
    end
    else if (stage==7) begin
        if (N==256)begin
            for (i=0;i<1;i=i+1) begin
                sign_a[i] = sign_s6[i];
                sign_b[i] = sign_s6[i+(N>>8)];
            end
            for (i=1;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end   
        end
        else  begin
            for (i=0;i<2;i=i+1) begin
                sign_a[i] = sign_s6[i];
                sign_b[i] = sign_s6[i+(N>>8)];
            end
            for (i=2;i<16;i=i+1) begin
                sign_a[i] = 0;
                sign_b[i] = 0;
            end   
        end
    end
    else if (stage==8) begin
        abs_a[0] = out_s7[0];
        abs_b[0] = out_s7[1];
        for (i=1;i<16;i=i+1) begin
            abs_a[i] =  0;
            abs_b[i] =  0;
        end
    end
    else begin
        for (i=0;i<16;i=i+1) begin
            abs_a[i] = 0;
            abs_b[i] = 0;
        end
    end
end




reg [18:0] f_out [0:15];
wire  f_sign [0:15], g_sign [0:15]; //
wire [19:0] f_next [0:15];
wire [19:0] g_next [0:15]; 

    genvar gen_i;
    generate 
        for (gen_i=0;gen_i<16;gen_i=gen_i+1) begin
            assign f_sign[gen_i] = (sign_a[gen_i]) ^ (sign_b[gen_i]);
            assign g_sign[gen_i] = (abs_a[gen_i] > abs_b[gen_i]) ? (sign_a[gen_i] ^ g_u[gen_i]) : sign_b[gen_i];
            
            assign f_next[gen_i] = (abs_a[gen_i] > abs_b[gen_i]) ? abs_b[gen_i] : abs_a[gen_i];
            assign g_next[gen_i] =(!(g_u[gen_i] ^ f_sign[gen_i])) ? (abs_a[gen_i] + abs_b[gen_i]) :
                                                                 ((abs_a[gen_i] > abs_b[gen_i]) ? (abs_a[gen_i] - abs_b[gen_i]) : (abs_b[gen_i] - abs_a[gen_i]));
            assign output_sign[gen_i] = (!sel) ? f_sign[gen_i] : g_sign[gen_i];
            assign output_val[gen_i] = (!sel) ? f_next[gen_i] : g_next[gen_i];

        end 
    endgenerate

//--------------------------------------stage_c-------------------------------------
always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        stage_c <= 0;
    else begin
        if (stage_c == addr_end)
            stage_c <= 0;
        else if (stt_c==`DATA_DEC && read_end==1)
            stage_c <= (skip || next_stage) ? 0: stage_c+1;
        else
            stage_c <= 0;
    end
end





always@(posedge clk or negedge rst_n)begin//s0
    if(!rst_n) begin
        for (i=0;i<16;i=i+1) begin
            for (j=0;j<16;j=j+1)begin
                out_s0[i][j] <= 0;
                out_s1[i][j] <= 0;
                out_s2[i][j] <= 0;
                out_s3[i][j] <= 0;

                sign_s0[i][j] <= 0;
                sign_s1[i][j] <= 0;
                sign_s2[i][j] <= 0;
                sign_s3[i][j] <= 0;
            end
        end

        for (i=0;i<16;i=i+1) begin
            out_s4[i] <= 0;
            sign_s4[i] <= 0;
        end

        for (i=0;i<8;i=i+1) begin
            out_s5[i] <= 0;
            sign_s5[i] <= 0;
        end
    end 
    else begin
        if (!skip && read_end && (!next_stage)) begin
            case(stage)
            0: begin
                for (i=0;i<16;i=i+1) begin
                    out_s0[stage_c][i] <= output_val[i];
                    sign_s0[stage_c][i] <= output_sign[i];
                end
            end
            1: begin
                for (i=0;i<16;i=i+1) begin
                    out_s1[stage_c][i] <= output_val[i];
                    sign_s1[stage_c][i] <= output_sign[i];
                end
            end
            2: begin
                for (i=0;i<16;i=i+1) begin 
                    out_s2[stage_c][i] <= output_val[i];
                    sign_s2[stage_c][i] <= output_sign[i];
                end
            end
            3: begin
                if(N==128)begin
                    for (i=0;i<8;i=i+1) begin 
                        out_s3[0][i] <= output_val[i]; 
                        sign_s3[0][i] <= output_sign[i]; 
                    end
                end
                else begin
                    if(N==256)
                        for (i=0;i<16;i=i+1) begin 
                            out_s3[0][i] <= output_val[i]; 
                            sign_s3[0][i] <= output_sign[i];
                        end
                    else 
                        for (i=0;i<16;i=i+1) begin
                            out_s3[stage_c][i] <= output_val[i];
                            sign_s3[stage_c][i] <= output_sign[i];
                        end
                end
            end
            4: begin
                for (i=0;i<(N>>5);i=i+1) begin 
                    out_s4[i] <= output_val[i]; 
                    sign_s4[i] <= output_sign[i]; 
                end
            end
            5: begin
                for (i=0;i<(N>>6);i=i+1) begin 
                    out_s5[i] <= output_val[i]; 
                    sign_s5[i] <= output_sign[i]; 
                end
            end
            default: begin
                for (i=0;i<16;i=i+1) begin
                    for (j=0;j<16;j=j+1)begin
                        out_s0[i][j] <= out_s0[i][j];
                        out_s1[i][j] <= out_s1[i][j];
                        out_s2[i][j] <= out_s2[i][j];
                        out_s3[i][j] <= out_s3[i][j];

                        sign_s0[i][j] <= sign_s0[i][j];
                        sign_s1[i][j] <= sign_s1[i][j];
                        sign_s2[i][j] <= sign_s2[i][j];
                        sign_s3[i][j] <= sign_s3[i][j];
                    end
                end

                for (i=0;i<16;i=i+1) begin
                    out_s4[i] <= out_s4[i];
                    sign_s4[i] <= sign_s4[i];
                end

                for (i=0;i<8;i=i+1) begin
                    out_s5[i] <= out_s5[i];
                    sign_s5[i] <= sign_s5[i];
                end
            end
            endcase
        end
        else begin
            for (i=0;i<16;i=i+1) begin
                for (j=0;j<16;j=j+1)begin
                    out_s0[i][j] <= out_s0[i][j];
                    out_s1[i][j] <= out_s1[i][j];
                    out_s2[i][j] <= out_s2[i][j];
                    out_s3[i][j] <= out_s3[i][j];

                    sign_s0[i][j] <= sign_s0[i][j];
                    sign_s1[i][j] <= sign_s1[i][j];
                    sign_s2[i][j] <= sign_s2[i][j];
                    sign_s3[i][j] <= sign_s3[i][j];
                end
            end

            for (i=0;i<16;i=i+1) begin
                out_s4[i] <= out_s4[i];
                sign_s4[i] <= sign_s4[i];
            end

            for (i=0;i<8;i=i+1) begin
                out_s5[i] <= out_s5[i];
                sign_s5[i] <= sign_s5[i];
            end
        end
    end 
end

//----------------------------stage 6 ----------------------------
always@(posedge clk or negedge rst_n)begin//s6
    if(!rst_n) begin
        for (i=0;i<4;i=i+1) begin
            out_s6[i] <= 0;
            sign_s6[i] <= 0;
        end
    end 
    else begin
        if(N==256 || N==512)begin
            if(stage==6 && !skip && read_end && (!next_stage))
                for (i=0;i<(N>>7);i=i+1) begin 
                    out_s6[i] <= output_val[i]; 
                    sign_s6[i] <= output_sign[i]; 
                end
            else
                for (i=0;i<4;i=i+1) begin 
                    out_s6[i] <= out_s6[i]; 
                    sign_s6[i] <= sign_s6[i]; 
            end
        end
        else
            for (i=0;i<4;i=i+1) begin 
                out_s6[i] <= 0; 
                sign_s6[i] <= 0; 
            end
    
    end
end 
//----------------------------stage 7------------------------------
always@(posedge clk or negedge rst_n)begin//s6
    if(!rst_n) begin
        for (i=0;i<2;i=i+1) begin
            out_s7[i] <= 0;
            sign_s7[i] <= 0;
        end
    end else begin
        if(N==512)begin
            if(stage==7 && !skip && read_end && (!next_stage))
                for (i=0;i<(N>>8);i=i+1) begin 
                    out_s7[i] <= output_val[i]; 
                    sign_s7[i] <= output_sign[i]; 
                end
            else
                for (i=0;i<16;i=i+1) begin 
                    out_s7[i] <= out_s7[i]; 
                    sign_s7[i] <= sign_s7[i];
            end
        end
        else begin//N=512
            for (i=0;i<2;i=i+1) begin
                out_s7[i] <= 0;
                sign_s7[i] <= 0;
            end
        end 
    end
end 



// -------------------------------read_end----------------------------
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        read_end <= 0;
        dec_begin <= 0;
    end
    else begin
        if(stt_c==`DATA_DEC && reg_ctr==0 && dec_begin==1) begin
            read_end <= 1;
            dec_begin <= dec_begin;
        end
        else if(stt_c==`DATA_DEC) begin
            read_end <= 0;
            dec_begin <= 1;
        end
        else begin
            read_end <= 0;
            dec_begin <= 0;
        end
    end
end


//------------------------packet--------------------------
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)
        packet <= 0;
    else begin
        if(stt_c==`INFO && ctr == 1 && addr_r == 0)
            packet <= rdata;
        else
            packet <= packet;
    end
end

//--------------------------------num_p--------------------------
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)
        num_p <=0;
    else begin
        if (stt_c == `IDLE)
            num_p <= 0;
        else if (end_p)
            num_p <= num_p+1;
        else
            num_p <= num_p;
    end
end

//---------------------------dec_----------------------------------
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        dec_ctr <= 0;
    else begin
        if (stt_c==`INFO && ctr == 2)
            dec_ctr <=0;
        else if(stt_c==`DATA_DEC && dec_ctr=='d31)begin
            dec_ctr <= dec_ctr;
        end
        else if(stt_c==`DATA_DEC && dec_begin==1 && addr_ctr==0)begin
            dec_ctr <= dec_ctr+1;
        end
        else begin
            dec_ctr <= dec_ctr;
        end
    end
end

//--------------------------LLR-----------------------------------
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)begin
        for(i=0;i<'d16;i=i+1)begin
            LLR_A[i]<=0;
            LLR_B[i] <= 0;
        end
    end 
    else begin
        if(stt_c==`DATA_DEC && addr_ctr==1 && reg_ctr==1)begin
            LLR_A[dec_ctr] <= rdata;
        end
        else if(stt_c==`DATA_DEC && addr_ctr==0 && reg_ctr==1)begin
            LLR_B[dec_ctr] <= rdata;
        end
        else begin
            for(i=0;i<'d16;i=i+1)begin
                LLR_A[i]<=LLR_A[i];
                LLR_B[i-1] <= LLR_B[i-1];
            end
        end
    end
end


//--------------------reg_ctr
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)begin
        reg_ctr <=0;
    end
    else begin
        if(stt_c==`DATA_DEC && (dec_ctr==((N>>5)-1)) && addr_ctr==0)begin
            reg_ctr <=0;
        end
        else if(stt_c==`DATA_DEC && (dec_ctr<((N>>5))))begin
            reg_ctr <=1;
        end
        else
            reg_ctr <=0;
    end
end

//----------------------end_p--------------------------
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)
        end_p <= 0;
    else begin
        if ((stt_c == `DATA_DEC) && (stage == total_stage)) begin
            if ((stage==6 && stage6 == 127) || (stage==7 && stage7 == 255) || (stage==8 && stage8 == 511)) begin
                end_p <= 1;
            end
            else begin
                end_p <= 0;
            end
        end
        else begin
            end_p <= 0;
        end
    end
end



    
endmodule