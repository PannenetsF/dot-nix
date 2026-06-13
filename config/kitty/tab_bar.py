import json
import subprocess
from collections import defaultdict
from datetime import datetime, timezone

from kitty.boss import get_boss
from kitty.fast_data_types import Screen, add_timer
from kitty.rgb import Color
from kitty.tab_bar import (
    DrawData,
    ExtraData,
    Formatter,
    TabBarData,
    as_rgb,
    draw_attributed_string,
    draw_title,
)
from kitty.utils import color_as_int

timer_id = None

ICON = "  "
RIGHT_MARGIN = 0
REFRESH_TIME = 15

icon_fg = as_rgb(color_as_int(Color(255, 250, 205)))
icon_bg = as_rgb(color_as_int(Color(47, 61, 68)))
# OR icon_bg = as_rgb(0x2f3d44)
bat_text_color = as_rgb(0x999F93)
clock_color = as_rgb(0x7FBBB3)
dnd_color = as_rgb(0x465258)
sep_color = as_rgb(0x999F93)
utc_color = as_rgb(color_as_int(Color(113, 115, 116)))


# cells = [
#     (Color(113, 115, 116), dnd),
#     (Color(135, 192, 149), clock),
#     (Color(113, 115, 116), utc),
# ]


def calc_draw_spaces(*args) -> int:
    length = 0
    for i in args:
        if not isinstance(i, str):
            i = str(i)
        length += len(i)
    return length


def _draw_icon(screen: Screen, index: int) -> int:
    if index != 1:
        return 0

    fg, bg = screen.cursor.fg, screen.cursor.bg
    screen.cursor.fg = icon_fg
    screen.cursor.bg = icon_bg
    screen.draw(ICON)
    screen.cursor.fg, screen.cursor.bg = fg, bg
    screen.cursor.x = len(ICON)
    return screen.cursor.x


def _draw_left_status(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    # print(extra_data)
    
    if tab.is_active:
        tab_bg = as_rgb(color_as_int(Color(47, 61, 68)))
    else:
        tab_bg = as_rgb(color_as_int(draw_data.inactive_bg))
        
    if draw_data.leading_spaces:
        screen.cursor.bg = tab_bg
        screen.draw(" " * draw_data.leading_spaces)

    # TODO: https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-2463083
    # tm = get_boss().active_tab_manager
    #     if tm is not None:
    #         w = tm.active_window
    #         if w is not None:
    #             cwd = w.cwd_of_child or ''
    #             log_error(cwd)

    draw_title(draw_data, screen, tab, index)
    trailing_spaces = min(max_title_length - 1, draw_data.trailing_spaces)
    max_title_length -= trailing_spaces
    extra = screen.cursor.x - before - max_title_length
    if extra > 0:
        screen.cursor.x -= extra + 1
        screen.draw("…")
    if trailing_spaces:
        screen.draw(" " * trailing_spaces)
    else:
        # Add padding equivalent to a single trailing space if it was missing 
        # so the text doesn't hit the edge abruptly.
        if tab.is_active:
            screen.cursor.bg = as_rgb(color_as_int(Color(47, 61, 68)))
        else:
            screen.cursor.bg = as_rgb(color_as_int(draw_data.inactive_bg))
        screen.draw(" ")
    
    end = screen.cursor.x
    screen.cursor.bold = screen.cursor.italic = False
    screen.cursor.fg = 0
    if not is_last:
        screen.cursor.bg = as_rgb(color_as_int(draw_data.inactive_bg))
        screen.draw(draw_data.sep)
    else:
        # Give the last tab a background color space matching its own state before falling back to default
        if tab.is_active:
            # We use the specific #2f3d44 color if the layout is not stack, or just draw_data.active_bg
            # Let's ensure it perfectly matches the 2f3d44
            screen.cursor.bg = as_rgb(color_as_int(Color(47, 61, 68)))
        else:
            screen.cursor.bg = as_rgb(color_as_int(draw_data.inactive_bg))
        
        # When `is_last` is True, Kitty often forces the background to terminal background (248, 248, 248 in light theme)
        # We explicitly draw a blank space with the correct tab background to act as padding.
        # However, we just added padding in `if trailing_spaces` above.
        # Doing this again might make the space double. 
        # But wait, we just want to ensure we transition cleanly.
        
        # Now transition to default background
        screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
        end = screen.cursor.x

    screen.cursor.bg = 0
    return end


def _get_dnd_status():
    result = subprocess.run("~/.dotfiles/bin/dnd -k", shell=True, capture_output=True)
    status = ""

    if result.stderr:
        raise subprocess.CalledProcessError(
            returncode=result.returncode, cmd=result.args, stderr=result.stderr
        )

    if result.stdout:
        status = result.stdout.decode("utf-8").strip()

    return status


# more handy kitty tab_bar things:
# REF: https://github.com/kovidgoyal/kitty/discussions/4447#discussioncomment-2183440
def _draw_right_status(screen: Screen, is_last: bool, draw_data: DrawData) -> int:
    if not is_last:
        return 0
    # global timer_id
    # if timer_id is None:
    #     timer_id = add_timer(_redraw_tab_bar, REFRESH_TIME, True)

    draw_attributed_string(Formatter.reset, screen)

    clock = datetime.now().strftime("%H:%M")
    utc = datetime.now(timezone.utc).strftime(" (UTC %H:%M)")
    dnd = _get_dnd_status()

    cells = []
    if dnd != "":
        cells.append((dnd_color, dnd))
        cells.append((sep_color, " ⋮ "))

    cells.append((clock_color, clock))
    cells.append((utc_color, utc))

    # right_status_length = calc_draw_spaces(dnd + " " + clock + " " + utc)

    right_status_length = RIGHT_MARGIN
    for cell in cells:
        right_status_length += len(str(cell[1]))

    draw_spaces = screen.columns - screen.cursor.x - right_status_length
    
    # Fill the empty space between the tabs and the right status area
    # using the default background. If we don't do this, the active tab's
    # background color might leak into the empty space.
    screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
    if draw_spaces > 0:
        screen.draw(" " * draw_spaces)

    screen.cursor.fg = 0
    for color, status in cells:
        screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
        screen.cursor.fg = color  # as_rgb(color_as_int(color))
        screen.draw(status)
    screen.cursor.bg = 0

    if screen.columns - screen.cursor.x > right_status_length:
        screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
        screen.cursor.x = screen.columns - right_status_length

    return screen.cursor.x

def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:

    _draw_icon(screen, index)
    
    # Active/inactive background setup for the padding
    if tab.is_active:
        tab_bg = as_rgb(color_as_int(Color(47, 61, 68))) # Hardcode to matching #2f3d44 to avoid template bug
    else:
        tab_bg = as_rgb(color_as_int(draw_data.inactive_bg))
        
    screen.cursor.bg = tab_bg

    end = _draw_left_status(
        draw_data,
        screen,
        tab,
        before,
        max_title_length,
        index,
        is_last,
        extra_data,
    )
    
    if is_last and not getattr(extra_data, "for_layout", False):
        # We need to make sure the right status drawing uses default background
        screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
        # Draw a little bit of spacing before right status just in case
        _draw_right_status(
            screen,
            is_last,
            draw_data,
        )

    return end

