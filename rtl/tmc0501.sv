// SPDX-License-Identifier: GPL-2.0-or-later
// TMC0501 / TMC0582/83 / TMC0598 instruction-level implementation.
// Architecture: Sladky, TI-58/59 HW Programming Guide (2014), pp. 6-21,
// and TI US4153937. One nibble is processed per FPGA clock; 'ce' schedules
// complete 16-digit instructions at the original calculator rate.
module tmc0501 (
    input  wire clk, reset, ce,
    input  wire [111:0] keys,
    input  wire lib_wr,
    input  wire [12:0] lib_waddr,
    input  wire [7:0] lib_wdata,
    input wire [7:0] card_data,
    output reg [2:0] card_cmd, // 1=read mode, 2=byte, 3=off, 4=write (unsupported)
    input wire printer_busy,
    output reg [3:0] printer_cmd,
    output reg [6:0] printer_data,
    output reg retired,
    output reg [12:0] pc,
    output reg [12:0] opcode,
    output reg [3:0] digit, r5,
    output reg [15:0] fa, fb, kr, sr,
    output reg [63:0] a, b, c, d, e,
    output reg idle, cond,
    output wire running,
    output reg [63:0] sout,
    output reg [15:0] ext,
    output wire [12:0] library_address
);
    reg [12:0] firmware [0:8191];
    reg [63:0] constants [0:63];
    reg [7:0] library_rom [0:8191];
    initial begin
        $readmemb("roms/firmware.bin", firmware);
        $readmemh("roms/constants.hex", constants);
        $readmemh("roms/library.hex", library_rom);
    end
    reg [63:0] ram [0:127];
    reg [63:0] scom [0:15];
    reg [12:0] rom_q;
    reg [63:0] const_q, ram_q, scom_q;
    reg [7:0] lib_q;
    reg [3:0] scom_addr;
    reg [7:0] ram_addr;
    reg [15:0] lib_bcd;
    reg [1:0] lib_read_pos;
    reg lib_writing;
    reg [12:0] lib_binary;
    assign library_address = lib_binary;
    wire [6:0] const_addr = {kr[11:8], kr[6:4]};
    always @(posedge clk) begin
        rom_q <= firmware[pc];
        const_q <= constants[const_addr[6] ? 6'd0 : const_addr[5:0]];
        ram_q <= ram[ram_addr[6:0]];
        scom_q <= scom[scom_addr];
        lib_binary <= 13'(lib_bcd[15:12]) * 13'd1000 +
                      13'(lib_bcd[11:8]) * 13'd100 +
                      13'(lib_bcd[7:4]) * 13'd10 + 13'(lib_bcd[3:0]);
        lib_q <= library_rom[lib_binary];
        if (lib_wr) library_rom[lib_waddr] <= lib_wdata;
    end

    localparam CLEAR=0, READY=1, EXEC=2, ALU=3, MEMORY=4, FINISH=5, CLEAR_RAM=6;
    reg [2:0] state;
    reg [7:0] clear_addr;
    reg [3:0] clear_left;
    reg previous_branch, hold_pc, preg_valid;
    reg [12:0] preg;
    reg io_valid, ext_valid, recall_scom, store_scom, ram_op, read_ram, write_ram;
    reg [63:0] x, y, field_bits;
    reg [3:0] n, carry_digit;
    reg carry;
    assign running = !idle;

    // {valid, first digit, last digit, constant position, constant value}
    function automatic [16:0] mask_info(input [3:0] m);
        case (m)
            1: mask_info = {1'b1,4'd0,4'd15,4'd0,4'd0};
            2: mask_info = {1'b1,4'd0,4'd0,4'd0,4'd0};
            3: mask_info = {1'b1,4'd0,4'd0,4'd0,4'd1};
            4: mask_info = {1'b1,4'd0,4'd0,4'd0,4'd12};
            5: mask_info = {1'b1,4'd3,4'd3,4'd3,4'd1};
            6: mask_info = {1'b1,4'd1,4'd2,4'd1,4'd0};
            7: mask_info = {1'b1,4'd1,4'd2,4'd1,4'd1};
            9: mask_info = {1'b1,4'd3,4'd15,4'd3,4'd0};
           11: mask_info = {1'b1,4'd3,4'd15,4'd3,4'd5};
           12: mask_info = {1'b1,4'd1,4'd15,4'd1,4'd0};
           13: mask_info = {1'b1,4'd1,4'd15,4'd3,4'd1};
           14: mask_info = {1'b1,4'd1,4'd15,4'd15,4'd1};
           15: mask_info = {1'b1,4'd1,4'd15,4'd1,4'd1};
          default: mask_info = 0;
        endcase
    endfunction
    wire [16:0] mask = mask_info(opcode[11:8]);
    wire [3:0] first = mask[15:12], last = mask[11:8];
    wire in_field = mask[16] && n >= first && n <= last;
    wire [4:0] op = opcode[7:3];
    wire shift_op = op >= 8 && op <= 15;
    wire subtract = opcode[3];
    wire [3:0] xn = x[{n,2'b00} +: 4];
    wire [3:0] yn = y[{n,2'b00} +: 4] | ((n == mask[7:4]) ? mask[3:0] : 4'd0);
    wire cin = (n == first) ? 1'b0 : carry;
    wire [7:0] total = subtract ? {4'd0,xn} - {4'd0,yn} - {7'd0,cin}
                                : {4'd0,xn} + {4'd0,yn} + {7'd0,cin};
    wire cout = (n == 0) ? (total >= 16) : (total >= 10);
    wire [3:0] corrected = (n == 0 || !cout) ? total[3:0] :
                           subtract ? total[3:0] + 4'd10 : total[3:0] - 4'd10;
    wire [3:0] result = shift_op ?
        (subtract ? (xn | yn) : ((n == first) ? 4'd0 : carry_digit)) : corrected[3:0];
    wire [3:0] write_n = (shift_op && subtract) ? n - 4'd1 : n;
    wire [6:0] key_mask = ~{opcode[7:4],opcode[2:0]};
    wire [6:0] key_pressed = keys[7*digit +: 7] & key_mask;
    wire one_key = key_pressed != 0 && ((key_pressed & (key_pressed - 7'd1)) == 0);
    reg [2:0] key_bit;
    integer i;
    always @* begin
        key_bit = 0;
        for (integer k=0; k<7; k=k+1) if (key_pressed[k]) key_bit = 3'(k);
    end
    wire [7:0] command_addr = 8'(sout[15:12]) * 8'd10 + 8'(sout[11:8]);

    always @(posedge clk) begin
        retired <= 0;
        card_cmd <= 0;
        printer_cmd <= 0;
        if (reset) begin
            state <= CLEAR; clear_addr <= 0; clear_left <= 0;
            pc <= 0; opcode <= 0; digit <= 0; r5 <= 0;
            fa <= 0; fb <= 0; kr <= 0; sr <= 0;
            a <= 0; b <= 0; c <= 0; d <= 0; e <= 0;
            idle <= 0; cond <= 1; previous_branch <= 0; hold_pc <= 0;
            preg <= 0; preg_valid <= 0;
            sout <= 0; ext <= 0; io_valid <= 0; ext_valid <= 0;
            recall_scom <= 0; store_scom <= 0; ram_op <= 0; read_ram <= 0; write_ram <= 0;
            scom_addr <= 0; ram_addr <= 0;
            lib_bcd <= 0; lib_read_pos <= 0; lib_writing <= 0;
            x <= 0; y <= 0; n <= 0; carry <= 0; carry_digit <= 0; field_bits <= 0;
        end else case (state)
            CLEAR: begin
                ram[clear_addr[6:0]] <= 0;
                if (clear_addr < 16) scom[clear_addr[3:0]] <= 0;
                if (clear_addr == 127) state <= READY;
                else clear_addr <= clear_addr + 8'd1;
            end
            READY: if (ce) begin
                opcode <= rom_q;
                digit <= digit - 4'd1;
                hold_pc <= 0;
                if (!rom_q[12] && previous_branch) begin cond <= 1; previous_branch <= 0; end
                if (!io_valid) sout <= 0;
                if (!ext_valid) ext <= 0;
                io_valid <= 0; ext_valid <= 0;
                state <= EXEC;
            end
            EXEC: begin
                state <= FINISH;
                if (opcode[12]) begin
                    previous_branch <= 1;
                    if (cond == opcode[11])
                        pc <= opcode[0] ? pc - {3'd0,opcode[10:1]} : pc + {3'd0,opcode[10:1]};
                    else pc <= pc + 13'd1;
                end else case (opcode[11:8])
                    0: case (opcode[3:0])
                         0: if (fa[opcode[7:4]]) cond <= 0;
                         1: fa[opcode[7:4]] <= 1;
                         2: fa[opcode[7:4]] <= 0;
                         3: fa[opcode[7:4]] <= ~fa[opcode[7:4]];
                         4: begin fa[opcode[7:4]] <= fb[opcode[7:4]]; fb[opcode[7:4]] <= fa[opcode[7:4]]; end
                         5: kr[opcode[7:4]] <= 1;
                         6: fa[opcode[7:4]] <= fb[opcode[7:4]];
                         7: fa[4:1] <= r5;
                         8: if (fb[opcode[7:4]]) cond <= 0;
                         9: fb[opcode[7:4]] <= 1;
                        10: fb[opcode[7:4]] <= 0;
                        11: fb[opcode[7:4]] <= ~fb[opcode[7:4]];
                        12: if (fa[opcode[7:4]] == fb[opcode[7:4]]) cond <= 0;
                        13: kr[opcode[7:4]] <= 0;
                        14: fb[opcode[7:4]] <= fa[opcode[7:4]];
                        15: fb[4:1] <= r5;
                    endcase
                    8: if (one_key) begin
                        cond <= 0;
                        if (!opcode[3]) kr <= {5'd0,key_bit,digit,4'd0};
                    end else if (!opcode[3] && digit != 0) hold_pc <= 1;
                    10: case (opcode[3:0])
                         0: hold_pc <= (digit != opcode[7:4]);
                         1: idle <= 0;
                         2: fa <= 0;
                         3: begin end // No connected WAIT BUSY pin on TMC0501.
                         4: begin kr[15:4] <= kr[15:4] + 12'd1; if (kr[15:4] == 12'hfff) kr[0] <= ~kr[0]; end
                         5: if (kr[opcode[7:4]]) cond <= 0;
                         6: r5 <= opcode[4] ? fb[4:1] : fa[4:1];
                         7: r5 <= opcode[7:4];
                         8: case (opcode[7:4])
                              0: r5 <= kr[7:4];
                              1: kr[7:4] <= r5;
                              2: begin ext <= {4'd0,card_data,4'd0}; ext_valid <= 1; card_cmd <= 2; end
                              4: card_cmd <= 3;
                              5: card_cmd <= 1;
                              6,7,8,9,10,11: begin
                                  printer_cmd <= opcode[7:4]; printer_data <= kr[10:4];
                              end
                             12: card_cmd <= 4;
                             15: ram_op <= 1;
                            default: begin end // Unused card-write data output.
                         endcase
                         9: idle <= 1;
                        10: fb <= 0;
                        11: if (printer_busy || keys[7*digit+4]) cond <= 0;
                        12: kr[15:4] <= ext[15:4];
                        13: begin kr <= sr; sr <= kr; end
                        14: case (opcode[7:4])
                             0: begin
                                ext <= {4'd0,lib_q,4'd0}; ext_valid <= 1;
                                if (lib_bcd >= 16'h4999) lib_bcd <= 0;
                                else if (lib_bcd[3:0] != 9) lib_bcd[3:0] <= lib_bcd[3:0] + 4'd1;
                                else begin
                                    lib_bcd[3:0] <= 0;
                                    if (lib_bcd[7:4] != 9) lib_bcd[7:4] <= lib_bcd[7:4] + 4'd1;
                                    else begin
                                        lib_bcd[7:4] <= 0;
                                        if (lib_bcd[11:8] != 9) lib_bcd[11:8] <= lib_bcd[11:8] + 4'd1;
                                        else begin lib_bcd[11:8] <= 0; lib_bcd[15:12] <= lib_bcd[15:12] + 4'd1; end
                                    end
                                end
                             end
                             1: begin lib_bcd <= {kr[7:4],lib_bcd[15:4]}; lib_read_pos <= 0; lib_writing <= 1; end
                             2: begin
                                 ext <= {8'd0,lib_bcd[{(lib_writing ? 2'd0 : lib_read_pos),2'b00} +: 4],4'd0};
                                 ext_valid <= 1; lib_read_pos <= lib_writing ? 2'd1 : lib_read_pos + 2'd1; lib_writing <= 0;
                             end
                             3: begin ext <= {8'd0,lib_q[7:4],4'd0}; ext_valid <= 1; end
                             default: begin end
                        endcase
                        15: begin
                            scom_addr <= sout[3:0];
                            if (opcode[7:4] == 0) store_scom <= 1;
                            if (opcode[7:4] == 1) recall_scom <= 1;
                        end
                    endcase
                    default: begin
                        state <= ALU; n <= 0; carry <= 0; carry_digit <= 0; sout <= 0;
                        io_valid <= opcode[2:0] == 1;
                        for (i=0; i<16; i=i+1)
                            field_bits[i*4 +: 4] <= (mask[16] && i >= int'(first) && i <= int'(last)) ? 4'hf : 4'h0;
                        x <= 0; y <= 0;
                        case (op)
                            0,1,8,9: x <= a;
                            2,3,10,11: y <= b;
                            4,5,12,13: x <= c;
                            6,7,14,15: y <= d;
                            16,17: begin x <= a; y <= b; end
                            18,19: begin x <= c; y <= b; end
                            20,21: begin x <= c; y <= d; end
                            22,23: begin x <= a; y <= d; end
                            24,25: begin x <= a; y <= const_q; end
                            26: begin
                                if (recall_scom) begin y <= scom_q; recall_scom <= 0; end
                                else if (read_ram) begin y <= ram_addr < 120 ? ram_q : 64'd0; read_ram <= 0; end
                            end
                            28,29: begin x <= c; y <= const_q; end
                            30,31: begin
                                y <= 0;
                                y[{first,2'b00} +: 4] <= r5;
                            end
                            default: begin end
                        endcase
                    end
                endcase
            end
            ALU: begin
                carry <= cout; carry_digit <= corrected[3:0];
                if (in_field) begin
                    if (io_valid) sout[{n,2'b00} +: 4] <= total[3:0];
                    if (n == mask[7:4]) r5 <= corrected[3:0];
                    if (n == last && !shift_op && cout) cond <= 0;
                    if (!(shift_op && subtract) || n > first) case (opcode[2:0])
                        0: a[{write_n,2'b00} +: 4] <= result;
                        3: b[{write_n,2'b00} +: 4] <= result;
                        4: c[{write_n,2'b00} +: 4] <= result;
                        6: d[{write_n,2'b00} +: 4] <= result;
                        default: begin end
                    endcase
                    if (shift_op && subtract && n == last) case (opcode[2:0])
                        0: a[{n,2'b00} +: 4] <= 0;
                        3: b[{n,2'b00} +: 4] <= 0;
                        4: c[{n,2'b00} +: 4] <= 0;
                        6: d[{n,2'b00} +: 4] <= 0;
                        default: begin end
                    endcase
                    case (opcode[2:0])
                        2: begin a[{n,2'b00} +: 4] <= b[{n,2'b00} +: 4]; b[{n,2'b00} +: 4] <= a[{n,2'b00} +: 4]; end
                        5: begin c[{n,2'b00} +: 4] <= d[{n,2'b00} +: 4]; d[{n,2'b00} +: 4] <= c[{n,2'b00} +: 4]; end
                        7: begin a[{n,2'b00} +: 4] <= e[{n,2'b00} +: 4]; e[{n,2'b00} +: 4] <= a[{n,2'b00} +: 4]; end
                        default: begin end
                    endcase
                end
                if (n == 15) state <= MEMORY;
                else n <= n + 4'd1;
            end
            MEMORY: begin
                state <= FINISH;
                if (store_scom) begin scom[scom_addr] <= sout; store_scom <= 0; end
                if (ram_op) begin
                    ram_op <= 0; ram_addr <= command_addr;
                    if (command_addr < 120) case (sout[3:0])
                        0: read_ram <= 1;
                        1: write_ram <= 1;
                        2,4: begin
                            clear_addr <= command_addr;
                            clear_left <= sout[3:0] == 2 ? 4'd1 : 4'd10;
                            state <= CLEAR_RAM;
                        end
                        default: begin end
                    endcase
                end else if (write_ram) begin
                    write_ram <= 0;
                    if (ram_addr < 120) ram[ram_addr[6:0]] <= (ram_q & ~field_bits) | (sout & field_bits);
                end
            end
            CLEAR_RAM: begin
                if (clear_addr < 120) ram[clear_addr[6:0]] <= 0;
                clear_addr <= clear_addr + 8'd1;
                clear_left <= clear_left - 4'd1;
                if (clear_left == 1) state <= FINISH;
            end
            FINISH: begin
                if (!opcode[12]) begin
                    if (!hold_pc) begin pc <= preg_valid ? preg : pc + 13'd1; preg_valid <= 0; end
                    if (kr[1]) begin preg <= {kr[0],kr[15:4]}; preg_valid <= 1; kr[1] <= 0; end
                end
                retired <= 1;
                state <= READY;
            end
            default: state <= CLEAR;
        endcase
    end
endmodule
