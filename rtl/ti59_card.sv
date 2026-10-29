// SPDX-License-Identifier: GPL-2.0-or-later
// TMC0594 read-side interface. The TI ROM consumes the image through IN CRD;
// no program RAM or calculator registers are patched by the loader.
// Raw banks: 3 header bytes, protection byte, 240 payload bytes, 2 checksums.
module ti59_card (
    input wire clk, reset, frame, ready,
    input wire download, wr,
    input wire [26:0] addr,
    input wire [7:0] dout,
    output wire busy, clear_key,
    output reg present,
    output wire [7:0] data,
    input wire [2:0] cmd,
    output reg [9:0] card_x,
    output wire visible, front, motor,
    output reg error
);
    reg [7:0] image [0:1023];
    reg [7:0] data_q;
    reg [9:0] ptr, bank_base;
    reg [7:0] byte_pos;
    reg reading, done;
    reg [10:0] count;
    reg [7:0] load_pos;
    reg [2:0] banks, remaining;
    reg [3:0] checksum;
    reg bad, downloading, seen;
    localparam [2:0] EMPTY=0, WAITING=1, FEED=2, GAP=3, SEAT=4, PARKED=5, FAILED=6, PREPARE=7;
    reg [2:0] state;
    reg [8:0] timer;
    assign busy = (state >= FEED && state <= SEAT) || state == PREPARE;
    assign motor = state == FEED && card_x > 330;
    // The real ROM takes the requested bank from X, even on auto-insertion.
    // OSD imports press/release CLR before each pass so any bank is accepted,
    // without power cycling, changing the partition, or clearing stored RAM.
    assign clear_key = state == PREPARE && timer < 5;
    assign visible = state == FEED || state == GAP || state == SEAT || state == PARKED || state == FAILED;
    assign front = state == SEAT || state == PARKED || state == FAILED;
    assign data = present && reading && byte_pos < 246 ? data_q : 8'd0;
    always @(posedge clk) begin
        data_q <= image[ptr];
        if (wr && download && !busy && addr < 984) image[addr[9:0]] <= dout;
        downloading <= download;
        if (reset) begin
            count<=0; load_pos<=0; banks<=0; remaining<=0; checksum<=0;
            bad<=0; downloading<=0; seen<=0;
            ptr<=0; bank_base<=0; byte_pos<=0; reading<=0; done<=0; present<=0;
            state<=EMPTY; timer<=0; card_x<=636; error<=0;
        end else begin
            // First write may arrive after ioctl_wait held a previous animation.
            // Validate every address, bank boundary, header and checksum before
            // presenting the card switch. Malformed images never reach RAM.
            if (wr && download && !busy) begin
                seen<=1;
                if (addr == 0 && !seen) begin
                    count<=1; load_pos<=1; banks<=0; checksum<=dout[3:0];
                    bad<=dout[3:0]<2 || dout[3:0]>12;
                end else begin
                    if (addr != {16'd0,count} || count >= 984) bad<=1;
                    if (count < 1024) count<=count+11'd1;
                    if (load_pos == 245) begin load_pos<=0; banks<=banks+3'd1; checksum<=0; end
                    else load_pos<=load_pos+8'd1;
                    case (load_pos)
                        0: begin
                            if (dout[3:0]<2 || dout[3:0]>12) bad<=1;
                            checksum<=dout[3:0];
                        end
                        1: begin
                            if (dout[3:0]>1) bad<=1;
                            checksum<=checksum+dout[3:0];
                        end
                        2: begin
                            if (dout[3:0]!=0 && dout[3:0]!=3 && dout[3:0]!=6 && dout[3:0]!=9) bad<=1;
                            checksum<=checksum+dout[3:0];
                        end
                        3: begin end // Protection is not included in the TI checksum.
                        244,245: if (dout[3:0]!=checksum) bad<=1;
                        default: checksum<=checksum+dout[7:4]+dout[3:0];
                    endcase
                end
            end
            if (downloading && !download && !busy) begin
                seen<=0; present<=0; reading<=0; error<=0; timer<=0;
                if (seen && !bad && load_pos==0 && banks>=1 && banks<=4 && count<=984) begin
                    remaining<=banks; ptr<=0; bank_base<=0; byte_pos<=0;
                    state<=WAITING;
                end else begin state<=FAILED; error<=1; card_x<=420; end
            end
            if (present) case (cmd)
                1: if (!reading) begin reading<=1; ptr<=bank_base; byte_pos<=0; end
                2: if (reading && byte_pos<246) begin ptr<=ptr+10'd1; byte_pos<=byte_pos+8'd1; end
                3: begin
                    present<=0; reading<=0; done<=1;
                    // A header/partition rejection terminates before the payload.
                    if (byte_pos<245) error<=1;
                end
                4: begin error<=1; present<=0; reading<=0; done<=1; end
                default: begin end
            endcase
            if (frame && !(downloading && !download && !busy)) case (state)
                WAITING: if (ready && !download) begin
                    state<=PREPARE; timer<=0;
                end
                PREPARE: if (timer==11) begin
                    state<=FEED; card_x<=636; timer<=0; done<=0; present<=1;
                end else timer<=timer+9'd1;
                FEED: begin
                    if (card_x>330) card_x<=card_x-10'd3;
                    if (timer<360) timer<=timer+9'd1;
                    if (card_x<=330 && done) begin state<=GAP; timer<=0; end
                    else if (timer==359) begin
                        present<=0; reading<=0; error<=1; state<=FAILED; card_x<=420; timer<=0;
                    end
                end
                GAP: if (timer==29) begin
                    timer<=0; byte_pos<=0; reading<=0;
                    if (remaining>1 && !error) begin
                        remaining<=remaining-3'd1; bank_base<=bank_base+10'd246; ptr<=bank_base+10'd246;
                        state<=WAITING;
                    end else if (error) begin state<=FAILED; card_x<=420; end
                    else begin state<=SEAT; card_x<=600; end
                end else timer<=timer+9'd1;
                SEAT: if (card_x<=420) state<=PARKED; else card_x<=card_x-10'd3;
                FAILED: if (timer==179) begin state<=EMPTY; error<=0; end else timer<=timer+9'd1;
                default: begin end
            endcase
        end
    end
endmodule
