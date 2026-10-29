// SPDX-License-Identifier: GPL-2.0-or-later
#include "Vti59_card.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
static void check(bool ok,const char*why){if(!ok)throw std::runtime_error(why);}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);Vti59_card d;
    d.clk=0;d.reset=1;d.frame=0;d.ready=1;d.download=0;d.wr=0;d.addr=0;d.dout=0;d.cmd=0;
    auto tick=[&](){d.clk=0;d.eval();d.clk=1;d.eval();};
    auto frame=[&](){d.frame=1;tick();d.frame=0;tick();};
    auto command=[&](int cmd){d.cmd=cmd;tick();d.cmd=0;tick();tick();};
    auto reset=[&](){d.reset=1;tick();d.reset=0;tick();};reset();
    std::ifstream f("examples/cards/two-pass.crd",std::ios::binary);
    std::vector<unsigned char> pair((std::istreambuf_iterator<char>(f)),{});
    std::vector<unsigned char> bank(pair.begin(),pair.begin()+246);
    auto load=[&](const std::vector<unsigned char>&v,int skip=-1){
        d.download=1;tick();
        for(unsigned i=0;i<v.size();i++){
            d.addr=(int(i)==skip)?0:i;d.dout=v[i];d.wr=1;tick();d.wr=0;tick();
        }
        d.download=0;tick();tick();
    };
    try{
        for(unsigned count=1;count<=4;count++){
            reset();std::vector<unsigned char> v;
            for(unsigned i=0;i<count;i++)v.insert(v.end(),bank.begin(),bank.end());
            load(v);check(!d.error,"valid multi-bank accepted");
            unsigned swipes=0,frames=0,half_frames=0;bool seated=false;
            while(frames++<1200){
                frame();
                check(d.motor == (d.visible && !d.front && d.card_x>330),"motor follows transport; stops half-out and during seating");
                if(d.visible && !d.front && d.card_x==330)half_frames++;
                if(d.present){
                    swipes++;command(1);
                    for(unsigned i=0;i<245;i++){
                        command(1); // Repeated CRD_READ must not rewind the bank.
                        check(d.data==bank[i],"synchronous card stream byte");command(2);
                    }
                    command(3);
                }
                if(d.front && d.visible && !d.busy){seated=true;break;}
            }
            check(swipes==count && seated && !d.error,"swipes complete then front slot");
            check(d.card_x==420,"card seated in recess");
            check(half_frames>=30*count,"half-out hold before each subsequent pass or seating");
        }
        for(unsigned size: {0U,1U,245U,247U,983U,985U,1100U}){
            reset();auto v=bank;v.resize(size);load(v);frame();
            check(d.error && !d.present && !d.motor,"bad lengths rejected silently before switch");
        }
        reset();auto bad=bank;bad[23]^=0x10;load(bad);check(d.error,"payload checksum");
        reset();bad=bank;bad[245]^=1;load(bad);check(d.error,"second checksum");
        reset();load(bank,100);check(d.error,"nonsequential/restarted address");
        reset();d.ready=0;load(bank);frame();check(!d.present,"OSD defers switch");
        load(pair);d.ready=1;for(int i=0;i<14;i++)frame();check(d.present,"pending load can be replaced without ioctl deadlock");
        for(int i=0;i<361;i++)frame();check(d.error && !d.present && !d.busy,"reader timeout ejects");
        reset();load(bank);for(int i=0;i<14;i++)frame();command(4);for(int i=0;i<180;i++)frame();
        check(d.error && !d.present,"unsupported write ejects with error");
        reset();load(bank);for(int i=0;i<14;i++)frame();command(1);reset();check(!d.present && !d.visible,"reset cancels card");
        std::cout<<"PASS: 1–4 banks, bytes and repeated read command, placement, malformed loads, OSD replacement, timeout, write rejection, reset\n";
    }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
    d.final();
}
