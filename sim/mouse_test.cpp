// SPDX-License-Identifier: GPL-2.0-or-later
#include "Vti59_input.h"
#include <algorithm>
#include <iostream>
#include <stdexcept>
static void check(bool ok,const char*s){if(!ok)throw std::runtime_error(s);}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);Vti59_input d;
    d.clk=0;d.reset=1;d.osd_open=0;d.ps2_key=0;d.ps2_mouse=0;d.joystick=0;
    unsigned clicks=0;
    auto tick=[&](){d.clk=0;d.eval();d.clk=1;d.eval();if(d.key_click)clicks++;};
    auto run=[&](int n){while(n--)tick();};
    auto packet=[&](int dx,int dy,int buttons=0,int overflow=0){
        d.ps2_mouse=((d.ps2_mouse^(1<<24))&(1<<24))|8|buttons|overflow|
            (dx<0?16:0)|(dy<0?32:0)|((dx&255)<<8)|((dy&255)<<16);run(5);
    };
    auto move=[&](int x,int y,int buttons=0){
        // The helpers finish on whole pixels; two counts per logical pixel.
        for(int guard=0;d.mouse_x!=x || d.mouse_y!=y;guard++){
            check(guard<20,"move converges");
            int dx=std::clamp(2*(x-int(d.mouse_x)),-200,200);
            int dy=std::clamp(2*(int(d.mouse_y)-y),-200,200);
            packet(dx,dy,buttons);
        }
    };
    auto keybit=[&](int k){
        const int columns[]={1,2,3,5,6};
        int bit=k<45?(k/5+1)*7+columns[k%5]:(k==45?86:k==46?107:84);
        return (d.keys[bit/32]>>(bit%32))&1;
    };
    auto release=[&](){packet(0,0);run(4032005);check(!d.pressed,"release clears captured key");};
    try{
        tick();d.reset=0;run(3);check(!d.mouse_visible && !d.pressed,"hidden and idle until mouse used");
        packet(1,0);check(d.mouse_visible && d.mouse_x==500,"half-pixel retained");
        packet(1,0);check(d.mouse_x==501,"fine reports accumulate");
        auto x=d.mouse_x;run(100);check(d.mouse_x==x,"packet consumed only once");
        packet(200,200);check(d.mouse_x==601 && d.mouse_y==140,"positive 9-bit deltas");
        packet(-200,-200);check(d.mouse_x==501 && d.mouse_y==240,"negative 9-bit deltas and inverted Y");
        for(int i=0;i<8;i++)packet(255,-255,0,0xc0);
        check(d.mouse_x==639 && d.mouse_y==479,"overflow saturates at bottom right");
        for(int i=0;i<8;i++)packet(-255,255,0,0xc0);
        check(d.mouse_x==0 && d.mouse_y==0,"overflow saturates at top left");
        const int xs[]={442,471,501,530,560};
        const int ys[]={184,209,235,260,286,311,337,362,388};
        for(int k=0;k<48;k++){
            move(k<45?xs[k%5]:105+(k-45)*47,k<45?ys[k/5]:411);
            check(d.selected==k && !d.pressed,"hover selects correct physical button");
            auto before=clicks;packet(0,0,1);check(d.pressed && keybit(k),"mouse drives correct TI matrix bit");
            packet(0,0,1);check(clicks==before+1,"held mouse makes one key sound");
            packet(0,0);run(100);check(d.pressed,"short click stretched for firmware scanning");
            run(4032005);check(!d.pressed,"short click eventually releases");
        }
        check(d.trace_on,"mouse TRACE latched once");
        move(152,411);packet(0,0,1);run(4032005);check(!d.trace_on,"second TRACE click unlatches");
        move(199,411,1);run(100);check(d.selected==46 && !d.trace_on,"drag does not press ADV or toggle TRACE again");release();
        move(456,184);packet(0,0,1);check(!d.pressed,"gap between calculator keys is not clickable");release();
        move(300,300);packet(0,0,1);move(442,184,1);check(!d.pressed,"drag from background does not type");release();
        packet(0,0,6);check(!d.pressed,"right and middle buttons do not press keys");release();
        packet(0,0,1);d.osd_open=1;run(10);check(!d.pressed && !d.mouse_visible,"OSD immediately cancels held key and cursor");
        auto oldx=d.mouse_x;packet(100,0,1);check(d.mouse_x==oldx,"OSD reports drained without movement");
        d.osd_open=0;packet(0,0,1);check(!d.pressed,"held button cannot click through after OSD");
        packet(0,0);packet(0,0,1);check(d.pressed,"fresh release rearms mouse");
        d.reset=1;tick();d.reset=0;packet(0,0,1);check(!d.pressed,"reset with button down requires release");release();
        // Existing input methods still work after mouse use.
        d.ps2_key=1024|512|0x16;run(5);check(d.selected==36 && keybit(36),"keyboard number after mouse");
        d.ps2_key=0x16;run(5);check(!d.pressed,"keyboard release");
        d.joystick=32;run(5);check(keybit(5),"gamepad 2nd after mouse");d.joystick=0;run(5);
        std::cout<<"PASS: all 48 mouse targets, signed/fine/overflow motion, edges, packet strobe, short clicks, drag capture, TRACE, OSD/reset, keyboard/gamepad\n";
    }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}
}
