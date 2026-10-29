// SPDX-License-Identifier: GPL-2.0-or-later
#include "Vti59_printer.h"
#include <iostream>
#include <stdexcept>
#include <fstream>
#include <vector>
static void check(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);Vti59_printer d;
    d.clk=0;d.reset=1;d.clear_paper=0;d.retired=0;d.cmd=0;d.data=0;d.read_addr=0;
    auto tick=[&](){d.clk=0;d.eval();d.clk=1;d.eval();};
    auto run=[&](int n){while(n--)tick();};
    auto cmd=[&](int c,int v=0){d.cmd=c;d.data=v;tick();d.cmd=0;run(4);};
    auto retire=[&](){d.retired=1;tick();d.retired=0;tick();};
    auto pixel=[&](int x,int y){d.read_addr=((y&511)<<7)|x;tick();return bool(d.pixel);};
    auto glyph=[&](int pos){int bit=pos*6;uint64_t v=d.last_line[bit/32];if(bit/32<3)v|=uint64_t(d.last_line[bit/32+1])<<32;return (v>>(bit%32))&63;};
    std::ifstream f("roms/printer_font.hex");std::vector<int> font;int v;while(f>>std::hex>>v)font.push_back(v);
    try{
        tick();check(!d.motor,"startup RAM clear is silent");d.reset=0;run(65540);check(!d.busy,"startup clear finished");
        cmd(6,2);cmd(10);check(!d.busy,"printer not armed before CLEAR");
        cmd(8);cmd(7,0x66);cmd(9);cmd(6,32);cmd(6,8);cmd(6,2);cmd(10);run(5000);check(d.motor,"printing runs motor");
        // Input .71 followed by blank and reversed STO: printed as 17. STO.
        check(glyph(0)==26 && glyph(1)==31 && glyph(2)==30,"function mnemonic reversed in input buffer");
        check(glyph(3)==0 && glyph(4)==32 && glyph(5)==8 && glyph(6)==2,"right-to-left character stream and STEP");
        for(int c=0;c<20;c++)for(int y=0;y<18;y++)for(int x=0;x<6;x++){
            bool want=y>=1 && y<=14 && x<5 && (font[glyph(19-c)*8+(y-1)/2]&(16>>x));
            check(pixel(4+c*6+x,y)==want,"5x7 glyph bitmap, vertical doubling, spacing and clear");
        }
        for(int i=0;i<4164;i++)retire();check(d.busy && d.motor,"line BUSY duration");retire();check(!d.busy && !d.motor && d.paper_head==18,"line completion advances 18 rows and stops motor");
        cmd(11);check(d.motor,"paper feed runs motor");for(int i=0;i<1370;i++)retire();check(!d.busy && !d.motor && d.paper_head==27,"FEED advances half a line");run(2000);
        for(int y=18;y<27;y++)for(int x=0;x<128;x++)check(!pixel(x,y),"FEED creates blank paper");
        // More than one full ring of paper; no stale dots may survive in new lines.
        for(int n=0;n<60;n++){cmd(11);run(2000);for(int i=0;i<1370;i++)retire();}
        check(d.paper_head==55,"circular paper head wraps");
        for(int y=0;y<512;y++)for(int x=0;x<128;x++)check(!pixel(x,y),"old ink scrolls out of ring");
        cmd(8);for(int n=0;n<22;n++)cmd(6,(n%10)+1);cmd(10);run(5000);
        check(glyph(0)==1 && glyph(1)==2 && glyph(19)==10,"20-character input buffer wraps");
        cmd(10);check(!d.busy,"GO while printing aborts");
        d.clear_paper=1;tick();check(!d.motor,"clear paper stops motor");d.clear_paper=0;run(65540);check(!d.busy && d.paper_head==0,"clear paper resets printer");
        std::cout<<"PASS: printer character/function codes, buffer ordering/wrap, raster dots, BUSY timing, half-line feed, paper ring and clear\n";
    }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
