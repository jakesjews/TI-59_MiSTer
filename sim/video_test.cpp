// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the same upstream mixer/freak instances used on MiSTer.
#include "Vvideo_test.h"
#include <algorithm>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool ok, const std::string &why) {
    if (!ok) throw std::runtime_error(why);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vvideo_test d;
    d.selected=36;d.trace_on=0;d.printer_busy=0;d.pressed=0;d.paper_ink=0; d.card_x=420; d.card_visible=0; d.card_front=0; d.card_error=0;
    d.clk=0; d.mode_480p=0; d.forced_scandoubler=0; d.aspect=0; d.scale=0;
    d.hdmi_width=1920; d.hdmi_height=1080;
    d.gamma_en=0; d.gamma_wr=0; d.gamma_addr=0; d.gamma_value=0;
    uint64_t cycles=0;
    auto tick=[&](){d.clk=0;d.eval();d.clk=1;d.eval();cycles++;};
    auto wait=[&](uint64_t n){for(uint64_t i=0;i<n;i++)tick();};
    auto frame=[&](bool native, bool doubled, bool capture=false){
        const bool high = native || doubled;
        const unsigned height=high?480:240, total=native?525:(doubled?524:262);
        const uint64_t deadline=cycles+3000000;
        // Count a complete frame after the pipeline has acquired its input.
        bool old_h=d.hs, old_v=d.vs, old_de=d.de;
        unsigned pixels=0, active=0, line=0, lines=0, h_edges=0;
        uint64_t last_h=0, start=0;
        std::vector<unsigned char> rgb;
        while(true){
            tick();
            require(cycles<deadline,"frame timeout");
            if(!d.ce_pixel)continue;
            if(!old_v && d.vs){
                if(start)break;
                start=cycles; pixels=active=line=lines=h_edges=0;
            }
            if(start){
                pixels++;
                if(!old_h && d.hs){
                    if(last_h)require(cycles-last_h==(high?1600:3200),"horizontal scan period");
                    last_h=cycles;h_edges++;
                }
                if(d.de){active++;line++;rgb.insert(rgb.end(),{d.r,d.g,d.b});}
                if(old_de && !d.de){require(line==640,"640 active pixels per line: "+std::to_string(line));lines++;line=0;}
            }
            old_h=d.hs;old_v=d.vs;old_de=d.de;
        }
        require(cycles-start==(native?840000:838400),"frame period");
        require(pixels==800*total,"pixels per frame");
        require(active==640*height,"active pixels per frame");
        require(lines==height,"active line count");
        require(h_edges==total,"sync pulse count");
        if(capture){
            std::ofstream out(native?"build/ti59-native-480p.ppm":(doubled?"build/ti59-doubled-240p.ppm":"build/ti59-native-240p.ppm"),std::ios::binary);
            out<<"P6\n640 "<<height<<"\n255\n";
            out.write(reinterpret_cast<char*>(rgb.data()),rgb.size());
        }
        return rgb;
    };
    auto mode=[&](bool native,bool forced){
        d.mode_480p=native;d.forced_scandoubler=forced;wait(840000*4);
        auto rgb=frame(native,forced&&!native,true);
        require(d.gamma_supported,"mixer gamma bus connected");
        require(d.arx==4 && d.ary==3,"video_freak 4:3 metadata");
        std::cout<<"PASS: native "<<(native?480:240)<<"p"<<", forced="<<forced
                 <<", "<<((native||forced)?"31.5":"15.75")<<" kHz\n";
        return rgb;
    };
    try {
        auto base=mode(0,0);
        auto doubled=mode(0,1);
        for(unsigned y=0;y<240;y++)for(unsigned repeat=0;repeat<2;repeat++)
            require(std::equal(base.begin()+y*640*3,base.begin()+(y*640+638)*3,
                               doubled.begin()+(y*2+repeat)*640*3),"line-doubled RGB content (upstream right-edge guard excluded)");
        // Upstream Hq2x's bypass pipeline blanks two guard pixels at the right edge.
        for(unsigned y=0;y<480;y++)for(unsigned x=638;x<640;x++)for(unsigned c=0;c<3;c++)
            require(doubled[(y*640+x)*3+c]==0,"upstream scandoubler right-edge guard");
        require(std::count(base.begin(),base.end(),255)>100,"live LED/highlight pixels are present");
        auto native=mode(1,0);
        require(native==mode(1,1),"forced scandoubler must not alter native 480p");
        for(unsigned y=0;y<240;y++)
            require(std::equal(base.begin()+y*640*3,base.begin()+(y+1)*640*3,
                               native.begin()+y*2*640*3),"240p samples even rows of the 480p artwork");
        require(native!=doubled,"native 480p must preserve artwork detail absent in line doubling");

        d.selected=46;d.trace_on=1;wait(840000*2);auto trace=frame(true,false);
        auto at=(400*640+130)*3;
        require(trace[at]==244 && trace[at+1]==191 && trace[at+2]==91,"TRACE stays gold while selected");
        d.trace_on=0;wait(840000*2);auto trace_off=frame(true,false);
        require(trace_off[at]==135 && trace_off[at+1]==198 && trace_off[at+2]==215,"TRACE off returns to selection color");
        d.selected=36;
        // The paper overlay must stay on the left, and the half-ejected card
        // must remain in the gap without touching the printer housing.
        d.paper_ink=1;wait(840000*2);auto ink=frame(true,false);
        unsigned ink_pixels=0;
        for(unsigned y=0;y<480;y++)for(unsigned x=0;x<640;x++){
            bool changed=false;for(unsigned c=0;c<3;c++)changed|=ink[(y*640+x)*3+c]!=native[(y*640+x)*3+c];
            if(changed){ink_pixels++;require(x>=108 && x<236 && y>=12 && y<264,"ink confined to printable paper");}
        }
        require(ink_pixels==128*252,"complete paper window");d.paper_ink=0;
        d.card_visible=1;d.card_front=0;d.card_x=330;wait(840000*2);
        auto behind=frame(true,false);
        unsigned card_pixels=0;
        for(unsigned y=0;y<480;y++)for(unsigned x=0;x<640;x++){
            bool changed=false;for(unsigned c=0;c<3;c++)changed|=behind[(y*640+x)*3+c]!=native[(y*640+x)*3+c];
            if(changed){card_pixels++;require(x>=330 && x<410 && y>=118 && y<142,"half-out card clears printer and is occluded by calculator");}
        }
        require(card_pixels==80*24,"exactly half a card exposed");
        d.card_front=1;d.card_x=420;wait(840000*2);auto parked=frame(true,false);
        card_pixels=0;
        for(unsigned y=0;y<480;y++)for(unsigned x=0;x<640;x++){
            bool changed=false;for(unsigned c=0;c<3;c++)changed|=parked[(y*640+x)*3+c]!=native[(y*640+x)*3+c];
            if(changed){card_pixels++;require(x>=420 && x<580 && y>=134 && y<158,"card seated in legend recess");}
        }
        require(card_pixels>3700,"parked card artwork visible");
        d.card_visible=0;wait(840000*2);
        // Gamma must be operational, not just an unconnected advertised port.
        for(unsigned channel=0;channel<3;channel++)for(unsigned v=0;v<256;v++){
            d.gamma_wr=1;d.gamma_addr=channel*256+v;d.gamma_value=255-v;tick();
        }
        d.gamma_wr=0;d.gamma_en=1;wait(838400*3);
        auto inverted=frame(true,false);
        require(inverted.size()==native.size(),"gamma capture geometry");
        for(unsigned i=0;i<native.size();i++)require(inverted[i]==255-native[i],"gamma LUT changes RGB correctly");
        d.gamma_en=0;

        d.aspect=1;wait(838400*2);frame(true,false);
        require(d.arx==0 && d.ary==0,"full-screen metadata");
        d.aspect=2;wait(838400*2);frame(true,false);
        require(d.arx==1 && d.ary==0,"ARC1 metadata");
        d.aspect=0;d.scale=2;wait(838400*3);frame(true,false);
        require(d.arx==(4096|1280) && d.ary==(4096|960),"HV integer scale metadata at 1080p");
        std::cout<<"PASS: 240p sampling, native 480p detail, doubled rows, native-480p gamma LUT, aspect ratios and integer scaling; "<<cycles<<" clocks\n";
    } catch(const std::exception &e){std::cerr<<"FAIL at clock "<<cycles<<": "<<e.what()<<"\n";return 1;}
    d.final();
}
