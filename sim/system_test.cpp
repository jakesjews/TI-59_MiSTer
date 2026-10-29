// SPDX-License-Identifier: GPL-2.0-or-later
#include "Vti59_system.h"
#include "Vti59_system___024root.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
#include <string>

static void require(bool ok,const std::string&why){if(!ok)throw std::runtime_error(why);}
int main(int argc,char**argv){
    std::cout.setf(std::ios::unitbuf);Verilated::commandArgs(argc,argv);Vti59_system d;
    d.clear_paper=0;d.mode_480p=0;d.clk=0;d.reset=1;d.osd_open=0;d.ps2_key=0;
    d.card_download=0; d.card_wr=0; d.card_addr=0; d.card_dout=0;
    d.joystick=0;d.lib_wr=0;d.lib_waddr=0;d.lib_wdata=0;d.sound_level=0;
    unsigned clicks=0,card_audio=0,printer_audio=0;
    uint64_t audio_last=0;
    uint64_t cycles=0,pixels=0,last_h=0,last_v=0;
    bool print_pending=false,old_h=true,old_v=true,old_de=false,record=false,old_card=false;
    std::vector<std::string> printed; unsigned feeds=0;
    unsigned swipes=0,read_bytes=0,record_frames=0;
    int line_pixels=0,lit_pixels=0,valid_frames=0,ignore_frames=2;
    std::vector<uint8_t> capture,last_capture;
    auto clock=[&](){
        d.clk=0;d.eval();d.clk=1;d.eval();cycles++;
        if(d.rootp->ti59_system__DOT__key_click)clicks++;
        if(d.reset)audio_last=cycles;
        else if(d.audio_ce){
            require(cycles-audio_last==1050,"audio stays at 48 kHz in full calculator");audio_last=cycles;
            if(d.audio && d.rootp->ti59_system__DOT__reader__DOT__state==2 && d.rootp->ti59_system__DOT__card_x>330)card_audio++;
            if(d.audio && d.rootp->ti59_system__DOT__printer__DOT__busy_cycles)printer_audio++;
        }
        if(d.rootp->ti59_system__DOT__printer_cmd==11)feeds++;
        if(print_pending){
            auto &bits=d.rootp->ti59_system__DOT__printer__DOT__last_line;
            std::string line;const std::string codes=" 0123456789ABCDE-FGHIJKLMNOPQRST.UVWXYZ+";
            for(int i=19;i>=0;i--){int bit=i*6;uint64_t w=bits[bit/32];if(bit/32<3)w|=uint64_t(bits[bit/32+1])<<32;unsigned g=(w>>(bit%32))&63;line+=g==52?'=':(g<40?codes[g]:'?');}
            printed.push_back(line);std::cout<<"Printed: ["<<line<<"]\n";
        }
        print_pending=d.rootp->ti59_system__DOT__printer_cmd==10 && !d.rootp->ti59_system__DOT__printer_busy;
        bool card=d.rootp->ti59_system__DOT__card_present;
        if(card && !old_card)swipes++;
        old_card=card;
        if(d.rootp->ti59_system__DOT__card_cmd==2)read_bytes++;
        if(d.ce_pixel){
            pixels++;
            if(!d.hs && old_h){if(last_h)require(pixels-last_h==800,"HS period must be 800 pixels");last_h=pixels;}
            if(!d.vs && old_v){
                if(ignore_frames)ignore_frames--;
                else if(last_v){
                    require(pixels-last_v==800*262,"VS frame length");
                    require(lit_pixels==640*240,"Active video area");
                    valid_frames++;
                }
                last_v=pixels;lit_pixels=0;
            }
            if(d.de){
                line_pixels++;lit_pixels++;
                capture.push_back(d.r);capture.push_back(d.g);capture.push_back(d.b);
            }
            if(!d.de && old_de){require(line_pixels==640,"Active line width");line_pixels=0;}
            if(!d.vs && old_v){
                last_capture.swap(capture);capture.clear();
                if(record && record_frames++%6==0 && last_capture.size()==640*240*3){
                    char path[100];snprintf(path,sizeof(path),"build/card-animation/frame-%04u.ppm",record_frames/6);
                    std::ofstream out(path,std::ios::binary);out<<"P6\n640 240\n255\n";
                    out.write(reinterpret_cast<char*>(last_capture.data()),last_capture.size());
                }
            }
            old_h=d.hs;old_v=d.vs;old_de=d.de;
        }
    };
    auto run=[&](uint64_t n){for(uint64_t i=0;i<n;i++)clock();};
    auto event=[&](int code,bool down){d.ps2_key=((d.ps2_key^1024)&1024)|(down?512:0)|code;run(8);};
    auto key=[&](int code){event(code,true);run(4032000);event(code,false);run(6048000);
        auto deadline=cycles+151200000ULL;unsigned quiet=0;
        while(quiet<10){require(cycles<deadline,"printer completion timeout");run(252000);quiet=d.rootp->ti59_system__DOT__printer_busy?0:quiet+1;}
    };
    auto display=[&](){
        std::string s;
        auto &v=d.rootp->ti59_system__DOT__segments;
        for(int i=11;i>=0;i--){
            uint8_t seg=(v[i/4]>>((i%4)*8))&255;
            const unsigned codes[]={0x3f,6,0x5b,0x4f,0x66,0x6d,0x7d,7,0x7f,0x6f};
            char c='?';if((seg&127)==0)c=' ';if((seg&127)==0x40)c='-';
            for(int j=0;j<10;j++)if((seg&127)==codes[j])c='0'+j;
            s+=c;if(seg&128)s+='.';
        }
        return s;
    };
    auto expect=[&](const char*value){auto s=display();auto at=s.find_first_not_of(' ');s=at==std::string::npos?"":s.substr(at);while(!s.empty()&&s.back()==' ')s.pop_back();std::cout<<"Display: ["<<s<<"]\n";require(s==value,std::string("Expected display ")+value);};
    try{
        run(100);d.reset=0;run(25200000);expect("0");require(!d.audio && !clicks,"silent startup");
        // Held/repeated keys click once, release/OSD navigation stay silent.
        event(0x16,true);run(10000);require(clicks==1,"key press clicks");
        event(0x16,true);run(10000);require(clicks==1,"typematic does not retrigger");
        event(0x16,false);run(10000);require(clicks==1,"release is silent");
        d.osd_open=1;event(0x1e,true);event(0x1e,false);run(10000);require(clicks==1,"OSD keys are silent");d.osd_open=0;
        d.reset=1;run(100);d.reset=0;run(25200000);
        key(0x1e);key(0x79);key(0x26);key(0x5a);expect("5.");
        key(0x66);key(0x16);key(0x3d);key(0x4d);key(0x45);key(0x45); // 17 STO 00
        key(0x66);key(0x44);key(0x45);key(0x45);expect("17.");
        key(0x0b);run(50400000); // Physical PRINT via F6.
        require(!printed.empty() && printed.back().find("17.")!=std::string::npos,"PRINT emits displayed result through firmware");
        unsigned feed_before=feeds;key(0x83);run(25200000);
        require(feeds==feed_before+2,"ADV emits two half-line feeds");
        auto printed_before=printed.size();key(0x0a); // TRACE switch via F8.
        require(d.rootp->ti59_system__DOT__trace_on,"TRACE enabled");
        key(0x66);key(0x1e);key(0x79);run(25200000);key(0x26);key(0x5a);run(50400000);expect("5.");
        require(printed.size()>printed_before+1 && printed.back().find("5.")!=std::string::npos,"TRACE prints operands and result");
        key(0x0a);require(!d.rootp->ti59_system__DOT__trace_on,"TRACE disabled");
        // Save a source-frame preview with real firmware-produced ink.
        while(d.vs)clock();while(!d.vs)clock();while(d.vs)clock();
        {std::ofstream out("build/ti59-printer.ppm",std::ios::binary);out<<"P6\n640 240\n255\n";out.write(reinterpret_cast<char*>(last_capture.data()),last_capture.size());}
        key(0x66);key(0x44);key(0x45);key(0x45);expect("17.");
        auto load_card=[&](const std::vector<uint8_t>&bytes){
            d.card_download=1;run(8);
            for(unsigned i=0;i<bytes.size();i++){
                d.card_addr=i;d.card_dout=bytes[i];d.card_wr=1;clock();d.card_wr=0;run(3);
            }
            d.card_download=0;run(8);
        };
        std::ifstream card_file("examples/cards/two-pass.crd",std::ios::binary);
        std::vector<uint8_t> card((std::istreambuf_iterator<char>(card_file)),{});
        require(card.size()==492,"two-bank fixture");
        auto broken=card;broken[10]^=1;load_card(broken);
        require(d.rootp->ti59_system__DOT__card_error && !d.rootp->ti59_system__DOT__card_present,"reject checksum before insertion");
        broken.resize(100);load_card(broken);
        require(d.rootp->ti59_system__DOT__card_error,"reject truncated bank");
        // Loading while the OSD owns input must defer insertion until it closes.
        d.osd_open=1;load_card(card);run(1680000);
        require(!d.rootp->ti59_system__DOT__card_present,"defer until OSD closes");
        record=true;
        d.osd_open=0;run(25200000);
        require(d.card_busy,"card transport started");
        auto deadline=cycles+50400000ULL*10;
        while(!(d.rootp->ti59_system__DOT__card_front && !d.card_busy) && cycles<deadline)clock();
        run(1680000);record=false;
        std::cout<<"Card result: busy="<<int(d.card_busy)<<" error="<<int(d.rootp->ti59_system__DOT__card_error)
                 <<" swipes="<<swipes<<" bytes="<<read_bytes<<" display="<<display()<<"\n";
        require(!d.card_busy && !d.rootp->ti59_system__DOT__card_error,"card transport completed");
        require(card_audio>1000 && printer_audio>1000,"actual firmware events produce both motor sounds");
        require(swipes==2 && read_bytes==490,"two firmware reads of 245 bytes");
        key(0x66);key(0x44);key(0x45);key(0x45);expect("17."); // R00 survived
        key(0x2c);key(0x2d);run(50400000);expect("6."); // RST, R/S, imported 2*3
        // The same file can be loaded again without power cycling.
        load_card(std::vector<uint8_t>(card.begin(),card.begin()+246));
        run(25200000);while(!(d.rootp->ti59_system__DOT__card_front && !d.card_busy) && cycles<deadline+504000000ULL)clock();
        require(!d.card_busy && !d.rootp->ti59_system__DOT__card_error && swipes==3,"repeat card load");
        std::cout<<"PASS: malformed images rejected, two-pass card read, program returns 6, data memory preserved, reload\n";
        // OSD ownership must release the calculator's keyboard matrix.
        event(0x26,true);d.osd_open=1;run(20);
        require(d.rootp->ti59_system__DOT__controls__DOT__held_key==63,"OSD clears held key");
        event(0x26,false);d.osd_open=0;
        // Video keeps running during a reset, including Direct Video output.
        d.reset=1;run(1680000);d.reset=0;run(25200000);expect("0");
        int frames240=valid_frames;require(frames240>5,"240p frames verified");
        // Capture the 240p source; video_test verifies the full mixer pipeline.
        while(d.vs)clock();while(!d.vs)clock();
        capture.clear();
        while(d.vs)clock();
        require(last_capture.size()==640*240*3,"Capture area");
        std::ofstream ppm("build/ti59-simulation.ppm",std::ios::binary);
        ppm<<"P6\n640 240\n255\n";ppm.write(reinterpret_cast<char*>(last_capture.data()),last_capture.size());
        std::cout<<"PASS: keyboard, memory, LED display, OSD release, reset continuity; "
                 <<frames240<<" 240p source frames; "<<cycles<<" clocks\n";
    }catch(const std::exception&e){std::cerr<<"FAIL at clock "<<cycles<<": "<<e.what()<<"\n";return 1;}
    d.final();
}
