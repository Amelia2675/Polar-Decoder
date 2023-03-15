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

    parameter IDLE      = 0;
    parameter MEM       = 1;
    parameter JUDGE     = 2;
    parameter PROCESS   = 3;
    parameter OUT       = 4;
    parameter DONE      = 5;

    reg     [2:0] stt_c , stt_n;
    reg     [7:0] K;
    reg     [9:0] N;
    reg     [6:0] packet;
    reg     [10:0] raddr_r;
    reg     [191:0] LLR[0:31];
    reg     [5:0] counter;
    reg     [5:0] dec_addr;
    reg     [139:0] answer; //110110001
    reg     [7:0] answer_addr;
    reg     [8:0] stage_c; //current stage
    reg     [8:0] stage_n; //next stage
    wire    [4:0] word;
    wire    [31:0] LLR_idx;
    wire    [11:0] f_ans;
    wire    [8:0] reliable_idx;
    wire       h_out;


    
    //

    reg     [3:0] cnt_c;
    reg     [3:0] cnt_n;


integer i;

assign raddr = raddr_r;
assign proc_done = (stt_c == DONE )? 1:0;
assign waddr = dec_addr;
assign wdata = /*(stt_c == PROCESS)?*/(stt_c == OUT)? answer : 0;


// PE_F U0(.llr_a(LLR[word][LLR_idx +:12]), .llr_b(LLR[word][LLR_idx+12 +:12]), .f_out(f_ans));
// PE_F U1(.llr_a(LLR[0][11:0]), .llr_b(LLR[0][11:0]), .f_out(f_ans));

// generate
//     genvar word_i, idx_i;
//     for (word_i=0; word_i<32; word_i = word_i+1) begin:f_word
//         for (idx_i=0; idx_i<180; idx_i = idx_i+24) begin:f_idx
//             PE_F U0(.llr_a(LLR[word_i][idx_i +:12]), .llr_b(LLR[word_i][idx_i+12 +:12]), .f_out(f_ans));
//             // assign  PE[word_i][idx_i +:12] = LLR[word_i][idx_i +: 12];
//             // assign  word = word_i;
//         end
//     end
// endgenerate


always@(posedge clk or negedge rst_n)begin  //// counter
    if(!rst_n )begin
        counter <= 0;
    end
    else begin
        if(stt_c == DONE)begin
            counter <= 0;
        end
        else if (stt_c == MEM && raddr != 0)begin
            counter <= counter + 1;
        end
        else begin
            counter <= 0;
        end
    end
end


always@(posedge clk or negedge rst_n)begin  //// decode address
    if(!rst_n)begin
        dec_addr <= 0;
    end
    else begin
        if(stt_c == DONE)begin
            dec_addr <= 0;
        end
        else if (stt_c == OUT)begin //initial packet is 0
            dec_addr <= dec_addr + 1;
        end
        else begin 
            dec_addr <= dec_addr;
        end
    end
end

