// SPDX-License-Identifier: GPL-2.0-or-later
// Record the actual TI59 RTL and firmware through keyboard/file inputs.
#include "Vti59_system.h"
#include "Vti59_system___024root.h"
#include <cstdio>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
static void require(bool ok,const std::string&s){if(!ok)throw std::runtime_error(s);}
int main(int argc,char**argv){
    std::cout.setf(std::ios::unitbuf);Verilated::commandArgs(argc,argv);Vti59_system d;
    d.clk=0;d.reset=1;d.mode_480p=1;d.clear_paper=0;d.osd_open=0;
    d.ps2_key=0;d.joystick=0;d.lib_wr=0;d.lib_waddr=0;d.lib_wdata=0;
    d.card_download=0;d.card_wr=0;d.card_addr=0;d.card_dout=0;d.sound_level=0;
    std::ofstream pcm("build/demo/audio.s16le",std::ios::binary);
    FILE*video=popen("ffmpeg -hide_banner -loglevel error -y -f rawvideo -pixel_format rgb24 -video_size 640x480 -framerate 30 -i pipe:0 -an -vf scale=1280:960:flags=neighbor -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p -movflags +faststart build/demo/ti59-card-and-printer-silent.mp4","w");
    require(video,"start encoder");
    uint64_t cycles=0,frames=0,record_frames=0,encoded=0;
    unsigned swipes=0,read_bytes=0,printed=0,feeds=0;
    bool record=false,old_v=true,old_card=false,print_pending=false,half_saved=false;
    std::vector<unsigned char> rgb,last;rgb.reserve(640*480*3);last.reserve(640*480*3);
    auto save=[&](const char*name){std::ofstream f(name,std::ios::binary);f<<"P6\n640 480\n255\n";f.write(reinterpret_cast<char*>(last.data()),last.size());};
    auto clock=[&](){
        d.clk=0;d.eval();d.clk=1;d.eval();cycles++;
        auto *r=d.rootp;
        if(record && d.audio_ce){pcm.put(d.audio&255);pcm.put(d.audio>>8);}
        if(r->ti59_system__DOT__card_present && !old_card)swipes++;
        old_card=r->ti59_system__DOT__card_present;
        if(r->ti59_system__DOT__card_cmd==2)read_bytes++;
        if(r->ti59_system__DOT__printer_cmd==11)feeds++;
        if(print_pending){
            printed++;std::string text;const std::string chars=" 0123456789ABCDE-FGHIJKLMNOPQRST.UVWXYZ+";
            auto &bits=r->ti59_system__DOT__printer__DOT__last_line;
            for(int i=19;i>=0;i--){int bit=i*6;uint64_t w=bits[bit/32];if(bit/32<3)w|=uint64_t(bits[bit/32+1])<<32;unsigned c=(w>>(bit%32))&63;text+=c<40?chars[c]:(c==52?'=':(c==40?'x':'?'));}
            std::cout<<"Print @ "<<record_frames/60.0<<"s: ["<<text<<"]\n";
        }
        print_pending=r->ti59_system__DOT__printer_cmd==10 && !r->ti59_system__DOT__printer_busy;
        if(d.ce_pixel){
            if(record && d.de)rgb.insert(rgb.end(),{d.r,d.g,d.b});
            if(!d.vs && old_v){
                frames++;
                if(record){
                    require(rgb.size()==640*480*3,"complete native 480p frame");
                    last.swap(rgb);rgb.clear();
                    if(record_frames++%2==0){require(fwrite(last.data(),1,last.size(),video)==last.size(),"encode frame");encoded++;}
                    if(record_frames==1)save("build/demo/first.ppm");
                    if(!half_saved && d.card_busy && !r->ti59_system__DOT__card_front && r->ti59_system__DOT__card_x==330){save("build/demo/half-out.ppm");half_saved=true;}
                    if(record_frames%120==0)std::cout<<"Recorded "<<record_frames/60<<" seconds\n";
                }
            }
            old_v=d.vs;
        }
    };
    auto run=[&](uint64_t n){while(n--)clock();};
    auto wait_frames=[&](unsigned n){auto end=frames+n;while(frames<end)clock();};
    auto key=[&](int code){
        d.ps2_key=((d.ps2_key^1024)&1024)|512|code;run(5040000);
        d.ps2_key=((d.ps2_key^1024)&1024)|code;run(10080000);
        unsigned quiet=0;auto deadline=cycles+50400000ULL*5;
        while(quiet<6){require(cycles<deadline,"printer wait");wait_frames(1);quiet=d.rootp->ti59_system__DOT__printer_busy?0:quiet+1;}
    };
    auto display=[&](){
        std::string text;auto &s=d.rootp->ti59_system__DOT__segments;
        const int code[]={0x3f,6,0x5b,0x4f,0x66,0x6d,0x7d,7,0x7f,0x6f};
        for(int i=11;i>=0;i--){unsigned seg=(s[i/4]>>((i%4)*8))&255;char c='?';if(!(seg&127))c=' ';for(int j=0;j<10;j++)if((seg&127)==unsigned(code[j]))c='0'+j;text+=c;if(seg&128)text+='.';}
        return text;
    };
    try{
        run(100);d.reset=0;wait_frames(40);require(d.native_480p,"native 480p selected");
        record=true;wait_frames(45);
        std::cout<<"Load two-pass magnetic card\n";
        std::ifstream f("examples/cards/two-pass.crd",std::ios::binary);
        std::vector<unsigned char> card((std::istreambuf_iterator<char>(f)),{});require(card.size()==492,"two-pass image");
        d.card_download=1;run(8);
        for(unsigned i=0;i<card.size();i++){d.card_addr=i;d.card_dout=card[i];d.card_wr=1;clock();d.card_wr=0;run(3);}
        d.card_download=0;run(8);
        auto deadline=cycles+50400000ULL*10;
        while(!(d.rootp->ti59_system__DOT__card_front && !d.card_busy)){require(cycles<deadline,"card completion");clock();}
        require(swipes==2 && read_bytes==490 && !d.rootp->ti59_system__DOT__card_error,"two firmware card passes");
        require(half_saved,"half-out pause recorded");wait_frames(35);
        std::cout<<"Enable TRACE and run imported program\n";
        key(0x0a);key(0x2c);key(0x2d);
        deadline=cycles+50400000ULL*10;
        unsigned quiet=0;
        while(quiet<20){require(cycles<deadline,"program completion");wait_frames(1);
            quiet=(display().find("6.")!=std::string::npos && !d.rootp->ti59_system__DOT__printer_busy && !d.running)?quiet+1:0;
        }
        key(0x0a);wait_frames(20); // Trace off.
        std::cout<<"PRINT result 6, then ADV paper\n";
        auto before=printed;key(0x0b);require(printed>before,"PRINT output");wait_frames(25);
        auto old_feeds=feeds;key(0x83);require(feeds==old_feeds+2,"ADV two half lines");wait_frames(90);
        require(display().find("6.")!=std::string::npos,"final result 6");require(printed>=3,"multiple printed lines");
        save("build/demo/final.ppm");record=false;
        pcm.close();
        int status=pclose(video);video=nullptr;require(status==0,"encoder status");
        std::cout<<"PASS: "<<encoded<<" frames at 30 fps; "<<encoded/30.0<<" seconds; "<<swipes<<" card passes; "<<printed<<" printed lines; final LED="<<display()<<"\n";
    }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";if(video)pclose(video);return 1;}
    d.final();
}
