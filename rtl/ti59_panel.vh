// SPDX-License-Identifier: GPL-2.0-or-later
// Shared 640x480 logical geometry for highlights and mouse hit testing.
function automatic integer panel_key_x(input integer key);
    panel_key_x = key < 45 ? 432 + ((key%5)*59)/2 : 83+(key-45)*47;
endfunction
function automatic integer panel_key_y(input integer key);
    panel_key_y = key < 45 ? 177 + ((key/5)*51)/2 : 399;
endfunction
function automatic integer panel_key_w(input integer key);
    panel_key_w = key < 45 ? 21 : 44;
endfunction
function automatic integer panel_key_h(input integer key);
    panel_key_h = key < 45 ? 15 : 24;
endfunction