always@(posedge clk or negedge rst_n)begin  //// addr_r
    if(!rst_n)begin
        raddr_r <= 0;
    end
    else begin
        if(stt_c == DONE)begin
            raddr_r <= 0;
        end
        else if (stt_c == MEM  && counter < 6'd33)begin
            raddr_r <= raddr_r + 1;
        end
        // else if (stt_c == PROCESS  && N == 128)begin
        //     raddr_r <= raddr_r + 22;
        // end
        // else if (stt_c == PROCESS  && N == 256)begin
        //     raddr_r <= raddr_r + 15;
        // end
        else if (stt_c == JUDGE  && N == 128)begin
            raddr_r <= raddr_r + 22;
        end
        else if (stt_c == JUDGE  && N == 256)begin
            raddr_r <= raddr_r + 14;
        end
        else begin
            raddr_r <= raddr_r;
        end
    end
end
/*L
always@(*)begin //// K N
    if(stt_c == MEM)begin
        if (raddr[4:0] == 5'b00001) begin
            N = rdata[9:0];
            K = rdata[17:10];
        end
        else begin
            N = 0;
            K = 0;
        end
    end
end
*/

always@(posedge clk or negedge rst_n)begin  //K N
	if(!rst_n)begin
		K <= 0;
        N <= 0;
    end 
    else begin
        if(stt_c == DONE)begin
            K <= 0;
            N <= 0;
        end
        else if (counter == 1)begin//stt_c == MEM && raddr[4:0] == 5'b00010) begin
            N <= rdata[9:0];
            K <= rdata[17:10];
        end
        else begin
            K <= K;
            N <= N;
        end
    end
end


always @(posedge clk or negedge rst_n) begin ////packet
    if(!rst_n)begin
        packet <= 0;
    end 
    else begin
        if(stt_c == DONE)begin
            packet <= 0;
        end
        else if(stt_c == MEM && raddr == 0)begin
            packet <= rdata[6:0];
        end
        else if(stt_c == OUT)begin
            packet <= packet - 1;
        end
        else begin
            packet <= packet;
        end
    end
end

always @(posedge clk or negedge rst_n) begin ////LLR
    if(!rst_n)begin
        for(i = 0 ; i < 32 ; i = i + 1)begin
            LLR[i] <= 0;
        end
    end
    else begin
        if(stt_c == PROCESS || raddr == 1 || stt_c == DONE)begin
            for(i = 0 ; i < 32 ; i = i + 1)begin
                LLR[i] <= 0;
            end
        end
        else if(stt_n == MEM)begin
            LLR[counter-2] <= rdata;
        end
        else begin
            for(i = 0 ; i < 32 ; i = i + 1)begin
                LLR[i] <= LLR[i];
            end
        end
        
    end
end

//------------------------------------FSM-----------------------------------------------//
    always@(*)begin
        case(stt_c)
            IDLE:
                if(module_en || !proc_done)begin
                    stt_n = MEM;
                end
                else begin
                    stt_n = IDLE;
                end
            MEM: 
                if ((N == 128 && counter == 6'd10)||(N == 256 && counter == 6'd18)||(N == 512 && counter == 6'b100011))begin//raddr[4:0] == 5'b00001 && |raddr[10:5] == 1)begin//((raddr == 0) || (raddr[4:0] == 5'b00001)) begin
                    stt_n = JUDGE;
                end 
                else begin
                    stt_n = MEM;
                end
            JUDGE: stt_n = PROCESS;
            PROCESS: begin
                if(packet != 0 && stage_c == 1)begin
                    stt_n = OUT;
                end
                else begin
                    stt_n = PROCESS;
                end
                // else if (stage_c != 1)begin 
                //     stt_n = PROCESS;
                // end
                // else begin
                //     stt_n = DONE;
                // end                
            end
            
            OUT: begin
                if (packet == 1) begin
                    stt_n = DONE;
                end 
                else begin
                    stt_n = MEM;
                end
            end
            DONE: stt_n = IDLE;
            default:
                stt_n = IDLE;
        endcase
    end
//------------------------------------sequential-------------------------------------------//
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            stt_c <= IDLE; 
        end
        else begin
            stt_c <= stt_n;
        end
    end

    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            //stt_c <= IDLE;
            answer <= 0;
            answer_addr <= 0;
        end
        else begin
            //stt_c <= stt_n;
            if(stt_c == DONE)begin
                //stt_c <= IDLE;
                answer <= 0;
                answer_addr <= 0;
            end
            else if (stt_c == PROCESS && cnt_c == 0 && (reliable_idx > (N-K-1)))begin//stage_c == 1)//stt_c == PROCESS && cnt_c==0)
                // answer <= 140'b1100001;
                answer[answer_addr] <= h_out;
                answer_addr <= answer_addr + 1;
            end
            else if(stt_c == MEM)begin
                answer <= 0;
                answer_addr <= 0;
            end
            else begin
                answer <= answer;
                answer_addr <= answer_addr;
            end

        end
    end



// -----------------------stage_c iteration----------------------------------------------------//

always@(*)begin
    //stage_n = stage_c;

    if (stt_c == PROCESS)begin
        for(i=0 ; i<16;i = i+1)begin
            if(i == cnt_c)begin
                stage_n[i] = ~ stage_c[i];
            end
            else begin
                stage_n[i] = stage_c[i];
            end          
        end
    end
    else begin
         stage_n = stage_c;
    end
end

always@(*) begin
    if(stt_c == MEM || stt_c == JUDGE)begin
        case(N)
            128:begin
                cnt_n = 6;
            end
            256:begin
                cnt_n = 7;
            end
            512:begin
                cnt_n = 8;
            end
            default:
                cnt_n = 6;
        endcase
    end
    else if (stt_c == PROCESS) begin //check
        case(N)
            128:begin
                if (cnt_c == 0) begin
                    if (stage_c[0] == 0) begin
                        cnt_n = 0;
                    end
                    else if (stage_c[1] == 1) begin
                        cnt_n = 1;
                    end
                    else if (stage_c[2] == 1 )begin
                        cnt_n = 2;
                    end
                    else if (stage_c[3] == 1 )begin
                        cnt_n = 3;
                    end
                    else if (stage_c[4] == 1) begin
                        cnt_n = 4;
                    end
                    else if (stage_c[5] == 1 )begin
                        cnt_n = 5;
                    end
                    else begin
                        cnt_n = 6;
                    end
                end
                else begin
                    cnt_n = cnt_c - 1;
                end
            end
            256:begin
                if (cnt_c == 0) begin
                    if (stage_c[0] == 0) begin
                        cnt_n = 0;
                    end
                    else if (stage_c[1] == 1) begin
                        cnt_n = 1;
                    end
                    else if (stage_c[2] == 1 )begin
                        cnt_n = 2;
                    end
                    else if (stage_c[3] == 1 )begin
                        cnt_n = 3;
                    end
                    else if (stage_c[4] == 1) begin
                        cnt_n = 4;
                    end
                    else if (stage_c[5] == 1 )begin
                        cnt_n = 5;
                    end
                    else if (stage_c[6] == 1 )begin
                        cnt_n = 6;
                    end
                    else begin
                        cnt_n = 7;
                    end
                end
                else begin
                    cnt_n = cnt_c - 1;
                end
            end
            512: begin
                if (cnt_c == 0) begin
                    if (stage_c[0] == 0) begin
                        cnt_n = 0;
                    end
                    else if (stage_c[1] == 1) begin
                        cnt_n = 1;
                    end
                    else if (stage_c[2] == 1 )begin
                        cnt_n = 2;
                    end
                    else if (stage_c[3] == 1 )begin
                        cnt_n = 3;
                    end
                    else if (stage_c[4] == 1) begin
                        cnt_n = 4;
                    end
                    else if (stage_c[5] == 1 )begin
                        cnt_n = 5;
                    end
                    else if (stage_c[6] == 1 )begin
                        cnt_n = 6;
                    end
                    else if (stage_c[7] == 1) begin
                        cnt_n = 7;
                    end
                    else begin
                        cnt_n = 8;
                    end
                end
                else begin
                    cnt_n = cnt_c - 1;
                end
            end
            default:
                cnt_n = cnt_c;
        endcase
    end
    else begin
        cnt_n = 0;
        //cnt_c = 0;
        //stage_c = 0;
        //stage_n = 0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stage_c <= 0;
    end 
    else begin
        if (stt_c == DONE) begin
            stage_c <= 0;
        end
        else begin
            stage_c <= stage_n;
        end
    end
end

always@(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt_c <= 0;
    end
    else begin
        if(stt_c == DONE) begin
            cnt_c <= 0;
        end
        else begin
            cnt_c <= cnt_n;
        end
    end
end


// ----------------------------computaiton-------------------------//
reg signed [12:0] out_s0[0:511];   //check bit number
reg signed [12:0] out_s1[0:255];   //check bit number
reg signed [13:0] out_s2[0:127];
reg signed [14:0] out_s3[0:63];
reg signed [15:0] out_s4[0:31];
reg signed [16:0] out_s5[0:15];
reg signed [17:0] out_s6[0:7];
reg signed [18:0] out_s7[0:3];
reg signed [19:0] out_s8[0:1];

wire signed [21:0] f_next[0:255], g_next[0:255];
wire               sign_value[0:255];
wire        [20:0] f_min[0:255];
wire        [20:0] f_min_com[0:255]; //2's complement
reg signed  [21:0] f_llr_a[0:255], f_llr_b[0:255], g_llr_a[0:255], g_llr_b[0:255];
wire        [20:0] abs_a[0:255], abs_b[0:255]; //abs(a), abs(b)
reg                 g_u[0:255];
wire        idx;

reg u [0:511];
reg u0 [0:511];
reg u1 [0:511];
reg u2 [0:511];
reg u3 [0:511];
reg u4 [0:511];
reg u5 [0:511];
reg u6 [0:511];
reg u7 [0:511];
reg u8 [0:511];


//-----------decide output f | g-----------------
always@(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i=0; i<512; i=i+1) begin
            out_s0[i] <= 0;
        end
        
        //stage1 output
        for (i=0; i<256; i=i+1) begin
            out_s1[i] <= 0;
        end

        //stage2 output
        for (i=0; i<128; i=i+1) begin
            out_s2[i] <= 0;
        end

        //stage3 output
        for (i=0; i<64; i=i+1) begin
            out_s3[i] <= 0;
        end

        //stage4 output
        for (i=0; i<32; i=i+1) begin
            out_s4[i] <= 0;
        end

        //stage5 output
        for (i=0; i<16; i=i+1) begin
            out_s5[i] <= 0;
        end

        //stage6 output
        for (i=0; i<8; i=i+1) begin
            out_s6[i] <= 0;
        end

        //stage7 output
        for (i=0; i<4; i=i+1) begin
            out_s7[i] <= 0;
        end

        //stage8 output
        for (i=0; i<2; i=i+1) begin
            out_s8[i] <= 0;
        end
    end 
    else begin
        if (stt_c == DONE) begin
            for (i=0; i<512; i=i+1) begin
                out_s0[i] <= 0;
            end
            
            //stage1 output
            for (i=0; i<256; i=i+1) begin
                out_s1[i] <= 0;
            end

            //stage2 output
            for (i=0; i<128; i=i+1) begin
                out_s2[i] <= 0;
            end

            //stage3 output
            for (i=0; i<64; i=i+1) begin
                out_s3[i] <= 0;
            end

            //stage4 output
            for (i=0; i<32; i=i+1) begin
                out_s4[i] <= 0;
            end

            //stage5 output
            for (i=0; i<16; i=i+1) begin
                out_s5[i] <= 0;
            end

            //stage6 output
            for (i=0; i<8; i=i+1) begin
                out_s6[i] <= 0;
            end

            //stage7 output
            for (i=0; i<4; i=i+1) begin
                out_s7[i] <= 0;
            end

            //stage8 output
            for (i=0; i<2; i=i+1) begin
                out_s8[i] <= 0;
            end
        end
        else if (stt_c == PROCESS) begin
            case (cnt_c)
                8: begin
                    for (i=0;i<256;i=i+1) begin
                        out_s1[i] <= (stage_c[cnt_c])? g_next[i]: f_next[i];
                    end
                end
                7: begin
                    for (i=0;i<128;i=i+1) begin
                        out_s2[i] <= (stage_c[cnt_c])? g_next[i]: f_next[i];
                    end
                end
                6: begin
                    for (i=0;i<64;i=i+1) begin
                        out_s3[i] <= (stage_c[cnt_c])? g_next[i]: f_next[i];
                    end
                end
                5: begin
                    for (i=0;i<32;i=i+1) begin
                        out_s4[i] <= (stage_c[cnt_c])? g_next[i]: f_next[i];
                    end
                end
                4: begin
                    for (i=0;i<16;i=i+1) begin
                        out_s5[i] <= (stage_c[cnt_c])? g_next[i]: f_next[i];
                    end
                end
                3: begin
                    for (i=0;i<8;i=i+1) begin
                        out_s6[i] <= (stage_c[cnt_c])? g_next[i]: f_next[i];
                    end
                end
                2: begin
                    for (i=0;i<4;i=i+1) begin
                        out_s7[i] <= (stage_c[cnt_c])? g_next[i]: f_next[i];
                    end
                end
                1: begin
                    for (i=0;i<2;i=i+1) begin
                        out_s8[i] <= (stage_c[cnt_c])? g_next[i]: f_next[i];
                    end
                end
            endcase
        end
        else if (stt_c==MEM)begin//check
            // if (N[7])
            //     for (i=0;i<128;i=i+1) begin

            //     end
            // else if (N[8]) begin
            //     for (i=0;i<)
            // end
            // else begin

            // end
            // for (i=0;i<256;i=i+1) begin
            //     out_s3[i] <= out_s3[i];//(stage_c[cnt_c])? g_next[i]: f_next[i];
            //     out_s4[i] <= out_s4[i];
            //     out_s5[i] <= out_s5[i];
            //     out_s6[i] <= out_s6[i];
            //     out_s7[i] <= out_s7[i];
            //     out_s8[i] <= out_s8[i];
            // end
            //out_s3 <= out_s3;
            if (N[7] == 1) begin
                for (i=0; i<128; i=i+1) begin
                    if (counter-3 == i[6:4]) begin
                        out_s2[i] <= $signed(LLR[counter-3][(12*i[3:0])+:12]); 
                    end
                    else begin
                        out_s2[i] <= out_s2[i];
                    end
                end
            end
            else if (N[8] == 1) begin
                for (i=0; i<256; i=i+1) begin
                    if (counter-3 == i[7:4]) begin
                        out_s1[i] <= $signed(LLR[counter-3][(12*i[3:0])+:12]);
                    end
                    else begin
                        out_s1[i] <= out_s1[i];
                    end
                end
            end
            else if (N[9] == 1) begin
                for (i=0; i<512; i=i+1) begin
                    if (counter-3 == i[8:4]) begin
                        out_s0[i] <= $signed(LLR[counter-3][(12*i[3:0])+:12]);
                    end
                    else begin
                        out_s0[i] <= out_s0[i];
                    end
                end
            end
        end
        else begin
            for (i=0;i<256;i=i+1) begin
                out_s0[i] <= out_s0[i];
                out_s1[i] <= out_s1[i];
                out_s2[i] <= out_s2[i];
                out_s3[i] <= out_s3[i];//(stage_c[cnt_c])? g_next[i]: f_next[i];
                out_s4[i] <= out_s4[i];
                out_s5[i] <= out_s5[i];
                out_s6[i] <= out_s6[i];
                out_s7[i] <= out_s7[i];
                out_s8[i] <= out_s8[i];
            end
        end
    end
end


//--------------f_value--------------------
always@(*) begin
    for (i=0;i<256;i=i+1) begin
        f_llr_a[i] = 0;
        f_llr_b[i] = 0;
    end

    case(cnt_c)
        8: begin
            for (i=0;i<256;i=i+1) begin
                f_llr_a[i] = out_s0[i];
                f_llr_b[i] = out_s0[i+256];
            end
        end  
        7: begin
            for (i=0;i<128;i=i+1) begin
                f_llr_a[i] = out_s1[i];
                f_llr_b[i] = out_s1[i+128];
            end
        end
        6: begin
            for (i=0;i<64;i=i+1) begin
                f_llr_a[i] = out_s2[i];
                f_llr_b[i] = out_s2[i+64];
            end
        end
        5: begin
            for (i=0;i<32;i=i+1) begin
                f_llr_a[i] = out_s3[i];
                f_llr_b[i] = out_s3[i+(2**cnt_c)];
            end
        end
        4: begin
            for (i=0;i<16;i=i+1) begin
                f_llr_a[i] = out_s4[i];
                f_llr_b[i] = out_s4[i+(2**cnt_c)];
            end
        end
        3: begin
            for (i=0;i<8;i=i+1) begin
                f_llr_a[i] = out_s5[i];
                f_llr_b[i] = out_s5[i+(2**cnt_c)];
            end
        end
        2: begin
            for (i=0;i<4;i=i+1) begin
                f_llr_a[i] = out_s6[i];
                f_llr_b[i] = out_s6[i+(2**cnt_c)];
            end
        end
        1: begin
            for (i=0;i<2;i=i+1) begin
                f_llr_a[i] = out_s7[i];
                f_llr_b[i] = out_s7[i+(2**cnt_c)];
            end
        end   
        0: begin
            for (i=0;i<1;i=i+1) begin
                f_llr_a[i] = out_s8[i];
                f_llr_b[i] = out_s8[i+(2**cnt_c)];
            end
        end  
        default:begin
            for (i=0;i<1;i=i+1) begin
                f_llr_a[i] = 0;
                f_llr_b[i] = 0;
            end
        end
    endcase

end


/*wire signed [11:0] f_next[0:255], g_next[0:255];
wire               sign_value[0:255];
wire        [11:0] f_min[0:255];
// wire        [11:0] f_min_com[0:255]; //2's complement
reg signed  [11:0] f_llr_a[0:255], f_llr_b[0:255], g_a[0:255], g_b[0:255];
// reg         [10:0] f_a_abs[0:255], f_b_abs[0:255]; //abs(a), abs(b)
reg                 g_u[0:255];*/

generate 
    genvar stage_i;
    for (stage_i=0; stage_i<256; stage_i=stage_i+1) begin: gen_f
        
        // abs_a
        assign abs_a[stage_i] =( f_llr_a[stage_i][21])? ~f_llr_a[stage_i][20:0] + 1 : f_llr_a[stage_i][20:0] ;

        //abs_b
        assign abs_b[stage_i] = (f_llr_b[stage_i][21])? ~f_llr_b[stage_i][20:0] + 1 : f_llr_b[stage_i][20:0];
        
        //min
        assign f_min[stage_i] = (abs_a[stage_i][20:0] > abs_b[stage_i][20:0])? abs_b[stage_i][20:0]: abs_a[stage_i][20:0];
        
        assign f_min_com[stage_i] = ~f_min[stage_i] + 1;
        assign f_next[stage_i] = (f_llr_a[stage_i][21] ^ f_llr_b[stage_i][21])? {1'b1, f_min_com[stage_i]}: {1'b0, f_min[stage_i]};
    end
endgenerate



//------------------g_value-------------------------
always@(*) begin
    for (i=0;i<256;i=i+1) begin
        g_llr_a[i] = 0;
        g_llr_b[i] = 0;
        g_u[i] = 0;
        // idx = 0;
    end

    case(cnt_c)
        8: begin
            for (i=0;i<256;i=i+1) begin
                g_llr_a[i] = out_s0[i];
                g_llr_b[i] = out_s0[i+256];
                g_u[i] = u8[i[7:0]];
            end
        end
        7: begin
            for (i=0;i<128;i=i+1) begin
                g_llr_a[i] = out_s1[i];
                g_llr_b[i] = out_s1[i+128];
                // idx = {~stage_c[8], 1'b0, i[6:0]};
                g_u[i] = u7[{~stage_c[8], 1'b0, i[6:0]}];
            end
        end
        6: begin
            for (i=0;i<64;i=i+1) begin
                g_llr_a[i] = out_s2[i];
                g_llr_b[i] = out_s2[i+64];
                // idx = {~stage_c[8:7], 1'b0, i[5:0]};
                g_u[i] = u6[{~stage_c[8:7], 1'b0, i[5:0]}];
            end
        end
        5: begin
            for (i=0;i<32;i=i+1) begin
                g_llr_a[i] = out_s3[i];
                g_llr_b[i] = out_s3[i+32];
                // idx = {~stage_c[8:6], 1'b0, i[5:0]};
                g_u[i] = u5[{~stage_c[8:6], 1'b0, i[4:0]}];
            end
        end
        4: begin
            for (i=0;i<16;i=i+1) begin
                g_llr_a[i] = out_s4[i];
                g_llr_b[i] = out_s4[i+16];
                // idx = {~stage_c[8:5], 1'b0, i[3:0]};
                g_u[i] = u4[{~stage_c[8:5], 1'b0, i[3:0]}];
            end
        end
        3: begin
            for (i=0;i<8;i=i+1) begin
                g_llr_a[i] = out_s5[i];
                g_llr_b[i] = out_s5[i+8];
                // idx = {~stage_c[8:6], 1'b0, i[2:0]};
                g_u[i] = u3[{~stage_c[8:4], 1'b0, i[2:0]}];
            end
        end
        2: begin
            for (i=0;i<4;i=i+1) begin
                g_llr_a[i] = out_s6[i];
                g_llr_b[i] = out_s6[i+4];
                // idx = {~stage_c[8:7], 1'b0, i[1:0]};
                g_u[i] = u2[{~stage_c[8:3], 1'b0, i[1:0]}];
            end
        end
        1: begin
            for (i=0;i<2;i=i+1) begin
                g_llr_a[i] = out_s7[i];
                g_llr_b[i] = out_s7[i+2];
                // idx = {~stage_c[8:2], 1'b0, i[0]};
                g_u[i] = u1[{~stage_c[8:2], 1'b0, i[0]}];
            end
        end   
        0: begin
            for (i=0;i<1;i=i+1) begin
                g_llr_a[i] = out_s8[i];
                g_llr_b[i] = out_s8[i+1];
                // idx = {~stage_c[8:1], 1'b0};
                g_u[i] = u0[{~stage_c[8:1], 1'b0}];
            end
        end  
        default:begin
            for (i=0;i<256;i=i+1) begin
                g_llr_a[i] = 0;
                g_llr_b[i] = 0;
                // idx = {~stage_c[8:1], 1'b0};
                g_u[i] = 0;
            end
        end
    endcase

end

generate 
    genvar stage_j;
    for (stage_j=0; stage_j<256; stage_j= stage_j+1)begin: gen_g
        assign g_next[stage_j] = (g_u[stage_j]) ? $signed(g_llr_b[stage_j] - g_llr_a[stage_j]):$signed(g_llr_b[stage_j] + g_llr_a[stage_j]);
        // $signed
    end
endgenerate

// --------------------------u_value----------------------
always@(*)begin
    //stage1
    for (i=0; i<512;i=i+1)begin
        u0[i] = u[i];
    end

    for (i=0; i<512;i=i+1)begin
        u1[i] = (i[0]) ? u0[i]: u0[i] ^ u0[i+1];
    end

    for (i=0; i<512;i=i+1)begin
        u2[i] = (i[1]) ? u1[i]: u1[i] ^ u1[i+2];
    end

    for (i=0; i<512;i=i+1)begin
        u3[i] = (i[2]) ? u2[i]: u2[i] ^ u2[i+4];
    end

    for (i=0; i<512;i=i+1)begin
        u4[i] = (i[3]) ? u3[i]: u3[i] ^ u3[i+8];
    end

    for (i=0; i<512;i=i+1)begin
        u5[i] = (i[4]) ? u4[i]: u4[i] ^ u4[i+16];
    end

    for (i=0; i<512;i=i+1)begin
        u6[i] = (i[5]) ? u5[i]: u5[i] ^ u5[i+32];
    end

    for (i=0; i<512;i=i+1)begin
        u7[i] = (i[6]) ? u6[i]: u6[i] ^ u6[i+64];
    end

    for (i=0; i<512;i=i+1)begin
        u8[i] = (i[7]) ? u7[i]: u7[i] ^ u7[i+128];
    end
end

// -------------read reliability file & h_out-----------------


reliability_list R1(.N(N[9:8]), .index({~stage_c[8:1], stage_c[0]}),
                                .reliability(reliable_idx));
assign h_out = ((N-K) > reliable_idx)? 0:                   //frozen
                (stage_c[0])? g_next[0][21]: f_next[0][21]; 

always@(posedge clk or negedge rst_n) begin
    if (!rst_n ) begin
        for (i=0 ; i<512 ;i=i+1) begin
            u[i] <= 0;
        end
    end
    else begin
        if(stt_c == DONE) begin
            for (i=0 ; i<512 ;i=i+1) begin
                u[i] <= 0;
            end
        end
        else if (stt_c == PROCESS)begin
            if (cnt_c == 0)begin
                u[{~stage_c[8:1], stage_c[0]}] <= h_out;
            end
            else begin
                for (i=0 ; i<512 ;i=i+1) begin
                    u[i] <= u[i];
                end
            end
        end
        else begin
            for (i=0 ; i<512 ;i=i+1) begin
                u[i] <= u[i];
            end
        end
    end
end

endmodule 