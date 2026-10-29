// SPDX-License-Identifier: GPL-2.0-or-later
// Local differential test. Links the unmodified, separately downloaded
// Calc-U-59 oracle; that implementation is NOT part of the FPGA project.
#include "Vtmc0501.h"
#include "TMC0501.hpp"
#include "ROM.hpp"
#include "RAM.hpp"
#include <fstream>
#include <iostream>
#include <iomanip>
#include <vector>
#include <stdexcept>

uint64_t pack(const uint8_t* p) {
    uint64_t v=0;
    for(int i=15;i>=0;--i) v=(v<<4)|(p[i]&15);
    return v;
}
std::vector<uint64_t> hexfile(const char* path) {
    std::ifstream in(path); std::vector<uint64_t> values; uint64_t v;
    if (!in) throw std::runtime_error(path);
    while(in>>std::hex>>v) values.push_back(v);
    return values;
}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    Vtmc0501 dut;
    ROM rom; RAM ram; TMC0501 ref(rom,ram);
    auto fw=hexfile("roms/firmware.hex");
    std::vector<uint16_t> words(fw.begin(),fw.begin()+6144);
    rom.load(words.data(),words.size());
    auto cr=hexfile("roms/constants.hex"); std::vector<uint8_t> nibs;
    for(auto v:cr) for(int i=0;i<16;i++) nibs.push_back((v>>(i*4))&15);
    ref.loadConstants(nibs.data(),nibs.size());
    auto lr=hexfile("roms/library.hex"); std::vector<uint8_t> lib(lr.begin(),lr.begin()+5000);
    ref.loadLibrary(lib.data(),lib.size());
    ref.setCardSwitchCol(10);
    std::vector<uint8_t> card;
    unsigned card_pos=0; bool card_reading=false, card_present=false;
    auto clock=[&](){
        dut.clk=0;dut.eval();dut.clk=1;dut.eval();
        if(dut.card_cmd==1 && !card_reading){card_reading=true;card_pos=0;}
        if(dut.card_cmd==2 && card_reading && card_pos<card.size())card_pos++;
        if(dut.card_cmd==3){card_present=false;card_reading=false;dut.keys[2]|=1U<<10;}
        dut.card_data=card_present && card_reading && card_pos<card.size()?card[card_pos]:0;
    };
    dut.printer_busy=0; dut.card_data=0; dut.ce=0; dut.lib_wr=0; dut.reset=1;
    for(int i=0;i<4;i++) dut.keys[i]=0;
    clock(); dut.reset=0; ref.reset(); ram.clear();
    ref.pressKey(4,10); dut.keys[74/32]|=1U<<(74%32);
    for(int i=0;i<140;i++) clock();
    uint64_t steps=0;
    auto eq=[&](const char*name,uint64_t actual,uint64_t wanted,uint16_t pc,uint16_t op){
        if(actual!=wanted){
            std::cerr<<"FAIL step "<<std::dec<<steps<<" PC="<<std::hex<<pc<<" op="<<op
                     <<" "<<name<<" RTL="<<actual<<" oracle="<<wanted<<"\n";
            throw std::runtime_error("CPU mismatch");
        }
    };
    auto step=[&](){
        auto before=ref.snapshotCPU();
        dut.ce=1;clock();dut.ce=0;
        int cycles=0;while(!dut.retired && cycles++<150)clock();
        if(!dut.retired)throw std::runtime_error("retire timeout");
        ref.step();auto s=ref.snapshotCPU();steps++;
#define CHECK(n,expected) eq(#n,dut.n,expected,before.pc,before.opcode)
        CHECK(pc,s.pc);CHECK(a,pack(s.A));CHECK(b,pack(s.B));CHECK(c,pack(s.C));
        CHECK(d,pack(s.D));CHECK(e,pack(s.E));CHECK(fa,s.fA);CHECK(fb,s.fB);
        CHECK(kr,s.KR);CHECK(sr,s.SR);CHECK(r5,s.R5&15);CHECK(digit,s.digit);
        CHECK(cond,(s.cpuFlags&FLG_COND)!=0);CHECK(idle,(s.cpuFlags&FLG_IDLE)!=0);
        CHECK(sout,pack(s.Sout));CHECK(ext,s.EXT);
#undef CHECK
        for(int i=0;i<4;i++)clock();
    };
    auto run=[&](int n){for(int i=0;i<n;i++)step();};
    const int kbits[]={0,1,2,3,5,6};
    auto key=[&](int code){
        int row=code/10,bit=kbits[code%10];
        ref.pressKey(bit,row);int pos=row*7+bit;
        dut.keys[pos/32]|=1U<<(pos%32);run(1000);
        ref.releaseKey(bit,row);dut.keys[pos/32]&=~(1U<<(pos%32));run(4000);
    };
    auto display=[&](){
        auto s=ref.snapshotCPU();
        std::cout<<" A="<<std::hex<<std::setw(16)<<std::setfill('0')<<pack(s.A)
                 <<" B="<<std::setw(16)<<pack(s.B)<<" R5="<<int(s.R5)<<std::dec<<"\n";
    };
    try {
        run(10000);std::cout<<"Boot";display();
        struct Case{const char* name;std::vector<int> keys;};
        const std::vector<Case> cases={
            {"12+34",{82,83,85,84,72,95}},
            {"Multiply",{25,62,65,73,95}},
            {"Divide",{25,82,55,62,95}},
            {"sqrt(2)",{25,83,34}},
            {"Square",{33}},
            {"sin(30)",{25,84,92,21,33}},
            {"ln(2)",{25,83,23}},
            {"AOS precedence",{25,83,85,84,65,72,95}},
            {"Parentheses",{25,53,83,85,84,54,65,72,95}},
            {"STO/RCL 00",{25,62,63,64,42,92,92,25,43,92,92}},
            {"Learn/run",{25,21,24,31,83,65,84,95,91,31,81,91}},
            {"Library diagnostic",{25,21,31,92,82,71,95}},
        };
        for(auto &test:cases){
            for(int k:test.keys)key(k);
            run(test.name == std::string("Library diagnostic") ? 2000000 : 30000);
            std::cout<<test.name;display();
        }
        // The original firmware detects the switch, reads a raw card and
        // writes program RAM. Compare every instruction against the oracle.
        dut.reset=1;clock();dut.reset=0;ref.reset();ram.clear();
        ref.pressKey(4,10);dut.keys[2]|=1U<<10;
        for(int i=0;i<140;i++)clock();run(10000);
        std::ifstream input("examples/cards/multiply.crd",std::ios::binary);
        card.assign(std::istreambuf_iterator<char>(input),{});
        if(card.size()!=246)throw std::runtime_error("missing card fixture");
        ref.insertCard(card.data(),card.size());card_present=true;card_reading=false;
        dut.keys[2]&=~(1U<<10);run(40000);
        if(card_present || card_pos<245)throw std::runtime_error("firmware did not read card");
        key(81);key(91);run(30000);std::cout<<"Magnetic card program";display();
        auto result=ref.snapshotCPU();
        if(pack(result.A)!=0x6000ULL)throw std::runtime_error("card program did not return 6");
        std::cout<<"PASS: "<<steps<<" ROM instructions match the reference CPU\n";
    }catch(const std::exception&ex){std::cerr<<ex.what()<<"\n";return 1;}
    dut.final();
}
