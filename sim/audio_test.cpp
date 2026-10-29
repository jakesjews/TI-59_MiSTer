// SPDX-License-Identifier: GPL-2.0-or-later
#include "Vti59_audio.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
static void check(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);Vti59_audio d;
    d.clk=0;d.reset=1;d.key_click=0;d.card_motor=0;d.printer_motor=0;d.level=0;
    uint64_t cycles=0,last_sample=0;unsigned samples=0;int peak=0;
    std::vector<int16_t> capture;
    auto tick=[&](){
        auto old=d.audio;d.clk=0;d.eval();d.clk=1;d.eval();cycles++;
        if(d.reset){check(d.audio==0 && !d.sample_ce,"reset silence");last_sample=cycles;}
        else if(d.sample_ce){
            check(cycles-last_sample==1050,"exact 48 kHz sample spacing");last_sample=cycles;samples++;
            peak=std::max(peak,std::abs(int(int16_t(d.audio))));
            check(std::abs(int(int16_t(d.audio)))<14000,"mix retains headroom");
        }else check(d.audio==old,"sample remains stable between enables");
    };
    auto next=[&](){do{tick();}while(!d.sample_ce);return int16_t(d.audio);};
    auto run=[&](unsigned n,bool silent=false){
        double sum=0,sq=0;
        while(n--){auto v=next();capture.push_back(v);sum+=v;sq+=double(v)*v;if(silent)check(v==0,"idle/off is exactly silent");}
        return std::pair<double,double>{sum,sq};
    };
    auto tap=[&](){d.key_click=1;tick();d.key_click=0;};
    try{
        tick();d.reset=0;run(4800,true);
        tap();auto key=run(960);check(key.second>100000,"single-cycle key pulse captured");run(3840,true);
        d.card_motor=1;auto card=run(24000);check(card.second>24000*10000.,"card audible");
        d.card_motor=0;run(200);run(4600,true); // Half-out pause must be silent.
        d.card_motor=1;run(12000);d.card_motor=0;run(200);run(4600,true);
        d.printer_motor=1;auto printer=run(24000);check(printer.second>24000*10000.,"printer audible");
        d.printer_motor=0;run(200);run(4600,true);
        d.card_motor=d.printer_motor=1;tap();auto both=run(24000);
        check(std::abs(both.first/24000)<200,"mixed audio has no large DC bias");
        d.level=2;run(4800,true);d.level=3;run(4800,true);
        d.level=1;auto quiet=run(24000);d.level=0;auto normal=run(24000);
        double ratio=std::sqrt(quiet.second/normal.second);
        check(ratio>.22 && ratio<.28,"Quiet is one quarter amplitude");
        d.reset=1;tick();d.reset=0;d.card_motor=d.printer_motor=0;run(4800,true);
        // A pulse exactly on the audio tick must also survive.
        for(int i=0;i<1049;i++)tick();d.key_click=1;tick();d.key_click=0;
        check(run(960).second>100000,"sample-boundary key pulse captured");
        std::ofstream out("build/audio/effects.s16le",std::ios::binary);
        for(auto v:capture){out.put(uint16_t(v)&255);out.put((uint16_t(v)>>8)&255);}
        std::cout<<"PASS: "<<samples<<" samples, 48 kHz, idle/reset/mute silence, event capture, motor stop, mix headroom, Quiet ratio "<<ratio<<", peak "<<peak<<"\n";
    }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
